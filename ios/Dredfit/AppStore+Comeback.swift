//
// The read-only companion of the comeback card (issue #127): what the two
// offers actually are in numbers. Nothing here mutates state — the mutation
// (acceptComeback) stays in AppStore proper.
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

    /// The WHOLE plan of that appearance, probe included. On a probing
    /// appearance the last set belongs to the NEXT movement, and `display`
    /// prints only the working sets — so "2×15" alone would understate the
    /// plan and could sit next to an "easier" row with a bigger number in it.
    private func line(_ ex: SessionExercise) -> String {
        let plan = "\(ex.name) · \(ex.display)"
        guard let probe = ex.probe else { return plan }
        return String(localized: "\(plan) + probe: \(probe.name) · \(probe.display)")
    }
}
