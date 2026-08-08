import SwiftUI
import SwiftData

/// One-time course setup: 18 pars and 18 stroke indexes, copied off the scorecard.
struct CourseEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = CourseEntryModel()
    let onSave: (CourseRecord) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Course name", text: $model.name)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("Total par \(model.totalPar)")
            }

            Section("Holes") {
                ForEach(0..<18, id: \.self) { index in
                    HoleEntryRow(
                        holeNumber: index + 1,
                        par: $model.pars[index],
                        strokeIndex: $model.strokeIndexes[index]
                    )
                }
            }

            if let message = model.validationMessage {
                Section {
                    Text(message).foregroundStyle(RoundPlayColors.destructive)
                }
            }
        }
        .navigationTitle("Add Course")
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
        let record = CourseRecord(
            name: model.name.trimmingCharacters(in: .whitespaces),
            pars: model.pars,
            strokeIndexes: model.strokeIndexes
        )
        modelContext.insert(record)
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
            Text("\(holeNumber)")
                .font(.headline.monospacedDigit())
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
