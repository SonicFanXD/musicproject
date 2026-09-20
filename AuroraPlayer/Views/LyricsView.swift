import SwiftUI

// MARK: - Vista de lyrics línea por línea (optimizada para iPhone 8 Plus)
// ✅ Diseño: ScrollView + LazyVStack para máximo rendimiento (60 fps)
// ✅ Línea activa en blanco opaco, líneas inactivas atenuadas
// ✅ Auto-scroll suave con ScrollViewReader
// ✅ Padding vertical generoso (200 pt) para centrar primera/última línea
// ✅ Render 100% por código, sin assets
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
        }
        .onAppear {
            parseLyricsIfNeeded()
        }
        .onChange(of: viewModel.activeID) { newID in
            // ✅ Scroll solo cuando cambia la línea activa, no en cada frame
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
                    // ✅ Padding vertical generoso para centrar primera/última línea
                    Color.clear.frame(height: 200)
                    
                    ForEach(viewModel.lyricsLines) { line in
                        lyricLineView(line: line, isActive: viewModel.activeID == line.id)
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                seekToLine(line)
                            }
                    }
                    
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 24)
            }
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
    
    // MARK: - Vista de línea individual
    private func lyricLineView(line: LyricsLine, isActive: Bool) -> some View {
        Text(line.cleanText)
            .font(.system(size: isActive ? 24 : 18, weight: isActive ? .bold : .medium))
            .foregroundStyle(isActive ? .white : .white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            // ✅ Animación solo cuando cambia el estado de activación
            .animation(.easeInOut(duration: 0.2), value: isActive)
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
        if let lyrics = song.lyrics, !lyrics.isEmpty {
            viewModel.parseLyrics(lyrics)
        } else {
            viewModel.hasLyrics = false
        }
    }
}

// MARK: - Preview
#if DEBUG
struct LyricsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LyricsViewModel(audioEngine: AudioEngine())
        viewModel.parseLyrics("""
        [00:01.00]Primera línea de prueba
        [00:05.50]Segunda línea de prueba
        [00:10.00]Tercera línea de prueba
        """)
        
        return LyricsView(song: nil, viewModel: viewModel)
    }
}
#endif
