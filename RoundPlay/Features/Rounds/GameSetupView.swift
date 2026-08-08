import SwiftUI
import RoundPlayEngine

/// Pick games and set the stake for each.
struct GameSetupView: View {
    @Bindable var model: NewRoundModel
    @State private var stakes: [GameType: Decimal] = [:]

    var body: some View {
        RoundPlayList.plain {
            if model.eligibleGames.isEmpty {
                ContentUnavailableView(
                    "No games for this group size",
                    systemImage: "person.2.slash",
                    description: Text("Add or remove a player to see available games.")
                )
            }

            ForEach(model.eligibleGames) { metadata in
                GameSelectionRow(
                    metadata: metadata,
                    isSelected: isSelected(metadata.gameType),
                    stake: stakeBinding(for: metadata.gameType),
                    onToggle: { toggle(metadata.gameType) }
                )
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Games")
    }

    private func isSelected(_ type: GameType) -> Bool {
        model.configurations.contains { $0.gameType == type }
    }

    private func stakeBinding(for type: GameType) -> Binding<Decimal> {
        Binding(
            get: { stakes[type] ?? 5 },
            set: { stakes[type] = $0; rebuild(type) }
        )
    }

    private func toggle(_ type: GameType) {
        if isSelected(type) {
            model.configurations.removeAll { $0.gameType == type }
        } else {
            model.configurations.append(configuration(for: type, stake: stakes[type] ?? 5))
        }
    }

    private func rebuild(_ type: GameType) {
        guard isSelected(type) else { return }
        model.configurations.removeAll { $0.gameType == type }
        model.configurations.append(configuration(for: type, stake: stakes[type] ?? 5))
    }

    /// Defaults come from each engine's documented convention, not from the UI's imagination.
    private func configuration(for type: GameType, stake: Decimal) -> GameConfiguration {
        switch type {
        case .skins: .skins(SkinsConfig(unitStake: stake))
        case .nassau: .nassau(NassauConfig(unitStake: stake))
        case .stableford: .stableford(StablefordConfig(unitStake: stake))
        case .nines: .nines(NinesConfig(unitStake: stake))
        case .wolf: .wolf(.standard(unitStake: stake))
        case .bingoBangoBongo: .bingoBangoBongo(BingoBangoBongoConfig(unitStake: stake))
        }
    }
}

private struct GameSelectionRow: View {
    let metadata: GameMetadata
    let isSelected: Bool
    @Binding var stake: Decimal
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? RoundPlayColors.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metadata.displayName).font(.headline)
                        Text(metadata.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack {
                    Text("Stake")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { NSDecimalNumber(decimal: stake).intValue },
                            set: { stake = Decimal($0) }
                        ),
                        in: 1...100
                    ) {
                        Text(stake, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Light") {
    let model = NewRoundModel()
    return NavigationStack { GameSetupView(model: model) }
}
