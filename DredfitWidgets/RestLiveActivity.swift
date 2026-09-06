//
//  During rest the system ticks the countdown itself via
//  Text(timerInterval:) — no updates needed from the app. All strings
//  arrive pre-localized in the content state.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Stale content dims instead of impersonating a live state.
            lockScreen(context.state)
                .opacity(context.isStale ? 0.45 : 1)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.detail)
                        .dredfitFont(13)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state, size: 24, cap: 30)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.title)
                        .dredfitFont(16, weight: .semibold)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.functional")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                // Capped at its own design size: the compact slot beside the
                // sensor housing is a fixed system capsule, so growth here is
                // clipped by the system rather than read by anyone.
                countdown(context.state, size: 14, cap: 14)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreen(_ state: RestActivityAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.detail)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                Text(state.title)
                    .dredfitFont(17, weight: .bold)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            countdown(state, size: 34, cap: 46)
        }
        .padding(16)
        // No manual tint: the lock screen supplies its own material and keeps
        // it in step with the system appearance. Painting the card was what
        // made it a white flash on a dark lock screen.
        .activitySystemActionForegroundColor(Theme.ink)
    }

    @ViewBuilder
    private func countdown(_ state: RestActivityAttributes.ContentState,
                           size: CGFloat, cap: CGFloat) -> some View {
        // Not `== .rest` any more: a hold sends its own end date through the
        // same field, and this is the one Dredfit countdown that keeps running
        // while the app is suspended — the phase that asks you to put the
        // phone down is the phase that needs it (UX review 05.09.2026).
        if state.phase != .work, let end = state.restEndDate, end > .now {
            CountdownLabel(end: end, size: size, cap: cap)
        } else {
            Circle()
                .fill(Theme.accent)
                .frame(width: size / 2.4, height: size / 2.4)
        }
    }
}

/// The number read off the lock screen from across the room — and the one
/// `.system(size:)` froze at 34 pt however large the reader's type setting
/// was (UX review 05.09.2026).
///
/// `cap` is the exception the rule allows: a display number, in a container
/// whose height belongs to the system, where unbounded growth clips the tile
/// instead of helping. The frame follows the SAME capped value the font does,
/// rather than the design size — it exists to stop the block jumping when
/// "1:00" becomes "59", and a frame left at 34 pt would crop scaled digits.
private struct CountdownLabel: View {
    private let end: Date
    private let design: CGFloat
    private let cap: CGFloat
    @ScaledMetric private var scaled: CGFloat

    init(end: Date, size: CGFloat, cap: CGFloat) {
        self.end = end
        self.design = size
        self.cap = cap
        _scaled = ScaledMetric(wrappedValue: size,
                               relativeTo: Font.TextStyle.forDesignSize(size))
    }

    var body: some View {
        // monospacedDigit on the Text and BEFORE the font: it resolves against
        // whatever font the text ends up with, while the same call moved
        // outside dredfitFont would sit above the font that modifier sets and
        // lose to it — and non-monospaced digits are the jump the frame below
        // exists to prevent.
        Text(timerInterval: Date.now...end, countsDown: true)
            .monospacedDigit()
            .dredfitFont(design, weight: .heavy, cap: cap)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: min(scaled, cap) * 2.4)
            .multilineTextAlignment(.trailing)
    }
}
