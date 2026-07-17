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
        // Sweep stale activities from an interrupted session first.
        Task.detached {
            for stale in Activity<RestActivityAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
        activityID = try? Activity.request(
            attributes: RestActivityAttributes(sessionNumber: sessionNumber),
            content: .init(state: state, staleDate: nil)).id
    }

    func update(_ state: RestActivityAttributes.ContentState) {
        guard let id = activityID else { return }
        Task.detached {
            for activity in Activity<RestActivityAttributes>.activities where activity.id == id {
                await activity.update(.init(state: state, staleDate: nil))
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
}
