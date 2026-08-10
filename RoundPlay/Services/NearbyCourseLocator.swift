import CoreLocation
import Observation

/// One-shot "where am I" for the Nearest Courses section — no background tracking, no continuous
/// updates, just enough to sort the catalog once when the screen appears.
@MainActor
@Observable
final class NearbyCourseLocator: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requesting
        case located(CLLocation)
        case denied
        case unavailable
    }

    private(set) var state: State = .idle
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // Sorting courses by distance never needs GPS-grade precision — reduced accuracy (city
        // block, roughly) is plenty, costs less battery, and is the honest ask to make. The
        // system permission prompt still lets the user flip on Precise Location themselves if
        // they want to; we just never request it.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func requestLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            state = .unavailable
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .requesting
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            state = .requesting
            manager.requestLocation()
        @unknown default:
            state = .unavailable
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                state = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in state = .located(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in state = .unavailable }
    }
}
