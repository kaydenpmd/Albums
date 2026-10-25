import SwiftUI

// No custom accent color, on purpose. iOS 27.2 took the pink-red out of the
// Music app (9to5Mac, 13 Oct 2026): its icon went black and white and its
// highlights went to the system's default blue. Leaving the tint alone gives
// the same blue, and follows any change Apple makes to it.

/// The small "E" Apple Music shows next to explicit titles.
struct ExplicitBadge: View {
    var body: some View {
        Image(systemName: "e.square.fill")
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
    }
}
