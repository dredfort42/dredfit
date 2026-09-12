//
//  What a break does: the comeback (v2.3) and the silent decay (v2.4).
//
//  Both are pure functions the app layer calls when the app opens after a
//  pause — never from `applyFeedback`: a break is not a training event and it
//  does not move the counter. Every pattern is lowered, `pull_bar` included
//  even with `hasBar` false: a break detrains the whole body.
//
//  §40.3 carries the return scale over by "1 old level = 1 rep per set". The
//  descent uses the same rungs as every other mechanism (`fallDoses`), so the
//  identity of §14.2 — "a return equals a decay plus a weakened return" —
//  holds BY CONSTRUCTION: walking 1 step and then drop−1 steps is walking drop
//  steps. The separate compensation code for the silent decay is gone; it was
//  needed only because the return used to be absolute level arithmetic.
//

import Foundation

extension Engine {

    /// The four "floors" of the old ceiling table stretched linearly over a
    /// ladder of N rungs: floor 1 is always the first variation, floor 4 always
    /// the top one.
    static func ceilVar(pattern p: Pattern, floorIndex: Int) -> Int {
        let n = Library.count(p)
        let scaled = Double((floorIndex - 1) * (n - 1)) / Double(EngineConfig.comebackCeilFloors - 1)
        return EngineState.clamped(1 + Int(scaled.rounded()), 1, n)
    }

    /// v2.12 (§22.3): a run of returns. Comebacks in a row with no session
    /// between them each deepen the drop by one (capped at `comebackMax`).
    public static func applyComeback(state dirty: EngineState, gapDays rawGap: Int,
                                     alreadyDecayed: Bool = false) -> EngineState {
        let gapDays = EngineState.clamped(rawGap, 0, EngineConfig.countMax)
        guard gapDays >= EngineConfig.comebackMinGapDays else { return dirty }
        let state = dirty.sanitized()
        let returnRun = state.returnRun
        var drop = EngineState.clamped(
            EngineConfig.comebackBase
                + (gapDays - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays
                + returnRun,
            2, EngineConfig.comebackMax)
        if alreadyDecayed { drop -= 1 }
        let ceilFloor = EngineConfig.comebackLandingCeil.first { gapDays >= $0.0 }?.1

        var next = state
        next.sub = [:]                     // a return is a descent: sub-steps come off everywhere
        next.lastHard = []                 // a break erases the evidence of hardness
        next.lessRun = 0
        next.creditPaused = []
        next.lessHist = [:]                // a return rebuilds positions; the window is about others
        next.returnRun = returnRun + 1
        next.rampWindow = EngineConfig.rampWindowSessions
        next.weekGain = [:]
        next.weekAgeDays = 0
        for p in Pattern.allCases {
            var pos = fallDoses(p, state.position(p), drop, shown: state.shown)
            if let ceilFloor {
                // The landing ceiling is ABSOLUTE and always the FLOOR of a
                // variation: landing on the ceiling cannot hand out a high dose
                // by construction. `min` composes with the `alreadyDecayed`
                // weakening without a correction, so §14.2 survives it too.
                let ceiling = ceilVar(pattern: p, floorIndex: ceilFloor)
                let floorDose = Dose.grid(Library.unit(p, ceiling)).min
                if pos.variation > ceiling {
                    pos = Position(variation: ceiling, sets: EngineConfig.setsBase,
                                   dose: floorDose, sub: 0, cut: 0)
                } else if pos.variation == ceiling {
                    pos = fit(p, Position(variation: pos.variation, sets: pos.sets,
                                          dose: floorDose, sub: 0, cut: pos.cut))
                }
            }
            setPosition(&next, p, pos)
            next.failStreak[p] = 0
        }
        return next
    }

    /// The blind spot of 7–13 days: the comeback says nothing and the body has
    /// already lost a rung. One quiet rung of dose off every pattern; the
    /// counter does not move.
    ///
    /// NOT idempotent, exactly like `applyComeback` — the app layer applies it
    /// at most once per break, keyed on `comebackDecidedFor`.
    public static func applySilentDecay(state dirty: EngineState, gapDays rawGap: Int) -> EngineState {
        let gapDays = EngineState.clamped(rawGap, 0, EngineConfig.countMax)
        guard gapDays >= EngineConfig.silentDecayGapDays,
              gapDays < EngineConfig.comebackMinGapDays else { return dirty }
        let state = dirty.sanitized()
        var next = state
        next.sub = [:]                     // a decay is a descent: sub-steps come off
        next.lessRun = 0                   // the run of "less" does not survive it (§19.1)
        next.creditPaused = []
        for p in Pattern.allCases {
            setPosition(&next, p, fallDoses(p, state.position(p), 1, shown: state.shown))
            next.failStreak[p] = 0
        }
        return next
    }
}
