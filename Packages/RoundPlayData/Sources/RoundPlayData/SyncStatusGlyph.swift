import SwiftUI

public struct SyncStatusGlyph: View {
    public var state: SyncConnectionState

    public init(state: SyncConnectionState) {
        self.state = state
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .live: Color(red: 0.20, green: 0.72, blue: 0.40)
        case .syncing: Color(red: 0.88, green: 0.64, blue: 0.18)
        case .offline: Color.secondary.opacity(0.55)
        }
    }

    private var label: String {
        switch state {
        case .live: "Live"
        case .syncing: "Syncing"
        case .offline: "Offline"
        }
    }
}
