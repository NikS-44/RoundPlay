import SpriteKit
import SwiftUI

// MARK: - Celebration center

/// Minimal, dependency-free celebration trigger.
///
/// Deliberately has no mascot view or shared messages catalog — the message is passed in by the
/// caller rather than looked up, so this stays a "fireworks + big word" effect with nothing else
/// to wire up for round completion.
@MainActor
@Observable
final class CelebrationCenter {
    static let shared = CelebrationCenter()

    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let word: String
    }

    private(set) var event: Celebration?

    private init() {}

    func celebrate(_ word: String) {
        event = Celebration(word: word)
    }

    /// Tears the overlay down once the animation has played out. Without this the SpriteKit scene
    /// stays mounted at the app root and keeps rendering particles for the rest of the session —
    /// invisible, but burning CPU and battery on a phone that's usually already back in a pocket.
    func finish(_ id: Celebration.ID) {
        guard event?.id == id else { return }
        event = nil
    }
}

// MARK: - Root overlay

/// Hosts the full-screen fireworks + word. Apply once near the app root.
struct CelebrationOverlay: ViewModifier {
    private let celebrations = CelebrationCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let event = celebrations.event {
                    CelebrationView(event: event, reduceMotion: reduceMotion)
                        .id(event.id)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: celebrations.event?.id)
    }
}

extension View {
    func celebrationOverlay() -> some View {
        modifier(CelebrationOverlay())
    }
}

private struct CelebrationView: View {
    let event: CelebrationCenter.Celebration
    let reduceMotion: Bool

    @State private var scene = FireworksScene()
    @State private var showWord = false
    @State private var hideWord = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea()
            }
            Text(event.word)
                .font(.system(size: 68, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                // 68pt is sized for a single short word; scale rather than clip if a caller ever
                // passes something longer than "CASHED".
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 24)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .scaleEffect(hideWord ? 1.15 : (showWord ? 1 : 0.55))
                .opacity(hideWord ? 0 : (showWord ? 1 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(event.word)
        }
        .ignoresSafeArea()
        .onAppear {
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            let appear: Animation = reduceMotion
                ? .easeOut(duration: 0.2)
                : .spring(response: 0.42, dampingFraction: 0.55)
            withAnimation(appear) { showWord = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.45)) { hideWord = true }
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            CelebrationCenter.shared.finish(event.id)
        }
    }
}
