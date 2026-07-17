//
//  RestLiveActivity.swift
//  DredfitWidgets
//
//  v1.3: the workout on the lock screen and in the Dynamic Island.
//  During rest the system ticks the countdown itself via
//  Text(timerInterval:) — no updates needed from the app.
//  All strings arrive pre-localized in the content state.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            lockScreen(context.state)
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
                    .foregroundStyle(WidgetTheme.accent)
            } compactTrailing: {
                countdown(context.state, size: 14)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(WidgetTheme.accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreen(_ state: RestActivityAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WidgetTheme.ink2)
                    .lineLimit(1)
                Text(state.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            countdown(state, size: 34)
        }
        .padding(16)
        .activityBackgroundTint(.white)
        .activitySystemActionForegroundColor(WidgetTheme.ink)
    }

    /// The rest countdown; during work — a quiet accent dot instead.
    @ViewBuilder
    private func countdown(_ state: RestActivityAttributes.ContentState, size: CGFloat) -> some View {
        if state.phase == .rest, let end = state.restEndDate, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(.system(size: size, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.accent)
                .frame(maxWidth: size * 2.4)
                .multilineTextAlignment(.trailing)
        } else {
            Circle()
                .fill(WidgetTheme.accent)
                .frame(width: size / 2.4, height: size / 2.4)
        }
    }
}
