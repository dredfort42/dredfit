//
//  Activity<T> is not Sendable, so all async work looks the activity up by
//  id inside one task — nothing crosses an isolation boundary. When
//  activities are unavailable or denied, every call is a silent no-op.
//

import ActivityKit
import Foundation

final class WorkoutActivityController {

    private var activityID: String?
    /// The tail of a FIFO chain: every operation awaits its predecessor, so
    /// ActivityKit sees them in call order. Without it two quick phase flips
    /// (rest → "Skip rest" → work) race and strand a stale countdown.
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
        // Request FIRST, then sweep: a concurrent sweep could end the very
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

    /// Cold-start sweep: any activity still alive is an orphan from a killed
    /// session. staleDate only dims content, it never dismisses — without
    /// this a frozen "set 2 of 3" sits there until the system's hours-long cap.
    static func endOrphans() {
        Task.detached {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// When the extension should start dimming content the app stopped
    /// updating. Removal is endOrphans()'s job, not this.
    static func staleDate(for state: RestActivityAttributes.ContentState,
                          now: Date = .now) -> Date {
        if state.phase == .rest, let end = state.restEndDate {
            return end.addingTimeInterval(60)
        }
        return now.addingTimeInterval(20 * 60)
    }
}
