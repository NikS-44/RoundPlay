import SwiftUI

// MARK: - Hub section header

/// Uppercase footnote header used inside `RoundPlayList.plain` sections so grouped content reads
/// as titled sections without pulling in a full `Section` header/footer.
struct HubSectionLabel: View {
    let title: String

    var body: some View {
        RoundPlayTypography.eyebrow(title)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 2, trailing: 16))
    }
}

// MARK: - List section header

/// The header for a `Section` inside a `RoundPlayList`.
///
/// Bold Archivo in the accent green rather than the 9.5pt mono eyebrow. The eyebrow works as a
/// label sitting on a dark card, where it has contrast to spare, but as a section header on a
/// white list it reads as barely-there grey — which is exactly wrong for an app used in direct
/// sun, and the first thing anyone says about it is that they can't see it.
struct RoundPlaySectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(RoundPlayFont.archivo(15, .bold))
            .foregroundStyle(RoundPlayColors.accent)
    }
}

// MARK: - Hub row

/// Icon + title + subtitle list row used by "pick a destination" screens.
struct HubRow: View {
    let icon: String
    let title: String
    let subtitle: String
    /// Font weight for the title; defaults to `.semibold`.
    var titleWeight: RoundPlayFont.Weight = .semiBold
    /// When true, draws a trailing chevron. `NavigationLink` already draws its own, so this
    /// defaults to off; set true when wrapping in a plain `Button` that doesn't push a view.
    var showsChevron: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RoundPlayFont.archivo(16, titleWeight))
                RoundPlayTypography.caption(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Round builder step header

/// "Step X of N" + a big question-style title, used at the top of every screen in the new-round
/// flow so each step reads with the same weight instead of only the player-count step standing out.
struct RoundBuilderStepHeader: View {
    let step: Int
    let totalSteps: Int
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.map { "Step \(step) of \(totalSteps) · \($0)" } ?? "Step \(step) of \(totalSteps)")
                .font(RoundPlayFont.archivo(15, .bold))
                .foregroundStyle(RoundPlayColors.accent)
            RoundPlayTypography.largeTitle(title)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
    }
}

/// The primary action for a round-builder step, pinned to the same spot at the bottom of every
/// screen in the flow — never a nav-bar toolbar button, so "how do I move on" never changes shape.
struct RoundBuilderContinueButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RoundPlayFont.archivo(20, .bold))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .roundPlayPrimaryButtonStyle()
        .tint(RoundPlayColors.accent)
        .disabled(!isEnabled)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

// MARK: - Chip button

/// Capsule chip used for selectable options — game picks, Wolf partner choice, Bingo Bango Bongo
/// award assignment. Selected uses a muted accent fill that reads well in dark mode.
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let sym = systemImage {
                    Image(systemName: sym)
                        .font(.caption2)
                }
                Text(title)
                    .font(RoundPlayFont.archivo(13, .medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(0.7)
                        : RoundPlayColors.fillSecondary
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented pill

/// Horizontal capsule-style segmented selector. One pill per case; selected fills with the accent
/// color. Prefer this over inlining the accent-vs-`fillTertiary` pattern per call site.
struct SegmentedPill<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var animation: Animation? = .easeInOut(duration: 0.2)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    if let animation {
                        withAnimation(animation) { selection = option }
                    } else {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(RoundPlayFont.archivo(15, .medium))
                        .foregroundStyle(selection == option ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(selection == option ? Color.accentColor.opacity(0.7) : RoundPlayColors.fillTertiary)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Themed card background

/// Fill style for `.themedCard(...)` backgrounds. Maps to the `RoundPlayColors` fill tokens.
enum ThemedCardFill {
    /// `RoundPlayColors.fillSecondary` — thumbnail placeholders, inline chips, small cards.
    case secondaryFill
    /// `RoundPlayColors.fillTertiary` — a layered chip on top of a card that already uses `secondaryFill`.
    case tertiaryFill
    /// `RoundPlayColors.backgroundSecondaryGrouped` — large section cards.
    case secondaryBackground

    var color: Color {
        switch self {
        case .secondaryFill: return RoundPlayColors.fillSecondary
        case .tertiaryFill: return RoundPlayColors.fillTertiary
        case .secondaryBackground: return RoundPlayColors.backgroundSecondaryGrouped
        }
    }
}

/// Rounded themed background used across cards so the rounding + fill stay consistent.
struct ThemedCardBackground: ViewModifier {
    let cornerRadius: CGFloat
    let fill: ThemedCardFill
    let strokeOpacity: Double?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill.color)
            )
            .modifier(OptionalStrokeBorder(cornerRadius: cornerRadius, opacity: strokeOpacity))
    }
}

private struct OptionalStrokeBorder: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double?

    func body(content: Content) -> some View {
        if let opacity {
            content.overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(opacity), lineWidth: 1)
            )
        } else {
            content
        }
    }
}

extension View {
    /// Board-surfaced card (the near-black featured cards: in-progress round, round summary hero).
    ///
    /// `board` is a fixed near-black, and dark mode's page background is pure black — so without a
    /// hairline edge these cards lose almost all separation from the page and read as a floating
    /// block of text rather than a card. The border is tuned to be near-invisible on light mode's
    /// cream page, where the fill already does the separating.
    func boardCard(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(RoundPlayColors.board)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(RoundPlayColors.paperOnBoard.opacity(0.12), lineWidth: 1)
        )
    }

    /// Apply a rounded themed fill (and optional hairline border) to a view.
    func themedCard(
        cornerRadius: CGFloat,
        fill: ThemedCardFill = .secondaryFill,
        strokeOpacity: Double? = nil
    ) -> some View {
        modifier(ThemedCardBackground(cornerRadius: cornerRadius, fill: fill, strokeOpacity: strokeOpacity))
    }
}

// MARK: - Flow layout (wrapping chip grid)

/// Wraps children onto multiple rows like text. Used for the Wolf partner picker and Bingo Bango
/// Bongo award chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: max(0, maxRowWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
