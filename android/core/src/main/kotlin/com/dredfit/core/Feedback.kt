//
//  What one rating does to the state.
//

package com.dredfit.core

import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** The result of deciding one exercise. `wantedDown` records the INTENT to
 *  descend rather than the movement of the plan: the streak toward the deload
 *  and the probe's "not hard" condition count the answer, not its effect. */
private class Step(
    var position: Position,
    var wantedDown: Boolean,
    /** Fast adaptation: the dose is what the person did, so the weekly
     *  ceiling leaves the rise alone. */
    var adapted: Boolean = false,
)

/** The weekly window, aged by the gap. */
private class WeekWindow(val haveGap: Boolean, val gain: Map<Pattern, Int>, val ageDays: Double)

/*
 * result:    less | plan | more        — one rating per session
 * overrides: [pattern: actual]         — point facts about the WORKING sets
 *                                        (folded by the mean)
 * skipped:   {pattern, …}              — exercises not done at all
 * gapDays:   number or null            — days since the last workout
 * probes:    [pattern: actual]         — the number from the PROBE SET
 *
 * `probes` is the SEVENTH parameter, and it is seventh deliberately: `gapDays`
 * stays sixth, so every caller written before v3 keeps passing the gap where
 * it always passed it. The probe is its own channel rather than one more
 * number in `overrides`: mixing it into the fold of the working sets would
 * average two different variations.
 */
fun Engine.applyFeedback(
    state: EngineState,
    session: Session,
    result: FeedbackResult,
    overrides: Map<Pattern, Double> = emptyMap(),
    skipped: Set<Pattern> = emptySet(),
    gapDays: Double? = null,
    probes: Map<Pattern, Int> = emptyMap(),
): EngineState {
    val clean = state.sanitized()
    val cleanOverrides = overrides.mapValues { sanitizeActual(it.value) }
    val cleanProbes = probes.mapValues { sanitizeProbe(it.value) }
    // A no-op on a stale pair, exactly as the reference: feedback is valid
    // only for a session generated from THIS state.
    if (session.sessionNumber != clean.counter + 1) return state.copy()

    val entryPos = mutableMapOf<Pattern, Position>()
    for (p in Pattern.allCases) entryPos[p] = clean.position(p)
    val window = rollWeeklyWindow(clean, gapDays = gapDays)

    val next = clean.copy()
    next.counter = clean.counter + 1
    next.returnRun = 0                          // a session breaks the series
    next.rampWindow = max(0, clean.rampWindow - 1)
    next.weekGain = window.gain.toMutableMap()
    next.weekAgeDays = window.ageDays

    val named = namedMovements(session = session, overrides = cleanOverrides)
    val unnamedLess = result == FeedbackResult.less && named.isEmpty()
    val chronic = rollChronicWindow(next, session = session, unnamedLess = unnamedLess,
                                    splitPullSlot = clean.hasBar)
    val targeted = lessTargets(LessAim(
        entryPos = entryPos, session = session, result = result, named = named,
        overrides = cleanOverrides, skipped = skipped, chronic = chronic,
        prevLessRun = clean.lessRun, hist = next.lessHist.toMap()))
    // A named "less" does not feed the run: it is a statement about one
    // movement, not about the plan.
    next.lessRun = if (unnamedLess) clean.lessRun + 1 else 0

    // Patterns that adapted fast by their numbers — a rise the weekly ceiling
    // below leaves alone. Keyed on what the loop did, not on a number being
    // there.
    val adapted = mutableSetOf<Pattern>()
    fun train(pushes: Boolean, bandCeil: Int) {
        for (ex in session.exercises) {
            if (ex.pattern in skipped || (ex.pattern in Pattern.pushSide) != pushes) continue
            if (advance(next, ex = ex, old = entryPos.getValue(ex.pattern), state = clean,
                        result = result, overrides = cleanOverrides, probes = cleanProbes,
                        targeted = targeted, chronic = chronic, rampLeft = clean.rampWindow,
                        bandCeil = bandCeil)) {
                adapted.add(ex.pattern)
            }
        }
    }
    fun weeklyCap(patterns: List<Pattern>) {
        if (window.haveGap) applyWeeklyCap(next, patterns, entryPos = entryPos, adapted = adapted)
    }
    // The pushes come LAST. A push enters a band only behind the pull slot as
    // it stands after the session, so the slot settles first: its own growth,
    // its weekly ceiling, the cross-credit and the other branch's ceiling.
    train(false, bandCeil = EngineConfig.setsMax)

    // The pull branch that trained meets its weekly ceiling BEFORE the
    // cross-credit, so the credit repeats the gain the branch KEPT.
    val pullEx = session.exercises.firstOrNull { it.pattern in Pattern.pullSide }
    weeklyCap(Pattern.allCases.filter { it == pullEx?.pattern })
    if (pullEx != null) {
        crossCredit(next, trainedEx = pullEx, result = result,
                    overrides = cleanOverrides, entryPos = entryPos)
    }
    // Everything else meets its ceiling after the credit, the other pull
    // branch included. The pushes meet theirs after they train.
    weeklyCap(Pattern.allCases.filter { it != pullEx?.pattern && it !in Pattern.pushSide })
    train(true, bandCeil = pullSlotSets(next))
    weeklyCap(Pattern.allCases.filter { it in Pattern.pushSide })
    rememberShowing(next, session = session, entryPos = entryPos, cap = pullSlotSets(clean))
    return next
}

