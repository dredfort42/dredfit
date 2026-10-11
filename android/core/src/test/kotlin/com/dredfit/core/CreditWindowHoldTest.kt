//
//  The weekly window and a number that met the plan, the cross-credit and its
//  set returns, and the hold armed by sets coming back on screen. Golden pins
//  these through whole scenarios; each test here names one rule, so a port
//  that breaks it says which. Port of CreditWindowHoldTests.swift.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CreditWindowHoldTest {

    // MARK: - Helpers

    /** A session in which the pattern under test stands, with the state it
     *  was generated from. */
    private class Appearance(val state: EngineState, val session: Session, val exercise: SessionExercise) {
        fun feedback(
            result: FeedbackResult,
            overrides: Map<Pattern, Double> = emptyMap(),
            gapDays: Double? = null,
            probes: Map<Pattern, Int> = emptyMap(),
        ): EngineState = Engine.applyFeedback(
            state = state, session = session, result = result,
            overrides = overrides, gapDays = gapDays, probes = probes)
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
        p: Pattern, variation: Int, dose: Int, sets: Int = EngineConfig.setsBase,
        sub: Int = 0, cut: Int = 0, journal: Map<Int, Int>,
    ): EngineState {
        val s = EngineState.initial
        s.vars[p] = variation
        s.doses[p] = dose
        if (sets != EngineConfig.setsBase) s.sets[p] = sets
        if (sub > 0) s.sub[p] = sub
        if (cut > 0) s.cut[p] = cut
        s.shown[p] = journal.toMutableMap()
        return s
    }

    /** The pull slot with the bar: the horizontal branch at a growing position,
     *  the vertical one as given. */
    private fun slot(
        barVariation: Int, barDose: Int, barSets: Int = EngineConfig.setsBase,
        barSub: Int = 0, barCut: Int, barJournal: Int, counter: Int,
    ): EngineState {
        val s = placed(Pattern.pullBar, variation = barVariation, dose = barDose, sets = barSets, sub = barSub,
                       cut = barCut, journal = mapOf(barVariation to barJournal))
        s.hasBar = true
        s.counter = counter
        s.vars[Pattern.pull] = 4
        s.doses[Pattern.pull] = 8
        s.shown[Pattern.pull] = mutableMapOf(4 to 8)
        return s
    }

    // MARK: - A number that met the plan obeys the weekly window

    /** A number that merely meets the plan rises by the engine's +1, as a tap
     *  does, so the window governs it as it governs the tap. Let through, it
     *  would rise past a spent budget where a tap on the same session stands
     *  still, and a daily logger would outgrow the window. */
    @Test
    fun underASpentWindowANumberThatMeetsThePlanStandsLikeATap() {
        val spent = placed(Pattern.squat, variation = 2, dose = 8, sub = 2, journal = mapOf(2 to 9))
        spent.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast
        spent.weekAgeDays = 1.0
        val a = appearance(spent, Pattern.squat)
        assertEquals(listOf(9, 9, 8), a.exercise.loads)
        val tapped = a.feedback(FeedbackResult.plan, gapDays = 1.0)
        val logged = a.feedback(FeedbackResult.plan, mapOf(Pattern.squat to 26.0 / 3.0), gapDays = 1.0)
        assertEquals(a.state.position(Pattern.squat), tapped.position(Pattern.squat), "control: the window stops a tap")
        assertEquals(tapped.position(Pattern.squat), logged.position(Pattern.squat), "a met number stands like the tap")
        assertEquals(EngineConfig.weeklyRiseFast, logged.weekGain[Pattern.squat])

        val roomy = a.state.copy()
        roomy.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast - 1
        val grown = Engine.applyFeedback(state = roomy, session = a.session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.squat to 26.0 / 3.0), gapDays = 1.0)
        assertEquals(9, grown.doses[Pattern.squat], "with budget to spare it rises to 3×9")
        assertEquals(EngineConfig.weeklyRiseFast, grown.weekGain[Pattern.squat], "and the rise is charged")
    }

    /** The other side: fast adaptation is what the person DID, and no window
     *  trims it or charges for it. */
    @Test
    fun underASpentWindowFastAdaptationStaysFree() {
        val spent = placed(Pattern.squat, variation = 2, dose = 8, sub = 2, journal = mapOf(2 to 9))
        spent.weekGain[Pattern.squat] = EngineConfig.weeklyRiseFast
        spent.weekAgeDays = 1.0
        val a = appearance(spent, Pattern.squat)
        val adopted = a.feedback(FeedbackResult.plan, mapOf(Pattern.squat to 12.0), gapDays = 1.0)
        assertEquals(12, adopted.doses[Pattern.squat], "the dose is what was done")
        assertEquals(EngineConfig.weeklyRiseFast, adopted.weekGain[Pattern.squat], "nothing charged")
    }

    /** A number for a movement outside the session is discarded whole. Taken
     *  for a fact, it would lift the window off the credit that branch
     *  receives. */
    @Test
    fun aNumberForAMovementOutsideTheSessionChangesNothing() {
        val s = slot(barVariation = 5, barDose = 8, barCut = 0, barJournal = 15, counter = 0)
        s.weekGain[Pattern.pullBar] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1.0
        val a = appearance(s, Pattern.pull)
        assertNull(a.session.exercises.firstOrNull { it.pattern == Pattern.pullBar })
        assertTrue(Engine.progress(a.feedback(FeedbackResult.more), Pattern.pullBar) >
                       Engine.progress(a.state, Pattern.pullBar),
                   "control: without the window the credit reaches the branch")
        val plain = a.feedback(FeedbackResult.more, gapDays = 1.0)
        assertEquals(a.state.position(Pattern.pullBar), plain.position(Pattern.pullBar),
                     "the spent window stops the credit")
        assertEquals(plain, a.feedback(FeedbackResult.more, mapOf(Pattern.pullBar to 20.0), gapDays = 1.0))
    }

    // MARK: - A set return ends the credit; the window charges what it gave

    /** A set the credit returns ends the credit, as a set return ends growth
     *  in `riseBy`. A dose step on top would make a jump the weekly window's
     *  rebuild cannot repeat: that rebuild goes through `riseBy`, which keeps
     *  the set alone. */
    @Test
    fun aCreditThatReturnsASetEndsThere() {
        val s = slot(barVariation = 2, barDose = 20, barCut = 1, barJournal = 45, counter = 0)
        val grows = s.copy()
        grows.vars[Pattern.pull] = 2                       // two events of credit: below the slow top variations
        grows.shown[Pattern.pull] = mutableMapOf(2 to 8)
        val a = appearance(grows, Pattern.pull)
        assertEquals(grows.counter, a.state.counter, "the horizontal branch stands first")
        val free = a.feedback(FeedbackResult.more)
        assertNull(free.cut[Pattern.pullBar], "the set came back")
        assertEquals(20, free.position(Pattern.pullBar).dose, "and nothing more: no dose step on top")
        assertEquals(0, free.position(Pattern.pullBar).sub)
        val windowed = a.feedback(FeedbackResult.more, gapDays = 2.0)
        assertEquals(free.position(Pattern.pullBar), windowed.position(Pattern.pullBar), "the window keeps the same set")
        assertEquals(1, windowed.weekGain[Pattern.pullBar], "and charges the one event it is")
    }

    /** The window grants one event of an "easy" under a hold and a cut, the
     *  event lands on the set the cut hides and is lost — and must not be
     *  charged. */
    @Test
    fun theWindowChargesOnlyWhatTheRebuildGave() {
        val s = slot(barVariation = 4, barDose = 11, barSub = 1, barCut = 1, barJournal = 12, counter = 1)
        s.setsHold[Pattern.pullBar] = EngineConfig.setsBackHold
        s.weekGain[Pattern.pullBar] = EngineConfig.weeklyRiseSlow - 1
        s.weekAgeDays = 1.0
        val a = appearance(s, Pattern.pullBar)
        assertEquals(listOf(12, 11), a.exercise.loads)
        val windowed = a.feedback(FeedbackResult.more, gapDays = 1.0)
        assertEquals(a.state.position(Pattern.pullBar), windowed.position(Pattern.pullBar), "the granted event was lost")
        assertEquals(EngineConfig.weeklyRiseSlow - 1, windowed.weekGain[Pattern.pullBar], "so nothing is charged")
        assertTrue(Engine.progress(a.feedback(FeedbackResult.more), Pattern.pullBar) >
                       Engine.progress(a.state, Pattern.pullBar),
                   "control: without the window the same answer moves the plan")
    }

    // MARK: - The hold is armed by sets coming back on screen

    /** A descent off a band carries the cut into the variation below: two
     *  sets on screen before, two after. A hold armed there spaces no return;
     *  it only parks the next growth event in its corner, where it is lost. */
    @Test
    fun aDescentThatCarriesTheCutArmsNoHold() {
        val band = placed(Pattern.squat, variation = Library.count(Pattern.squat), dose = 4,
                          sets = EngineConfig.setsMax, cut = 3, journal = mapOf(5 to 15, 6 to 4))
        val a = appearance(band, Pattern.squat)
        val down = a.feedback(FeedbackResult.less)
        assertEquals(Library.count(Pattern.squat) - 1, down.vars[Pattern.squat])
        assertEquals(1, down.cut[Pattern.squat], "the cut came along")
        assertNull(down.setsHold[Pattern.squat], "no more sets on screen, no hold")
        val back = appearance(down, Pattern.squat).feedback(FeedbackResult.plan)
        assertNull(back.cut[Pattern.squat], "so the next \"on plan\" brings the set back")
    }

    /** The other side: a probe taken on a cut plan — one set and the probe —
     *  enters 3×4. Sets on screen went up, and the hold is the hold's job. */
    @Test
    fun aProbeEntryThatAddsSetsArmsTheHold() {
        val cut = placed(Pattern.squat, variation = 1, dose = 15, cut = 1, journal = mapOf(1 to 15))
        val a = appearance(cut, Pattern.squat)
        assertNotNull(a.exercise.probe)
        val entered = a.feedback(FeedbackResult.plan, probes = mapOf(Pattern.squat to 4))
        assertEquals(2, entered.vars[Pattern.squat])
        assertEquals(EngineConfig.setsBackHold, entered.setsHold[Pattern.squat])
    }

    // MARK: - A set the credit returns arms the hold

    /** Without the hold, the branch's own next appearance would return a
     *  second set at once: 2 → 3 → 4 sets on consecutive appearances. */
    @Test
    fun aSetTheCreditReturnsArmsTheHold() {
        val s = slot(barVariation = Library.count(Pattern.pullBar), barDose = 9, barSets = EngineConfig.setsMax,
                     barCut = 3, barJournal = 15, counter = 0)
        val afterCredit = appearance(s, Pattern.pull).feedback(FeedbackResult.plan)
        assertEquals(2, afterCredit.cut[Pattern.pullBar], "the credit returned a set")
        assertEquals(EngineConfig.setsBackHold, afterCredit.setsHold[Pattern.pullBar], "and armed the hold")
        val afterOwn = appearance(afterCredit, Pattern.pullBar).feedback(FeedbackResult.plan)
        assertEquals(2, afterOwn.cut[Pattern.pullBar], "the branch's own appearance returns no second set")
    }

    /** A credit that returns no set leaves the hold as it was, and a window
     *  that takes the credit's set back takes the hold with it. */
    @Test
    fun aCreditHoldGoesOnlyWithItsSet() {
        val noCut = slot(barVariation = 5, barDose = 8, barCut = 0, barJournal = 15, counter = 0)
        val dosed = appearance(noCut, Pattern.pull).feedback(FeedbackResult.plan)
        assertTrue(Engine.progress(dosed, Pattern.pullBar) > Engine.progress(noCut, Pattern.pullBar),
                   "control: the credit grew the dose")
        assertNull(dosed.setsHold[Pattern.pullBar], "no set, no hold")

        val spent = slot(barVariation = 5, barDose = 8, barCut = 1, barJournal = 15, counter = 0)
        spent.weekGain[Pattern.pullBar] = EngineConfig.weeklyRiseSlow
        spent.weekAgeDays = 1.0
        val capped = appearance(spent, Pattern.pull).feedback(FeedbackResult.plan, gapDays = 1.0)
        assertEquals(1, capped.cut[Pattern.pullBar], "the window took the credit's set back")
        assertNull(capped.setsHold[Pattern.pullBar], "and the hold with it")
    }

    // MARK: - The credit repeats what the trained branch kept

    /** The trained branch stands under its spent window, and the branch it
     *  credits stands with it. Credited before the window, the other branch
     *  would grow for growth the trained one never kept. */
    @Test
    fun underASpentWindowTheCreditRepeatsNothing() {
        val s = slot(barVariation = 5, barDose = 8, barCut = 0, barJournal = 15, counter = 0)
        s.weekGain[Pattern.pull] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1.0
        val a = appearance(s, Pattern.pull)
        assertTrue(Engine.progress(a.feedback(FeedbackResult.plan), Pattern.pullBar) >
                       Engine.progress(a.state, Pattern.pullBar),
                   "control: without the window the credit lands")
        val capped = a.feedback(FeedbackResult.plan, gapDays = 1.0)
        assertEquals(a.state.position(Pattern.pull), capped.position(Pattern.pull), "the window stops the trained branch")
        assertEquals(a.state.position(Pattern.pullBar), capped.position(Pattern.pullBar), "and the credit repeats nothing")
        assertNull(capped.weekGain[Pattern.pullBar])
    }

    /** The other side: with one event of budget left, an "easy" keeps one of
     *  its two events, and the credit repeats exactly that one. */
    @Test
    fun theCreditRepeatsTheEventTheWindowLeft() {
        val s = slot(barVariation = 3, barDose = 4, barCut = 0, barJournal = 15, counter = 0)
        s.weekGain[Pattern.pull] = EngineConfig.weeklyRiseSlow - 1
        s.weekAgeDays = 1.0
        val a = appearance(s, Pattern.pull)
        fun rise(after: EngineState, p: Pattern): Int =
            Engine.progress(after, p) - Engine.progress(a.state, p)
        val free = a.feedback(FeedbackResult.more)
        assertEquals(2, rise(free, Pattern.pull), "control: an easy is two events")
        assertEquals(2, rise(free, Pattern.pullBar), "and without the window the credit repeats both")
        val capped = a.feedback(FeedbackResult.more, gapDays = 1.0)
        assertEquals(1, rise(capped, Pattern.pull), "the window keeps one")
        assertEquals(1, rise(capped, Pattern.pullBar), "and the credit repeats that one")
    }
}
