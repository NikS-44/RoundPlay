import SwiftUI
import SwiftData

/// One-time course setup: 18 pars and 18 stroke indexes, copied off the scorecard.
struct CourseEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: CourseEntryModel
    /// Set when this course was pre-filled from the OpenGolf catalog, so `save()` can record
    /// where it came from.
    private let openGolfID: String?
    /// Set when editing a course already in the store — `save()` updates it in place (and every
    /// other round at this course sees the fix) instead of creating a duplicate.
    private let existingRecord: CourseRecord?
    let onSave: (CourseRecord) -> Void

    init(model: CourseEntryModel = CourseEntryModel(), openGolfID: String? = nil, onSave: @escaping (CourseRecord) -> Void) {
        _model = State(initialValue: model)
        self.openGolfID = openGolfID
        self.existingRecord = nil
        self.onSave = onSave
    }

    /// Editing mode: pre-fills from `record` and updates it in place on save.
    init(editing record: CourseRecord, onSave: @escaping (CourseRecord) -> Void) {
        let model = CourseEntryModel()
        model.name = record.name
        model.pars = record.pars
        model.strokeIndexes = record.strokeIndexes
        _model = State(initialValue: model)
        self.openGolfID = record.openGolfID
        self.existingRecord = record
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                TextField("Course name", text: $model.name)
                    .textInputAutocapitalization(.words)
            } footer: {
                RoundPlayTypography.eyebrow("Total par \(model.totalPar)")
                    .foregroundStyle(.secondary)
            }

            if openGolfID != nil {
                Section {
                    Label("Verify this scorecard against the course's physical card before playing. Missing catalog values are only placeholders.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(RoundPlayColors.destructive)
                }
            }

            Section {
                ForEach(0..<18, id: \.self) { index in
                    HoleEntryRow(
                        holeNumber: index + 1,
                        par: $model.pars[index],
                        strokeIndex: $model.strokeIndexes[index]
                    )
                }
            } header: {
                RoundPlaySectionHeader("Holes")
                    .foregroundStyle(.secondary)
            }

            if let message = model.validationMessage {
                Section {
                    Text(message).foregroundStyle(RoundPlayColors.destructive)
                }
            }
        }
        .navigationTitle(existingRecord == nil ? "Add Course" : "Edit Course")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!model.isValid)
            }
        }
    }

    private func save() {
        let name = model.name.trimmingCharacters(in: .whitespaces)
        let record: CourseRecord
        if let existingRecord {
            existingRecord.name = name
            existingRecord.pars = model.pars
            existingRecord.strokeIndexes = model.strokeIndexes
            record = existingRecord
        } else {
            record = CourseRecord(name: name, pars: model.pars, strokeIndexes: model.strokeIndexes, openGolfID: openGolfID)
            modelContext.insert(record)
        }
        try? modelContext.save()
        onSave(record)
        dismiss()
    }
}

/// One hole's par and stroke index, both as steppers — no keyboard, no numeric input errors.
private struct HoleEntryRow: View {
    let holeNumber: Int
    @Binding var par: Int
    @Binding var strokeIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundPlayTypography.numeral("\(holeNumber)", size: 17)
                .frame(width: 28, alignment: .leading)

            Picker("Par", selection: $par) {
                ForEach(3...6, id: \.self) { Text("Par \($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Spacer()

            Picker("Stroke index", selection: $strokeIndex) {
                ForEach(1...18, id: \.self) { Text("SI \($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hole \(holeNumber), par \(par), stroke index \(strokeIndex)")
    }
}

#Preview("Light") {
    NavigationStack { CourseEntryView { _ in } }
        .modelContainer(RoundPlaySchema.makeContainer(inMemory: true))
}

#Preview("Dark") {
    NavigationStack { CourseEntryView { _ in } }
        .modelContainer(RoundPlaySchema.makeContainer(inMemory: true))
        .preferredColorScheme(.dark)
}
