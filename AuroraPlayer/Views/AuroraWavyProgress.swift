import SwiftUI

struct AuroraWavyProgress: View {
    let progress: Double
    let isPlaying: Bool
    let isScrubbing: Bool
    
    // Acción opcional para cuando el usuario arrastra
    var onScrub: ((Double) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let midY = size.height / 2.0
                    
                    // 1. Dibujar la pista de fondo (línea gris)
                    var trackPath = Path()
                    trackPath.move(to: CGPoint(x: 0, y: midY))
                    trackPath.addLine(to: CGPoint(x: size.width, y: midY))
                    context.stroke(trackPath, with: .color(Color.secondary.opacity(0.2)), lineWidth: 4.0)
                    
                    // 2. Dibujar la onda de progreso
                    var wavePath = Path()
                    let amplitude: CGFloat = isPlaying ? 2.5 : 0.0 // Se aplana si está pausado
                    let frequency: CGFloat = 2.0 * .pi / 20.0 // Longitud de la onda
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 5.0
                    
                    let activeWidth = size.width * CGFloat(min(max(progress, 0), 1))
                    
                    if activeWidth > 0 {
                        wavePath.move(to: CGPoint(x: 0, y: midY))
                        
                        for x in stride(from: 0, through: activeWidth, by: 1.0) {
                            let y = midY + sin((x * frequency) + phase) * amplitude
                            wavePath.addLine(to: CGPoint(x: x, y: y))
                        }
                        
                        // Color de la onda (usando .accentColor por defecto)
                        context.stroke(wavePath, with: .color(.accentColor), lineWidth: 4.0)
                    }
                }
            }
            .frame(width: width, height: height)
            
            // 3. Dibujar el "Thumb" (el circulito que indica la posición)
            // Usamos GeometryReader para que se posicione exactamente en el ancho real
            Circle()
                .fill(Color.accentColor)
                .frame(width: isScrubbing ? 16 : 12, height: isScrubbing ? 16 : 12)
                .position(x: width * CGFloat(min(max(progress, 0), 1)), y: height / 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isScrubbing)
        }
        .frame(height: 24) // Altura fija segura para la barra
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let newProgress = value.location.x / max(1, UIScreen.main.bounds.width - 48) // Ajuste estimado
                    onScrub?(min(max(newProgress, 0), 1))
                }
        )
    }
}