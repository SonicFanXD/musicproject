import Foundation
import Darwin      // mach_timebase_info (hostTime → segundos)
import AVFoundation
import SFBAudioEngine

// ✅ MIGRACIÓN SFB — NÚCLEO DE REPRODUCCIÓN (archivo aislado, iOS 16, sin UI).
//
// Este archivo contiene TODO lo que habla con SFBAudioEngine (tag 0.14.0,
// https://github.com/sbooth/SFBAudioEngine) para que AudioEngine.swift solo
// tenga que cambiar por "seams" (early-returns) y conserve intacta su ruta
// AVAudioPlayerNode como rollback.
//
// Elección de arquitectura (documentada en el plan de migración):
//  · SFBAudioPlayer YA renderiza a través de un AVAudioEngine propio dirigido
//    por AVAudioSourceNode, así que el grafo de procesamiento (EQ de 10 bandas
//    y downmix mono) se INSERTA dentro del grafo de SFB con
//    `modifyProcessingGraph` y el delegate `reconfigureProcessingGraph`.
//    No hay dos engines de audio en paralelo: solo uno está vivo por núcleo.
//  · Gapless: SFB lo resuelve nativamente (encolado de decoders; mismo formato
//    = unión exacta, distinto formato = reconfiguración automática del grafo).
//    NO se reimplementa gapless por encima: solo se ENCOLA con `enqueue(_:)`
//    y se escucha `nowPlayingChanged`.
//  · El reloj de pared de AudioEngine (posAnchor/wallAnchor) sigue siendo la
//    única fuente de tiempo para la UI y MPNowPlayingInfoCenter; el backend
//    aporta SOLO el offset real de arranque de cada pista (derivado del
//    hostTime de `renderingWillStart`, en ticks de mach).

// MARK: - Preferencia de núcleo (rollback en una línea)

/// Núcleo de reproducción activo.
///
/// - `sfb`: SFBAudioEngine (nuevo, gapless nativo, decodificación extendida).
/// - `avAudioPlayerNode`: núcleo original AVAudioPlayerNode (rollback).
///
/// Cambio de núcleo: `UserDefaults` → clave `com.aurora.playbackCore`
/// (`"sfb"` | `"avAudioPlayerNode"`). Requiere reiniciar la app (el grafo de
/// audio se construye en `init`). Por defecto `sfb` (la migración es el objetivo).
enum PlaybackCorePreference {
    enum Core: String {
        case sfb
        case avAudioPlayerNode
    }

    static let defaultsKey = "com.aurora.playbackCore"

    static var current: Core {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let core = Core(rawValue: raw)
        else { return .sfb }
        return core
    }
}

// MARK: - Sonda de pista (cabecera, sin decodificar)

/// Metadatos de reproducción leídos de la CABECERA del archivo (barato:
/// `AVAudioFile(forReading:)` no decodifica, solo parsea el contenedor).
struct SFBTrackProbe {
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let bitsPerChannel: Int
    let channelCount: Int
    let fileFormatKey: String

    /// Formato de referencia para consultar `formatWillBeGaplessIfEnqueued(_:)`.
    var format: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                      channels: AVAudioChannelCount(max(1, min(channelCount, 8))))
    }
}

// MARK: - Backend

/// Envuelve `AudioPlayer` (SFBAudioEngine) y expone:
///  · control transport (play/pause/resume/stop/seek/gapless-enqueue);
///  · inserción de nodos propios (EQ/mono) entre `sourceNode` y `mainMixerNode`;
///  · eventos traducidos a closures SIEMPRE entregados en el hilo principal.
///
/// No conoce `Song`, ni la cola, ni Now Playing: esa lógica vive en AudioEngine.
final class SFBPlaybackBackend: NSObject {

    // MARK: Eventos (siempre en main)

    /// Pista nueva empezando a sonar.
    /// - Parameters:
    ///   - url: archivo que empieza a sonar (resuelto desde el decoder).
    ///   - startOffset: segundos ya reproducidos de la pista en el momento del
    ///     callback (0 cuando el callback llega justo en el arranque). Se deriva
    ///     del `hostTime` de `renderingWillStart` (ticks de mach → segundos).
    ///   - probe: cabecera del archivo si se pudo leer (duración/tasa/canales).
    ///   - gapless: `true` si SFB confirmó que la unión era gapless de origen.
    var onTrackChange: ((URL, TimeInterval, SFBTrackProbe?, Bool) -> Void)?

