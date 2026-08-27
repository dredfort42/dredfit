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
        return (line(was), line(easier))
    }

    /// The WHOLE plan of that appearance, probe included. A probing appearance
    /// carries one set of the NEXT movement on top of its working sets
    /// (§40.4), and `display` prints only the working ones — so a row reading
    /// "2×15" understated the work and made the two offers look incomparable:
    /// the card sat next to an "easier" row with a bigger number in it
    /// (UI-truth audit, 27.08.2026; the arithmetic behind it is §41.10).
    private func line(_ ex: SessionExercise) -> String {
        let plan = "\(ex.name) · \(ex.display)"
        guard let probe = ex.probe else { return plan }
        return String(localized: "\(plan) + probe: \(probe.name) · \(probe.display)")
    }

    // `comebackDrop` — "how many levels accepting would subtract" — went with
    // the level itself (§40.7). Nothing called it: the card shows the two
    // plans as movements and doses, which is the honest form of the same
    // answer and the only one v3 can state.

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
