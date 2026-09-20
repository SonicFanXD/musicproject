import SwiftUI

// MARK: - Vista de lyrics línea por línea con animación SpotiFLAC-style
// ✅ Diseño: ScrollView + LazyVStack para máximo rendimiento (60 fps)
// ✅ Animación de relleno progresivo: línea oscura que se "ilumina" de izquierda a derecha
// ✅ CADisplayLink a 60 Hz en ViewModel para interpolación fluida
// ✅ Aislamiento de rendimiento: solo línea activa anima a 60 fps
// ✅ Padding vertical generoso (200 pt) para centrar primera/última línea
// ✅ Render 100% por código, sin assets
// ✅ PROHIBIDO: APIs de iOS 17+ (MeshGradient, scrollTargetBehavior, etc.)
struct LyricsView: View {
    let song: Song?
    @ObservedObject var viewModel: LyricsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var scrollTarget: Int? = nil
    
    var body: some View {
        ZStack {
            blurredArtworkBackground
            
            VStack(spacing: 0) {
                // Header transparente
                headerView
                
                Group {
                    if !viewModel.hasLyrics {
                        emptyLyricsView
                    } else {
                        lyricsContentView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            #if DEBUG
            // ✅ DEBUG: Overlay para diagnóstico de lyrics
            debugOverlay
                .padding(8)
            #endif
        }
        .onAppear {
            parseLyricsIfNeeded()
        }
        // ✅ iOS 16 onChange clásico: scroll solo cuando cambia activeLineID
        .onChange(of: viewModel.activeLineID) { newID in
            if let newID = newID {
                scrollTarget = newID
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
            
            Spacer()
            
            Text("Letras")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            
            Spacer()
            
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - Contenido de lyrics
    private var lyricsContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // ✅ Padding vertical generoso (200 pt) para centrar primera/última línea
                    Color.clear.frame(height: 200)
                    
                    ForEach(viewModel.lyricsLines) { line in
                        let isActive = viewModel.activeLineID == line.id
                        let progress = isActive ? viewModel.progress : 0.0
                        
                        if isActive {
                            // ✅ Línea activa con animación de relleno progresivo
                            animatedLyricLine(line: line, progress: progress)
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    seekToLine(line)
                                }
                        } else {
                            // ✅ Línea inactiva estática (sin animación a 60 fps)
                            staticLyricLine(line: line)
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    seekToLine(line)
                                }
                        }
                    }
                    
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 24)
            }
            // ✅ iOS 16 onChange clásico: scroll suave solo cuando cambia scrollTarget
            .onChange(of: scrollTarget) { target in
                if let target = target {
                    // ✅ Animación suave solo cuando cambia la línea activa
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Línea animada con relleno progresivo (SpotiFLAC-style)
    // ✅ Solo la línea activa tiene esta complejidad (renderizado a 60 fps)
    // ✅ Dos capas de Text superpuestas: base atenuada + superior brillante con máscara
    private func animatedLyricLine(line: LyricsLine, progress: Double) -> some View {
        ZStack(alignment: .leading) {
            // ✅ Capa base: texto atenuado (siempre visible)
            Text(line.cleanText)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            
            // ✅ Capa superior: texto brillante con máscara de relleno
            Text(line.cleanText)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                }
        }
    }
    
    // MARK: - Línea estática (inactiva)
    // ✅ Sin animación, renderizado estático para máximo rendimiento
    private func staticLyricLine(line: LyricsLine) -> some View {
        Text(line.cleanText)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
    
    // MARK: - Seek a línea
    private func seekToLine(_ line: LyricsLine) {
        guard let audioEngine = viewModel.audioEngine else { return }
        
        // ✅ Seek al inicio de la línea
        let seekTime = TimeInterval(line.startMs) / 1000.0
        audioEngine.seek(to: seekTime)
        
        // ✅ Recalcular línea activa inmediatamente
        viewModel.handleSeek()
    }
    
    // MARK: - Fondo difuminado
    private var blurredArtworkBackground: some View {
        GeometryReader { geometry in
            Group {
                if let artwork = song?.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .opacity(0.4)
                        .overlay(Color(UIColor.systemBackground).opacity(0.72))
                } else {
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.12), Color(UIColor.systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
    }
    
    // MARK: - Vista vacía
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Esta canción no tiene letras")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Parse lyrics
    private func parseLyricsIfNeeded() {
        guard let song = song else { return }
        
        // ✅ Usar lyrics del modelo de canción (ya parseado en FileAccessService)
        let lyrics = song.lyrics
        if !lyrics.isEmpty {
            viewModel.parseLyrics(lyrics)
        } else {
            viewModel.hasLyrics = false
        }
    }
    
    #if DEBUG
    // MARK: - Debug Overlay
    /// Overlay temporal para diagnóstico de lyrics
    /// Muestra en tiempo real el estado del ViewModel para identificar bugs
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LYRICS DEBUG")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
            
            Text("activeLineID: \(String(describing: viewModel.activeLineID))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.green)
            
            Text("Total lines: \(viewModel.lyricsLines.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.green)
            
            if !viewModel.lyricsLines.isEmpty {
                Text("First line id: \(viewModel.lyricsLines.first?.id ?? -1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                
                Text("Last line id: \(viewModel.lyricsLines.last?.id ?? -1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                
                let activeCount = viewModel.lyricsLines.filter { viewModel.activeLineID == $0.id }.count
                Text("isActive count: \(activeCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
        .frame(maxWidth: 200, alignment: .leading)
    }
    #endif
}

// MARK: - Preview
#if DEBUG
struct LyricsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LyricsViewModel()
        viewModel.parseLyrics("""
        [00:01.00]Primera línea de prueba
        [00:05.50]Segunda línea de prueba
        [00:10.00]Tercera línea de prueba
        """)
        
        return LyricsView(song: nil, viewModel: viewModel)
    }
}
#endif
