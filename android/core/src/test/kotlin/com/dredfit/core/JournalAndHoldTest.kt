//
//  The journal a number that meets the plan leaves, the accepted corner of
//  the sets hold, and the hold the weekly ceiling must not arm. Golden pins
//  these through whole scenarios; the tests here name each rule on its own,
//  so a port that breaks one says which. Port of JournalAndHoldTests.swift.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JournalAndHoldTest {

    // MARK: - Helpers

    /** A session in which the pattern under test stands, with the state it
     *  was generated from. */
    private class Appearance(val state: EngineState, val session: Session, val exercise: SessionExercise) {
        fun feedback(
            result: FeedbackResult,
            overrides: Map<Pattern, Double> = emptyMap(),
            gapDays: Double? = null,
        ): EngineState = Engine.applyFeedback(
            state = state, session = session, result = result,
            overrides = overrides, gapDays = gapDays)
    }

    /** Found by moving the counter alone — everything else is the state
     *  under test. */
    private fun appearance(s: EngineState, p: Pattern): Appearance {
        var found: Appearance? = null
        for (c in s.counter until (s.counter + 16)) {
            if (found != null) break
            val t = s.copy()
            t.counter = c
            val session = Engine.generateSession(t)
            val ex = session.exercises.firstOrNull { it.pattern == p }
            if (ex != null) found = Appearance(t, session, ex)
        }
        return assertNotNull(found, "${p.rawValue} never stands in a session")
    }

    /** One pattern placed by hand on top of a clean start. */
    private fun placed(
        p: Pattern, variation: Int, dose: Int, sub: Int = 0, cut: Int = 0, journal: Int,
    ): EngineState {
        val s = EngineState.initial
        s.vars[p] = variation
        s.doses[p] = dose
        if (sub > 0) s.sub[p] = sub
        if (cut > 0) s.cut[p] = cut
        s.shown[p] = mutableMapOf(variation to journal)
        return s
    }

    // MARK: - A number that meets the plan journals the best set it proves

    /** 9-9-8 done as 10, 8, 8: the plan's sum, so "the plan was met", and the
     *  rise crosses the rung to 3×9. Journalling the fold — 8, the plan's
     *  base — would put the journal under the plan it just assigned; a tap
     *  on the same session journals 9, and so must the number. */
    @Test
    fun aMixedFactAtTheRungBoundaryJournalsWhatATapWould() {
        val a = appearance(placed(Pattern.squat, variation = 2, dose = 8, sub = 2, journal = 9), Pattern.squat)
        assertEquals(listOf(9, 9, 8), a.exercise.loads)
        val logged = a.feedback(FeedbackResult.plan, mapOf(Pattern.squat to 26.0 / 3.0))
        val tapped = a.feedback(FeedbackResult.plan)
        assertEquals(tapped.position(Pattern.squat), logged.position(Pattern.squat), "the same rise either way")
        assertEquals(9, logged.doses[Pattern.squat], "3×9 next")
        assertEquals(9, logged.shownDose(Pattern.squat, variation = 2),
                     "the journal sits under the plan it just assigned")
        assertEquals(tapped.shownDose(Pattern.squat, variation = 2), logged.shownDose(Pattern.squat, variation = 2))
    }

    /** A met number journals no more than the plan's top. 3×9 done as 10, 9,
     *  9 is inside the window (9.33), and the mean rounded up says 10 — but
     *  "met" means the plan was done, and the plan's top here is its base, so
     *  a uniform plan journals its own dose, exactly as a tap does. */
    @Test
    fun aMetFactNeverJournalsAboveThePlansTop() {
        val a = appearance(placed(Pattern.squat, variation = 2, dose = 9, journal = 9), Pattern.squat)
        assertNull(a.exercise.loads, "a uniform plan")
        val logged = a.feedback(FeedbackResult.plan, mapOf(Pattern.squat to 28.0 / 3.0))
        assertEquals(9, logged.shownDose(Pattern.squat, variation = 2))
        assertEquals(a.feedback(FeedbackResult.plan).shownDose(Pattern.squat, variation = 2),
                     logged.shownDose(Pattern.squat, variation = 2), "as a tap")
    }

    /** The probe reads the journal (`probeAllowed`). 15-15-14 done as 16, 14,
     *  14 met the plan and reached 3×15; with the fold journalled the probe
     *  would wait an appearance the tapper does not wait. */
    @Test
    fun theLoggerIsOfferedTheProbeWhenTheTapperIs() {
        val a = appearance(placed(Pattern.squat, variation = 2, dose = 14, sub = 2, journal = 15), Pattern.squat)
        val afterLog = appearance(a.feedback(FeedbackResult.plan, mapOf(Pattern.squat to 44.0 / 3.0)), Pattern.squat).exercise
        val afterTap = appearance(a.feedback(FeedbackResult.plan), Pattern.squat).exercise
        assertNotNull(afterTap.probe, "control: the tapper is offered the probe")
        assertNotNull(afterLog.probe, "the logger who met the same plan is offered it too")
        assertEquals(afterTap.display, afterLog.display)
    }

    /** The cross-credit is bounded by the branch's own journal. A vertical
     *  pull 9-9-8 done as 10, 8, 8 that journalled 8 would stop the next
     *  growth of the horizontal pull from reaching the branch at 3×9. */
    @Test
    fun theLoggerKeepsTheCrossCreditTheTapperGets() {
        val start = placed(Pattern.pullBar, variation = 5, dose = 8, sub = 2, journal = 9)
        start.hasBar = true
        start.counter = 1                         // odd: the vertical branch stands
        start.vars[Pattern.pull] = 4
        start.doses[Pattern.pull] = 8
        start.shown[Pattern.pull] = mutableMapOf(4 to 8)
        fun creditAfter(overrides: Map<Pattern, Double>): Position {
            val own = appearance(start, Pattern.pullBar)
            assertEquals(start.counter, own.state.counter, "the branch's own appearance comes first")
            val mid = own.feedback(FeedbackResult.plan, overrides)
            val horizontal = appearance(mid, Pattern.pull)
            return horizontal.feedback(FeedbackResult.plan).position(Pattern.pullBar)
        }
        val tapped = creditAfter(emptyMap())
        assertEquals(1, tapped.sub, "control: the tap's journal lets the credit through")
        assertEquals(tapped, creditAfter(mapOf(Pattern.pullBar to 26.0 / 3.0)))
    }

    /** Holds: the engine sees only the mean of the seconds, and the grid steps
     *  by five. Someone who can hold 44 s and declares 44 on every set of
     *  45-45-40 has NOT shown the ceiling: the plan still crosses to 3×45 (an
     *  accepted residual), but the journal stays at 40 and no probe comes — the
     *  top taken on trust would offer one their working sets then throw out.
     *  45, 45, 44 proves the top: journal 45, and the probe follows. */
    @Test
    fun aHoldJournalsTheTopOnlyWhenTheSecondsProveIt() {
        val a = appearance(placed(Pattern.coreAntiExt, variation = 4, dose = 40, sub = 2, journal = 45),
                           Pattern.coreAntiExt)
        assertEquals(listOf(45, 45, 40), a.exercise.loads)

        val unproven = a.feedback(FeedbackResult.plan, mapOf(Pattern.coreAntiExt to 44.0))
        assertEquals(45, unproven.doses[Pattern.coreAntiExt], "the met plan still rises")
        assertEquals(40, unproven.shownDose(Pattern.coreAntiExt, variation = 4),
                     "44 s in every set proves no 45")
        assertNull(appearance(unproven, Pattern.coreAntiExt).exercise.probe,
                   "no probe without the ceiling shown")

        val proven = a.feedback(FeedbackResult.plan, mapOf(Pattern.coreAntiExt to 134.0 / 3.0))
        assertEquals(45, proven.shownDose(Pattern.coreAntiExt, variation = 4),
                     "a mean of 44.67 s means a set of at least 45 s")
        assertNotNull(appearance(proven, Pattern.coreAntiExt).exercise.probe)
    }

    // MARK: - The hold's corner, accepted

    /** Under a cut, while the hold ticks, the next sub-step can land on the
     *  set the cut took off; `fit` clamps it back and "on plan" moves nothing.
     *  Kept on purpose: `Engine.riseBy` says what each repair would break.
     *  Pinned both ways — the plan stands, and without the hold the same tap
     *  brings the set back. */
    @Test
    fun underACutTheHoldCanLeaveTheNextPlanStanding() {
        val held = placed(Pattern.squat, variation = 2, dose = 8, sub = 1, cut = 1, journal = 9)
        held.setsHold[Pattern.squat] = 1
        val a = appearance(held, Pattern.squat)
        assertEquals(listOf(9, 8), a.exercise.loads, "two sets on screen, the top one already raised")
        val next = a.feedback(FeedbackResult.plan)
        assertEquals(a.state.position(Pattern.squat), next.position(Pattern.squat), "the accepted corner: nothing moves")
        assertEquals(Engine.progress(a.state, Pattern.squat), Engine.progress(next, Pattern.squat))
        assertNull(next.setsHold[Pattern.squat], "the appearance still spends the hold")

        val after = appearance(next, Pattern.squat).feedback(FeedbackResult.plan)
        assertNull(after.cut[Pattern.squat], "the hold ran out: the set comes back")
        assertEquals(EngineConfig.setsBackHold, after.setsHold[Pattern.squat])

        val free = held.copy()
        free.setsHold.remove(Pattern.squat)
        assertNull(appearance(free, Pattern.squat).feedback(FeedbackResult.plan).cut[Pattern.squat],
                   "control: without the hold the same tap returns the set")
    }

    // MARK: - The weekly ceiling arms no hold for a return it undid

    /** The week's budget is spent: the main loop gives a set back and arms
     *  the hold, the ceiling takes the return back. Left armed, the hold
     *  would keep the set off for two more appearances under a cut, though
     *  no set had returned. */
    @Test
    fun aReturnTheWeeklyCeilingUndoesArmsNoHold() {
        val spent = placed(Pattern.squat, variation = 2, dose = 8, cut = 1, journal = 8)
        spent.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast
        spent.weekAgeDays = 1.0
        val a = appearance(spent, Pattern.squat)

        val capped = a.feedback(FeedbackResult.plan, gapDays = 1.0)
        assertEquals(1, capped.cut[Pattern.squat], "the ceiling undid the return")
        assertNull(capped.setsHold[Pattern.squat], "and so armed no hold")

        val free = a.feedback(FeedbackResult.plan)
        assertNull(free.cut[Pattern.squat], "control: without the window the set comes back")
        assertEquals(EngineConfig.setsBackHold, free.setsHold[Pattern.squat], "control: and the hold is armed")

        val roomy = a.state.copy()
        roomy.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast - 1
        val kept = Engine.applyFeedback(state = roomy, session = a.session, result = FeedbackResult.plan, gapDays = 1.0)
        assertNull(kept.cut[Pattern.squat], "control: with budget to spare the return stands")
        assertEquals(EngineConfig.setsBackHold, kept.setsHold[Pattern.squat], "control: and so does the hold")
    }

    /** The same on a band of the top variation, where a return leaves a cut
     *  behind: the rule is "no return happened", not "some cut is left". */
    @Test
    fun onABandTheCeilingUndoesTheHoldOnlyWithTheReturn() {
        val band = placed(Pattern.squat, variation = Library.count(Pattern.squat), dose = 4, cut = 3, journal = 4)
        band.sets[Pattern.squat] = EngineConfig.setsMax
        band.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast
        band.weekAgeDays = 1.0
        val a = appearance(band, Pattern.squat)
        assertEquals(2, a.exercise.sets, "five sets, three taken off")

        val capped = a.feedback(FeedbackResult.plan, gapDays = 1.0)
        assertEquals(3, capped.cut[Pattern.squat])
        assertNull(capped.setsHold[Pattern.squat])

        val roomy = a.state.copy()
        roomy.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast - 1
        val kept = Engine.applyFeedback(state = roomy, session = a.session, result = FeedbackResult.plan, gapDays = 1.0)
        assertEquals(2, kept.cut[Pattern.squat], "one set back, two still off")
        assertEquals(EngineConfig.setsBackHold, kept.setsHold[Pattern.squat],
                     "a return that stands keeps its hold, cut or no cut")
    }

    /** The ceiling also trims a cross-credit. Under a running hold the credit
     *  returns no set, so the rollback has nothing to take back: the other
     *  branch's hold ticks only with its own appearances. */
    @Test
    fun theCeilingLeavesTheOtherBranchHoldAlone() {
        val s = placed(Pattern.pullBar, variation = 5, dose = 8, cut = 1, journal = 15)
        s.hasBar = true
        s.counter = 0                             // even: the horizontal branch stands
        s.vars[Pattern.pull] = 4
        s.doses[Pattern.pull] = 8
        s.shown[Pattern.pull] = mutableMapOf(4 to 8)
        s.setsHold[Pattern.pullBar] = EngineConfig.setsBackHold
        s.weekGain[Pattern.pullBar] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1.0
        val a = appearance(s, Pattern.pull)
        assertEquals(s.counter, a.state.counter)
        assertNull(a.session.exercises.firstOrNull { it.pattern == Pattern.pullBar })

        val capped = a.feedback(FeedbackResult.plan, gapDays = 1.0)
        assertEquals(EngineConfig.setsBackHold, capped.setsHold[Pattern.pullBar],
                     "a branch that did not appear keeps its hold")
        val free = a.feedback(FeedbackResult.plan)
        assertTrue(Engine.progress(free, Pattern.pullBar) > Engine.progress(s, Pattern.pullBar),
                   "control: without the window the credit reaches the branch")
    }
}
