import SwiftUI
import RoundPlayEngine
import RoundPlayData

struct WatchScorecardView: View {
    let round: RoundRecord
    let course: Course

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var holes: [Int] {
        let current = state.currentHole(in: round.holeSegment)
        let start = max(round.holeSegment.holeRange.lowerBound, current - 3)
        return Array(start...current)
    }

    var body: some View {
        List {
            ForEach(holes, id: \.self) { hole in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hole \(hole) · Par \(course.hole(hole)?.par ?? 4)")
                        .font(.headline)
                    ForEach(round.orderedSeats) { seat in
                        HStack {
                            Text(seat.name)
                            Spacer()
                            if let gross = state.gross(hole: hole, player: seat.playerID) {
                                Text("\(gross)")
                                    .font(.body.monospacedDigit())
                            } else {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}
