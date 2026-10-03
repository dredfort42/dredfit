import SwiftUI

extension View {
    /// Taps that land in the first moments after `screen` changes do nothing.
    ///
    /// Consecutive screens of the workout put different buttons in the same
    /// place — "Start the warm-up" on the offer and "Skip warm-up" on the block
    /// it opens, "Done" on a hold's summary and "Skip rest" or "+15 s" on the
    /// rest after it — so the second tap of a double tap meant for the first
    /// screen would act on the second one.
    ///
    /// Keyed by the screen, never by what it shows: "+15 s" changes the rest's
    /// total, not the screen, and must not lock the button for the next tap.
    func settleWindow(after screen: some Hashable) -> some View {
        modifier(SettleWindow(screen: screen))
    }
}

/// Long enough to swallow the second tap of a double tap, short enough that
/// nobody reaches for a button inside it on purpose. The UI suite taps as soon
/// as a screen appears, so under its launch flags the window all but closes.
enum SettleWindowLength {
    static var value: Duration {
        #if DEBUG
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--uitest") }) {
            return .milliseconds(50)
        }
        #endif
        return .milliseconds(350)
    }
}

private struct SettleWindow<Screen: Hashable>: ViewModifier {
    let screen: Screen
    @State private var settled = true
    /// Only ever cancelled by the wait that replaces it, never by the view
    /// going away: a wait cancelled on its own would leave the screen locked.
    @State private var waiting: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(settled)
            .onChange(of: screen) {
                settled = false
                waiting?.cancel()
                waiting = Task {
                    // Throws only when cancelled, and a cancelled wait has
                    // been replaced by a newer one that unlocks instead.
                    try? await Task.sleep(for: SettleWindowLength.value)
                    guard !Task.isCancelled else { return }
                    settled = true
                }
            }
    }
}
