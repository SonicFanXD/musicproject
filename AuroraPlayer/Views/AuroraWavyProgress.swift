import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — indicador de progreso ONDULADO de Material 3
// Expressive (M3E), nativo en SwiftUI y pensado para el A11.
//
// CÓMO SE ANIMA LA ONDA (y por qué así):
//
// 1. La forma de la onda es ESTÁTICA. `AuroraWavyLine` dibuja una sinusoide
//    periódica que cubre `ancho + λ` (una longitud de onda de más). NO se
//    regenera por frame: `animatableData` solo interpola la AMPLITUD, que es
//    lo único que cambia de geometría (aplanar al pausar, erizar al reproducir).
//
// 2. El MOVIMIENTO es una traslación. La vista de la onda se desplaza de 0 a
//    −λ con una animación lineal `repeatForever`. Al ser una transformación
//    (`offset`), la GPU mueve la capa ya rasterizada: cero `Path`, cero
//    layout, cero CPU de dibujo por frame. El salto de −λ a 0 al cerrar el
//    ciclo es INVISIBLE porque λ es exactamente el periodo de la sinusoide
//    (el patrón en x y en x+λ es idéntico).
//
//    ⚠️ Nota de ingeniería: animar `phase` dentro de `animatableData` (la
//    opción "de libro") obliga a SwiftUI a recalcular el `Path` completo en el
//    hilo principal 60 veces por segundo. En el A11 eso es exactamente lo que
//    este proyecto prohíbe. Aquí la fase existe como parámetro de forma
//    (constante) y la periodicidad la aporta la traslación.
//
// 3. El AVANCE no toca la onda: se recorta con una máscara de cápsula cuyo
//    ancho es `ancho × progreso`. Es un cambio de layout de un rectángulo
//    (baratísimo) que ocurre al ritmo del reloj (≈0.4 s), no por frame.
//    Durante el scrub el padre actualiza el progreso a 60 fps: la máscara
//    sigue el dedo sin animación (1:1) y la onda se aplana, así que no hay
//    trabajo de dibujo que hacer.
//
// 4. BATERÍA: en pausa se retira el `repeatForever` (no queda un bucle
//    animando opacidades o geometría en segundo plano) y la amplitud cae a 0
//    con el spring estándar de la app: la barra se aplana sola, como en M3E.
//    Con "Reducir movimiento" activo no hay desplazamiento de onda en absoluto.
//
// 5. CERO blurs / materiales: pista sólida (`SurfaceVariant`) y trazo de
//    acento. Nada de `.shadow` por frame dentro de la onda (solo el thumb, que
//    es una capa estática de 12-16 pt).
//
// Requisitos: iOS 16.0 (no usa ninguna API posterior). Componente
// PRESENTACIONAL: el gesto de scrub y el seek siguen viviendo en el padre,
// que solo le pasa `progress`, `isPlaying` e `isScrubbing`.
// ═══════════════════════════════════════════════════════════════════════════

// MARK: - Forma de la onda (estática + amplitud animable)

/// Sinusoide periódica que ocupa `rect.width` y se sale `waveLength` por la
/// derecha. El llamador le da un frame `ancho + λ` y lo traslada; así el borde
/// derecho nunca queda vacío en ningún punto del ciclo.
struct AuroraWavyLine: Shape {
    /// Semiamplitud en puntos (0 = línea recta). Es el ÚNICO dato animable:
    /// la transición reproducir ↔ pausa interpola aquí, con spring.
    var amplitude: CGFloat
    /// Longitud de onda en puntos. También es la distancia del bucle de
    /// traslación, así que debe coincidir con la que use la vista.
    var waveLength: CGFloat
    /// Fase inicial en radianes (constante; el movimiento NO va por aquí).
    var phase: CGFloat = 0

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let span = max(rect.width, 1)
        let midY = rect.midY
        let lambda = max(waveLength, 1)
        // Paso de ~3 pt: suficiente para que la curva se vea lisa en pantalla
        // retina y ~130 puntos en un ancho de 400 pt. Se calcula UNA vez por
        // cambio de geometría (layout), no por frame.
        let steps = max(8, Int(span / 3))
        let dx = span / CGFloat(steps)
        let k = (2 * CGFloat.pi) / lambda

        func y(at x: CGFloat) -> CGFloat {
            midY + amplitude * sin(k * x + phase)
        }

        path.move(to: CGPoint(x: 0, y: y(at: 0)))
        for step in 1...steps {
            let x = CGFloat(step) * dx
            path.addLine(to: CGPoint(x: x, y: y(at: x)))
        }
        return path
    }
}

// MARK: - Componente

struct AuroraWavyProgress: View {
    /// 0…1. El componente lo acota; el padre puede pasarlo con más rango.
    let progress: Double
    /// Conduce la onda: al pausar se aplana y se detiene el bucle.
    var isPlaying: Bool
    /// El padre lo pone a true mientras arrastra: el thumb crece y el
    /// seguimiento es 1:1 (sin animación de posición).
    var isScrubbing: Bool = false

    /// Grosor del trazo. M3E usa trazos gruesos; en la PlayerBar (compacta)
    /// el padre puede bajarlo a 4.
    var thickness: CGFloat = 5
    /// Semiamplitud de la onda. Debe caber en el alto que el padre reserve:
    /// alto ≥ thickness + 2 × amplitude.
    var amplitude: CGFloat = 1.8
    var waveLength: CGFloat = 24
    /// Duración de un ciclo completo de traslación (0 → −λ). M3E se mueve
    /// despacio: 1.4 s por ciclo da ese vaivén calmado, no un "loading".
    var wavePeriod: Double = 1.4

