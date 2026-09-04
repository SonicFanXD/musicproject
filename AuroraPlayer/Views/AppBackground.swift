import SwiftUI

struct AppBackground: View {
    var body: some View {
        // Simplified background for better performance on iPhone 8 Plus
        LinearGradient(
            gradient: Gradient(colors: [
                Color(UIColor.systemBackground),
                Color(UIColor.secondarySystemBackground).opacity(0.3)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}