import SwiftUI

struct AppBackground: View {
    var body: some View {
        // iOS 16 native background using system colors
        Color.clear
            .background {
                LinearGradient(
                    colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }
}