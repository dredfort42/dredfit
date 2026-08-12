//
//  RestLiveActivity.swift
//  DredfitWidgets
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
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state, size: 24)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.functional")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                countdown(context.state, size: 14)
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                Text(state.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            countdown(state, size: 34)
        }
        .padding(16)
        // No manual tint: the lock screen supplies its own material and keeps
        // it in step with the system appearance. Painting the card was what
        // made it a white flash on a dark lock screen.
        .activitySystemActionForegroundColor(Theme.ink)
    }

    @ViewBuilder
    private func countdown(_ state: RestActivityAttributes.ContentState, size: CGFloat) -> some View {
        if state.phase == .rest, let end = state.restEndDate, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(.system(size: size, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: size * 2.4)
                .multilineTextAlignment(.trailing)
        } else {
            Circle()
                .fill(Theme.accent)
                .frame(width: size / 2.4, height: size / 2.4)
        }
    }
}
