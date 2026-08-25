//
//  The athlete's handles.
//
//  v2.26 removed the two mechanisms that decided FOR the person — the pain
//  channel and the time budget — and gave back controls that decide WITH them.
//  v2.27 removed the last two that still asked for the decision BEFORE the
//  workout: "shorter today" and "fewer sets" on the plan. Both wanted an
//  answer to a question the person only knows the answer to standing on the
//  mat, and both are replaced by the skip on the work screen (§38.2).
//
//  What is left on the plan is one handle and one number. The handle changes
//  the VARIATION, not the volume — a different question, and the only one
//  worth asking before the first set. The number is the range the session can
//  land in, so "will this fit today" has an answer without a control at all.
//
//  This file holds what the plan can be ASKED. The one action that WRITES
//  state lives in AppStore proper, the same way `acceptComeback` does: the
//  store owns its own mutations. Every handle goes through the ENGINE — the
//  app writing a level or a cut into the state by hand is the bypass of
//  `applyFeedback` the audit counts as a finding: it would skip the floor, the
//  sanitizer, and the position measure the postcondition repair reads.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Per-movement: an easier variation

    /// False on tier 1 — there is no variation below it, and the control says
    /// so instead of disappearing.
    func canMakeEasier(_ pattern: Pattern) -> Bool {
        Engine.easierLevel(pattern: pattern,
                           level: engineState.levels[pattern] ?? 0,
                           sub: engineState.sub[pattern] ?? 0,
                           cut: engineState.cutOf(pattern)) != nil
    }

    /// The name this movement would carry after the handle — shown BEFORE the
    /// tap, so the choice is made on the thing itself rather than on a
    /// promise. Nil when the handle is inactive.
    func easierPreview(_ pattern: Pattern) -> String? {
        guard canMakeEasier(pattern) else { return nil }
        let after = Engine.easierVariation(state: engineState, pattern: pattern)
        return Engine.generateSession(after).exercises
            .first { $0.pattern == pattern }
            .map { "\($0.name) · \($0.display)" }
    }
}