/** Remember what the person SAW and at what position — the ENTRY one. */
private fun Engine.rememberShowing(next: EngineState, session: Session,
                                   entryPos: Map<Pattern, Position>, cap: Int) {
    for (ex in session.exercises) {
        next.shownWork[ex.pattern] = shownWorkOf(ex)
        next.shownOrd[ex.pattern] = posOrd(ex.pattern, entryPos.getValue(ex.pattern))
        rememberCap(next, ex.pattern, entryPos.getValue(ex.pattern), cap = cap)
    }
}

// MARK: - One exercise

/** One exercise of the session. Answers whether it adapted fast by its number. */
@Suppress("LongParameterList")
private fun Engine.advance(next: EngineState, ex: SessionExercise,
                           old: Position, state: EngineState, result: FeedbackResult,
                           overrides: Map<Pattern, Double>, probes: Map<Pattern, Int>,
                           targeted: Set<Pattern>?, chronic: List<Pattern>,
                           rampLeft: Int, bandCeil: Int): Boolean {
    val p = ex.pattern
    val unit = Library.unit(p, old.variation)
    val g = Dose.grid(unit)
    val setsBackOk = (next.setsHold[p] ?: 0) == 0
    val cap = EngineConfig.maxUp(pattern = p, variation = old.variation)
    // The MAXIMUM dose per set in the plan that was shown — what a tap journals.
    val planTop = ex.load + (if (ex.loads?.any { it > ex.load } == true) g.step else 0)
    // The plan's MEAN — what a trainee shows by doing it set for set.
    val planMean: Double = run {
        val loads = ex.loads
        if (loads.isNullOrEmpty()) ex.load.toDouble() else loads.sum().toDouble() / loads.size.toDouble()
    }

    // The fraction judges; the grid-snapped integer assigns. Deliberately NO
    // clamp here (#139).
    val actualRaw = overrides[p]
    val actual = actualRaw?.let { Dose.snapToInt(unit, it) }
    // "the plan was met" is a WINDOW one rung wide from the plan's MEAN.
    val metPlan = actualRaw?.let { it >= planMean && it < planMean + g.step.toDouble() } ?: false
    val step = if (actual != null) {
        stepFromFact(p, ex = ex, actual = actual, metPlan = metPlan, old = old,
                     cap = cap, setsBackOk = setsBackOk, bandCeil = bandCeil, shown = state.shown)
    } else {
        stepFromRating(p, old = old, result = result, targeted = targeted,
                       chronic = chronic, cap = cap, rampLeft = rampLeft,
                       setsBackOk = setsBackOk, bandCeil = bandCeil, shown = state.shown)
    }

    // The journal is written for a COMPLETED appearance. An exercise with a
    // probe writes no journal for the OLD variation.
    if (ex.probe == null) {
        setShown(next, p, old.variation,
                 journalEntry(actualRaw, metPlan = metPlan, planTop = planTop, unit = unit))
    } else {
        resolveProbe(next, ex = ex, step = step, probes = probes)
    }

    if (step.wantedDown) {
        val streak = (next.failStreak[p] ?: 0) + 1
        next.failStreak[p] = streak
        if (streak >= EngineConfig.failsToDeload) {
            step.position = fallDoses(p, step.position, EngineConfig.deloadDrop, shown = state.shown)
            next.failStreak[p] = 0
        }
    } else {
        next.failStreak[p] = 0
    }
    // The input to the probe condition. It outlives a deload on purpose.
    if (step.wantedDown) next.lastHard.add(p) else next.lastHard.remove(p)

    val fitted = fit(p, step.position)
    if (setsCameBack(from = old, to = fitted)) {
        next.setsHold[p] = EngineConfig.setsBackHold
    } else {
        val held = (next.setsHold[p] ?: 0) - 1
        if (held > 0) next.setsHold[p] = held else next.setsHold.remove(p)
    }
    setPosition(next, p, fitted)
    return step.adapted
}

