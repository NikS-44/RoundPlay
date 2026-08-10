import UIKit
import Observation

/// The single source of truth `RoundPlayAppDelegate` reads from `application(_:supportedInterfaceOrientationsFor:)`.
///
/// The app is portrait-only everywhere except the full-screen landscape scorecard, which sets
/// this to `.landscape` while it's on screen and puts it back to `.portrait` when dismissed.
@MainActor
@Observable
final class OrientationLock {
    static let shared = OrientationLock()

    var mask: UIInterfaceOrientationMask = .portrait

    private init() {}

    /// Flips the mask and nudges the active scene to actually rotate — setting the mask alone
    /// only changes what's *allowed*, not what's on screen right now.
    func requestLandscape() {
        mask = .landscape
        requestGeometryUpdate(interfaceOrientations: .landscapeRight)
    }

    func requestPortrait() {
        mask = .portrait
        requestGeometryUpdate(interfaceOrientations: .portrait)
    }

    private func requestGeometryUpdate(interfaceOrientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: interfaceOrientations)) { _ in }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
