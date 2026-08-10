import SwiftUI
import RoundPlayEngine

/// The Wolf's per-hole decision, shown before scores are entered.
///
/// Rendered whenever any active game declares `.partnerChoice` — this view is reached through the
/// input declaration, not through a check for "is this Wolf".
struct WolfPromptView: View {
    let wolfName: String
    let candidates: [(id: UUID, name: String)]
    let declaration: WolfDeclaration?
    let onDeclare: (WolfDeclaration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundPlayTypography.eyebrow("Decide first")
                .foregroundStyle(RoundPlayColors.pin)

            RoundPlayTypography.headline("\(wolfName) is the Wolf")

            RoundPlayTypography.caption("Pick a partner after their tee shot, or go it alone for quadruple points.")
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(candidates, id: \.id) { candidate in
                    WolfOptionRow(
                        title: candidate.name,
                        subtitle: nil,
                        isSelected: declaration == .partner(candidate.id)
                    ) {
                        onDeclare(.partner(candidate.id))
                    }
                }
                WolfOptionRow(
                    title: "Lone Wolf",
                    subtitle: "Quadruple points",
                    isSelected: declaration == .lone
                ) {
                    onDeclare(.lone)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// One full-width, easy-to-hit choice — a partner or "Lone Wolf" — stacked with the others instead
/// of a row of small chips that are fussy to tap and don't leave room for a subtitle.
private struct WolfOptionRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? RoundPlayColors.accent : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(RoundPlayFont.archivo(16, .semiBold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(RoundPlayFont.archivo(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? RoundPlayColors.accent.opacity(0.12) : RoundPlayColors.fillSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? RoundPlayColors.accent : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light") {
    WolfPromptView(
        wolfName: "Ann",
        candidates: [(UUID(), "Ben"), (UUID(), "Cal"), (UUID(), "Dee")],
        declaration: nil
    ) { _ in }
    .padding()
}

#Preview("Dark") {
    WolfPromptView(
        wolfName: "Ann",
        candidates: [(UUID(), "Ben"), (UUID(), "Cal"), (UUID(), "Dee")],
        declaration: .lone
    ) { _ in }
    .padding()
    .preferredColorScheme(.dark)
}
