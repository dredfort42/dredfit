//
//  What a break does: the comeback and the silent decay.
//
//  Both are pure functions the app layer calls when the app opens after a
//  pause — never from `applyFeedback`: a break is not a training event and it
//  does not move the counter. Every pattern is lowered, `pull_bar` included
//  even with `hasBar` false: a break detrains the whole body.
//
//  The descent uses the same rungs as every other mechanism (`fallDoses`), so
//  "a return equals a decay plus a weakened return" holds BY CONSTRUCTION.
//
//  The only file of the engine that sees calendar time — and even here only
//  as a whole number of days the app hands in.
//

package com.dredfit.core

/** The four landing-ceiling "floors" stretched linearly over a ladder of N
 *  rungs: floor 1 is always the first variation, floor 4 always the top one. */
internal fun Engine.ceilVar(pattern: Pattern, floorIndex: Int): Int {
    val n = Library.count(pattern)
    val scaled = ((floorIndex - 1) * (n - 1)).toDouble() / (EngineConfig.comebackCeilFloors - 1).toDouble()
    return EngineState.clamped(1 + roundedAwayFromZero(scaled).toInt(), 1, n)
}

/** A run of returns: comebacks in a row with no session between them each
 *  deepen the drop by one (capped at `comebackMax`). */
fun Engine.applyComeback(state: EngineState, gapDays: Int,
                         alreadyDecayed: Boolean = false): EngineState {
    val gap = EngineState.clamped(gapDays, 0, EngineConfig.countMax)
    if (gap < EngineConfig.comebackMinGapDays) return state.copy()
    val clean = state.sanitized()
    val returnRun = clean.returnRun
    var drop = EngineState.clamped(
        EngineConfig.comebackBase +
            (gap - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays +
            returnRun,
        2, EngineConfig.comebackMax)
    if (alreadyDecayed) drop -= 1
    val ceilFloor = EngineConfig.comebackLandingCeil.firstOrNull { gap >= it.first }?.second

    val next = clean.copy()
    next.sub.clear()                    // a return is a descent: sub-steps come off everywhere
    next.lastHard.clear()               // a break erases the evidence of hardness
    next.lessRun = 0
    next.creditPaused.clear()
    next.lessHist.clear()               // a return rebuilds positions; the window is about others
    next.returnRun = returnRun + 1
    next.rampWindow = EngineConfig.rampWindowSessions
    next.weekGain.clear()
    next.weekAgeDays = 0.0
    for (p in Pattern.allCases) {
        var pos = fallDoses(p, clean.position(p), drop, shown = clean.shown)
        if (ceilFloor != null) {
            // The landing ceiling is ABSOLUTE and always the FLOOR of a
            // variation: landing on the ceiling cannot hand out a high dose by
            // construction. `min` composes with the `alreadyDecayed` weakening
            // without a correction.
            val ceiling = ceilVar(pattern = p, floorIndex = ceilFloor)
            val floorDose = Dose.grid(Library.unit(p, ceiling)).min
            if (pos.variation > ceiling) {
                pos = Position(variation = ceiling, sets = EngineConfig.setsBase,
                               dose = floorDose, sub = 0, cut = 0)
            } else if (pos.variation == ceiling) {
                pos = fit(p, Position(variation = pos.variation, sets = pos.sets,
                                      dose = floorDose, sub = 0, cut = pos.cut))
            }
        }
        setPosition(next, p, pos)
        next.failStreak[p] = 0
    }
    return next
}

/** The blind spot of 7–13 days: one quiet rung of dose off every pattern; the
 *  counter does not move. NOT idempotent — the app layer applies it at most
 *  once per break, keyed on `comebackDecidedFor`. */
fun Engine.applySilentDecay(state: EngineState, gapDays: Int): EngineState {
    val gap = EngineState.clamped(gapDays, 0, EngineConfig.countMax)
    if (gap < EngineConfig.silentDecayGapDays || gap >= EngineConfig.comebackMinGapDays) {
        return state.copy()
    }
    val clean = state.sanitized()
    val next = clean.copy()
    next.sub.clear()                    // a decay is a descent: sub-steps come off
    next.lessRun = 0                    // the run of "less" does not survive it
    next.creditPaused.clear()
    for (p in Pattern.allCases) {
        setPosition(next, p, fallDoses(p, clean.position(p), 1, shown = clean.shown))
        next.failStreak[p] = 0
    }
    return next
}
