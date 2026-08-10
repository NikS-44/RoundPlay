import SwiftUI
import RoundPlayEngine

/// Pick games and set the stake for each.
struct GameSetupView: View {
    @Bindable var model: NewRoundModel
    let onStart: () -> Void
    /// False when reused as a standalone "edit games" sheet (e.g. Play Again) rather than the
    /// last step of the round builder — hides the "Step 6 of 6" chrome that wouldn't apply there.
    var showsStepHeader: Bool = true
    var continueButtonTitle: String = "Start Round"
    @State private var stakes: [GameType: Decimal] = [:]

    var body: some View {
        VStack(spacing: 0) {
            RoundPlayList.plain {
                if showsStepHeader {
                    RoundBuilderStepHeader(
                        step: 6,
                        totalSteps: 6,
                        title: "What games do you want to play?",
                        detail: "\(model.seats.count) players"
                    )
                }

                Section {
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
                            holeCount: model.holeSegment.holeRange.count,
                            onToggle: { toggle(metadata.gameType) }
                        )
                        .roundPlayListRowSeparatorFullWidth()
                    }
                    if isSelected(.bestBall) {
                        BestBallTeamPicker(model: model)
                            .roundPlayListRowSeparatorFullWidth()
                    }
                } header: {
                    Text("Games")
                        .font(RoundPlayFont.archivo(15, .bold))
                        .foregroundStyle(RoundPlayColors.accent)
                } footer: {
                    RoundPlayTypography.caption("Optional — pick none and it's still a normal scorecard, just no side bets.")
                        .foregroundStyle(.secondary)
                }
            }

            RoundBuilderContinueButton(title: continueButtonTitle, isEnabled: model.canStart, action: onStart)
        }
        .navigationTitle("Games")
        .onAppear {
            if let existingBestBall = model.configurations.compactMap({ configuration in
                if case .bestBall(let config) = configuration { return config }
                return nil
            }).first {
                model.bestBallTeamA = existingBestBall.teamASeatPositions
            }
            for configuration in model.configurations {
                stakes[configuration.gameType] = configuration.unitStake
            }
            guard let preselected = model.preselectedGameType,
                  model.eligibleGames.contains(where: { $0.gameType == preselected }),
                  !isSelected(preselected)
            else { return }
            toggle(preselected)
        }
    }

    private func isSelected(_ type: GameType) -> Bool {
        model.configurations.contains { $0.gameType == type }
    }

    private func stakeBinding(for type: GameType) -> Binding<Decimal> {
        Binding(
            get: { stakes[type] ?? 1 },
            set: { stakes[type] = $0; rebuild(type) }
        )
    }

    private func toggle(_ type: GameType) {
        if isSelected(type) {
            model.configurations.removeAll { $0.gameType == type }
        } else {
            model.configurations.append(configuration(for: type, stake: stakes[type] ?? 1))
        }
    }

    private func rebuild(_ type: GameType) {
        guard isSelected(type) else { return }
        model.configurations.removeAll { $0.gameType == type }
        model.configurations.append(configuration(for: type, stake: stakes[type] ?? 1))
    }

    /// Defaults come from each engine's documented convention, not from the UI's imagination.
    private func configuration(for type: GameType, stake: Decimal) -> GameConfiguration {
        switch type {
        case .strokePlay: .strokePlay(StrokePlayConfig())
        case .matchPlay: .matchPlay(MatchPlayConfig(unitStake: stake))
        case .bestBall: .bestBall(BestBallConfig(unitStake: stake, teamASeatPositions: model.bestBallTeamA))
        case .skins: .skins(SkinsConfig(unitStake: stake))
        case .nassau: .nassau(NassauConfig(unitStake: stake))
        case .stableford: .stableford(StablefordConfig(unitStake: stake))
        case .nines: .nines(NinesConfig(unitStake: stake))
        case .wolf: .wolf(.standard(unitStake: stake))
        case .bingoBangoBongo: .bingoBangoBongo(BingoBangoBongoConfig(unitStake: stake))
        }
    }
}

