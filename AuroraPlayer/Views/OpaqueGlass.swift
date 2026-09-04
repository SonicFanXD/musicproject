import SwiftUI

// iOS 16 native materials using system framework
extension View {
    func nativeGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    func nativeGlassCapsule() -> some View {
        self.background {
            Capsule()
                .fill(.regularMaterial)
        }
    }

    func nativeThinGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        }
    }

    func nativeUltraThinGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
