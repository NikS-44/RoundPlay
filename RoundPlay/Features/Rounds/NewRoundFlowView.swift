import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// Round setup: course, player count, who you know, fill in the rest, games. Every step is one
/// focused screen with one job — no scrolling past a stepper to find a list, no combined form.
struct NewRoundFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = NewRoundModel()
    @State private var path = NavigationPath()

    /// When launched from a game's rules screen, that game is pre-selected in step 3.
    var preselectedGameType: GameType?
    /// When launched from onboarding with a favorite already chosen, skip the course step.
    var startingCourse: CourseRecord?
    let onStart: (RoundRecord) -> Void

    private enum Step: Hashable { case playerCount, knownPlayers, fillRemaining, strokes, holes, games, bestBallTeams }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let startingCourse {
                    PlayerCountStep(
                        model: model,
                        onSolo: { path.append(Step.holes) },
                        onGroup: { path.append(Step.knownPlayers) }
                    )
                        .onAppear {
                            model.course = startingCourse
                            // Onboarding already picked the course, so the course step never
                            // renders — tell the model so every later step's "of N" drops it.
                            model.skipsCourseStep = true
                        }
                } else {
                    CourseListView(
                        stepNumber: model.stepNumber(for: .course),
                        totalSteps: model.totalSteps
                    ) { course in
                        model.course = course
                        path.append(Step.playerCount)
                    }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .playerCount:
                    PlayerCountStep(
                        model: model,
                        onSolo: { path.append(Step.holes) },
                        onGroup: { path.append(Step.knownPlayers) }
                    )
                case .knownPlayers:
                    // Every seat already has a real roster player — there's nothing left to
                    // fill in, so skip straight to Holes instead of showing an empty-feeling
                    // "confirm your placeholders" step with no placeholders on it.
                    KnownPlayersStep(model: model) {
                        if model.seats.allSatisfy({ !$0.isAnonymous }) {
                            path.append(Step.strokes)
                        } else {
                            path.append(Step.fillRemaining)
                        }
                    }
                case .fillRemaining:
                    FillRemainingStep(model: model) { path.append(Step.strokes) }
                case .strokes:
                    StrokesStepView(model: model) { path.append(Step.holes) }
                case .holes:
                    // Solo has no games step to walk to — the holes screen is the last one, so its
                    // button starts the round rather than continuing the flow.
                    HoleSegmentStep(model: model) {
                        if model.isSolo { start() } else { path.append(Step.games) }
                    }
                case .games:
                    GameSetupView(
                        model: model,
                        onStart: {
                            if model.configurations.contains(where: { $0.gameType == .bestBall }) {
                                path.append(Step.bestBallTeams)
                            } else {
                                start()
                            }
                        },
                        continueButtonTitle: model.configurations.contains(where: { $0.gameType == .bestBall }) ? "Next" : "Start Round"
                    )
                case .bestBallTeams:
                    BestBallTeamsStep(model: model, onStart: start)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            model.preselectedGameType = preselectedGameType
            applyPreselectedPlayerCount()
            autoAssignMe()
        }
    }

    /// A game launched from its own rules screen often implies the group size — Nines is exactly
    /// three, Nassau exactly two. Defaulting the count to that removes a step that's really just
    /// restating what "Start a Round" from Nines already meant.
    private func applyPreselectedPlayerCount() {
        guard let type = preselectedGameType else { return }
        let range = GameLibrary.metadata(for: type).playerRange
        guard range.lowerBound == range.upperBound else { return }
        model.playerCount = range.lowerBound
    }

    /// The person who set up this app is almost always in the round — defaulting them into the
    /// first seat means most groups never see an unclaimed seat for their own scorekeeper.
    /// Still just a normal seat assignment, so swapping them out is one tap like any other.
    private func autoAssignMe() {
        guard let me = MyPlayer.existing(in: modelContext),
              !model.seats.contains(where: { $0.assignedPlayer?.id == me.id }),
              let openSeat = model.seats.first(where: { $0.assignedPlayer == nil })
        else { return }
        openSeat.assign(to: me)
    }

    private func start() {
        guard let round = model.makeRound(in: modelContext) else { return }
        onStart(round)
        dismiss()
    }
}

