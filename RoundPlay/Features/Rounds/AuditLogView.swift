import SwiftUI
import RoundPlayEngine

/// Every entry ever made in this round, newest first.
///
/// This is the append-only log read backwards — no separate audit table exists, and none is
/// needed. A corrected score shows as two entries, which is exactly the point: "Ben changed your
/// 6 to a 5 on 14" is visible rather than silent.
struct AuditLogView: View {
    let round: RoundRecord

    private var entries: [ScoreEventRecord] {
        (round.events ?? []).sorted { $0.sequence > $1.sequence }
    }

    private func name(for playerID: UUID) -> String {
        round.orderedSeats.first { $0.playerID == playerID }?.name ?? "Unknown"
    }

    private func describe(_ record: ScoreEventRecord) -> String {
        switch record.payload {
        case .strokes(let count):
            "\(name(for: record.playerID)) scored \(count)"
        case .wolfDeclaration(.lone):
            "\(name(for: record.playerID)) went Lone Wolf"
        case .wolfDeclaration(.partner(let partner)):
            "\(name(for: record.playerID)) partnered with \(name(for: partner))"
        case .holeEvent(let kind):
            "\(name(for: record.playerID)) took the \(kind.rawValue)"
        case .clearStrokes:
            "Cleared \(name(for: record.playerID))'s score"
        case .clearHoleEvent(let kind):
            "Cleared the \(kind.rawValue) award"
        case nil:
            "Unreadable entry"
        }
    }

    var body: some View {
        RoundPlayList.plain {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet",
                    systemImage: "clock",
                    description: Text("Scores appear here as they're entered.")
                )
            }

            ForEach(entries) { record in
                VStack(alignment: .leading, spacing: 2) {
                    RoundPlayTypography.headline("Hole \(record.hole) — \(describe(record))")
                    Text("Entered by \(record.enteredByName) · \(record.recordedAt, style: .time)")
                        .font(RoundPlayFont.archivo(13))
                        .foregroundStyle(.secondary)
                }
                .roundPlayListRowSeparatorFullWidth()
            }

            if !entries.isEmpty {
                Section {
                    RoundPlayTypography.eyebrow("Corrections append — nothing is overwritten, so a silent edit is impossible")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Light") {
    NavigationStack { AuditLogView(round: PreviewData.sampleRound) }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { AuditLogView(round: PreviewData.sampleRound) }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
