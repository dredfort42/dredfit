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
//  by id inside one detached task — nothing crosses an isolation boundary.
//

import ActivityKit
import Foundation

final class WorkoutActivityController {

    private var activityID: String?

    func start(sessionNumber: Int, state: RestActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Request the new activity FIRST, then sweep everything else — a
        // detached sweep that ran concurrently with the request could end the
        // very activity we just created.
        let newID = try? Activity.request(
            attributes: RestActivityAttributes(sessionNumber: sessionNumber),
            content: .init(state: state, staleDate: staleDate(for: state))).id
        activityID = newID
        Task.detached {
            for stale in Activity<RestActivityAttributes>.activities where stale.id != newID {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func update(_ state: RestActivityAttributes.ContentState) {
        guard let id = activityID else { return }
        let stale = staleDate(for: state)
        Task.detached {
            for activity in Activity<RestActivityAttributes>.activities where activity.id == id {
                await activity.update(.init(state: state, staleDate: stale))
            }
        }
    }

    func end() {
        guard let id = activityID else { return }
        activityID = nil
        Task.detached {
            for activity in Activity<RestActivityAttributes>.activities where activity.id == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// A staleDate so a killed app doesn't leave a zombie activity lingering
    /// for hours: rest goes stale shortly after the countdown ends; a work
    /// set gets a generous cap it can't realistically outlast.
    private func staleDate(for state: RestActivityAttributes.ContentState) -> Date {
        if state.phase == .rest, let end = state.restEndDate {
            return end.addingTimeInterval(60)
        }
        return Date.now.addingTimeInterval(20 * 60)
    }
}
