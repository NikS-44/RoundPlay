import SwiftUI
import SwiftData
import UIKit
import RoundPlayEngine

/// The Rounds tab: start a round, or resume one in progress.
struct RoundsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoundRecord.startedAt, order: .reverse) private var rounds: [RoundRecord]
    @Query private var courses: [CourseRecord]

    @State private var isCreatingRound = false
    @State private var activeRound: RoundRecord?
    @State private var newRoundStartingCourse: CourseRecord?
    @State private var playAgainSource: RoundRecord?
    @State private var isShowingRecentlyDeleted = false

    /// External trigger (from onboarding's "Start a Round"): a favorite course to preselect, and
    /// a signal to open the new-round sheet. Both default to no-ops so every other call site and
    /// every preview is unaffected.
    var autoStartFavorite: Binding<OpenGolfCourse?> = .constant(nil)
    var autoStartRound: Binding<Bool> = .constant(false)

    private func course(for round: RoundRecord) -> Course? {
        courses.first { $0.id == round.courseID }?.engineCourse
    }

    private func courseRecord(for round: RoundRecord) -> CourseRecord? {
        courses.first { $0.id == round.courseID }
    }

    private var inProgress: [RoundRecord] { rounds.filter { !$0.isComplete && !$0.isDeleted } }
    private var earlier: [RoundRecord] { rounds.filter { $0.isComplete && !$0.isDeleted } }

    /// "Delete" is a soft delete — the round moves to Recently Deleted, where it can be restored
    /// or purged for good. Nothing calls `modelContext.delete(_:)` on a round outside that screen.
    private func delete(_ round: RoundRecord) {
        if activeRound?.id == round.id { activeRound = nil }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            round.deletedAt = Date()
            try? modelContext.save()
        }
    }

    var body: some View {
        RoundPlayList.plain {
            if inProgress.isEmpty {
                StartRoundEmptyState { isCreatingRound = true }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(inProgress) { round in
                if let course = course(for: round) {
                    Button {
                        activeRound = round
                    } label: {
                        InProgressRoundCard(round: round, course: course)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(round)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }

            if !earlier.isEmpty {
                Section {
                    ForEach(earlier) { round in
                        VStack(spacing: 8) {
                            roundLink(round) {
                                EarlierRoundRow(round: round, course: course(for: round))
                            }

                            HStack {
                                // A capsule chip, not an underlined text link — underlines read as
                                // web chrome and made the busiest row on the home screen look
                                // unfinished next to everything else in the app.
                                Button {
                                    guard courseRecord(for: round) != nil else { return }
                                    playAgainSource = round
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Play Again")
                                            .font(RoundPlayFont.archivo(13, .semiBold))
                                    }
                                    .foregroundStyle(RoundPlayColors.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().strokeBorder(RoundPlayColors.accent.opacity(0.45), lineWidth: 1)
                                    )
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                        }
                        .padding(.vertical, 6)
                        .roundPlayListRowSeparatorFullWidth()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(round)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                } header: {
                    RoundPlaySectionHeader("Previous Rounds")
                }
            }
        }
        // Without this the gap between the Start a Round CTA and "Previous Rounds" reads as a
        // rendering gap rather than a section break.
        .listSectionSpacing(.compact)
        .navigationTitle("Rounds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isShowingRecentlyDeleted = true
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Round", systemImage: "plus") { isCreatingRound = true }
            }
        }
        .sheet(isPresented: $isShowingRecentlyDeleted) {
            NavigationStack {
                RecentlyDeletedRoundsView()
            }
        }
        .fullScreenCover(isPresented: $isCreatingRound) {
            NewRoundFlowView(startingCourse: newRoundStartingCourse) { round in
                activeRound = round
                newRoundStartingCourse = nil
            }
        }
        .onChange(of: autoStartRound.wrappedValue) { _, shouldStart in
            guard shouldStart else { return }
            if let favorite = autoStartFavorite.wrappedValue {
                newRoundStartingCourse = courses.first { $0.openGolfID == favorite.id }
            }
            isCreatingRound = true
            autoStartRound.wrappedValue = false
            autoStartFavorite.wrappedValue = nil
        }
        .sheet(item: $playAgainSource) { round in
            if let record = courseRecord(for: round) {
                PlayAgainConfirmView(sourceRound: round, courseRecord: record, context: modelContext) { newRound in
                    activeRound = newRound
                }
            }
        }
        .navigationDestination(item: $activeRound) { round in
            if let course = course(for: round) {
                RoundTabsView(round: round, course: course)
            } else {
                ContentUnavailableView(
                    "Course unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The course for this round is missing or incomplete.")
                )
            }
        }
    }

    @ViewBuilder
    private func roundLink<Label: View>(_ round: RoundRecord, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            if let course = course(for: round) {
                RoundTabsView(round: round, course: course)
            } else {
                ContentUnavailableView(
                    "Course unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The course for this round is missing or incomplete.")
                )
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

/// The featured card for a round still being played: status, score-strip progress, and the
/// scorekeeper's net across every game.
private struct InProgressRoundCard: View {
    let round: RoundRecord
    let course: Course

    private var state: RoundState { EngineBridge.roundState(for: round, course: course) }
    private var holeRange: ClosedRange<Int> { round.holeSegment.holeRange }

    private var holesPlayed: Int {
        holeRange.last { state.isComplete(hole: $0) }.map { $0 - holeRange.lowerBound + 1 } ?? 0
    }

    private var gameNames: String {
        (round.games ?? [])
            .compactMap { $0.gameType.map { GameLibrary.metadata(for: $0).displayName } }
            .joined(separator: ", ")
    }

    private var net: Decimal {
        guard let scorekeeper = round.orderedSeats.first else { return 0 }
        return EngineBridge.settlements(for: round, course: course)
            .reduce(Decimal(0)) { $0 + $1.money(for: scorekeeper.playerID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundPlayTypography.eyebrow("In Progress")
                    .foregroundStyle(RoundPlayColors.pin)
                Spacer()
                RoundPlayTypography.money(net.formatted(.currency(code: "USD").sign(strategy: .always())))
                    .foregroundStyle(net >= 0 ? RoundPlayColors.moneyPositiveOnBoard : RoundPlayColors.moneyNegativeOnBoard)
            }

            RoundPlayTypography.title(round.courseName)
                .foregroundStyle(RoundPlayColors.paperOnBoard)

            Text("\(pluralized(round.orderedSeats.count, "player")) · \(gameNames) · thru \(holesPlayed)")
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))

            Text(round.startedAt, style: .date)
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))

            HoleProgressDots(holesPlayed: holesPlayed, totalHoles: holeRange.count)

            Divider().overlay(RoundPlayColors.paperOnBoard.opacity(0.15))

            HStack {
                RoundPlayTypography.body("Continue round")
                    .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
            }
        }
        .padding(18)
        .boardCard(cornerRadius: 16)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

/// The empty state when nothing is in progress: one unmissable way to begin, rather than a lone
/// toolbar "+" a first-time user has no reason to notice.
private struct StartRoundEmptyState: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.circle")
                .font(.system(size: 44))
                .foregroundStyle(RoundPlayColors.accent)
            RoundPlayTypography.headline("No rounds in progress")
            RoundPlayTypography.caption("Start a round, keep score for your group, and track the bets — Skins, Nassau, and more.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onStart) {
                Text("Start a Round")
                    .font(RoundPlayFont.archivo(17, .semiBold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .roundPlayPrimaryButtonStyle()
            .tint(RoundPlayColors.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// A row of 18 dots, filled fairway-green up through the last completed hole.
private struct HoleProgressDots: View {
    let holesPlayed: Int
    let totalHoles: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...totalHoles, id: \.self) { hole in
                Capsule()
                    .fill(hole <= holesPlayed ? RoundPlayColors.moneyPositiveOnBoard : RoundPlayColors.paperOnBoard.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("\(holesPlayed) of \(totalHoles) holes scored")
    }
}

/// A finished round in the "Earlier" list: course, date, and the scorekeeper's net.
private struct EarlierRoundRow: View {
    let round: RoundRecord
    let course: Course?

    /// `nil` when this round had no money games at all — a friendly round shouldn't advertise a
    /// meaningless "+$0.00" in the same slot where a real result goes.
    private var net: Decimal? {
        guard let course, let scorekeeper = round.orderedSeats.first else { return nil }
        let moneyGames = EngineBridge.settlements(for: round, course: course)
            .filter { $0.gameType != .strokePlay }
        guard !moneyGames.isEmpty else { return nil }
        return moneyGames.reduce(Decimal(0)) { $0 + $1.money(for: scorekeeper.playerID) }
    }

    private var playerNames: String {
        round.orderedSeats.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                RoundPlayTypography.headline(round.courseName)
                // Players and date share a line — three stacked lines per round made the list
                // scroll twice as far for the same information.
                Text("\(playerNames) · \(round.startedAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(RoundPlayFont.archivo(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if let net {
                RoundPlayTypography.money(net.formatted(.currency(code: "USD").sign(strategy: .always())))
                    .foregroundStyle(net > 0 ? RoundPlayColors.moneyPositive : net < 0 ? RoundPlayColors.moneyNegative : RoundPlayColors.moneyEven)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Scoring and standings for a round in progress.
///
/// Pushed from the Rounds tab, so without hiding the root tab bar here, its own Scorecard/
/// Standings bar would stack on top of the root Rounds/Games/Players bar and the root bar would
/// cover the bottom of whichever tab's content is showing.
struct RoundTabsView: View {
    let round: RoundRecord
    let course: Course

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum RoundTab: Hashable { case summary, scorecard, standings }
    @State private var selection: RoundTab
    @State private var isEditingRound = false
    @State private var isEditingScores = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingFinishEarly = false
    @State private var isFullScreen = false
    @State private var isShowingRoundOptions = false
    @State private var isSharingScorecard = false
    @State private var isSharingSettlement = false
    /// Generated as soon as the finished scorecard appears, not when Share is tapped — so there's
    /// no wait for the share sheet to have something to show.
    @State private var scorecardShareImage: UIImage?

    /// A finished round lands on Summary every time it's reopened; a round still being played
    /// always resumes on the Scorecard, mid-hole.
    init(round: RoundRecord, course: Course) {
        self.round = round
        self.course = course
        _selection = State(initialValue: round.isComplete ? .summary : .scorecard)
    }

    private var hasGames: Bool { !(round.games ?? []).isEmpty }

    private var shareItems: [Any] {
        var items: [Any] = [RoundShareContent.settlementSummaryText(round: round, course: course)]
        if let scorecardShareImage {
            items.insert(scorecardShareImage, at: 0)
        }
        return items
    }

    /// The live Scorecard tab sits directly under `HoleHeader`'s near-black board background —
    /// the nav bar needs light text/icons there, same as the rest of the app's default dark-on-
    /// light everywhere else (the finished scorecard, Summary, Standings).
    private var showsDarkNavBar: Bool {
        !round.isComplete && selection == .scorecard
    }

    private var navigationTitleText: String {
        switch selection {
        case .summary: "Summary"
        case .scorecard: "Scorecard"
        case .standings: "Standings"
        }
    }

    var body: some View {
        // One NavigationStack for the whole tab view, not one per tab — RoundTabsView is itself
        // pushed from RoundsHomeView's stack, and nesting a fresh NavigationStack inside each tab
        // left the outer stack owning the visible bar while every tab's own navigationTitle/
        // toolbar silently never rendered (only the outer stack's bare back button showed). The
        // "Round Options" menu lives here — the shallowest point in this single stack — rather
        // than nested inside a tab's content, for the same reason.
        NavigationStack {
            TabView(selection: $selection) {
                if round.isComplete {
                    Tab("Summary", systemImage: "checkmark.seal", value: RoundTab.summary) {
                        RoundSummaryView(
                            round: round,
                            course: course,
                            onShare: { isSharingScorecard = true },
                            onSettleUp: { isSharingSettlement = true },
                            onShowScorecard: { isFullScreen = true },
                            onShowStandings: { selection = .standings }
                        )
                    }
                }
                Tab("Scorecard", systemImage: "square.grid.3x3", value: RoundTab.scorecard) {
                    if round.isComplete {
                        PaperScorecardView(round: round, course: course)
                    } else {
                        HoleScreenView(round: round, course: course) { selection = .summary }
                    }
                }
                Tab("Standings", systemImage: "chart.bar", value: RoundTab.standings) {
                    RoundDashboardView(round: round, course: course)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarColorScheme(showsDarkNavBar ? .dark : nil, for: .navigationBar)
            .toolbar {
                // A generic "<" back button reads like undo or "go to the previous step" — this
                // isn't a step in a flow, it's leaving the round entirely, so it gets an explicit
                // exit affordance instead.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Exit Round", systemImage: "xmark")
                    }
                }
                if round.isComplete {
                    if selection == .scorecard {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                isFullScreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isSharingScorecard = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingRoundOptions = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .task(id: "\(round.isComplete)-\(round.nextSequence)") {
                guard round.isComplete, scorecardShareImage == nil else { return }
                scorecardShareImage = RoundShareContent.scorecardImage(round: round, course: course)
            }
            .sheet(isPresented: $isEditingRound) {
                RoundEditSheet(round: round, course: course)
            }
            .sheet(isPresented: $isEditingScores) {
                NavigationStack {
                    HoleScreenView(round: round, course: course, isPostCompletionEdit: true) {
                        isEditingScores = false
                    }
                }
            }
            .fullScreenCover(isPresented: $isFullScreen) {
                FullScreenScorecardView(round: round, course: course)
            }
            .sheet(isPresented: $isSharingScorecard) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $isSharingSettlement) {
                SettleUpSheet(round: round, course: course)
            }
            .confirmationDialog("Round Options", isPresented: $isShowingRoundOptions, titleVisibility: .visible) {
                if round.isComplete {
                    Button("Correct Scores") {
                        isEditingScores = true
                    }
                }
                Button("Edit Round") {
                    isEditingRound = true
                }
                if !round.isComplete {
                    if hasGames {
                        // Opens the breakdown directly. This used to just switch to Standings,
                        // which was where the disabled "Coming soon" stub lived.
                        Button("Settle Up") {
                            isSharingSettlement = true
                        }
                    }
                    Button("Finish Early") {
                        isConfirmingFinishEarly = true
                    }
                }
                Button("Delete Round", role: .destructive) {
                    isConfirmingDelete = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Finish this round now?",
                isPresented: $isConfirmingFinishEarly,
                titleVisibility: .visible
            ) {
                Button("Finish Early", role: .destructive) {
                    round.completedAt = Date()
                    try? modelContext.save()
                    selection = .summary
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Holes without a score for every player will be left blank. Standings only count what's been entered.")
            }
            .confirmationDialog(
                "Delete this round?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Round", role: .destructive) {
                    round.deletedAt = Date()
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This moves the round to Recently Deleted, where it can be restored.")
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { RoundsHomeView() }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { RoundsHomeView() }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
