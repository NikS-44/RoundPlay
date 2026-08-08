import SwiftUI
import UIKit

private let accordionCaretDuration: TimeInterval = 0.22

/// UIKit-backed chevron so expansion uses **only** a layer transform animation. SwiftUI's default
/// list/content transitions won't treat the caret as a newly inserted view (no slide/fade from top or bottom).
private struct AccordionCaretUIView: UIViewRepresentable {
    var expanded: Bool

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear

        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let image = UIImage(systemName: "chevron.down", withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        let iv = UIImageView(image: image)
        iv.tintColor = UIColor.secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.isAccessibilityElement = false
        iv.translatesAutoresizingMaskIntoConstraints = false

        host.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 18),
            iv.heightAnchor.constraint(equalToConstant: 18),
            host.widthAnchor.constraint(equalToConstant: 22),
            host.heightAnchor.constraint(equalToConstant: 22),
        ])

        context.coordinator.imageView = iv
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        guard let iv = context.coordinator.imageView else { return }
        let angle: CGFloat = expanded ? .pi : 0

        if !context.coordinator.didLayOutInitialTransform {
            iv.transform = CGAffineTransform(rotationAngle: angle)
            context.coordinator.didLayOutInitialTransform = true
            context.coordinator.expanded = expanded
            return
        }

        guard expanded != context.coordinator.expanded else { return }
        context.coordinator.expanded = expanded

        UIView.animate(
            withDuration: accordionCaretDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            iv.transform = CGAffineTransform(rotationAngle: angle)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var imageView: UIImageView?
        var didLayOutInitialTransform = false
        var expanded: Bool = false
    }
}

/// A collapsible section with optional top and bottom dividers framing the title row and content.
///
/// Designed to be embedded inside `RoundPlayList.plain { ... }` as `Section { ... }` content;
/// consumers wrap rows in their own `Section` so list semantics stay intact.
struct AccordionSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    var showsTopDivider: Bool = true
    var showsBottomDivider: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if showsTopDivider {
                Divider()
            }
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("\(title) (\(count))")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    AccordionCaretUIView(expanded: isExpanded)
                        .frame(width: 22, height: 22)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .contentTransition(.identity)
            }
            .buttonStyle(.plain)
            Group {
                if isExpanded {
                    content()
                }
            }
            .clipped()
            .transaction { $0.animation = nil }
            if showsBottomDivider {
                Divider()
            }
        }
    }
}
