import SwiftUI
import UIKit
import RoundPlayEngine

/// One minimum-cash-flow payment: `debtorName` pays `creditorName` `amount`.
struct SettlementPayment: Identifiable {
    let debtorName: String
    let creditorName: String
    let amount: Decimal
    var id: String { "\(debtorName)-\(creditorName)-\(amount)" }
}

/// Renders the scorecard grid to a `UIImage` off-screen, and turns a round's settlements into
/// minimum-cash-flow payments — both feed the Share/Settle Up buttons, generated ahead of time
/// rather than at the moment they're tapped so there's no lag before the sheet appears.
enum RoundShareContent {
    /// Full picture in one image: the scorecard grid, what everyone won or lost, and the
    /// minimum-cash-flow "who owes who" — so the one thing shared to the group chat is the whole
    /// story, not just the raw grid.
    @MainActor
    static func scorecardImage(round: RoundRecord, course: Course) -> UIImage? {
        let renderer = ImageRenderer(content: ShareableRoundCard(round: round, course: course))
        // Fixed 2x rather than `UIScreen.main.scale`: `UIScreen.main` is deprecated and not
        // scene-aware, and if it ever hands back a zero scale `ImageRenderer` silently returns
        // nil — which shipped as "Share posts the text but no picture". The card is ~600–1,100pt
        // wide, so 2x is already sharper than any chat app will display it.
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Each player's total across every game, biggest winner first.
    static func netStandings(round: RoundRecord, course: Course) -> [(name: String, net: Decimal)] {
        let settlements = EngineBridge.settlements(for: round, course: course)
        var totals: [UUID: Decimal] = [:]
        for settlement in settlements {
            for standing in settlement.standings {
                totals[standing.playerID, default: 0] += standing.money
            }
        }
        return round.orderedSeats
            .map { ($0.name, totals[$0.playerID] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    /// Greedy debt simplification: repeatedly settles the biggest creditor against the biggest
    /// debtor so "who owes who" is the minimum number of payments — if A owes B and B owes C the
    /// same amount, that nets out to zero for B and one straight payment from A to C — instead of
    /// listing every game's raw result.
    static func settlementPayments(round: RoundRecord, course: Course) -> [SettlementPayment] {
        let settlements = EngineBridge.settlements(for: round, course: course)
        guard !settlements.isEmpty else { return [] }

        var netByPlayer: [UUID: Decimal] = [:]
        for settlement in settlements {
            for standing in settlement.standings {
                netByPlayer[standing.playerID, default: 0] += standing.money
            }
        }
        func name(for id: UUID) -> String {
            round.orderedSeats.first { $0.playerID == id }?.name ?? "Unknown"
        }

        var balances = netByPlayer.map { (id: $0.key, amount: $0.value) }.filter { $0.amount != 0 }
        var payments: [SettlementPayment] = []
        while true {
            balances.sort { $0.amount < $1.amount }
            guard let debtor = balances.first, let creditor = balances.last, debtor.amount < 0, creditor.amount > 0 else { break }
            let amount = min(-debtor.amount, creditor.amount)
            payments.append(SettlementPayment(debtorName: name(for: debtor.id), creditorName: name(for: creditor.id), amount: amount))
            balances = balances.compactMap { entry in
                var updated = entry
                if entry.id == debtor.id { updated.amount += amount }
                if entry.id == creditor.id { updated.amount -= amount }
                return updated.amount == 0 ? nil : updated
            }
        }
        return payments
    }

    static func settlementSummaryText(round: RoundRecord, course: Course) -> String {
        let settlements = EngineBridge.settlements(for: round, course: course)
        guard !settlements.isEmpty else {
            return "\(round.courseName) — no games played, nothing owed."
        }
        let gameNames = (round.games ?? []).compactMap { $0.gameType.map { GameLibrary.metadata(for: $0).displayName } }
        let payments = settlementPayments(round: round, course: course)
        let lines = payments.map { "\($0.debtorName) owes \($0.creditorName) \($0.amount.formatted(.currency(code: "USD")))" }

        var text = "\(round.courseName) — \(gameNames.joined(separator: ", "))\n"
        text += lines.isEmpty ? "Everyone's settled up — no money owed." : lines.joined(separator: "\n")
        return text
    }
}

/// The single image `RoundShareContent.scorecardImage` renders: title, the grid, then money and
/// settle-up sections stacked underneath — everything someone would want from "here's how it
/// went" in one picture, on a plain white background so it reads the same in any chat app.
private struct ShareableRoundCard: View {
    let round: RoundRecord
    let course: Course

    private var netStandings: [(name: String, net: Decimal)] {
        RoundShareContent.netStandings(round: round, course: course)
    }

    private var payments: [SettlementPayment] {
        RoundShareContent.settlementPayments(round: round, course: course)
    }

    private var grid: ScorecardGrid {
        ScorecardGrid(round: round, course: course, forSharing: true)
    }

    /// The money lists sit in their own narrow column rather than stretching to the grid's width.
    /// Spanning the full card put half a screen of dead space between "Eric Palmer" and "$60.00",
    /// which is unreadable at a glance and only gets worse on an 18-hole card.
    private let moneyColumnWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(RoundPlayFont.archivo(22, .bold))
                    .foregroundStyle(.black)
                Text(round.startedAt, style: .date)
                    .font(RoundPlayFont.archivo(13))
                    .foregroundStyle(.black.opacity(0.6))
            }

            grid.flatGrid

            if !netStandings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Won & Lost")
                    ForEach(netStandings, id: \.name) { entry in
                        HStack {
                            Text(entry.name)
                                .font(RoundPlayFont.archivo(15, .semiBold))
                                .foregroundStyle(.black)
                            Spacer(minLength: 16)
                            Text(entry.net.formatted(.currency(code: "USD").sign(strategy: .always())))
                                .font(RoundPlayFont.plexMono(15, .semiBold))
                                .foregroundStyle(entry.net > 0 ? RoundPlayColors.scoreUnderPar : entry.net < 0 ? RoundPlayColors.scoreOverPar : .black.opacity(0.6))
                        }
                        .frame(width: moneyColumnWidth, alignment: .leading)
                    }
                }
            }

            if !payments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Who Owes Who")
                    ForEach(payments) { payment in
                        // One plain-English sentence, sized to its own text. "Eric Palmer → Tilly"
                        // with the amount pushed to the far edge made the reader join two things
                        // separated by a hand's width of nothing; this reads in one pass.
                        (
                            Text("\(payment.debtorName) owes \(payment.creditorName) ")
                                .font(RoundPlayFont.archivo(15, .semiBold))
                            + Text(payment.amount.formatted(.currency(code: "USD")))
                                .font(RoundPlayFont.plexMono(15, .semiBold))
                        )
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(24)
        // Sized to the grid rather than to a constant, so a nine-hole round ships a nine-hole-wide
        // image instead of an 18-hole frame with the right half left blank. A frame narrower than
        // the grid silently clips holes in ImageRenderer, so this must never be a guess.
        .frame(width: grid.intrinsicWidth + 48, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(RoundPlayFont.plexMono(11, .semiBold))
            .tracking(1.2)
            .foregroundStyle(.black.opacity(0.5))
    }
}

/// A read-only grid scorecard for a finished round — hole numbers across the top, par and stroke
/// index below, one row per player underneath. This is the shape everyone already knows from the
/// paper card in the cart, not another hole-by-hole flip-through.
struct PaperScorecardView: View {
    let round: RoundRecord
    let course: Course

    var body: some View {
        ScorecardGrid(round: round, course: course)
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The full-screen, auto-rotated-to-landscape presentation — same grid, more width to show more
/// holes at once without scrolling. Flips the device to landscape on appearance and hands it back
/// to portrait the moment this closes, since the rest of the app is portrait-only.
struct FullScreenScorecardView: View {
    let round: RoundRecord
    let course: Course
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundPlayColors.pageBackground.ignoresSafeArea()

            ScorecardGrid(round: round, course: course)
                .padding(.top, 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary, RoundPlayColors.fillSecondary)
            }
            .padding(12)
        }
        .onAppear { OrientationLock.shared.requestLandscape() }
        .onDisappear { OrientationLock.shared.requestPortrait() }
    }
}

/// The grid itself: one sticky label column (Hole/Par/S.I., then each player) beside a single
/// horizontally-scrolling region holding every row — header and scores move together because
/// they're the same `ScrollView`, not two independently-scrolling ones.
private struct ScorecardGrid: View {
    let round: RoundRecord
    let course: Course
    /// True only when this is being rendered off-screen for `ImageRenderer` — flat and
    /// non-scrolling (`ImageRenderer` can't capture a `ScrollView`'s clipped-off content) on a
    /// plain white background instead of the app's themed one, since a shared image should look
    /// right regardless of the recipient's system appearance.
    var forSharing: Bool = false

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var holes: [Int] { Array(round.holeSegment.holeRange) }
    private var showsOutIn: Bool { round.holeSegment == .total }
    private var front: [Int] { holes.filter { $0 <= 9 } }
    private var back: [Int] { holes.filter { $0 > 9 } }

