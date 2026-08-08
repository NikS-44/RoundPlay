import SwiftUI

/// Reusable single-field rename sheet (course names, player names, …).
///
/// The caller owns persistence and any validation beyond non-empty (e.g. duplicate checks):
/// `onSave` is invoked with the trimmed value only when it is non-empty.
struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// Field placeholder, e.g. "Course name".
    var placeholder: String = "Name"
    /// Pre-filled value.
    let initialValue: String
    let onSave: (String) -> Void

    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(
        title: String,
        placeholder: String = "Name",
        initialValue: String,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.onSave = onSave
        _text = State(initialValue: initialValue)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $text)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
