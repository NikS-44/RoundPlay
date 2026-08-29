import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// "Who's getting shots?" — the step where a group agrees strokes before any money is on it.
///
/// The screen is built around one number per player: **the strokes they get**. Everything else —
/// the mode, the allowance, the cap — exists to produce that number, so the number is what's big,
/// and it's what's tappable. A group that just wants to say "you give me four" never has to know
/// what an allowance is.
struct StrokesStepView: View {
    @Bindable var model: NewRoundModel
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var editingSeat: RoundSeatDraft?
    @State private var isShowingAdvanced = false

    private static let advancedRowID = "advanced"

    private var lowSeatName: String? {
        guard model.handicapSettings.mode == .offTheLow else { return nil }
        return model.lowSeat?.displayName
    }

    /// True when the computation has nothing to work with — nobody in the group has a handicap on
    /// file, which is the normal case for a foursome of guests.
    private var everyoneIsScratch: Bool {
        model.seats.allSatisfy { model.strokes(for: $0) == 0 }
    }

    /// Plain-English restatement of what the group just chose, in the words they'd use out loud.
    private var modeExplanation: String {
        switch model.handicapSettings.mode {
        case .offTheLow:
            // Saying "X plays off scratch, everyone else gets the difference" when the difference
            // is zero for everybody is technically true and completely useless. Say what to do.
            if everyoneIsScratch {
                return "Nobody has a handicap yet, so everyone's level. Tap a player to give them shots."
            }
            guard let lowSeatName else { return "The lowest handicap plays off scratch." }
            return "\(lowSeatName) plays off scratch. Everyone else gets the difference."
        case .full:
            return "Everyone plays their full handicap. Best for stroke play and Stableford."
        case .straightUp:
            return "No strokes. Lowest gross score wins, however you're playing."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundPlayList.plainScrolling { scrollProxy in
                RoundBuilderStepHeader(
                    step: model.stepNumber(for: .strokes),
                    totalSteps: model.totalSteps,
                    // "Who's giving who shots?" was the sentence a group says out loud, but it
                    // reads as a grammar mistake on screen and asks about the wrong side of the
                    // deal — every row below answers "gets N", not "gives N".
                    title: "Who's getting shots?"
                )

                // Cards and explanation share one row rather than sitting in their own section —
                // as separate rows the default section spacing opened a gap under the explanation
                // wide enough to read as the end of the screen.
                VStack(alignment: .leading, spacing: 10) {
                    // The same cards as the front-9/back-9/all-18 step, not a segmented pill.
                    // Both screens ask "pick one of three", and a pill sized to its own text made
                    // "Full" a target a third the size of "Straight up".
                    HStack(spacing: 10) {
                        ForEach(StrokeMode.allCases, id: \.self) { mode in
                            RoundBuilderChoiceCard(
                                title: label(for: mode),
                                isSelected: model.handicapSettings.mode == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.handicapSettings.mode = mode
                                }
                            }
                        }
                    }

                    RoundPlayTypography.caption(modeExplanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))

                if model.handicapSettings.mode != .straightUp {
                    Section {
                        ForEach(model.seats) { seat in
                            Button {
                                editingSeat = seat
                            } label: {
                                strokeRow(for: seat)
                            }
                            .buttonStyle(RoundPlayRowButtonStyle())
                            .roundPlayListRowSeparatorFullWidth()
                        }
                    } header: {
                        // Matches the "Games" header rather than the 9.5pt mono eyebrow — that
                        // eyebrow is legible as a label on a card but disappears as a section
                        // header on a white list, especially outdoors.
                        RoundPlaySectionHeader("Strokes")
                    }
                    // No footer explaining that the rows are tappable. Each one carries a
                    // chevron and a value; a line of text saying so is a caption nobody needs
                    // and one more thing between the group and Advanced.

                    Section {
                        DisclosureGroup(isExpanded: $isShowingAdvanced) {
                            allowanceRow
                            // The scroll target below. A `List` lays a DisclosureGroup's content
                            // out as sibling rows rather than inside the label's frame, so
                            // tagging the group itself gave `scrollTo` a row that was already
                            // fully on screen — and it correctly did nothing. The last revealed
                            // row is the one that actually has to come into view.
                            capRow
                                .id(Self.advancedRowID)
                        } label: {
                            Text("Advanced")
                                .font(RoundPlayFont.archivo(15, .semiBold))
                        }
                        .listRowSeparator(.hidden)
                        // Advanced is the last thing on the screen, so opening it puts everything
                        // it reveals below the fold — the group looked like it hadn't opened at
                        // all until you happened to scroll.
                        //
                        // On the DisclosureGroup rather than the enclosing `Section`: a Section
                        // is a list-structure builder, not a view, and an `onChange` attached to
                        // one never runs.
                        .onChange(of: isShowingAdvanced) { _, isExpanded in
                            guard isExpanded else { return }
                            Task {
                                // After the disclosure's own animation, or the rows being
                                // scrolled to do not exist yet.
                                try? await Task.sleep(for: .milliseconds(250))
                                withAnimation(.easeOut(duration: 0.25)) {
                                    scrollProxy.scrollTo(Self.advancedRowID, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }

            RoundBuilderContinueButton(title: "Next", action: onContinue)
        }
        .listSectionSpacing(.compact)
        .sensoryFeedback(RoundPlayHaptics.decision, trigger: model.handicapSettings)
        .navigationTitle("Strokes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSeat) { seat in
            StrokeOverrideSheet(
                seat: seat,
                strokes: model.strokes(for: seat),
                isOverridden: model.strokeOverrides[seat.id] != nil,
                onSave: { strokes, savesToRoster in
                    model.strokeOverrides[seat.id] = strokes
                    if savesToRoster { saveIndexToRoster(seat, strokes: strokes) }
                },
                onReset: { model.strokeOverrides[seat.id] = nil }
            )
            .presentationDetents([.height(430)])
        }
    }

    private func label(for mode: StrokeMode) -> String {
        switch mode {
        case .offTheLow: "Off the low"
        case .full: "Full"
        case .straightUp: "Straight up"
        }
    }

    // MARK: - Rows

    private func strokeRow(for seat: RoundSeatDraft) -> some View {
        let strokes = model.strokes(for: seat)
        let isOverridden = model.strokeOverrides[seat.id] != nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                RoundPlayTypography.headline(seat.displayName)
                HStack(spacing: 6) {
                    RoundPlayTypography.caption(seat.handicapLabel)
                        .foregroundStyle(.secondary)
                    if isOverridden {
                        RoundPlayTypography.eyebrow("Agreed")
                            .foregroundStyle(RoundPlayColors.accent)
                    }
                }
            }
            Spacer()
            // The whole point of the screen. "Gets 6" is the sentence a group says out loud, so
            // it's the sentence on the row — not a handicap the reader has to do math on.
            Text(strokes == 0 ? "Scratch" : "Gets \(strokes)")
                .font(RoundPlayFont.archivo(strokes == 0 ? 15 : 19, .bold))
                .foregroundStyle(strokes == 0 ? Color.secondary : RoundPlayColors.accent)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var allowanceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Allowance")
                    .font(RoundPlayFont.archivo(15))
                Spacer()
                Picker("Allowance", selection: $model.handicapSettings.allowancePercent) {
                    ForEach([100, 95, 90, 85, 75, 50], id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(RoundPlayColors.accent)
            }
            if let recommended = model.recommendedAllowance,
               recommended != model.handicapSettings.allowancePercent {
                Button {
                    model.handicapSettings.allowancePercent = recommended
                } label: {
                    RoundPlayTypography.caption("The games you picked recommend \(recommended)%. Tap to use it.")
                        .foregroundStyle(RoundPlayColors.accent)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            } else {
                RoundPlayTypography.caption("Trims everyone's handicap. Team formats use less than 100%.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var capRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Max handicap")
                    .font(RoundPlayFont.archivo(15))
                Spacer()
                Picker("Max handicap", selection: capBinding) {
                    Text("None").tag(0)
                    ForEach([8, 12, 18, 24, 36], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(RoundPlayColors.accent)
            }
            RoundPlayTypography.caption("Stops one very high handicap running away with every hole.")
                .foregroundStyle(.secondary)
        }
    }

    /// The picker needs a non-optional tag, so 0 stands in for "no cap" — a cap of zero would mean
    /// nobody gets a stroke, which is what Straight up is for.
    private var capBinding: Binding<Int> {
        Binding(
            get: { model.handicapSettings.maxStrokes ?? 0 },
            set: { model.handicapSettings.maxStrokes = $0 == 0 ? nil : $0 }
        )
    }

    // MARK: - Roster

    /// Only reached when the seat had no handicap on file, so this is new information rather than
    /// an override of something the player already told us.
    private func saveIndexToRoster(_ seat: RoundSeatDraft, strokes: Int) {
        guard let player = seat.assignedPlayer else { return }
        player.handicapIndex = Double(strokes)
        try? modelContext.save()
    }
}

/// Set one player's strokes by hand.
private struct StrokeOverrideSheet: View {
    let seat: RoundSeatDraft
    let strokes: Int
    let isOverridden: Bool
    let onSave: (Int, Bool) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Int = 0
    @State private var savesToRoster = false

    /// Offered only when nobody has recorded a handicap for this player. Overwriting an index
    /// someone already gave us with a number negotiated for one round is how a roster quietly goes
    /// wrong, so that case is round-only with no toggle at all.
    private var canSaveToRoster: Bool {
        seat.assignedPlayer != nil && seat.handicapIndexForRound == nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(seat.displayName)
                    .font(RoundPlayFont.archivo(23, .black))
                    .padding(.top, 8)

                Text("Strokes for this round")
                    .font(RoundPlayFont.archivo(15))
                    .foregroundStyle(.secondary)

                Picker("Strokes", selection: $value) {
                    ForEach(0...36, id: \.self) { number in
                        Text(number == 0 ? "Scratch" : "\(number)").tag(number)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)

                if canSaveToRoster {
                    Toggle("Save as \(seat.displayName)'s handicap", isOn: $savesToRoster)
                        .font(RoundPlayFont.archivo(15))
                        .tint(RoundPlayColors.accent)
                        .padding(.horizontal, 4)
                }

                if isOverridden {
                    Button("Use the calculated strokes") {
                        onReset()
                        dismiss()
                    }
                    .font(RoundPlayFont.archivo(15, .semiBold))
                    .tint(RoundPlayColors.accent)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(value, savesToRoster)
                        dismiss()
                    }
                }
            }
            .onAppear { value = strokes }
        }
    }
}