    private func par(_ hole: Int) -> Int { course.hole(hole)?.par ?? 0 }
    private func strokeIndex(_ hole: Int) -> Int { course.hole(hole)?.strokeIndex ?? 0 }
    private func sum(_ range: [Int], _ value: (Int) -> Int) -> Int { range.reduce(0) { $0 + value($1) } }

    private let labelColumnWidth: CGFloat = 152
    private let cellWidth: CGFloat = 42
    private let sumCellWidth: CGFloat = 56
    private let rowHeight: CGFloat = 50

    /// Exactly how wide `flatGrid` draws, so the shared image can size itself to the grid instead
    /// of to a constant. An 18-hole card is 1,076pt; a nine-hole card is 586pt, and hardcoding the
    /// former shipped every nine-hole round with ~500pt of white space down the right-hand side.
    ///
    /// Nine-hole rounds carry one total column; eighteen carry OUT, IN and TOT.
    var intrinsicWidth: CGFloat {
        let sumColumns: CGFloat = showsOutIn ? 3 : 1
        return labelColumnWidth
            + CGFloat(holes.count) * cellWidth
            + sumColumns * sumCellWidth
    }

    private func rowTint(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? .clear : RoundPlayColors.fillSecondary.opacity(0.5)
    }

    private var labelColumn: some View {
        VStack(spacing: 0) {
            rowLabelCell("Hole")
            rowDivider
            rowLabelCell("Par")
            rowDivider
            rowLabelCell("S.I.")
            rowDivider
            ForEach(Array(round.orderedSeats.enumerated()), id: \.element.id) { index, seat in
                rowLabelCell(seat.name, subtitle: "HCP \(seat.courseHandicap)")
                    .background(rowTint(index))
                rowDivider
            }
        }
        .frame(width: labelColumnWidth)
        .background(RoundPlayColors.fillSecondary)
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            holeRow
            rowDivider
            parRow
            rowDivider
            strokeIndexRow
            rowDivider
            ForEach(Array(round.orderedSeats.enumerated()), id: \.element.id) { index, seat in
                scoreRow(for: seat)
                    .background(rowTint(index))
                rowDivider
            }
        }
    }