    /// Cola agotada: no queda ningún decoder por reproducir.
    var onEndOfAudio: (() -> Void)?

    /// Error asíncrono de decodificación/render (motivo de fallback).
    var onError: ((Error) -> Void)?

    /// El grafo de SFB se reconfiguró (cambio de formato de pista o de ruta):
    /// hay que refrescar telemetría (tasas, bit-perfect, SRC).
    var onGraphReconfigured: (() -> Void)?

    /// Interrupción de sesión gestionada por SFB (solo telemetría/registro;
    /// el ciclo de vida lo dirige AudioEngine con sus propios observers).
    var onInterruptionEnd: (() -> Void)?

    /// Registra el delegate. El customizer del grafo se inyecta DESPUÉS con
    /// `graphCustomizer = …` + `installGraph()` (en `wireSFBBackend()` de
    /// AudioEngine): el closure necesita propiedades de AudioEngine (el EQ y el
    /// mezclador mono) que aún no existen al inicializar estas propiedades.
    override init() {
        super.init()
        player.delegate = self
    }

    private let player = AudioPlayer()

    /// Recibe (engine, source, mixer, format) y devuelve el PRIMER nodo tras
    /// `source` al que SFB debe conectarlo; dentro del bloque se conecta ese
    /// nodo → … → `mixer` (cadena EQ/mono). Es el mismo closure para la
    /// instalación inicial y para `reconfigureProcessingGraph`, manteniendo el
    /// conocimiento del grafo (EQ, mono, formatos) dentro de AudioEngine.
    var graphCustomizer: ((AVAudioEngine, AVAudioSourceNode, AVAudioMixerNode, AVAudioFormat) -> AVAudioNode)?

    /// Cancela el seek diferido de restauración cuando arranca otra pista.
    private var seekToken = 0
    private var pendingRestoreSeek: TimeInterval?

    /// (url, hostTime de mach) del último `renderingWillStart` — para medir el
    /// offset real de arranque de la pista en `nowPlayingChanged`.
    private var lastRenderStart: (url: URL, hostTime: UInt64)?

    /// Sonda cacheada por URL (se reutiliza entre armar y confirmar pista).
    private var probeCache: [URL: SFBTrackProbe] = [:]

    /// Pista ACTUALMENTE sonando (su cabecera) — referencia para el
    /// diagnóstico de gapless.
    private var activeTrackProbe: SFBTrackProbe?

    // MARK: Estado (síncrono, seguro para leer desde AudioEngine)

    var engineIsRunning: Bool { player.engineIsRunning }
    var isPlaying: Bool { player.isPlaying }
    var isStopped: Bool { player.isStopped }
    var queueIsEmpty: Bool { player.queueIsEmpty }

    /// Mezclador principal del grafo de SFB: la ganancia y los fades de
    /// AudioEngine operan sobre él (equivalente a `engine.mainMixerNode`).
    var mainMixerNode: AVAudioMixerNode { player.mainMixerNode }

    /// Formato REAL de salida del hardware (telemetría/bit-perfect).
    var outputFormat: AVAudioFormat { player.outputNode.outputFormat(forBus: 0) }

    /// Tiempo total de la pista actual si SFB lo conoce (si no, `nil`).
    var currentTotalTime: TimeInterval? {
        let t = player.playbackTime.totalTime
        return (t > 0 && t < 1_000_000) ? t : nil
    }

    // MARK: Control de transporte

