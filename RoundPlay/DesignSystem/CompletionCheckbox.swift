import SwiftUI

/// Shared checkbox for list rows (circle / checkmark.circle.fill) — used for hole-complete
/// indicators and any other binary done/not-done state.
struct CompletionCheckbox: View {
    let isCompleted: Bool
    var isOverdue: Bool = false
    var isDisabled: Bool = false
    var style: Style = .listLarge

    enum Style {
        case listLarge
        case compact
        case chip

        var font: Font {
            switch self {
            case .listLarge: return .title2
            case .compact: return .title3
            case .chip: return .caption
            }
        }

        var minSize: CGFloat {
            switch self {
            case .listLarge: return 44
            case .compact: return 28
            case .chip: return 22
            }
        }
    }

    private var foreground: Color {
        if isCompleted { return RoundPlayColors.scoreUnderPar }
        if isOverdue { return RoundPlayColors.scoreOverPar }
        return RoundPlayColors.holePending
    }

    var body: some View {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
            .font(style.font)
            .foregroundStyle(foreground)
            .opacity(isDisabled ? 0.35 : 1)
            // Snappy feedback: avoid default symbol bounce/replace (feels slow on lists).
            .animation(.easeOut(duration: 0.12), value: isCompleted)
    }
}
