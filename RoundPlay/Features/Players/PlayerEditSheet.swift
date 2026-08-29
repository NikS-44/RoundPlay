import SwiftUI
import SwiftData
import RoundPlayData

/// Add or edit someone in your roster.
///
/// Every player needs a name, but a guest added on the first tee without one gets a random
/// nickname instead of hitting a wall — it lands in this same text field, so renaming it later
/// needs no separate affordance. Handicap is optional because plenty of casual golfers do not
/// have one, and demanding it would be a wall in front of the first round.
struct PlayerEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allPlayers: [PlayerRecord]

    let player: PlayerRecord?
    let onSave: (PlayerRecord) -> Void

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var handicap: Double?

    private var trimmedName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// `nil` represented as -1 on the wheel; every other value is a whole-number handicap 0...40.
    private var wheelValue: Binding<Int> {
        Binding(
            get: { handicap.map { Int($0.rounded()) } ?? -1 },
            set: { handicap = $0 < 0 ? nil : Double($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $firstName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Last name (optional)", text: $lastName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                RoundPlaySectionHeader("Name")
            } footer: {
                if player == nil {
                    RoundPlayTypography.caption("Leave blank for a random nickname.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Handicap", selection: wheelValue) {
                    Text("No handicap").tag(-1)
                    ForEach(0...40, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
            } header: {
                RoundPlaySectionHeader("Handicap")
            } footer: {
                RoundPlayTypography.caption("Optional. Leave blank to play off scratch. Strokes are given on the hardest holes.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(player == nil ? "New Player" : "Edit Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            let parts = (player?.name ?? "").split(separator: " ", maxSplits: 1)
            firstName = parts.first.map(String.init) ?? ""
            lastName = parts.count > 1 ? String(parts[1]) : ""
            handicap = player?.handicapIndex
        }
    }

    private func save() {
        let resolvedName = trimmedName.isEmpty ? assignNickname() : trimmedName
        let record: PlayerRecord
        if let player {
            player.name = resolvedName
            player.handicapIndex = handicap
            record = player
        } else {
            record = PlayerRecord(name: resolvedName, handicapIndex: handicap)
            modelContext.insert(record)
        }
        try? modelContext.save()
        onSave(record)
        dismiss()
    }

    private func assignNickname() -> String {
        let usedNames = Set(allPlayers.map(\.name))
        return GuestNickname.random(avoiding: usedNames)
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