    /// The bare grid, no title/padding/white background — used when embedding inside a bigger
    /// composite (`ShareableRoundCard`) that supplies its own chrome once for the whole image.
    var flatGrid: some View {
        HStack(spacing: 0) {
            labelColumn
            contentColumn
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    var body: some View {
        if forSharing {
            VStack(alignment: .leading, spacing: 12) {
                Text(round.courseName)
                    .font(RoundPlayFont.archivo(20, .bold))
                    .foregroundStyle(.black)
                flatGrid
            }
            .padding(20)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                HStack(spacing: 0) {
                    labelColumn
                    ScrollView(.horizontal, showsIndicators: false) {
                        contentColumn
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(16)
            }
        }
    }

    // MARK: - Header rows

    private var holeRow: some View {
        HStack(spacing: 0) {
            ForEach(front, id: \.self) { hole in cell("\(hole)") }
            if showsOutIn { sumCell("OUT").fontWeight(.bold) }
            ForEach(back, id: \.self) { hole in cell("\(hole)") }
            sumCell(showsOutIn ? "IN" : "TOT").fontWeight(.bold)
            if showsOutIn { sumCell("TOT").fontWeight(.bold) }
        }
        .background(RoundPlayColors.fillSecondary)
    }

    private var parRow: some View {
        HStack(spacing: 0) {
            ForEach(front, id: \.self) { hole in cell("\(par(hole))") }
            if showsOutIn { sumCell("\(sum(front, par))") }
            ForEach(back, id: \.self) { hole in cell("\(par(hole))") }
            sumCell("\(sum(showsOutIn ? back : front, par))")
            if showsOutIn { sumCell("\(sum(holes, par))") }
        }
        .foregroundStyle(.secondary)
        .background(RoundPlayColors.fillSecondary)
    }

    private var strokeIndexRow: some View {
        HStack(spacing: 0) {
            ForEach(front, id: \.self) { hole in cell("\(strokeIndex(hole))") }
            if showsOutIn { sumCell("") }
            ForEach(back, id: \.self) { hole in cell("\(strokeIndex(hole))") }
            sumCell("")
            if showsOutIn { sumCell("") }
        }
        .foregroundStyle(.tertiary)
        .background(RoundPlayColors.fillSecondary)
    }

    // MARK: - Player rows

    private func scoreRow(for seat: SeatRecord) -> some View {
        HStack(spacing: 0) {
            ForEach(front, id: \.self) { hole in scoreCell(hole: hole, seat: seat) }
            if showsOutIn { sumCell(grossSum(front, seat)).fontWeight(.semibold) }
            ForEach(back, id: \.self) { hole in scoreCell(hole: hole, seat: seat) }
            sumCell(grossSum(showsOutIn ? back : front, seat)).fontWeight(.semibold)
            if showsOutIn { sumCell(grossSum(holes, seat)).fontWeight(.semibold) }
        }
        .frame(height: rowHeight)
    }

    private func grossSum(_ range: [Int], _ seat: SeatRecord) -> String {
        let values = range.compactMap { state.gross(hole: $0, player: seat.playerID) }
        guard values.count == range.count else { return "–" }
        return "\(values.reduce(0, +))"
    }

    /// The number shown is always gross — that's what a paper scorecard shows — but the color is
    /// judged against net (gross minus any handicap stroke on this hole), so a player getting a
    /// stroke here sees the same green/red a scratch player would for the equivalent net result.
    private func scoreCell(hole: Int, seat: SeatRecord) -> some View {
        let gross = state.gross(hole: hole, player: seat.playerID)
        let net = state.net(hole: hole, player: seat.playerID)
        let relative = net.map { $0 - par(hole) }
        return Text(gross.map { "\($0)" } ?? "–")
            .font(RoundPlayFont.plexMono(19, .semiBold))
            .foregroundStyle(color(for: relative))
            .frame(width: cellWidth, height: rowHeight)
    }

    private func color(for relativeToPar: Int?) -> Color {
        guard let relativeToPar else { return .secondary }
        if relativeToPar < 0 { return RoundPlayColors.scoreUnderPar }
        if relativeToPar > 0 { return RoundPlayColors.scoreOverPar }
        return RoundPlayColors.scoreAtPar
    }

    // MARK: - Cells

    private func cell(_ text: String) -> some View {
        Text(text)
            .font(RoundPlayFont.plexMono(16, .medium))
            .frame(width: cellWidth, height: rowHeight)
    }

    private func sumCell(_ text: String) -> some View {
        Text(text)
            .font(RoundPlayFont.plexMono(16, .medium))
            .frame(width: sumCellWidth, height: rowHeight)
    }

    private func rowLabelCell(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(RoundPlayFont.archivo(16, .semiBold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(RoundPlayFont.archivo(12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: labelColumnWidth - 14, height: rowHeight, alignment: .leading)
        .padding(.leading, 12)
    }

    private var rowDivider: some View { Divider() }
}

#Preview("Light") {
    NavigationStack {
        PaperScorecardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
}

#Preview("Dark") {
    NavigationStack {
        PaperScorecardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .preferredColorScheme(.dark)
}
