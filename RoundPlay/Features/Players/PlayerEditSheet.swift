import SwiftUI
import SwiftData

/// Add or edit someone in your roster.
///
/// A name is **required** — the whole point of the roster is that scores belong to Bob, not to
/// "Player 3". Handicap is optional because plenty of casual golfers do not have one, and
/// demanding it would be a wall in front of the first round.
struct PlayerEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: PlayerRecord?
    let onSave: (PlayerRecord) -> Void

    @State private var name: String = ""
    @State private var handicapText: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            Section {
                TextField("Handicap index", text: $handicapText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Handicap")
            } footer: {
                Text("Optional. Leave blank to play off scratch. Strokes are given on the hardest holes.")
            }
        }
        .navigationTitle(player == nil ? "New Player" : "Edit Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            name = player?.name ?? ""
            handicapText = player?.handicapIndex.map { String($0) } ?? ""
        }
    }

    private func save() {
        let handicap = Double(handicapText.trimmingCharacters(in: .whitespaces))
        let record: PlayerRecord
        if let player {
            player.name = trimmedName
            player.handicapIndex = handicap
            record = player
        } else {
            record = PlayerRecord(name: trimmedName, handicapIndex: handicap)
            modelContext.insert(record)
        }
        try? modelContext.save()
        onSave(record)
        dismiss()
    }
}

#Preview("Light") {
    NavigationStack { PlayerEditSheet(player: nil) { _ in } }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { PlayerEditSheet(player: nil) { _ in } }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