/** What a completed appearance writes into the journal of its variation: a
 *  tap journals the plan's top, a number its FOLD — except INSIDE the "plan
 *  met" window, where it journals the best set the numbers prove. */
private fun journalEntry(actualRaw: Double?, metPlan: Boolean, planTop: Int, unit: LoadUnit): Int {
    if (actualRaw == null) return planTop
    if (!metPlan) return Dose.snapToInt(unit, actualRaw)
    return min(planTop, Dose.snapToInt(unit, ceil(actualRaw)))
}

@Suppress("LongParameterList")
private fun Engine.stepFromFact(p: Pattern, ex: SessionExercise, actual: Int,
                                metPlan: Boolean, old: Position, cap: Int,
                                setsBackOk: Boolean, bandCeil: Int,
                                shown: Map<Pattern, Map<Int, Int>>): Step {
    val g = Dose.grid(Library.unit(p, old.variation))
    if (metPlan) {
        return Step(position = riseBy(p, old, min(EngineConfig.deltaPlan, cap),
                                      allowSetsBack = setsBackOk, bandCeil = bandCeil),
                    wantedDown = false)
    }
    if (actual >= ex.load + g.step) {
        // FAST ADAPTATION: the dose becomes the mean on the grid (no higher
        // than the variation's ceiling), sub-step cleared. `maxUp` does not
        // apply — the dose is what the person just did on their own.
        val pos = old.copy(dose = min(g.max, actual), sub = 0)
        return Step(position = fit(p, pos), wantedDown = false, adapted = true)
    }
    if (actual < g.min) {
        // A fact below the floor of the variation: a variation down, landing
        // under its journal.
        val pos = if (old.variation > 1) {
            landInVar(p, old.variation - 1, shown = shown, from = old)
        } else {
            fit(p, Position(variation = old.variation, sets = old.sets,
                            dose = g.min, sub = 0, cut = old.cut))
        }
        return Step(position = pos, wantedDown = true)
    }
    // Below the plan but inside the variation: the next showing equals the
    // fact. The cut and the band are kept.
    val pos = old.copy(dose = actual, sub = 0)
    return Step(position = fit(p, pos), wantedDown = true)
}

@Suppress("LongParameterList")
private fun Engine.stepFromRating(p: Pattern, old: Position, result: FeedbackResult,
                                  targeted: Set<Pattern>?, chronic: List<Pattern>,
                                  cap: Int, rampLeft: Int, setsBackOk: Boolean, bandCeil: Int,
                                  shown: Map<Pattern, Map<Int, Int>>): Step {
    // While the window a comeback opened is open, "more" is credited as
    // "plan". It does not block the way down.
    val capped = if (rampLeft > 0 && result == FeedbackResult.more) FeedbackResult.plan else result
    val delta = if (targeted != null) {
        if (p in targeted) {
            if (p in chronic) EngineConfig.chronicStep else EngineConfig.deltaLess
        } else {
            0
        }
    } else {
        capped.delta
    }
    val rampCap = if (rampLeft > 0) min(cap, EngineConfig.deltaPlan) else cap
    if (delta > 0) {
        return Step(position = riseBy(p, old, min(delta, rampCap), allowSetsBack = setsBackOk,
                                      bandCeil = bandCeil),
                    wantedDown = false)
    }
    if (delta < 0) {
        return Step(position = fallBy(p, old, -delta, shown = shown), wantedDown = true)
    }
    return Step(position = old, wantedDown = false)
}

