import SwiftUI

struct AppBackground: View {
    var body: some View {
        // Full-bleed gradient that extends behind navigation bars
        LinearGradient(
            colors: [
                Color(UIColor.systemBackground),
                Color(UIColor.secondarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}