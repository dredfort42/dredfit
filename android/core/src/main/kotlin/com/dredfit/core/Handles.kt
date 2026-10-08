//
//  The athlete's handles.
//
//  The app does not guess what a person can do. It offers handles and works
//  out the consequences. The handles that change the state do it THROUGH the
//  engine: each starts from the sanitized state and carries a rule the app
//  layer would otherwise have to repeat — the floor of the cut, the landing
//  in the variation below, the order of feedback, cut and raise. That is why
//  they are entry points and not helpers.
//

package com.dredfit.core

import kotlin.math.max
import kotlin.math.min

/** "Give me an easier variation": one variation down, at the dose from the
 *  JOURNAL OF WHAT WAS SHOWN — the journal as the CEILING, not the answer.
 *  On the first variation the handle is inert. */
fun Engine.easierPosition(pattern: Pattern, position: Position,
                          shown: Map<Pattern, Map<Int, Int>>): Position? {
    if (position.variation <= 1) return null
    return landInVar(pattern, position.variation - 1, shown = shown, from = position)
}

fun Engine.easierVariation(state: EngineState, pattern: Pattern): EngineState {
    val clean = state.sanitized()
    val to = easierPosition(pattern = pattern, position = clean.position(pattern),
                            shown = clean.shown) ?: return state.copy()
    val next = clean.copy()
    setPosition(next, pattern, to)
    return next
}

/** "Fewer sets" on one movement (also the entry point a skipped set arrives
 *  through). A set taken off a push leaves a trace (`shownSkip`): a cut is a
 *  descent, and a cap that rises before the next showing must not hand that
 *  set back. */
fun Engine.setCut(state: EngineState, pattern: Pattern, cut: Int): EngineState {
    val clean = state.sanitized()
    val next = clean.copy()
    val pos = clean.position(pattern)
        .let { it.copy(cut = effCut(sets = clean.sets[pattern] ?: EngineConfig.setsBase, cut = cut)) }
    setPosition(next, pattern, pos)
    if (pattern in Pattern.pushSide && pos.cut > clean.cutOf(pattern)) next.shownSkip.add(pattern)
    return next
}

/** "Next time, more" on one movement: `steps` growth events along the DOSE axis
 *  only. The sub-step counts against the sets ON SCREEN (after the cut), not
 *  against the band as `riseBy` does. Zero returns the state AS IS. */
fun Engine.raiseDose(state: EngineState, pattern: Pattern, steps: Int): EngineState {
    val k = min(EngineConfig.raiseStepsMax, max(0, steps))
    if (k <= 0) return state.copy()
    val clean = state.sanitized()
    var cur = fit(pattern, clean.position(pattern))
    for (i in 0 until k) {
        val g = Dose.grid(Library.unit(pattern, cur.variation))
        if (cur.dose >= g.max) break
        cur = if (cur.sub + 1 < cur.sets - cur.cut) {
            cur.copy(sub = cur.sub + 1)
        } else {
            cur.copy(dose = cur.dose + g.step, sub = 0)
        }
    }
    val next = clean.copy()
    setPosition(next, pattern, cur)
    return next
}

/**
 * Feedback plus the sets skipped DURING the session, in the one order that is
 * correct: `applyFeedback` FIRST, then `setCut`; `raised` lands LAST, over
 * both. The golden fixture pins the cut before the skip and the position
 * before the raise, so a port that swaps either order fails by number.
 *
 * `setsSkipped` carries no default: it is what selects this overload.
 */
@Suppress("LongParameterList")
fun Engine.applyFeedback(
    state: EngineState,
    session: Session,
    result: FeedbackResult,
    overrides: Map<Pattern, Double> = emptyMap(),
    skipped: Set<Pattern> = emptySet(),
    setsSkipped: Map<Pattern, Int>,
    gapDays: Double? = null,
    probes: Map<Pattern, Int> = emptyMap(),
    raised: Map<Pattern, Int> = emptyMap(),
): EngineState {
    // The stale-session guard holds for the whole entry point: a replayed
    // session would cut sets and raise doses a second time.
    if (session.sessionNumber != state.sanitized().counter + 1) return state.copy()
    var next = applyFeedback(state = state, session = session, result = result,
                             overrides = overrides, skipped = skipped,
                             gapDays = gapDays, probes = probes)
    // Walked in `Pattern.allCases` order — the reference's `ALL_PATTERNS`.
    for (p in Pattern.allCases) {
        val k = setsSkipped[p] ?: continue
        if (k <= 0) continue
        // Held to the technical range: `k` comes off a persisted record.
        next = setCut(state = next, pattern = p, cut = next.cutOf(p) + min(k, EngineConfig.countMax))
    }
    for (p in Pattern.allCases) {
        val k = raised[p] ?: continue
        if (k <= 0) continue
        next = raiseDose(state = next, pattern = p, steps = k)
    }
    return next
}
