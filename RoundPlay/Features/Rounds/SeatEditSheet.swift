import SwiftUI
import SwiftData
import RoundPlayData

/// Rename a seat or fix its handicap mid-round. The handicap is always the seat's own copy —
/// a round always settles using the number agreed on when it started, so a correction here fixes
/// this round without silently changing anyone's roster handicap. A name correction is different:
/// it's normally just fixing a typo in someone real, so saving offers to carry it into the roster
/// too — updating the linked player if this seat already has one, or creating a new roster entry
/// for a guest/placeholder seat that's being given a real name for the first time.
struct SeatEditSheet: View {
    @Bindable var seat: SeatRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var players: [PlayerRecord]

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var courseHandicap: Int = 0
    @State private var updatesRoster = true
    @State private var savesNewNameToRoster = true

    private var linkedPlayer: PlayerRecord? {
        players.first { $0.id == seat.playerID }
    }

    private var trimmedName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var isNameChanged: Bool { trimmedName != seat.name }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    TextField("Last name (optional)", text: $lastName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if let linkedPlayer, trimmedName != linkedPlayer.name {
                        Toggle("Also update in Roster", isOn: $updatesRoster)
                    } else if linkedPlayer == nil, isNameChanged {
                        Toggle("Save to Roster", isOn: $savesNewNameToRoster)
                    }
                } header: {
                    RoundPlaySectionHeader("Name")
                } footer: {
                    if linkedPlayer != nil {
                        RoundPlayTypography.caption("This is \(linkedPlayer?.name ?? "a") from your roster. You can fix their name here and in the roster at the same time.")
                            .foregroundStyle(.secondary)
                    } else if isNameChanged {
                        RoundPlayTypography.caption("Not in your roster yet. Save it there so it's one tap away next time.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Course Handicap", selection: $courseHandicap) {
                        ForEach(0...40, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    RoundPlaySectionHeader("Course Handicap")
                } footer: {
                    RoundPlayTypography.caption("This round only. Your roster handicap is unchanged.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Player")
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
                let parts = seat.name.split(separator: " ", maxSplits: 1)
                firstName = parts.first.map(String.init) ?? ""
                lastName = parts.count > 1 ? String(parts[1]) : ""
                courseHandicap = seat.courseHandicap
            }
        }
    }

    private func save() {
        let renamed = isNameChanged
        seat.name = trimmedName
        seat.courseHandicap = courseHandicap
        if let linkedPlayer {
            if updatesRoster {
                linkedPlayer.name = trimmedName
            }
        } else if renamed && savesNewNameToRoster {
            let newPlayer = PlayerRecord(name: trimmedName, handicapIndex: Double(courseHandicap))
            newPlayer.lastPlayedAt = Date()
            newPlayer.playCount = 1
            modelContext.insert(newPlayer)
            seat.playerID = newPlayer.id
        }
        try? modelContext.save()
        dismiss()
    }
}
