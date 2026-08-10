import UIKit
import UserNotifications

/// UIKit bridge.
///
/// Its one job today is the table-view appearance configuration below. `RoundPlayList`
/// relies on it: without `separatorInset = .zero` and `separatorInsetReference = .fromCellEdges`,
/// SwiftUI insets list separators to the title column and rows with a leading element render
/// with a ragged gap.
final class RoundPlayAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        let table = UITableView.appearance()
        table.separatorInset = .zero
        table.layoutMargins = .zero
        table.separatorInsetReference = .fromCellEdges
        table.keyboardDismissMode = .interactive
        table.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? .systemBackground
                : UIColor(red: 0.961, green: 0.953, blue: 0.933, alpha: 1)
        }
        UITableViewCell.appearance().layoutMargins = .zero
        UITableViewCell.appearance().backgroundColor = .clear

        configureNavigationBarTypography()

        return true
    }

    /// Portrait everywhere except the full-screen scorecard, which flips `OrientationLock.shared`
    /// to landscape while it's on screen — this is the one hook UIKit gives an app to answer
    /// "what orientations are allowed right now" per presentation instead of app-wide.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.shared.mask }
    }

    /// Large and inline titles use Archivo Black, matching every other display-sized headline
    /// in the app — UIKit's appearance proxy is the only way to reach these from SwiftUI.
    private func configureNavigationBarTypography() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [
            .font: UIFont(name: "Archivo-Black", size: 34) ?? .systemFont(ofSize: 34, weight: .black)
        ]
        appearance.titleTextAttributes = [
            .font: UIFont(name: "Archivo-Bold", size: 17) ?? .systemFont(ofSize: 17, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
