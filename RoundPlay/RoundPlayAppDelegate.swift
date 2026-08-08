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
        UITableViewCell.appearance().layoutMargins = .zero

        return true
    }
}