    /// Arranca una pista desde 0 (o desde `start` con seek diferido: SFB no
    /// expone arranque en offset, así que se hace play + seek con reintentos;
    /// mientras tanto la mezcla puede quedar atenuada — lo decide AudioEngine).
    func play(_ url: URL, startingAt start: TimeInterval) throws {
        seekToken += 1
        let token = seekToken
        // ✅ FIX -10868: el transporte anterior se detiene ANTES de abrir el
        // archivo nuevo. SFB reutiliza decoders/engine y, con una pista a otra
        // tasa (ALAC 24/96 tras 44.1), el motor podía quedar con el formato
        // viejo y CoreAudio respondía `kAudioUnitErr_FormatNotSupported`
        // (-10868). `stop()` deja el transporte en un estado conocido.
        if !player.isStopped {
            player.stop()
        }
        // ✅ Validación REAL del archivo con la ruta de decodificación
        // estándar de iOS: Float32 NO intercalado. Si esto falla, el error
        // llega como `throw` (capturable por AudioEngine → fallback AVPlayer)
        // en vez de estallar dentro del render de SFB, donde no hay catch.
        _ = try validateDecodableFormat(url)
        // Llena la caché de metadatos y fija la referencia para gapless.
        activeTrackProbe = probe(url)
        try player.play(url)
        if start > 0.05 {
            pendingRestoreSeek = start
            attemptRestoreSeek(token: token, attempt: 0)
        } else {
            pendingRestoreSeek = nil
        }
    }

    /// Abre el archivo con `AVAudioFile(forReading:commonFormat:interleaved:)`
    /// forzando **Float32 no intercalado** (el formato de proceso estándar de
    /// AVFoundation) y valida tasa/canales. No se usa para reproducir (de eso
    /// se encarga SFB), sino como PUERTA DE ENTRADA: los contenedores que no
    /// se pueden abrir así son exactamente los que disparan -10868 dentro del
    /// motor, y aquí todavía podemos lanzar un error capturable.
    @discardableResult
    func validateDecodableFormat(_ url: URL) throws -> AVAudioFormat {
        let file = try AVAudioFile(forReading: url,
                                  commonFormat: .pcmFormatFloat32,
                                  interleaved: false)
        let format = file.processingFormat
        guard format.sampleRate > 1, format.channelCount > 0, format.channelCount <= 64 else {
            throw NSError(
                domain: "AuroraSFBPlayback",
                code: -10868,
                userInfo: [NSLocalizedDescriptionKey:
                    "Formato de archivo no reproducible (\(format.sampleRate) Hz · \(format.channelCount) canales) en \(url.lastPathComponent)"]
            )
        }
        return format
    }

    /// Encola la siguiente pista para reproducción gapless. SFB la arranca
    /// solo cuando termina la actual (mismo formato = unión exacta; formato
    /// distinto = reconfiguración del grafo, sin que la app tenga que tocar nada).
    func enqueueNext(_ url: URL) throws {
        probe(url)
        try player.enqueue(url)
    }

    func pause() {
        _ = player.pause()
    }

    @discardableResult
    func resume() -> Bool {
        player.resume()
    }

    /// Detiene transporte y DESCARTA decoders y cola (estado de AudioEngine
    /// queda intacto: la reanudación reconstruye con playCurrentSong).
    func stop() {
        seekToken += 1
        pendingRestoreSeek = nil
        lastRenderStart = nil
        player.stop()
    }

    /// Reinicio completo (media-services reset, grafo muerto, cambio de núcleo).
    func reset() {
        seekToken += 1
        pendingRestoreSeek = nil
        lastRenderStart = nil
        player.reset()
    }

    @discardableResult
    func seek(to time: TimeInterval) -> Bool {
        guard time.isFinite, time >= 0 else { return false }
        return player.seek(time: time)
    }

    /// Descarta SOLO los decoders encolados (no el que suena). Equivalente a
    /// `clearChainedAhead()`/`invalidateChainedAhead()` de la ruta AVAudioPlayerNode.
    func clearPendingDecoders() {
        player.clearQueue()
    }

    // MARK: Grafo de procesamiento (EQ/mono dentro de SFB)

    /// (Re)instala la cadena personalizada entre sourceNode y mainMixerNode.
    /// Llamar tras crear un EQ nuevo o al cambiar la topología (mono on/off).
    func rebuildGraph() {
        installGraph()
    }

    /// Instala (o reinstala) la cadena personalizada. Llamar DESPUÉS de
    /// inyectar `graphCustomizer`; sin customizer es un no-op (source→mixer).
    func installGraph() {
        guard graphCustomizer != nil else { return }
        player.modifyProcessingGraph { [self] engine in
            _ = applyCustomizer(engine, format: nil)
        }
    }

