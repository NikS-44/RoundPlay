import SwiftUI
import SwiftData
import RoundPlayEngine

/// Course info and every player's name/handicap, all editable from one place — reached from the
/// Scorecard toolbar, not buried in Standings where nobody looks for "edit."
struct RoundEditSheet: View {
    let round: RoundRecord
    let course: Course

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var courseRecords: [CourseRecord]
    @State private var isEditingCourse = false
    @State private var editingSeat: SeatRecord?

    private var courseRecord: CourseRecord? {
        courseRecords.first { $0.id == round.courseID }
    }

    var body: some View {
        NavigationStack {
            RoundPlayList.plain {
                Section {
                    Button {
                        isEditingCourse = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                RoundPlayTypography.headline(round.courseName)
                                Text("Par \(course.totalPar) · 18 holes")
                                    .font(RoundPlayFont.archivo(13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(RoundPlayColors.accent)
                        }
                    }
                    .buttonStyle(RoundPlayRowButtonStyle())
                    .roundPlayListRowSeparatorFullWidth()
                } header: {
                    RoundPlayTypography.eyebrow("Course")
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(round.orderedSeats) { seat in
                        Button {
                            editingSeat = seat
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundPlayTypography.headline(seat.name)
                                    Text("Course handicap \(seat.courseHandicap)")
                                        .font(RoundPlayFont.archivo(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .foregroundStyle(RoundPlayColors.accent)
                            }
                        }
                        .buttonStyle(RoundPlayRowButtonStyle())
                        .roundPlayListRowSeparatorFullWidth()
                    }
                } header: {
                    RoundPlayTypography.eyebrow("Players")
                        .foregroundStyle(.secondary)
                } footer: {
                    RoundPlayTypography.caption("Tap the pencil to fix a name, handicap, or course detail.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isEditingCourse) {
                if let courseRecord {
                    NavigationStack {
                        CourseEntryView(editing: courseRecord) { _ in }
                    }
                }
            }
            .sheet(item: $editingSeat) { seat in
                SeatEditSheet(seat: seat)
            }
        }
    }
}
