import SwiftUI

/// Presentation styling for "glass" bottom sheets — the compact, frosted look used for quick
/// setup sheets. The sheet stays partial-height (so the darkened backdrop shows behind it)
/// with rounded corners and a drag indicator.
///
/// We deliberately do **not** override `presentationBackground`: iOS's native partial-sheet
/// background already renders as translucent glass over the dimmed content. Forcing a flat
/// `.ultraThinMaterial` fill instead samples the dim layer and reads as solid grey. Hiding the
/// scroll content background (which propagates through the environment to any `Form`/`List` in the
/// sheet) lets that native glass show through instead of an opaque grouped background.
struct GlassBottomSheetModifier: ViewModifier {
    var detents: Set<PresentationDetent> = [.medium]
    var cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(cornerRadius)
    }
}

extension View {
    /// Applies the glass bottom-sheet look: partial-height, darkened backdrop, frosted material,
    /// rounded corners. Apply to a sheet's root view (e.g. the `NavigationStack`).
    ///
    /// - Parameter detents: presentation detents; defaults to `[.medium]`. Pass `[.medium, .large]`
    ///   for longer forms that should open at medium but allow expanding.
    func glassBottomSheet(detents: Set<PresentationDetent> = [.medium]) -> some View {
        modifier(GlassBottomSheetModifier(detents: detents))
    }
}
