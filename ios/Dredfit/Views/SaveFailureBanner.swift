//
//  The line that says a write failed, wherever the person is.
//
//  The store keeps a failed change in memory and keeps working, so nothing on
//  screen changed when the disk refused it — and a quit then lost the workout
//  without a word. This is that word, and the way to answer it.
//

import SwiftUI

struct SaveFailureBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Room kept free at the trailing edge for something drawn over this
    /// screen: Today's settings gear sits exactly where "Try again" would.
    let trailingClearance: CGFloat

    var body: some View {
        // Beside the button while the line is short, under the message once
        // the type is large enough that the two would squeeze each other.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("Couldn't save your progress. It's kept only until you close the app.")
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
        // the banner overflowed upward under the status bar.
        .fixedSize(horizontal: false, vertical: true)
        // One container for VoiceOver: the message is read first, the button
        // is the next stop.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("save-failed-banner")
    }
}

extension View {
    /// A top inset rather than an overlay: it moves the content down instead
    /// of covering it, so the workout's controls stay reachable, and the top is
    /// the one edge both Today and the work screen leave free of controls.
    /// Applied at the root of Today AND of the workout, because the workout's
    /// full-screen cover hides everything the root draws — and on the TabView
    /// itself the inset left each tab's content running under the banner.
    func saveFailureBanner(_ store: AppStore, trailingClearance: CGFloat = 0) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if store.lastPersistError != nil {
                SaveFailureBanner(trailingClearance: trailingClearance)
            }
        }
    }
}