private struct BestBallTeamPicker: View {
    @Bindable var model: NewRoundModel

    var body: some View {
        Section {
            Text("Choose Team A. The other two players are Team B.")
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(.secondary)
            ForEach(Array(model.seats.enumerated()), id: \.offset) { index, seat in
                Button {
                    guard model.bestBallTeamA.contains(index) || model.bestBallTeamA.count < 2 else { return }
                    if model.bestBallTeamA.contains(index) {
                        model.bestBallTeamA.remove(index)
                    } else {
                        model.bestBallTeamA.insert(index)
                    }
                    if model.bestBallTeamA.count == 2, let bestBall = model.configurations.firstIndex(where: { $0.gameType == .bestBall }) {
                        model.configurations[bestBall] = .bestBall(BestBallConfig(unitStake: model.configurations[bestBall].unitStake, teamASeatPositions: model.bestBallTeamA))
                    }
                } label: {
                    HStack {
                        Image(systemName: model.bestBallTeamA.contains(index) ? "checkmark.circle.fill" : "circle")
                        Text(seat.displayName)
                        Spacer()
                        Text(model.bestBallTeamA.contains(index) ? "Team A" : "Team B")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Best Ball Teams")
                .font(RoundPlayFont.archivo(15, .bold))
                .foregroundStyle(RoundPlayColors.accent)
        } footer: {
            Text("Two players per team.")
        }
    }
}

private struct GameSelectionRow: View {
    let metadata: GameMetadata
    let isSelected: Bool
    @Binding var stake: Decimal
    let holeCount: Int
    let onToggle: () -> Void
    @State private var stakeText: String = ""
    @FocusState private var isStakeFocused: Bool

    /// A rough "worst case" unit multiplier per game, so the exposure row is an honest estimate
    /// rather than a made-up number. Nassau is the one figure golfers actually agree on — stake ×
    /// 3 for front/back/overall with no presses. The others don't have one universal convention
    /// (Skins carryovers in particular can run higher depending on house rules), so this floors on
    /// "every hole pays out once," which is the same shape every group already reasons in.
    private var worstCaseMultiplier: Decimal {
        switch metadata.gameType {
        case .strokePlay: 0
        case .matchPlay: 1
        case .bestBall: Decimal(holeCount)
        case .nassau: 3
        case .wolf: Decimal(holeCount) * 4
        case .bingoBangoBongo: Decimal(holeCount) * 3
        case .skins, .stableford, .nines: Decimal(holeCount)
        }
    }

    private var maxExposure: Decimal { stake * worstCaseMultiplier }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? RoundPlayColors.accent : .secondary)
                    Image(systemName: metadata.iconName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        RoundPlayTypography.headline(metadata.displayName)
                        RoundPlayTypography.caption(metadata.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack {
                    RoundPlayTypography.eyebrow(metadata.gameType == .strokePlay ? "No wager" : "Stake")
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Free-form, not a picker — a $1–100 wheel bakes in an assumption about scale
                    // that isn't ours to make; some groups play for a dollar, some for fifty.
                    if metadata.gameType != .strokePlay {
                        HStack(spacing: 2) {
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $stakeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isStakeFocused)
                                .frame(width: 56)
                                .onChange(of: stakeText) { _, newValue in
                                    stake = Decimal(string: newValue) ?? stake
                                }
                        }
                        .font(RoundPlayFont.plexMono(15, .semiBold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(RoundPlayColors.fillSecondary))
                        .onTapGesture { isStakeFocused = true }
                    }
                }

                if metadata.gameType != .strokePlay { HStack {
                    RoundPlayTypography.eyebrow("Up For Grabs")
                        .foregroundStyle(.secondary)
                    Spacer()
                    RoundPlayTypography.money(maxExposure.formatted(.currency(code: "USD")), size: 14)
                        .foregroundStyle(.secondary)
                } }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            stakeText = stake.formatted(.number.precision(.fractionLength(0...2)))
        }
    }
}

#Preview("Light") {
    let model = NewRoundModel()
    return NavigationStack { GameSetupView(model: model, onStart: {}) }
}