    /// Desengancha un nodo del grafo de SFB (p. ej. un EQ sustituido).
    func detachNode(_ node: AVAudioNode) {
        player.modifyProcessingGraph { engine in
            if engine.attachedNodes.contains(node) { engine.detach(node) }
        }
    }

    private func applyCustomizer(_ engine: AVAudioEngine, format: AVAudioFormat?) -> AVAudioNode {
        let source = player.sourceNode
        let mixer = player.mainMixerNode
        guard let graphCustomizer else { return mixer }
        let resolved = format ?? safeConnectionFormat(engine)
        return graphCustomizer(engine, source, mixer, resolved)
    }

    /// Formato de conexión válido SIEMPRE (evita la aserción interna
    /// `IsFormatSampleRateAndChannelCountValid` con 0 Hz en rutas en transición;
    /// misma política que `makeHardwareFormat()` de AudioEngine).
    private func safeConnectionFormat(_ engine: AVAudioEngine) -> AVAudioFormat {
        let out = engine.outputNode.outputFormat(forBus: 0)
        if out.sampleRate > 1, out.channelCount > 0 {
            return AVAudioFormat(standardFormatWithSampleRate: out.sampleRate, channels: 2) ?? out
        }
        let rate = AVAudioSession.sharedInstance().sampleRate
        return AVAudioFormat(standardFormatWithSampleRate: rate > 1 ? rate : 44_100, channels: 2)!
    }

    // MARK: Sonda (cabecera)

    @discardableResult
    func probe(_ url: URL) -> SFBTrackProbe? {
        if let cached = probeCache[url] { return cached }
        // ✅ PASO 1: misma ruta de decodificación que la reproducción (Float32
        // no intercalado). Si el contenedor no se puede abrir así, la sonda
        // devuelve nil y no se arma gapless con un archivo inválido.
        guard let file = try? AVAudioFile(forReading: url,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false) else { return nil }
        let fmt = file.processingFormat
        guard fmt.sampleRate > 1, file.length > 0 else { return nil }
        let bits = Int(file.fileFormat.streamDescription.pointee.mBitsPerChannel)
        let probe = SFBTrackProbe(url: url,
                                  duration: Double(file.length) / fmt.sampleRate,
                                  sampleRate: fmt.sampleRate,
                                  bitsPerChannel: bits,
                                  channelCount: Int(fmt.channelCount),
                                  fileFormatKey: String(describing: file.fileFormat.streamDescription.pointee.mFormatID))
        probeCache[url] = probe
        return probe
    }

    /// ¿Sería gapless esta pista si se encola ahora? Aplica LA MISMA regla
    /// documentada por SFB ("gapless para audio con la misma tasa y número de
    /// canales") comparando la cabecera de la candidata con la de la pista
    /// activa. Solo TELEMETRÍA honesta: SFB encola de todos modos y resuelve
    /// él solo el caso distinto (reconfiguración del grafo).
    func willBeGapless(_ url: URL) -> Bool {
        guard let candidate = probe(url), let reference = activeTrackProbe else { return false }
        return abs(reference.sampleRate - candidate.sampleRate) < 1
            && reference.channelCount == candidate.channelCount
    }

    // MARK: Seek de restauración (reintentos)

    private func attemptRestoreSeek(token: Int, attempt: Int) {
        guard token == seekToken, let target = pendingRestoreSeek else { return }
        guard attempt < 12 else {
            AppLog.warning(.playback, String(format: "SFB: seek de restauración a %.1fs no aplicado (timeout); se arranca desde 0", target))
            pendingRestoreSeek = nil
            return
        }
        if player.supportsSeeking, player.seek(time: target) {
            // Confirmación real llega por didSeek; se limpia aquí y allí es idempotente.
            pendingRestoreSeek = nil
            AppLog.info(.playback, String(format: "SFB: seek de restauración aplicado a %.1fs", target))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.attemptRestoreSeek(token: token, attempt: attempt + 1)
        }
    }

    // MARK: Utilidad hostTime (mach ticks → segundos)

