import SwiftUI
import UIKit

/// Thin wrapper around the native iOS share sheet (`UIActivityViewController`) — Messages, Mail,
/// AirDrop, Save Image, all for free, instead of hand-rolling a share picker.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
