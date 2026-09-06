import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// The end of the round: what everyone shot, what is still missing, and the way to close it out.
///
/// The watch lets you walk off a hole with scores unentered, on purpose — somebody is still
/// putting, somebody has already driven off. That only works if the gaps come back to you at the
/// end instead of quietly becoming blanks on the card, so every hole still short of a score is
/// listed here and tapping one takes you back to it.
struct WatchRoundReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let course: Course
    /// Bound to the hole screen behind this sheet, so tapping a gap lands you on it.
    @Binding var hole: Int

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var seats: [SeatRecord] { round.orderedSeats }
    private var holes: [Int] { Array(round.holeSegment.holeRange) }

    private var incompleteHoles: [Int] {
        holes.filter { hole in
            seats.contains { state.gross(hole: hole, player: $0.playerID) == nil }
        }
    }

    var body: some View {
        List {
            Section("Card") {
                ForEach(seats) { seat in
                    HStack(spacing: 6) {
                        Text(seat.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(total(for: seat))
                            .font(.body.monospacedDigit())
                        Text(versusParLabel(for: seat))
                            .font(.caption2)
                            .foregroundStyle(versusParColor(for: seat))
                    }
                }
            }

            if !incompleteHoles.isEmpty {
                Section("Missing scores") {
                    ForEach(incompleteHoles, id: \.self) { hole in
                        Button {
                            self.hole = hole
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(WatchPalette.pin)
                                Text("Hole \(hole)")
                                Spacer(minLength: 4)
                                Text(missingNames(on: hole))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section {
                Button(incompleteHoles.isEmpty ? "Finish round" : "Finish anyway") {
                    finish()
                }
                .tint(WatchPalette.accent)
            } footer: {
                if !incompleteHoles.isEmpty {
                    Text("Holes without a score for every player stay blank, and standings only count what's been entered.")
                }
            }
        }
        .navigationTitle("Review")
    }

    // MARK: - Card

    /// Gross over the holes actually played. A round abandoned after nine shouldn't be reported as
    /// if the back nine were all zeros.
    private func played(for seat: SeatRecord) -> [(hole: Int, gross: Int)] {
        holes.compactMap { hole in
            state.gross(hole: hole, player: seat.playerID).map { (hole, $0) }
        }
    }

    private func total(for seat: SeatRecord) -> String {
        let scores = played(for: seat)
        guard !scores.isEmpty else { return "—" }
        return "\(scores.reduce(0) { $0 + $1.gross })"
    }

    private func versusPar(for seat: SeatRecord) -> Int? {
        let scores = played(for: seat)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0) { $0 + $1.gross - (course.hole($1.hole)?.par ?? 4) }
    }

    private func versusParLabel(for seat: SeatRecord) -> String {
        guard let value = versusPar(for: seat) else { return "" }
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func versusParColor(for seat: SeatRecord) -> Color {
        guard let value = versusPar(for: seat) else { return .secondary }
        if value < 0 { return WatchPalette.underPar }
        if value > 0 { return WatchPalette.overPar }
        return .secondary
    }

    private func missingNames(on hole: Int) -> String {
        let missing = seats.filter { state.gross(hole: hole, player: $0.playerID) == nil }
        // Not "nobody" — that reads as "nobody is missing", which is the opposite of what an
        // untouched hole means.
        if missing.count == seats.count { return "none entered" }
        return missing.count <= 2
            ? missing.map(\.name).joined(separator: ", ")
            : "\(missing.count) players"
    }

    // MARK: - Finishing

    private func finish() {
        // Same single field the phone sets. Nothing in the app ever clears it, which is what makes
        // finishing the one action here that can't be taken back.
        round.completedAt = Date()
        try? modelContext.save()
        EngineBridge.onLocalChange?()
        dismiss()
    }
}
