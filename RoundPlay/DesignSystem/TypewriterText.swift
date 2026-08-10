import SwiftUI

/// Types a string out one character at a time.
///
/// Used for onboarding's value-prop beat, where the pacing *is* the point — the copy reads like
/// it's being told to you across the first tee rather than posted at you as a wall of marketing.
///
/// Two details matter for it not to feel cheap:
/// - The full string is laid out (hidden) underneath, so the paragraph never re-wraps as
///   characters land. Without that, every character that pushes a word to the next line shifts
///   everything below it and the whole screen jitters.
/// - Reduce Motion renders the full string immediately and still fires `onComplete`, so anything
///   sequenced behind this (the rows that fade in after it) doesn't get stranded.
struct TypewriterText: View {
    let text: String
    var characterInterval: Duration = .milliseconds(26)
    var startDelay: Duration = .zero
    var onComplete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleCount = 0

    init(
        _ text: String,
        characterInterval: Duration = .milliseconds(26),
        startDelay: Duration = .zero,
        onComplete: (() -> Void)? = nil
    ) {
        self.text = text
        self.characterInterval = characterInterval
        self.startDelay = startDelay
        self.onComplete = onComplete
    }

    var body: some View {
        Text(text)
            .hidden()
            .overlay(alignment: .topLeading) {
                Text(String(text.prefix(visibleCount)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // VoiceOver should hear the finished sentence, not a string growing by a letter at a
            // time — the animation is decoration, the copy is the content.
            .accessibilityElement()
            .accessibilityLabel(text)
            .task(id: text) { await type() }
    }

    private func type() async {
        guard !reduceMotion else {
            visibleCount = text.count
            onComplete?()
            return
        }

        visibleCount = 0
        if startDelay > .zero {
            try? await Task.sleep(for: startDelay)
            guard !Task.isCancelled else { return }
        }

        for offset in text.indices {
            try? await Task.sleep(for: characterInterval)
            guard !Task.isCancelled else { return }
            visibleCount = text.distance(from: text.startIndex, to: offset) + 1
        }
        onComplete?()
    }
}

#Preview {
    VStack(alignment: .leading) {
        TypewriterText("Here's what we'll take off your hands.")
            .font(RoundPlayFont.archivo(32, .black))
    }
    .padding()
}