    /// Dos paradas de acento (identidad Aurora: nunca un color plano).
    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.45)]
    /// `SurfaceVariant` tonal: la pista inactiva es sólida, sin material.
    var trackColor: Color = Color.secondary.opacity(0.18)

    var showsThumb: Bool = true
    var thumbColor: Color = .white
    var thumbSize: CGFloat = 12
    /// Punto de parada al final de la pista (detalle M3E opcional).
    var showsStopIndicator: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveShift: CGFloat = 0

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    /// Amplitud objetivo: 0 en pausa o con Reducir movimiento. La transición
    /// la anima `AuroraMotion.normal` sobre el `animatableData` de la forma.
    private var targetAmplitude: CGFloat {
        (isPlaying && !reduceMotion) ? amplitude : 0
    }

    private var targetTrackHeight: CGFloat {
        thickness
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, targetTrackHeight)

            ZStack(alignment: .leading) {
                // Pista: sólida, sin blur (SurfaceVariant).
                Capsule()
                    .fill(trackColor)
                    .frame(width: width, height: targetTrackHeight)

                // Onda activa, recortada al progreso. El grosor del recorte
                // vertical es el alto completo: los extremos de la cápsula
                // redondean el corte, no lo dejan plano.
                wave(width: width, height: height)
                    .mask(alignment: .leading) {
                        Capsule()
                            .frame(width: max(0, width * clampedProgress), height: height)
                    }

                if showsStopIndicator {
                    Circle()
                        .fill(trackColor)
                        .frame(width: targetTrackHeight * 0.7, height: targetTrackHeight * 0.7)
                        .position(x: width - targetTrackHeight * 0.35, y: height / 2)
                        .allowsHitTesting(false)
                }

                if showsThumb && thumbVisible {
                    thumbView
                        .position(x: width * clampedProgress, y: height / 2)
                }
            }
            .frame(width: width, height: height)
        }
        .onAppear { syncWave() }
        .onChange(of: isPlaying) { _ in syncWave() }
        .onChange(of: reduceMotion) { _ in syncWave() }
    }

    // MARK: - Waved layer

    @ViewBuilder
    private func wave(width: CGFloat, height: CGFloat) -> some View {
        AuroraWavyLine(amplitude: targetAmplitude, waveLength: waveLength)
            .stroke(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: targetTrackHeight, lineCap: .round, lineJoin: .round)
            )
            // λ extra a la derecha para que la traslación nunca descubra hueco.
            .frame(width: width + waveLength, height: height, alignment: .leading)
            // ✅ Movimiento = transformación GPU (no regenera el Path).
            .offset(x: waveShift)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            // ✅ La ÚNICA animación de geometría: aplanar / erizar con spring.
            .animation(AuroraMotion.normal, value: targetAmplitude)
    }

    // MARK: - Thumb

    private var thumbVisible: Bool {
        isScrubbing || (clampedProgress > 0.01 && clampedProgress < 0.99)
    }

    private var thumbView: some View {
        Circle()
            .fill(thumbColor)
            .frame(width: thumbSize, height: thumbSize)
            .overlay {
                Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            }
            // Sombra pequeña y estática: separa el thumb de la onda sin blur
            // grande ni material (una capa de 12-16 pt, no se recalcula).
            .shadow(color: .black.opacity(isScrubbing ? 0.28 : 0.16),
                    radius: isScrubbing ? 5 : 3, x: 0, y: 2)
            // ✅ Feedback elástico al agarrar (mismo spring expresivo de M3E).
            .scaleEffect(isScrubbing ? 1.38 : 1)
            .animation(AuroraMotion.emphasized, value: isScrubbing)
            // Avance normal del reloj: suavizado corto. Durante el scrub, 1:1.
            .animation(isScrubbing ? nil : .linear(duration: 0.25), value: clampedProgress)
            .allowsHitTesting(false)
    }

    // MARK: - Ciclo de la onda

    /// Arranca/para el bucle de traslación. Nunca se llama desde `body`.
    private func syncWave() {
        guard isPlaying, !reduceMotion else {
            stopWave()
            return
        }
        // Reinicio sin animación (el valor anterior puede estar a mitad de
        // ciclo): un `Transaction` sin animaciones evita el "salto" visible
        // que produciría heredar la transacción en curso.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { waveShift = 0 }

        withAnimation(.linear(duration: wavePeriod).repeatForever(autoreverses: false)) {
            waveShift = -waveLength
        }
    }

    private func stopWave() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { waveShift = 0 }
    }
}

// MARK: - Preview (solo para diseño; no se ejecuta en la app)

#if DEBUG
struct AuroraWavyProgress_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            AuroraWavyProgress(progress: 0.42, isPlaying: true)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.68, isPlaying: true, isScrubbing: true)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.2, isPlaying: false)
                .frame(height: 18)
            AuroraWavyProgress(progress: 1, isPlaying: false, thickness: 3, amplitude: 1, waveLength: 18)
                .frame(height: 12)
        }
        .padding(32)
        .background(Color(UIColor.systemBackground))
    }
}
#endif
