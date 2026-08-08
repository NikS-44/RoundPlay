import SwiftUI

/// Destructive outline control — same geometry as `AccentOutlineButtonStyle` (continuous corners, 2pt stroke).
struct RedOutlineButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RoundPlayColors.destructive)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(RoundPlayColors.destructive, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