/// Best Ball's partner assignment is a separate decision from choosing the wager itself.
private struct BestBallTeamsStep: View {
    @Bindable var model: NewRoundModel
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundPlayList.plain {
                RoundBuilderStepHeader(
                    step: model.stepNumber(for: .bestBallTeams),
                    totalSteps: model.totalSteps,
                    title: "Set Best Ball teams",
                    detail: "4 players"
                )

                BestBallTeamPicker(model: model)
            }

            RoundBuilderContinueButton(
                title: "Start Round",
                isEnabled: model.canStart,
                action: onStart
            )
        }
        .navigationTitle("Best Ball Teams")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Step 2a: how many

/// One job: how many seats. Nothing else on the screen to look at.
private struct PlayerCountStep: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: NewRoundModel
    let onSolo: () -> Void
    let onGroup: () -> Void

    /// Seven counts across a four-column grid would leave a ragged last row, so the rows are
    /// split 4 + 3 and each row fills the width.
    private let topRow = [2, 3, 4, 5]
    private let bottomRow = [6, 7, 8]

    var body: some View {
        RoundPlayList.plain {
            RoundBuilderStepHeader(
                step: model.stepNumber(for: .playerCount),
                totalSteps: model.totalSteps,
                title: "How many players?",
                detail: "Tap to continue"
            )

            Button {
                model.makeSolo(in: modelContext)
                onSolo()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.golf")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(RoundPlayColors.accent))
                    VStack(alignment: .leading, spacing: 1) {
                        RoundPlayTypography.headline("Just me")
                        RoundPlayTypography.caption("Solo round · no games")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(RoundPlayColors.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(RoundPlayColors.accent.opacity(0.10))
                        .strokeBorder(RoundPlayColors.accent.opacity(0.42), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16))

            RoundPlaySectionHeader("Or a group")

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(topRow, id: \.self) { count in countCell(count) }
                }
                HStack(spacing: 10) {
                    ForEach(bottomRow, id: \.self) { count in countCell(count) }
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
        }
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countCell(_ count: Int) -> some View {
        Button {
            model.playerCount = count
            onGroup()
        } label: {
            Text("\(count)")
                .font(RoundPlayFont.archivo(27, .bold))
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(RoundPlayColors.fillSecondary)
                )
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) players")
    }
}

// MARK: - Step 2b: who you know

/// One job: pick anyone in this group who's already in your roster. Nothing yet about the ones
/// who aren't — that's the next screen, deliberately, so this one stays a single fast list.
private struct KnownPlayersStep: View {
    @Bindable var model: NewRoundModel
    let onContinue: () -> Void

    @Query(sort: [SortDescriptor(\PlayerRecord.playCount, order: .reverse),
                  SortDescriptor(\PlayerRecord.name)])
    private var players: [PlayerRecord]

    @State private var searchText = ""

    private var filtered: [PlayerRecord] {
        guard !searchText.isEmpty else { return players }
        return players.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedCount: Int {
        model.seats.filter { $0.assignedPlayer != nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundPlayList.plain {
                RoundBuilderStepHeader(
                    step: model.stepNumber(for: .knownPlayers),
                    totalSteps: model.totalSteps,
                    title: "Anybody from your roster?",
                    detail: "\(selectedCount) of \(model.playerCount) selected"
                )

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search roster", text: $searchText)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(RoundPlayColors.fillSecondary))
                .listRowSeparator(.hidden)

                if players.isEmpty {
                    ContentUnavailableView(
                        "No one in your roster yet",
                        systemImage: "person.2",
                        description: Text("That's fine. Everyone can be filled in on the next screen.")
                    )
                } else {
                    ForEach(filtered) { player in
                        Button {
                            toggle(player)
                        } label: {
                            HStack {
                                Image(systemName: isSelected(player) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(isSelected(player) ? RoundPlayColors.accent : .secondary)
                                PlayerRow(player: player)
                            }
                        }
                        .buttonStyle(RoundPlayRowButtonStyle())
                        .disabled(!isSelected(player) && selectedCount >= model.playerCount)
                        .roundPlayListRowSeparatorFullWidth()
                    }
                }
            }

            RoundBuilderContinueButton(title: "Next", action: onContinue)
        }
        .sensoryFeedback(RoundPlayHaptics.selection, trigger: selectedCount)
        .navigationTitle("From Your Roster")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ player: PlayerRecord) -> Bool {
        model.seats.contains { $0.assignedPlayer?.id == player.id }
    }

    private func toggle(_ player: PlayerRecord) {
        if let seat = model.seats.first(where: { $0.assignedPlayer?.id == player.id }) {
            seat.assignedPlayer = nil
            seat.isPlaceholder = true
        } else if let openSeat = model.seats.first(where: { $0.assignedPlayer == nil && $0.isPlaceholder }) {
            openSeat.assign(to: player)
        }
    }
}

// MARK: - Step 2c: fill in the rest

/// Whoever wasn't picked on the previous screen already has a placeholder nickname — this screen
/// is for confirming or renaming those, not for blocking on them. Next always works.
private struct FillRemainingStep: View {
    @Bindable var model: NewRoundModel
    let onContinue: () -> Void

    @State private var assigningSeat: RoundSeatDraft?
    @State private var settingHandicapFor: RoundSeatDraft?

    var body: some View {
        VStack(spacing: 0) {
            RoundPlayList.plain {
                RoundBuilderStepHeader(
                    step: model.stepNumber(for: .fillRemaining),
                    totalSteps: model.totalSteps,
                    title: "Add other players"
                )

                Section {
                    ForEach(Array(model.seats.enumerated()), id: \.element.id) { index, seat in
                        SeatRow(
                            seatNumber: index + 1,
                            seat: seat,
                            onAssign: { assigningSeat = seat },
                            onEditHandicap: { settingHandicapFor = seat }
                        )
                        .roundPlayListRowSeparatorFullWidth()
                    }
                } footer: {
                    RoundPlayTypography.caption("Placeholder names are random and only used for this round. Tap one to give it a real name, which saves it to your roster.")
                        .foregroundStyle(.secondary)
                }
            }

            RoundBuilderContinueButton(title: "Next", action: onContinue)
        }
        .navigationTitle("Fill in the rest")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $assigningSeat) { seat in
            NavigationStack {
                SeatAssignmentSheet(model: model, seat: seat)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $settingHandicapFor) { seat in
            HandicapPickerSheet(handicap: Binding(
                get: { seat.guestHandicap },
                set: { seat.guestHandicap = $0 }
            ))
            .presentationDetents([.height(300)])
        }
        .onAppear(perform: assignInitialNicknames)
    }

    /// Every seat needs a name the moment this screen appears, so the list never shows a blank
    /// row waiting to be noticed.
    private func assignInitialNicknames() {
        for seat in model.seats where seat.isAnonymous && seat.guestName.isEmpty {
            seat.guestName = GuestNickname.random(avoiding: model.namesInUse)
        }
    }
}

// MARK: - Step 2d: how many holes

/// One job: front 9, back 9, or all 18. Its own screen rather than a strip bolted onto Games, so
/// it gets the same weight as every other choice in this flow.
private struct HoleSegmentStep: View {
    @Bindable var model: NewRoundModel
    let onContinue: () -> Void

    private let options: [RoundSegment] = [.front, .back, .total]

    private func label(for segment: RoundSegment) -> String {
        switch segment {
        case .front: "Front 9"
        case .back: "Back 9"
        case .total: "All 18"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundPlayList.plain {
                RoundBuilderStepHeader(
                    step: model.stepNumber(for: .holes),
                    totalSteps: model.totalSteps,
                    title: "How many holes are you playing?",
                    showsStepCount: !model.isSolo
                )

                HStack(spacing: 10) {
                    ForEach(options, id: \.self) { segment in
                        RoundBuilderChoiceCard(
                            title: label(for: segment),
                            isSelected: model.holeSegment == segment
                        ) {
                            model.holeSegment = segment
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            RoundBuilderContinueButton(title: model.isSolo ? "Start Round" : "Next", action: onContinue)
        }
        .navigationTitle("Holes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One seat: a roster player, a renamed guest (both "confirmed," solid styling), or a still-
/// untouched placeholder (dashed outline, muted — reads as "not filled in yet" without blocking).
struct SeatRow: View {
    let seatNumber: Int
    let seat: RoundSeatDraft
    let onAssign: () -> Void
    let onEditHandicap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(seatNumber)")
                .font(RoundPlayFont.archivo(13, .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(RoundPlayColors.fillSecondary))

            Button(action: onAssign) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        RoundPlayTypography.headline(seat.displayName)
                            .foregroundStyle(seat.isPlaceholder ? .secondary : .primary)
                        if seat.isPlaceholder {
                            RoundPlayTypography.eyebrow("Placeholder")
                                .foregroundStyle(RoundPlayColors.pin)
                        }
                    }
                    if !seat.isPlaceholder {
                        RoundPlayTypography.caption(seat.handicapLabel)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            seat.isPlaceholder ? RoundPlayColors.pin.opacity(0.4) : Color.clear,
                            style: StrokeStyle(lineWidth: 1, dash: seat.isPlaceholder ? [4, 3] : [])
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if seat.isAnonymous {
                Button(action: onEditHandicap) {
                    RoundPlayTypography.caption(seat.handicapLabel)
                        .foregroundStyle(RoundPlayColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Who's really in this seat: search the roster, or give it a real name of your own. Reachable
/// from a single tap on any seat, placeholder or not — changing your mind should never be harder
/// than the first choice was.
struct SeatAssignmentSheet: View {
    @Bindable var model: NewRoundModel
    let seat: RoundSeatDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\PlayerRecord.playCount, order: .reverse),
                  SortDescriptor(\PlayerRecord.name)])
    private var players: [PlayerRecord]

    @State private var searchText = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @FocusState private var isNameFocused: Bool

    /// Players already claimed by another seat can't be picked again.
    private var available: [PlayerRecord] {
        let takenIDs = Set(model.seats.filter { $0 !== seat }.compactMap { $0.assignedPlayer?.id })
        let pool = players.filter { !takenIDs.contains($0.id) }
        guard !searchText.isEmpty else { return pool }
        return pool.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var trimmedFullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        RoundPlayList.plain {
            // Primary: name this seat directly. The roster was already offered a full screen ago
            // ("From Your Roster") — someone opening this sheet is here to name a placeholder,
            // not browse the roster again, so that goes second, always visible, no accordion.
            Section {
                VStack(spacing: 10) {
                    TextField("First name", text: $firstName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                        .font(RoundPlayFont.archivo(21, .semiBold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RoundPlayColors.fillSecondary))

                    TextField("Last name (optional)", text: $lastName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(RoundPlayFont.archivo(21, .semiBold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RoundPlayColors.fillSecondary))

                    Button {
                        seat.rename(to: trimmedFullName, handicap: seat.guestHandicap)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(RoundPlayFont.archivo(19, .bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .roundPlayPrimaryButtonStyle()
                    .tint(RoundPlayColors.accent)
                    .disabled(trimmedFullName.isEmpty)

                    if seat.assignedPlayer == nil {
                        Button {
                            saveAndAddToRoster()
                        } label: {
                            Text("Save and Add to Roster")
                                .font(RoundPlayFont.archivo(15, .semiBold))
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .disabled(trimmedFullName.isEmpty)
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                RoundPlaySectionHeader("Who's in this seat?")
                    .foregroundStyle(.secondary)
            }

            // Secondary: the roster, always visible underneath — no accordion to open first.
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search roster", text: $searchText)
                        .autocorrectionDisabled()
                }
                .listRowSeparator(.hidden)

                ForEach(available) { player in
                    Button {
                        seat.assign(to: player)
                        dismiss()
                    } label: {
                        HStack {
                            PlayerRow(player: player)
                            if seat.assignedPlayer?.id == player.id {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(RoundPlayColors.accent)
                            }
                        }
                    }
                    .buttonStyle(RoundPlayRowButtonStyle())
                    .roundPlayListRowSeparatorFullWidth()
                }
            } header: {
                RoundPlaySectionHeader("Roster")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Who's playing?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            let parts = seat.guestName.split(separator: " ", maxSplits: 1)
            if seat.isPlaceholder {
                // A placeholder's random nickname isn't worth pre-filling — start blank so the
                // user isn't stuck deleting "Birdie Malone" before typing a real name.
                isNameFocused = true
            } else {
                firstName = parts.first.map(String.init) ?? ""
                lastName = parts.count > 1 ? String(parts[1]) : ""
            }
        }
    }

    private func saveAndAddToRoster() {
        seat.rename(to: trimmedFullName, handicap: seat.guestHandicap, addToRoster: true)
        let record = PlayerRecord(name: trimmedFullName, handicapIndex: seat.guestHandicap)
        modelContext.insert(record)
        seat.assign(to: record)
        try? modelContext.save()
        dismiss()
    }
}

#Preview("Light") {
    NewRoundFlowView { _ in }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NewRoundFlowView { _ in }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
