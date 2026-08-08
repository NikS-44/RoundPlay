import SwiftUI
import SwiftData

/// Pick a course, or add one. Recents first — most groups replay the same two or three.
struct CourseListView: View {
    @Query(sort: [SortDescriptor(\CourseRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\CourseRecord.name)])
    private var courses: [CourseRecord]

    @State private var isAddingCourse = false
    let onSelect: (CourseRecord) -> Void

    var body: some View {
        RoundPlayList.plain {
            if courses.isEmpty {
                ContentUnavailableView(
                    "No courses yet",
                    systemImage: "flag",
                    description: Text("Add a course from the scorecard in your hand. Everyone who plays there after you gets it automatically.")
                )
            }

            ForEach(courses) { course in
                Button {
                    onSelect(course)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.body)
                            Text("Par \(course.totalPar)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Course")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAddingCourse = true }
            }
        }
        .sheet(isPresented: $isAddingCourse) {
            NavigationStack {
                CourseEntryView { course in onSelect(course) }
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { CourseListView { _ in } }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { CourseListView { _ in } }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
