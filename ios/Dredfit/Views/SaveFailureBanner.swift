//
//  The line that says a write failed, on every screen the person can be on
//  (see `saveFailureBanner` for the list).
//
//  The store keeps a failed change in memory and keeps working, so without
//  this nothing on screen would change when the disk refuses a write, and a
//  quit would lose the change without a word.
//

import SwiftUI

struct SaveFailureBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Room kept free at the trailing edge for something drawn over this
    /// screen: Today's settings gear sits exactly where "Try again" would.
    let trailingClearance: CGFloat

    /// One definition for the sentence the banner shows and the one VoiceOver
    /// is told when it appears (RootView); the literal is the catalog key.
    static let message = String(localized: "Couldn't save your latest changes. They'll be lost if the app closes before a save works.")

    var body: some View {
        // Beside the button while the line is short, under the message once
        // the type is large enough that the two would squeeze each other.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(verbatim: Self.message)
                .dredfitFont(13.5, weight: .medium)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.retryPersist()
            } label: {
                Text("Try again")
                    .dredfitFont(13.5, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .underline()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("save-retry")
        }
        .padding(.leading, 14)
        .padding(.trailing, 14 + trailingClearance)
        .padding(.vertical, 4)
        // The accent fill and `ink` words, as the other notes that block
        // nothing: accentText on accentSoft is under 4.5:1 in dark (I-21).
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Its own height at any type size: squeezed by a tall screen below it,
        // the banner would overflow upward under the status bar.
        .fixedSize(horizontal: false, vertical: true)
        // One container for VoiceOver: the message is read first, the button
        // is the next stop. The appearance itself is announced by RootView.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("save-failed-banner")
    }
}

extension View {
    /// A top inset rather than an overlay, so it moves the content down instead
    /// of covering it. Applied wherever the person can be while a write fails:
    /// each of the three tab roots (in RootView, because on the TabView itself
    /// the inset left every tab running under the banner), the Settings sheet,
    /// and the workout's own root, since its full-screen cover hides
    /// everything RootView draws. `trailingClearance` is for the tab screens,
    /// where the settings gear floats over the top-trailing corner.
    func saveFailureBanner(_ store: AppStore, trailingClearance: CGFloat = 0) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if store.lastPersistError != nil {
                SaveFailureBanner(trailingClearance: trailingClearance)
            }
        }
    }
}