    private static func seconds(fromHostTime ticks: UInt64) -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom > 0 else { return 0 }
        return TimeInterval(ticks) * TimeInterval(info.numer) / TimeInterval(info.denom) / 1_000_000_000
    }

    /// Offset (segundos ya reproducidos) de la pista representada por `url`
    /// en el instante de AHORA, usando el hostTime anunciado por SFB.
    private func startOffset(for url: URL) -> TimeInterval {
        guard let last = lastRenderStart, last.url == url else { return 0 }
        let age = CACurrentMediaTime() - Self.seconds(fromHostTime: last.hostTime)
        // age > 0 → la pista lleva `age` s sonando; age < 0 → aún no ha llegado
        // su primer frame (event programado con antelación): se arranca en 0.
        return max(0, min(age, 3_600))
    }
}

// MARK: - AudioPlayer.Delegate

extension SFBPlaybackBackend: AudioPlayer.Delegate {

    func audioPlayer(_ audioPlayer: AudioPlayer, renderingWillStart decoder: PCMDecoding, at hostTime: UInt64) {
        if let url = decoder.inputSource.url {
            lastRenderStart = (url, hostTime)
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?) {
        guard let decoder = nowPlaying, let url = decoder.inputSource.url else { return }
        let probe = self.probe(url)
        // ⚠️ El orden importa: gapless se compara CONTRA la pista ANTERIOR, y
        // solo DESPUÉS la nueva pasa a ser la referencia.
        let gapless = willBeGapless(url)
        activeTrackProbe = probe
        let offset = startOffset(for: url)
        DispatchQueue.main.async { [weak self] in
            self?.onTrackChange?(url, offset, probe, gapless)
        }
    }

    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        DispatchQueue.main.async { [weak self] in
            self?.onEndOfAudio?()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        // Solo registro: AudioEngine es el dueño del estado isPlaying (dirige
        // play/pausa él); este evento sirve para ver transiciones AUTOMÁTICAS
        // (p. ej. stop interno de SFB tras una interrupción).
        AppLog.debug(.playback, "SFB: playbackStateChanged → \(playbackState)")
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, didSeek decoder: PCMDecoding, toFrame frame: AVAudioFramePosition) {
        pendingRestoreSeek = nil
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, decodingAborted decoder: PCMDecoding, error: Error, framesRendered: AVAudioFramePosition) {
        AppLog.error(.playback, error, context: "SFB: decodingAborted (\(decoder.inputSource.url?.lastPathComponent ?? "?"), \(framesRendered) frames)")
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        AppLog.error(.playback, error, context: "SFB: encounteredError")
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine, with format: AVAudioFormat) -> AVAudioNode {
        // SFB desconecta sourceNode, llama AQUÍ con el formato real de la
        // fuente y después conecta source → nodo devuelto con ese formato.
        // La cadena EQ/mono hasta mainMixer se (re)conecta dentro.
        let first = applyCustomizer(engine, format: format)
        DispatchQueue.main.async { [weak self] in
            self?.onGraphReconfigured?()
        }
        return first
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, audioEngineConfigurationChange userInfo: [AnyHashable: Any]?) {
        // Cambio de hardware (ruta/vasija): SFB ya reconectó su grafo; aquí
        // solo se refresca la telemetría de AudioEngine.
        AppLog.info(.playback, "SFB: audioEngineConfigurationChange (\(userInfo?.description ?? "sin userInfo"))")
        DispatchQueue.main.async { [weak self] in
            self?.onGraphReconfigured?()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, audioSessionInterruption userInfo: [AnyHashable: Any]?) {
        // SFB gestiona su propio ciclo de interrupción (para y reanuda). Los
        // observers de AVAudioSession de AudioEngine siguen mandando en la app;
        // aquí solo se deja constancia para auditar el orden en LogsView.
        AppLog.info(.playback, "SFB: audioSessionInterruption (\(userInfo?.description ?? "fin de interrupción"))")
        if userInfo == nil || userInfo?["AVAudioSessionInterruptionTypeKey"] != nil {
            DispatchQueue.main.async { [weak self] in
                self?.onInterruptionEnd?()
            }
        }
    }
}
