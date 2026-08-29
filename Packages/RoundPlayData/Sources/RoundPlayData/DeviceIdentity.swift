import Foundation

/// Stable per-install identifier for the phone or watch that wrote an event.
public enum DeviceIdentity {
    private static let defaultsKey = "roundplay.deviceID"

    public static var id: UUID {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let minted = UUID()
        UserDefaults.standard.set(minted.uuidString, forKey: defaultsKey)
        return minted
    }
}
