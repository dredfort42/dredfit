//
// The read-only companions of the comeback card (issue #127): what the two
// offers actually are in numbers, and what accepting would subtract now.
// Nothing here mutates state — the mutation (acceptComeback) stays in AppStore
// proper. The illness lens that shared this file is gone; why, and what
// covers its window instead, is at the bottom.
//

import Foundation
import DredfitCore

extension AppStore {

    /// Both offers of the comeback card as the same movement, in numbers
    /// (#127): the pull slot is in every session, so it is the honest
    /// exemplar of what "easier" — or "as it was" — actually means.
    func comebackPreview(now: Date? = nil) -> (was: String, easier: String)? {
        guard let gap = gapDays(now: now) else { return nil }
        let after = Engine.applyComeback(state: engineState, gapDays: gap,
                                         alreadyDecayed: silentDecayAppliedForCurrentBreak)
        let slot: (EngineState) -> SessionExercise? = { state in
            Engine.generateSession(state).exercises.first { Pattern.pullSide.contains($0.pattern) }
        }
        guard let was = slot(engineState), let easier = slot(after) else { return nil }
        return ("\(was.name) · \(was.display)", "\(easier.name) · \(easier.display)")
    }

    /// After a silent decay for the same break this is the weakened
    /// remainder — what accepting would actually subtract now.
    func comebackDrop(now: Date? = nil) -> Int {
        guard let gap = gapDays(now: now) else { return 0 }
        let before = engineState
        let after = Engine.applyComeback(state: before, gapDays: gap,
                                         alreadyDecayed: silentDecayAppliedForCurrentBreak)
        return (before.levels[.pull] ?? 0) - (after.levels[.pull] ?? 0)
    }

    // The "I was sick" lens is gone, and with it `illnessSessionsLeft` and the
    // quiet offer that armed it. The lens made the plan HEAVIER in 76 cells
    // out of 480 — the opposite of what the offer promised — so there was
    // nothing to keep.
    //
    // The window it covered (a 2–13 day gap, below the comeback and past a
    // missed beat) is not left empty: a person coming back from a break skips
    // sets on the work screen as they go, which shortens the session without
    // touching the levels and without a six-session tail.
}
