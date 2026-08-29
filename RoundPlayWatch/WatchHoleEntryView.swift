import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

struct WatchHoleEntryView: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let course: Course

    @State private var hole: Int
    @State private var stepIndex = 0

    init(round: RoundRecord, course: Course) {
        self.round = round
        self.course = course
        let state = EngineBridge.roundState(for: round, course: course)
        _hole = State(initialValue: state.currentHole(in: round.holeSegment))
    }

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var requiredInputs: Set<InputKind> {
        var inputs: Set<InputKind> = []
        for game in round.games ?? [] {
            guard let type = game.gameType else { continue }
            inputs.formUnion(GameLibrary.metadata(for: type).requiredInputs)
        }
        if inputs.isEmpty { inputs = [.strokes] }
        return inputs
    }

    private var steps: [HoleEntryStep] {
        HoleEntrySequence.steps(requiredInputs: requiredInputs, seatCount: round.orderedSeats.count)
    }

    private var scorekeeper: SeatRecord? { round.orderedSeats.first }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Hole \(hole)")
                    .font(.headline)
                Spacer()
                if case .score(let index) = currentStep {
                    Text("\(index + 1) of \(round.orderedSeats.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            stepView
        }
        .padding(.horizontal, 4)
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.width > 40 { goBack() }
            }
        )
    }

    @ViewBuilder
    private var stepView: some View {
        switch currentStep {
        case .partnerChoice:
            WatchWolfStep(round: round, course: course, hole: hole, onConfirm: advance)
        case .score(let seatIndex):
            if round.orderedSeats.indices.contains(seatIndex) {
                WatchScoreStep(
                    round: round,
                    course: course,
                    hole: hole,
                    seat: round.orderedSeats[seatIndex],
                    onConfirm: advance
                )
            }
        case .holeEvents:
            WatchHoleEventsStep(round: round, hole: hole, onConfirm: advance)
        }
    }

    private var currentStep: HoleEntryStep {
        guard steps.indices.contains(stepIndex) else {
            return .score(seatIndex: 0)
        }
        return steps[stepIndex]
    }

    private func advance() {
        if stepIndex + 1 < steps.count {
            stepIndex += 1
        } else {
            let range = round.holeSegment.holeRange
            if hole < range.upperBound {
                hole += 1
                stepIndex = 0
            }
        }
    }

    private func goBack() {
        if stepIndex > 0 {
            stepIndex -= 1
        } else if hole > round.holeSegment.holeRange.lowerBound {
            hole -= 1
            stepIndex = max(0, steps.count - 1)
        }
    }
}

struct WatchScoreStep: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let course: Course
    let hole: Int
    let seat: SeatRecord
    let onConfirm: () -> Void

    @State private var crownValue: Double
    @FocusState private var focused: Bool

    init(round: RoundRecord, course: Course, hole: Int, seat: SeatRecord, onConfirm: @escaping () -> Void) {
        self.round = round
        self.course = course
        self.hole = hole
        self.seat = seat
        self.onConfirm = onConfirm
        let par = Double(course.hole(hole)?.par ?? 4)
        let existing = EngineBridge.roundState(for: round, course: course).gross(hole: hole, player: seat.playerID)
        _crownValue = State(initialValue: Double(existing ?? Int(par)))
    }

    private var strokes: Int { Int(crownValue.rounded()) }

    var body: some View {
        VStack(spacing: 4) {
            Text(seat.name)
                .font(.headline)
                .lineLimit(1)
            Text("Par \(course.hole(hole)?.par ?? 4)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(strokes)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.accent)
                .focusable()
                .focused($focused)
                .digitalCrownRotation(
                    $crownValue,
                    from: 1,
                    through: 15,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            Button("Confirm") {
                let keeper = round.orderedSeats.first
                try? EngineBridge.appendStrokes(
                    strokes, hole: hole, playerID: seat.playerID, to: round,
                    enteredBy: keeper?.playerID ?? seat.playerID,
                    enteredByName: keeper?.name ?? seat.name,
                    in: modelContext
                )
                onConfirm()
            }
            .tint(WatchPalette.accent)
        }
        .onAppear { focused = true }
    }
}

struct WatchWolfStep: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let course: Course
    let hole: Int
    let onConfirm: () -> Void

    private var wolf: SeatRecord {
        let seats = round.orderedSeats.map(\.engineSeat)
        let engineWolf = WolfEngine.wolf(forHole: hole, seats: seats)
        return round.orderedSeats.first { $0.playerID == engineWolf.playerID } ?? round.orderedSeats[0]
    }

    var body: some View {
        List {
            Text("\(wolf.name) is Wolf")
                .font(.headline)
            Button("Lone Wolf") { declare(.lone) }
            ForEach(round.orderedSeats.filter { $0.playerID != wolf.playerID }) { seat in
                Button("Partner \(seat.name)") { declare(.partner(seat.playerID)) }
            }
        }
    }

    private func declare(_ declaration: WolfDeclaration) {
        let keeper = round.orderedSeats.first
        try? EngineBridge.appendWolfDeclaration(
            declaration, hole: hole, wolfID: wolf.playerID, to: round,
            enteredBy: keeper?.playerID ?? wolf.playerID,
            enteredByName: keeper?.name ?? wolf.name,
            in: modelContext
        )
        onConfirm()
    }
}

struct WatchHoleEventsStep: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let hole: Int
    let onConfirm: () -> Void

    var body: some View {
        List {
            ForEach(HoleEventKind.allCases, id: \.self) { kind in
                Section(kind.rawValue.capitalized) {
                    ForEach(round.orderedSeats) { seat in
                        Button(seat.name) {
                            let keeper = round.orderedSeats.first
                            try? EngineBridge.appendHoleEvent(
                                kind, hole: hole, playerID: seat.playerID, to: round,
                                enteredBy: keeper?.playerID ?? seat.playerID,
                                enteredByName: keeper?.name ?? seat.name,
                                in: modelContext
                            )
                        }
                    }
                }
            }
            Button("Next hole") { onConfirm() }
        }
    }
}
