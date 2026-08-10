import SwiftUI
import SwiftData
import RoundPlayEngine

/// One screen with everything from a previous round already filled in — course, players, games,
/// and stakes. Replaying a regular Thursday game should be one tap plus maybe one tweak, not the
/// full six-step builder again. Each section edits in its own sheet; this screen never pushes.
struct PlayAgainConfirmView: View {
    let sourceRound: RoundRecord
    let onStart: (RoundRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: NewRoundModel
    @State private var isPickingCourse = false
    @State private var editingSeat: RoundSeatDraft?
    @State private var isEditingGames = false

    init(sourceRound: RoundRecord, courseRecord: CourseRecord, context: ModelContext, onStart: @escaping (RoundRecord) -> Void) {
        self.sourceRound = sourceRound
        self.onStart = onStart
        _model = State(initialValue: NewRoundModel.replaying(sourceRound, course: courseRecord, in: context))
    }

    private var gamesSummary: String {
        guard !model.configurations.isEmpty else { return "No games — plain stroke play" }
        return model.configurations
            .map { GameLibrary.metadata(for: $0.gameType).displayName }
            .joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RoundPlayList.plain {
                    Section {
                        Button {
                            isPickingCourse = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundPlayTypography.headline(model.course?.name ?? "Choose a course")
                                    if let course = model.course {
                                        Text("Par \(course.totalPar) · 18 holes")
                                            .font(RoundPlayFont.archivo(13))
                                            .foregroundStyle(.secondary)
                                    }
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
                        ForEach(Array(model.seats.enumerated()), id: \.element.id) { index, seat in
                            SeatRow(
                                seatNumber: index + 1,
                                seat: seat,
                                onAssign: { editingSeat = seat },
                                onEditHandicap: { editingSeat = seat }
                            )
                            .roundPlayListRowSeparatorFullWidth()
                        }
                    } header: {
                        RoundPlayTypography.eyebrow("Players")
                            .foregroundStyle(.secondary)
                    } footer: {
                        RoundPlayTypography.caption("Tap anyone to swap them out for this round.")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button {
                            isEditingGames = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundPlayTypography.headline("Games")
                                    Text(gamesSummary)
                                        .font(RoundPlayFont.archivo(13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .foregroundStyle(RoundPlayColors.accent)
                            }
                        }
                        .buttonStyle(RoundPlayRowButtonStyle())
                        .roundPlayListRowSeparatorFullWidth()
                    } header: {
                        RoundPlayTypography.eyebrow("Games & Bets")
                            .foregroundStyle(.secondary)
                    }
                }

                RoundBuilderContinueButton(title: "Start Round", isEnabled: model.canStart, action: start)
            }
            .navigationTitle("Play Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isPickingCourse) {
                NavigationStack {
                    CourseListView(showsStepHeader: false) { course in
                        model.course = course
                        isPickingCourse = false
                    }
                }
            }
            .sheet(item: $editingSeat) { seat in
                NavigationStack {
                    SeatAssignmentSheet(model: model, seat: seat)
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isEditingGames) {
                NavigationStack {
                    GameSetupView(
                        model: model,
                        onStart: { isEditingGames = false },
                        showsStepHeader: false,
                        continueButtonTitle: "Done"
                    )
                }
            }
        }
    }

    private func start() {
        guard let round = model.makeRound(in: modelContext) else { return }
        onStart(round)
        dismiss()
    }
}
