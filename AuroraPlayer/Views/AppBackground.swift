import SwiftUI

struct AppBackground: View {
    var body: some View {
        // Modern mesh gradient background
        ZStack {
            // Base gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground).opacity(0.4)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Accent color gradient blob
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 500
            )
            
            // Secondary color gradient blob
            RadialGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 400
            )
            
            // Purple accent blob
            RadialGradient(
                colors: [
                    Color.purple.opacity(0.04),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
    }
}