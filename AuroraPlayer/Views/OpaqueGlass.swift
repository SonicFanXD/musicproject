import SwiftUI

// Liquid glass style - clean, no glowing borders, optimized for performance
extension View {
    func nativeGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    func nativeGlassCapsule() -> some View {
        self.background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }

    func nativeThinGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    func enhancedGlass(cornerRadius: CGFloat = 16) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
