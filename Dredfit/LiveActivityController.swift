//
//  LiveActivityController.swift
//  Dredfit
//
//  v1.3: one Live Activity per workout — the rest countdown on the lock
//  screen and in the Dynamic Island. Started with the workout, updated on
//  phase changes, always ended on exit. When activities are unavailable
//  or denied, every call is a silent no-op.
//
//  Activity<T> is not Sendable, so all async work looks the activity up
//  by id inside one task — nothing crosses an isolation boundary.
//
//  v1.6: updates are chained FIFO instead of one detached task per call —
//  two quick phase flips (rest → "Skip rest" → work) used to race, and the
//  loser could leave a stale rest countdown on the lock screen.
//

import ActivityKit
import Foundation

final class WorkoutActivityController {

    private var activityID: String?
    /// The tail of the FIFO chain: every operation awaits its predecessor,
    /// so ActivityKit sees them strictly in call order.
    private var chain: Task<Void, Never>?

    private func enqueue(_ op: @escaping @Sendable () async -> Void) {
        let previous = chain
        chain = Task.detached {
            await previous?.value
            await op()
        }
    }

    func start(sessionNumber: Int, state: RestActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Request the new activity FIRST, then sweep everything else — a
        // sweep that ran concurrently with the request could end the very
        // activity we just created.
        let newID = try? Activity.request(
            attributes: RestActivityAttributes(sessionNumber: sessionNumber),
            content: .init(state: state, staleDate: Self.staleDate(for: state))).id
        activityID = newID
        enqueue {
            for stale in Activity<RestActivityAttributes>.activities where stale.id != newID {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func update(_ state: RestActivityAttributes.ContentState) {
        guard let id = activityID else { return }
        let stale = Self.staleDate(for: state)
        enqueue {
            for activity in Activity<RestActivityAttributes>.activities where activity.id == id {
                await activity.update(.init(state: state, staleDate: stale))
            }
        }
    }

    func end() {
        guard let id = activityID else { return }
        activityID = nil
        enqueue {
            for activity in Activity<RestActivityAttributes>.activities where activity.id == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Cold-start sweep (v1.6): no workout can be in progress when the process
    /// launches, so any activity still alive is an orphan from a killed or
    /// crashed session. staleDate alone only dims the content — it never
    /// dismisses, and without this sweep a frozen "set 2 of 3" would sit on
    /// the lock screen until the system's multi-hour cap.
    static func endOrphans() {
        Task.detached {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// When the content should be considered out of date if the app stops
    /// updating it: rest shortly after its own countdown ends; a work set
    /// after a generous cap it can't realistically outlast. The extension
    /// renders stale content dimmed — actual removal is endOrphans()'s job.
    static func staleDate(for state: RestActivityAttributes.ContentState,
                          now: Date = .now) -> Date {
        if state.phase == .rest, let end = state.restEndDate {
            return end.addingTimeInterval(60)
        }
        return now.addingTimeInterval(20 * 60)
    }
}
