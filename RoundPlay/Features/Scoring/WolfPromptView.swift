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
            Text("\(wolfName) is the Wolf")
                .font(.subheadline.weight(.semibold))

            Text("Pick a partner after their tee shot, or go it alone for quadruple points.")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(candidates, id: \.id) { candidate in
                    ChipButton(
                        title: candidate.name,
                        isSelected: declaration == .partner(candidate.id)
                    ) {
                        onDeclare(.partner(candidate.id))
                    }
                }
                ChipButton(title: "Lone Wolf", isSelected: declaration == .lone) {
                    onDeclare(.lone)
                }
            }
        }
        .padding(.vertical, 8)
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
