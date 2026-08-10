import SwiftUI

/// A wheel picker for handicap — no keyboard, no typing, matching the score picker elsewhere in
/// the app. Shared between round setup (anonymous seats) and the Players tab (adding someone).
struct HandicapPickerSheet: View {
    @Binding var handicap: Double?
    @Environment(\.dismiss) private var dismiss

    /// `nil` represented as -1 on the wheel; every other value is a whole-number handicap 0...40.
    private var wheelValue: Binding<Int> {
        Binding(
            get: { handicap.map { Int($0.rounded()) } ?? -1 },
            set: { handicap = $0 < 0 ? nil : Double($0) }
        )
    }

    var body: some View {
        NavigationStack {
            Picker("Handicap", selection: wheelValue) {
                Text("No handicap").tag(-1)
                ForEach(0...40, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle("Handicap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
