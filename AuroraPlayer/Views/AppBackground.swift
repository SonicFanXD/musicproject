import SwiftUI

struct AppBackground: View {
    var body: some View {
        // Enhanced iOS 16 native background with subtle gradient
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle accent gradient overlay for depth
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.03),
                    Color.clear,
                    Color.accentColor.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}