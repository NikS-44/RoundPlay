import SwiftUI
import SwiftData
import RoundPlayEngine

/// Live standings and money for every game in the round.
///
/// Every figure comes from `Settlement`. The dashboard performs no arithmetic of its own — if a
/// number is wrong here, the bug is in the engine and there is a failing fixture to write.
struct RoundDashboardView: View {
    let round: RoundRecord
    let course: Course

    private var settlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course)
    }

    private func name(for playerID: UUID) -> String {
        round.orderedSeats.first { $0.playerID == playerID }?.name ?? "Unknown"
    }

    var body: some View {
        RoundPlayList.plain {
            ForEach(settlements, id: \.gameType) { settlement in
                Section {
                    ForEach(settlement.standings.sorted { $0.money > $1.money }) { standing in
                        HStack {
                            Text(name(for: standing.playerID))
                            Spacer()
                            Text("\(standing.points) pts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(standing.money, format: .currency(code: "USD"))
                                .monospacedDigit()
                                .foregroundStyle(moneyColor(standing.money))
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .roundPlayListRowSeparatorFullWidth()
                    }

                    if !settlement.holeExplanations.isEmpty {
                        DisclosureGroup("Hole by hole") {
                            // Indexed rather than keyed on `text`: Nassau emits two explanations
                            // for one hole (the result, then a press opening), and identical
                            // strings across holes are common ("Hole 4: halved.").
                            ForEach(Array(settlement.holeExplanations.enumerated()), id: \.offset) { _, explanation in
                                Text(explanation.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(GameLibrary.metadata(for: settlement.gameType).displayName)
                }
            }

            Section {
                SettleUpStub()
            }
        }
        .navigationTitle("Standings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { AuditLogView(round: round) } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private func moneyColor(_ amount: Decimal) -> Color {
        if amount > 0 { return RoundPlayColors.moneyPositive }
        if amount < 0 { return RoundPlayColors.moneyNegative }
        return RoundPlayColors.moneyEven
    }
}

/// Payments are Phase 5. The affordance ships now, disabled, so the shape of the app is honest
/// about where it is going — and so the ledger has a home when it arrives.
private struct SettleUpStub: View {
    var body: some View {
        VStack(spacing: 6) {
            Button("Settle Up") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
            Text("Coming soon — for now, settle up however you normally do.")
                .font(.caption)
                .foregroundStyle(RoundPlayColors.moneyDisabled)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview("Light") {
    NavigationStack {
        RoundDashboardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack {
        RoundDashboardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
