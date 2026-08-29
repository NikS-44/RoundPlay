import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// Deleted rounds aren't actually gone — "Delete Round" just moves them here, where they can be
/// brought back or purged for good. Nothing outside this screen calls the real, permanent delete.
struct RecentlyDeletedRoundsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RoundRecord.startedAt, order: .reverse) private var allRounds: [RoundRecord]
    @Query private var courses: [CourseRecord]

    @State private var pendingPermanentDelete: RoundRecord?

    private var deletedRounds: [RoundRecord] {
        allRounds
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private func course(for round: RoundRecord) -> Course? {
        courses.first { $0.id == round.courseID }?.engineCourse
    }

    var body: some View {
        RoundPlayList.plain {
            if deletedRounds.isEmpty {
                ContentUnavailableView(
                    "Nothing deleted",
                    systemImage: "trash",
                    description: Text("Rounds you delete stay here until you restore or remove them for good.")
                )
            } else {
                Section {
                    ForEach(deletedRounds) { round in
                        DeletedRoundRow(
                            round: round,
                            course: course(for: round),
                            onRestore: { restore(round) },
                            onDeleteForever: { pendingPermanentDelete = round }
                        )
                        .roundPlayListRowSeparatorFullWidth()
                    }
                } footer: {
                    RoundPlayTypography.caption("Deleted rounds stay here until you restore or remove them for good.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        // An alert rather than an action sheet: this is the one irreversible action in the app, and
        // it deserves the modal treatment that lands in the centre of the screen instead of sliding
        // up under the finger that just tapped Delete.
        .alert(
            "Delete this round forever?",
            isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { if !$0 { pendingPermanentDelete = nil } }
            )
        ) {
            Button("Delete Forever", role: .destructive) {
                if let round = pendingPermanentDelete {
                    modelContext.delete(round)
                    try? modelContext.save()
                }
                pendingPermanentDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingPermanentDelete = nil }
        } message: {
            Text("This can't be undone. The round and all its scores are gone for good.")
        }
    }

    private func restore(_ round: RoundRecord) {
        round.deletedAt = nil
        try? modelContext.save()
    }
}

private struct DeletedRoundRow: View {
    let round: RoundRecord
    let course: Course?
    let onRestore: () -> Void
    let onDeleteForever: () -> Void

    private var playerNames: String {
        round.orderedSeats.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                RoundPlayTypography.headline(round.courseName)
                Text(playerNames)
                    .font(RoundPlayFont.archivo(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let deletedAt = round.deletedAt {
                    Text("Deleted \(deletedAt, style: .relative) ago")
                        .font(RoundPlayFont.archivo(12))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 16) {
                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(RoundPlayFont.archivo(15, .semiBold))
                        .foregroundStyle(RoundPlayColors.accent)
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDeleteForever) {
                    Label("Delete Forever", systemImage: "trash")
                        .font(RoundPlayFont.archivo(15, .semiBold))
                        .foregroundStyle(RoundPlayColors.scoreOverPar)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Light") {
    NavigationStack {
        RecentlyDeletedRoundsView()
    }
    .modelContainer(PreviewData.container)
}
