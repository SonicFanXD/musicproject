import SwiftUI

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}