/** The outcomes of a probe. A failed or unresolved probe changes no field
 *  but the journal of facts. */
private fun Engine.resolveProbe(next: EngineState, ex: SessionExercise,
                                step: Step, probes: Map<Pattern, Int>) {
    val probe = ex.probe ?: return
    if (step.wantedDown) return
    val raw = probes[ex.pattern] ?: return
    val got = Dose.snap(probe.unit, raw)
    setShown(next, ex.pattern, probe.variation, got)
    if (got < Dose.grid(probe.unit).min) return
    // ENTRY IS ALWAYS 3×4 (3×15 s).
    step.position = Position(variation = probe.variation, sets = EngineConfig.setsBase,
                             dose = Dose.grid(probe.unit).min, sub = 0, cut = 0)
}

// MARK: - The session-wide "less" (#91)

/** Who a point fact NAMED: a number below the plan. */
private fun namedMovements(session: Session, overrides: Map<Pattern, Double>): Set<Pattern> {
    val named = mutableSetOf<Pattern>()
    for (ex in session.exercises) {
        val raw = overrides[ex.pattern] ?: continue
        if (Dose.snapToInt(ex.unit, raw) < ex.load) named.add(ex.pattern)
    }
    return named
}

/** The window of appearances (#137). Returns the patterns the chronic signal
 *  fires for, IN SESSION ORDER. */
private fun rollChronicWindow(next: EngineState, session: Session, unnamedLess: Boolean,
                              splitPullSlot: Boolean): List<Pattern> {
    for (ex in session.exercises) {
        val shifted = (((next.lessHist[ex.pattern] ?: 0) shl 1) or (if (unnamedLess) 1 else 0)) and
            EngineState.chronicMaskMax
        if (shifted > 0) next.lessHist[ex.pattern] = shifted else next.lessHist.remove(ex.pattern)
    }
    return session.exercises.map { it.pattern }
        .filter { !(splitPullSlot && it in Pattern.pullSide) }
        .filter { next.chronicFires(it) }
}

/** Everything the aim of a session-wide "less" is decided from. */
private class LessAim(
    val entryPos: Map<Pattern, Position>,
    val session: Session,
    val result: FeedbackResult,
    val named: Set<Pattern>,
    val overrides: Map<Pattern, Double>,
    val skipped: Set<Pattern>,
    val chronic: List<Pattern>,
    val prevLessRun: Int,
    val hist: Map<Pattern, Int>,
) {
    fun eligible(p: Pattern): Boolean = p !in skipped && overrides[p] == null
}

/** Who receives the session-wide "less". Null means "everyone", which is what
 *  a run of unnamed ratings earns. */
private fun Engine.lessTargets(aim: LessAim): Set<Pattern>? {
    if (aim.result != FeedbackResult.less || aim.prevLessRun >= EngineConfig.lessRunToGlobal) return null
    if (aim.named.isNotEmpty()) return aim.named
    fun advance(p: Pattern): Int = posOrd(p, aim.entryPos.getValue(p))
    // The culprit is whoever fails their OWN appearances more often; on an
    // equal share — the one further along its ladder.
    var best: Pattern? = null
    var bestHits = -1
    var bestAdvance = -1
    for (p in aim.chronic) {
        if (!aim.eligible(p)) continue
        val hits = (aim.hist[p] ?: 0).countOneBits()
        val adv = advance(p)
        if (hits > bestHits || (hits == bestHits && adv > bestAdvance)) {
            bestHits = hits
            bestAdvance = adv
            best = p
        }
    }
    if (best != null) return setOf(best)
    // An unnamed "less" hits ONE movement — the session's most advanced.
    var target: Pattern? = null
    var targetAdvance = -1
    for (ex in aim.session.exercises) {
        if (!aim.eligible(ex.pattern)) continue
        val adv = advance(ex.pattern)
        if (adv > targetAdvance) {
            targetAdvance = adv
            target = ex.pattern
        }
    }
    return if (target != null) setOf(target) else emptySet()
}

