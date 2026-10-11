//
//  Port of ios/DredfitTests/ProbeChannelTests.swift: the probe channel, seen
//  from above the engine.
//
//  The probe is the only door into a new variation. The engine's own fixtures
//  cover `probeAllowed` and `resolveProbe`; this suite covers the SEAM the app
//  owns — a plan that carries a probe, the number the flow hands back for it,
//  and what the persisted state does with that number. A break in that seam
//  freezes the ladders of anyone who only taps. Everything here is driven
//  through `AppStore`, because the app layer is the one the engine's fixtures
//  do not reach.
//
//  Every test is ported. As on iOS, the WORDS of the probe's caption stay out
//  of reach (they live in the screen); which outcome it states is
//  `WorkoutSession.probeOutcome`, pinned in HoldSummaryTest.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.core.applySilentDecay
import com.dredfit.core.generateSession
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.workout.SetFacts
import com.dredfit.workout.TechniqueTarget
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProbeChannelTest : AppStoreTestCase() {

    // MARK: - Fixtures

    /**
     * A store seeded through the storage file — the same door the real app
     * loads through, and the only one that catches a seed the store silently
     * replaced with a clean start.
     *
     * Every pattern stands ONE RUNG BELOW its grid's ceiling, which is a
     * position the plan offers no probe from, so a probe anywhere in these
     * sessions was asked for by name. `maxed` lifts the named patterns onto
     * the ceiling; `journal` pins what the trainee actually SHOWED there when
     * that has to differ from the dose the plan climbed to.
     */
    @Suppress("LongParameterList")
    private fun seededStore(variation: Map<Pattern, Int> = emptyMap(),
                            maxed: Set<Pattern> = emptySet(),
                            journal: Map<Pattern, Int> = emptyMap(),
                            lastHard: Set<Pattern> = emptySet(),
                            hasBar: Boolean = false,
                            counter: Int = 0): AppStore {
        fun rung(p: Pattern): Int = minOf(variation[p] ?: 1, Library.count(p))
        fun dose(p: Pattern): Int {
            val grid = Dose.grid(Library.unit(p, rung(p)))
            return if (p in maxed) grid.max else grid.max - grid.step
        }
        fun shownHere(p: Pattern): Int = journal[p] ?: dose(p)
        // Every rung below the current one is journalled at its own ceiling: a
        // descent out of a variation lands under the journal of the one below,
        // and without it would land on that variation's floor instead of
        // where the movement has actually been.
        val rows = Pattern.allCases.joinToString(",") { p ->
            val cells = (1..rung(p)).joinToString(",") { v ->
                val value = if (v == rung(p)) shownHere(p) else Dose.grid(Library.unit(p, v)).max
                "\"$v\":$value"
            }
            "\"${p.rawValue}\",{$cells}"
        }
        val varsJSON = pairs { rung(it) }
        val dosesJSON = pairs { dose(it) }
        val zerosJSON = pairs { 0 }
        val hardJSON = lastHard.joinToString(",") { "\"${it.rawValue}\"" }
        val json = """
        {"engineState":{"counter":$counter,"hasBar":$hasBar,
                        "vars":[$varsJSON],"doses":[$dosesJSON],
                        "shown":[$rows],"failStreak":[$zerosJSON],
                        "lastHard":[$hardJSON]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        val store = storeFrom(json)
        // A state that fails to decode starts clean, and every assertion below
        // would then be true of a state nobody wrote. Position AND journal AND
        // lastHard: a clean start carries no journal at all, so checking the
        // position alone would pass whenever the seed sits on variation 1.
        assertEquals(dose(Pattern.pull), store.engineState.position(Pattern.pull).dose,
                     "the seed did not load: the pull slot is not on the dose it was written at")
        assertEquals(shownHere(Pattern.pull), store.engineState.shownDose(Pattern.pull, variation = rung(Pattern.pull)),
                     "the seed did not load: the journal of what was shown is not there")
        assertEquals(lastHard, store.engineState.lastHard,
                     "the seed did not load: \"the last answer was hard\" is not the set that was written")
        return store
    }

    private fun exercise(pattern: Pattern, session: Session): SessionExercise =
        assertNotNull(session.exercises.firstOrNull { it.pattern == pattern },
                      "${pattern.rawValue} must be in session ${session.sessionNumber}, " +
                          "or this test is asserting about a plan that does not contain it")

    // MARK: - When the plan offers a probe

    @Test
    fun session_whenBothTheDoseAndTheJournalAreOnTheCeiling_swapsTheLastSetForAProbe() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val pulling = exercise(Pattern.pull, session)
        val probe = assertNotNull(pulling.probe,
                                  "a maxed variation with the journal to match IS the probe condition")

        assertEquals(pulling.variation + 1, probe.variation,
                     "the probe offers the NEXT rung of the ladder, never one further up")
        assertEquals(Dose.grid(Library.unit(Pattern.pull, probe.variation)).min, probe.load,
                     "and asks for the floor of the new grid — 4 reps, or 15 s")
        assertEquals(EngineConfig.setsBase - 1, pulling.sets,
                     "the probe REPLACES a working set: the volume of the session must not grow")

        val control = exercise(Pattern.hinge, session)
        assertNull(control.probe, "a movement one rung below its ceiling is offered nothing")
        assertEquals(EngineConfig.setsBase, control.sets, "and keeps every working set it had")
    }

    @Test
    fun session_whenTheJournalStopsShortOfTheCeiling_offersNoProbe() {
        val grid = Dose.grid(Library.unit(Pattern.pull, 1))
        val store = seededStore(maxed = setOf(Pattern.pull), journal = mapOf(Pattern.pull to grid.max - grid.step))
        val pulling = exercise(Pattern.pull, store.nextSession)

        assertEquals(grid.max, store.engineState.position(Pattern.pull).dose,
                     "the PLAN did climb to the ceiling — the half of the old gate that still holds")
        assertNull(pulling.probe,
                   "the gate reads the journal of what was SHOWN, and 14 against a ceiling of 15 " +
                       "is not a maxed variation — eleven probes in 75 appearances were thrown away this way")
        assertEquals(EngineConfig.setsBase, pulling.sets, "so the last set stays a working one")
    }

    @Test
    fun session_whenTheLastAnswerForThePatternWasHard_offersNoProbe() {
        val store = seededStore(maxed = setOf(Pattern.pull), lastHard = setOf(Pattern.pull))

        assertNull(exercise(Pattern.pull, store.nextSession).probe,
                   "a movement just called hard is not offered a harder one — and this cannot be read off " +
                       "failStreak, which a deload zeroes while \"hard\" does not stop having been said")
    }

    @Test
    fun session_onTheTopVariationOfTheLadder_offersNoProbe() {
        val store = seededStore(variation = mapOf(Pattern.pull to Library.count(Pattern.pull)), maxed = setOf(Pattern.pull))

        assertNull(exercise(Pattern.pull, store.nextSession).probe,
                   "there is no next variation to try: growth continues in the set bands instead")
    }

    // MARK: - What the reported number does

    @Test
    fun probe_whenTheReportedNumberMeetsItsTarget_entersTheNextVariationAtThreeByTheFloor() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val probe = assertNotNull(exercise(Pattern.pull, session).probe, "the fixture must carry a probe")
        val leftBehind = assertNotNull(store.engineState.shownDose(Pattern.pull, variation = 1),
                                       "the seed journals the rung the probe is offered from")

        store.completeWorkout(session = session, result = FeedbackResult.plan, probes = mapOf(Pattern.pull to probe.load))

        val after = store.engineState.position(Pattern.pull)
        assertEquals(probe.variation, after.variation,
                     "a passed probe is the door into the new variation, and the only one there is")
        assertEquals(Dose.grid(Library.unit(Pattern.pull, probe.variation)).min, after.dose,
                     "entry is always the grid floor — 3×4 (3×15 s), never the dose of the rung left behind")
        assertEquals(EngineConfig.setsBase, after.sets, "at the base set count")
        assertEquals(0, after.sub, "with no sub-step already owed")
        assertEquals(0, after.cut, "and nothing already cut")
        assertEquals(probe.load, store.engineState.shownDose(Pattern.pull, variation = probe.variation),
                     "what the probe showed is what the new rung's journal says")
        assertEquals(leftBehind, store.engineState.shownDose(Pattern.pull, variation = 1),
                     "and the rung left behind keeps its own number — a descent back to it takes that as its ceiling")
    }

    @Test
    fun probe_whenTheReportedNumberFallsShortOfItsTarget_movesNothingButTheJournal() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val probe = assertNotNull(exercise(Pattern.pull, session).probe, "the fixture must carry a probe")
        val before = store.engineState.position(Pattern.pull)
        // One RUNG below the target, not one unit: the number is snapped to
        // the grid on the way in, and on a hold's grid of five "one less"
        // would land back on the floor and read as a pass.
        val short = probe.load - Dose.grid(probe.unit).step

        store.completeWorkout(session = session, result = FeedbackResult.plan, probes = mapOf(Pattern.pull to short))

        assertEquals(before, store.engineState.position(Pattern.pull),
                     "a failed probe changes no coordinate. Staying on a movement you can already do " +
                         "is not a failure and is never charged for")
        assertEquals(short, store.engineState.shownDose(Pattern.pull, variation = probe.variation),
                     "what was honestly shown on the new rung is still recorded — it is a fact either way")
        assertFalse(Pattern.pull in store.engineState.lastHard,
                    "and a short probe is not a \"hard\", or the gate would withhold the next probe too")
    }

    /**
     * The number reaches the JOURNAL too, not only `applyFeedback`: without
     * it, what a probe showed would be unrecoverable the moment the rating
     * landed — and the history sheet, reading a record that carries the
     * probe in its own plan, could say nothing about the outcome.
     *
     * Both halves: the number that came back is written, and a session where
     * none did writes no key at all rather than a zero that would read as
     * "showed nothing".
     */
    @Test
    fun probe_whateverNumberCameBack_isWrittenIntoTheJournalOfWorkouts() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val probe = assertNotNull(exercise(Pattern.pull, session).probe, "the fixture must carry a probe")

        store.completeWorkout(session = session, result = FeedbackResult.plan, probes = mapOf(Pattern.pull to probe.load))

        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(probe.load, record.probes?.get(Pattern.pull),
                     "the record keeps what the probe showed, not only what the engine did with it")
        assertNotNull(assertNotNull(record.exercises).firstOrNull { it.pattern == Pattern.pull }?.probe,
                      "and the plan it was offered in, which is what names the movement")
    }

    @Test
    fun probe_whenNothingCameBack_theRecordCarriesNoProbeKeyAtAll() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, probes = emptyMap())

        assertNull(assertNotNull(store.records.lastOrNull()).probes,
                   "an absent number is absent — a zero would read as a probe done and failed")
    }

    @Test
    fun probe_whenNoNumberComesBackAtAll_leavesTheOfferStandingForNextTime() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val probe = assertNotNull(exercise(Pattern.pull, session).probe, "the fixture must carry a probe")
        val before = store.engineState.position(Pattern.pull)

        store.completeWorkout(session = session, result = FeedbackResult.plan, probes = emptyMap())

        assertEquals(before, store.engineState.position(Pattern.pull),
                     "a probe nobody resolved moves nothing — it is not a failed one")
        assertNull(store.engineState.shownDose(Pattern.pull, variation = probe.variation),
                   "and writes nothing down: nobody showed anything on the new rung")
        // The pull slot appears in EVERY session, which is why the assertion
        // below can ask the very next plan whether the offer still stands.
        assertNotNull(exercise(Pattern.pull, store.nextSession).probe,
                      "the probe comes round again at the next appearance")
    }

    @Test
    fun probeSet_finishedByATapWithNoNumberTyped_countsAsItsTargetAndMovesTheLadder() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val pulling = exercise(Pattern.pull, session)
        val probe = assertNotNull(pulling.probe, "the fixture must carry a probe")
        // Exactly what the flow's completeSet() hands over when the probe set
        // ends on a Done tap and nothing was typed into the adjuster.
        val reported = SetFacts.recordingProbe(emptyMap(), pulling.pattern,
                                               isProbe = true, target = probe.load)

        store.completeWorkout(session = session, result = FeedbackResult.plan, probes = reported)

        assertEquals(probe.variation, store.engineState.position(Pattern.pull).variation,
                     "a tapped probe is a done probe: while it was not, eight ladders out of ten were " +
                         "frozen forever for anyone who only taps")
    }

    // MARK: - What a probing exercise remembers

    /** The plan WITHOUT its probe — the set the probe occupied counted back in. */
    private fun planWithoutTheProbe(ex: SessionExercise): Int =
        (ex.plannedVolume + ex.load) * (if (ex.perSide) 2 else 1)

    @Test
    fun probingExercise_whenThePlanIsShown_remembersThePlanWithoutItsProbe() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val pulling = exercise(Pattern.pull, session)
        assertNotNull(pulling.probe, "the fixture must carry a probe")

        store.recordPlanShown(session)

        // A probing appearance writes a memory too — with none, the base
        // would stay a showing two appearances old. And not the working sets
        // alone: those are the position MINUS the set the probe borrowed for
        // one session, so the postcondition would read a plan that came back
        // to three sets as a rise and cut one off. The memory is the plan the
        // position implies, which is also the one the duration model assumes
        // — `estimatedMin` counts the probe as its own set because the session
        // is no shorter for trying.
        assertEquals(planWithoutTheProbe(pulling), store.engineState.shownWork[Pattern.pull],
                     "a probing appearance is remembered as the plan without its probe")
        assertTrue(planWithoutTheProbe(pulling) > pulling.plannedVolume * (if (pulling.perSide) 2 else 1),
                   "and that is strictly more than its working sets alone")
        assertNotNull(store.engineState.shownOrd[Pattern.pull],
                      "and by the position it was shown at")
        assertNotNull(store.engineState.shownWork[Pattern.hinge],
                      "an ordinary exercise in the same plan is remembered as before")
    }

    @Test
    fun probingExercise_whenTheSessionIsRated_remembersThePlanWithoutItsProbe() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val pulling = exercise(Pattern.pull, session)

        store.completeWorkout(session = session, result = FeedbackResult.plan, probes = emptyMap())

        assertEquals(planWithoutTheProbe(pulling), store.engineState.shownWork[Pattern.pull],
                     "the rating writes the same memory the showing does")
    }

    /** An ordinary exercise is untouched by that: its memory is its plan. */
    @Test
    fun ordinaryExercise_isRememberedByItsPlanExactly() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val ordinary = exercise(Pattern.hinge, session)
        assertNull(ordinary.probe, "the control must not be probing")

        store.recordPlanShown(session)

        assertEquals(ordinary.plannedVolume * (if (ordinary.perSide) 2 else 1),
                     store.engineState.shownWork[Pattern.hinge],
                     "no probe, no borrowed set, nothing added")
    }

    /** The case a probing memory could be feared for, pinned so the fear can
     *  be checked rather than believed: a probe that is PASSED raises the
     *  position, and a risen position is never trimmed — `repairDescent` keys
     *  on the position ordinal, not on the work. */
    @Test
    fun aPassedProbe_isNotTrimmedByTheMemoryTheProbingPlanLeft() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val pulling = exercise(Pattern.pull, session)
        val probe = assertNotNull(pulling.probe)
        store.recordPlanShown(session)
        val remembered = assertNotNull(store.engineState.shownWork[Pattern.pull])

        store.completeWorkout(session = session, result = FeedbackResult.plan,
                              probes = mapOf(Pattern.pull to probe.load))

        val entered = exercise(Pattern.pull, store.nextSession)
        assertEquals(probe.variation, entered.variation, "the probe was passed")
        assertEquals(EngineConfig.setsBase, entered.sets,
                     "entry is 3×4: the memory of the probing plan must not cut it")
        assertTrue(remembered > 0, "the memory it could have been cut by exists")
    }

    /**
     * And the case the probing memory exists for, on the axis the repair
     * actually acts on.
     *
     * "No more than the working sets" is deliberately NOT what is asserted:
     * under it a quiet week would have to come back as two sets, keeping the
     * borrowed set for good. What a descent may not do is ask more than the
     * plan the POSITION holds, or raise the dose — and it must give the slot
     * back, because the probe only borrowed it.
     */
    @Test
    fun aDescentOffTheCeiling_staysUnderThePlanThePositionHolds() {
        val store = seededStore(maxed = setOf(Pattern.pull))
        val session = store.nextSession
        val pulling = exercise(Pattern.pull, session)
        val held = planWithoutTheProbe(pulling)
        store.recordPlanShown(session)

        val decayed = Engine.applySilentDecay(state = store.engineState, gapDays = 10)
        val after = exercise(Pattern.pull, Engine.generateSession(decayed))

        assertNull(after.probe, "off the ceiling the probe is not offered")
        assertTrue(after.plannedVolume * (if (after.perSide) 2 else 1) <= held,
                   "a quiet week must not outgrow the plan the position holds")
        assertTrue(after.load < pulling.load, "and the dose is the axis that falls")
        assertEquals(pulling.sets + 1, after.sets,
                     "the slot the probe borrowed comes back — it was never lost")
    }

    // MARK: - What the probe puts on screen

    @Test
    fun techniqueTarget_forAProbe_pointsAtTheOfferedMovementInItsOwnUnit() {
        // pull_bar 2 → 3 is the one boundary in the whole library where the
        // unit changes: seconds below it, reps above. A target that
        // took its unit from the planned exercise would read "seconds" over a
        // set of negatives, and no other rung in the library would show it.
        val store = seededStore(variation = mapOf(Pattern.pullBar to 2), maxed = setOf(Pattern.pullBar),
                                hasBar = true, counter = 1)
        val barring = exercise(Pattern.pullBar, store.nextSession)
        val probe = assertNotNull(barring.probe, "the fixture must carry a probe")
        assertNotEquals(probe.unit, barring.unit,
                        "the fixture must straddle the unit boundary, or it proves nothing")

        val target = TechniqueTarget(probe, of = barring.pattern)

        assertEquals(barring.pattern, target.pattern, "the sheet stays inside the same movement pattern")
        assertEquals(probe.variation, target.variation, "but shows the movement being OFFERED")
        assertEquals(probe.unit, target.unit, "in the unit that movement is actually trained in")
        assertNotEquals(TechniqueTarget(barring).id, target.id,
                        "and it must be a different item, or .sheet(item:) would leave the planned " +
                            "movement's sheet open when the probe's is asked for")
    }

    @Test
    fun probeDisplay_readsAsOneSetAndNeverAsAMultiplier() {
        val reps = SessionProbe(variation = 2, name = "any", unit = LoadUnit.reps, load = 4, perSide = false)
        val perSide = SessionProbe(variation = 2, name = "any", unit = LoadUnit.reps, load = 4, perSide = true)
        val hold = SessionProbe(variation = 2, name = "any", unit = LoadUnit.hold, load = 15, perSide = false)

        assertEquals("4", reps.display,
                     "one set of four reps reads as the bare number — the probe is never \"N×\"")
        assertTrue(perSide.display.startsWith("4 "), "the per-side probe still leads with its number")
        assertNotEquals(reps.display, perSide.display,
                        "and has to say which side, or two very different sets read identically")
        assertTrue(hold.display.startsWith("15 "),
                   "a hold leads with its seconds and then names the unit")
        for (probe in listOf(reps, perSide, hold)) {
            assertFalse("×" in probe.display,
                        "${probe.display}: a probe is ONE set, so it never carries a multiplier")
        }
    }
}