// MARK: - Cross-credit and the weekly cap

/** (#90) With a bar the pull slot's accounting splits into two branches. The
 *  applied gain is repeated to the other branch, bounded by ITS OWN growth
 *  cell and BY ITS OWN JOURNAL. */
private fun Engine.crossCredit(next: EngineState, trainedEx: SessionExercise,
                               result: FeedbackResult, overrides: Map<Pattern, Double>,
                               entryPos: Map<Pattern, Position>) {
    if (!next.hasBar) return
    val trained = trainedEx.pattern
    val other = if (trained == Pattern.pull) Pattern.pullBar else Pattern.pull
    // (#141) The mark is set by a "less" for the WHOLE session, named or not,
    // and by an override for this branch below its base dose.
    val strained = result == FeedbackResult.less ||
        (overrides[trained]?.let { Dose.snapToInt(trainedEx.unit, it) < trainedEx.load } ?: false)
    if (strained) next.creditPaused.add(trained) else next.creditPaused.remove(trained)

    val gained = max(0, posOrd(trained, next.position(trained)) -
        posOrd(trained, entryPos.getValue(trained)))
    if (gained <= 0 || other in next.creditPaused) return
    val q = next.position(other)
    val pos = riseWithinJournal(
        other, q, min(gained, EngineConfig.maxUp(pattern = other, variation = q.variation)),
        allowSetsBack = (next.setsHold[other] ?: 0) == 0, shown = next.shown)
    setPosition(next, other, pos)
    // A set the credit returns arms the branch's hold, as its own return does.
    if (setsCameBack(from = q, to = pos)) next.setsHold[other] = EngineConfig.setsBackHold
}

private fun rollWeeklyWindow(state: EngineState, gapDays: Double?): WeekWindow {
    if (gapDays == null || !gapDays.isFinite()) {
        return WeekWindow(haveGap = false, gain = emptyMap(), ageDays = 0.0)
    }
    val aged = state.weekAgeDays + max(EngineConfig.minSessionAgeDays, gapDays)
    if (aged >= EngineConfig.weeklyWindowDays.toDouble()) {
        return WeekWindow(haveGap = true, gain = emptyMap(), ageDays = 0.0)
    }
    return WeekWindow(haveGap = true, gain = state.weekGain.toMap(), ageDays = aged)
}

/**
 * (#129) The weekly ceiling is applied ONCE to each pattern, after every rise
 * of it this session. Fast adaptation by facts and a RESOLVED PROBE are left
 * alone; a set return the ceiling undoes arms no hold; the window charges what
 * the rebuild REALISED, not what it granted. See Feedback.swift for the why.
 */
private fun Engine.applyWeeklyCap(next: EngineState, patterns: List<Pattern>,
                                  entryPos: Map<Pattern, Position>,
                                  adapted: Set<Pattern>) {
    for (p in patterns) {
        if (p in adapted) continue
        val entry = entryPos.getValue(p)
        if (next.vars[p] != entry.variation) continue
        val rise = max(0, posOrd(p, next.position(p)) - posOrd(p, entry))
        if (rise <= 0) continue
        val budget = if (EngineConfig.isSlowTissue(p) || p in Pattern.pullSide) {
            EngineConfig.weeklyRiseSlow
        } else {
            EngineConfig.weeklyRiseFast
        }
        val spent = next.weekGain[p] ?: 0
        val granted = min(rise, max(0, budget - spent))
        // The rebuild does not decide again whether to give a set back — it
        // only trims the steps, repeating the main loop's decision.
        val returned = (next.cut[p] ?: 0) < entry.cut
        val rebuilt = riseBy(p, entry, granted, allowSetsBack = returned,
                             bandCeil = EngineConfig.setsMax)
        setPosition(next, p, rebuilt)
        if (returned && rebuilt.cut >= entry.cut) next.setsHold.remove(p)
        val realised = max(0, posOrd(p, rebuilt) - posOrd(p, entry))
        if (realised > 0) next.weekGain[p] = spent + realised
    }
}
