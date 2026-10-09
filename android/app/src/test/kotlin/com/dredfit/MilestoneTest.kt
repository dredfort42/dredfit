//
//  Port of ios/DredfitTests/MilestoneTests.swift: what a finished workout
//  earns, derived from the state before and after it.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.generateSession
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.workout.Milestone
import com.dredfit.workout.MilestoneDetector
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MilestoneTest : AppStoreTestCase() {

    /**
     * A store with a known counter and chosen positions, seeded through a
     * file: only `completeWorkout` moves `engineState`, and these tests are
     * no exception. `atCeiling` puts a movement on the top of ITS CURRENT
     * variation with a journal to match — the one position a probe is
     * offered from, and a probe is the only door into a new movement.
     */
    private fun seededStore(counter: Int = 0,
                            atCeiling: List<Pattern> = emptyList(),
                            atTopVariation: List<Pattern> = emptyList(),
                            atFloorOfSecond: List<Pattern> = emptyList(),
                            failStreak: Map<Pattern, Int> = emptyMap()): AppStore {
        fun variation(p: Pattern) = when (p) {
            in atTopVariation -> Library.count(p)
            in atFloorOfSecond -> 2
            else -> 1
        }
        fun dose(p: Pattern): Int {
            val grid = Dose.grid(Library.unit(p, variation(p)))
            return if (p in atCeiling || p in atTopVariation) grid.max else grid.min
        }
        // The journal is sparse: only the movements put somewhere have one.
        val journal = (atCeiling + atTopVariation + atFloorOfSecond).joinToString(",") { p ->
            val rows = (1..variation(p)).joinToString(",") { v ->
                "\"$v\":${if (v == variation(p)) dose(p) else Dose.grid(Library.unit(p, v)).max}"
            }
            "\"${p.rawValue}\",{$rows}"
        }
        return storeFrom("""
            {"engineState":{"counter":$counter,
              "vars":[${pairs(::variation)}],
              "doses":[${pairs(::dose)}],
              "shown":[$journal],
              "failStreak":[${pairs { failStreak[it] ?: 0 }}]},
             "records":[],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
    }

    /** The session for a given counter, as a pure engine function — the
     *  probe pattern must come from the session the seeded store generates. */
    private fun session(atCounter: Int): Session =
        Engine.generateSession(EngineState.initial.also { it.counter = atCounter })

    /** A number for every probe the plan offers, at the target it asks for. */
    private fun passing(session: Session): Map<Pattern, Int> =
        session.exercises.mapNotNull { ex -> ex.probe?.let { ex.pattern to Dose.grid(it.unit).min } }.toMap()

    // MARK: - A new movement

    @Test
    fun variationUpNamesTheExerciseYouJustUnlocked() {
        val subject = session(atCounter = 0).exercises[0].pattern
        val store = seededStore(atCeiling = listOf(subject))
        val session = store.nextSession
        assertNotNull(session.exercises.first { it.pattern == subject }.probe, "the seed must actually offer a probe")

        val earned = store.completeWorkout(session = session, result = FeedbackResult.plan, probes = passing(session))

        assertEquals(1, earned.size, "only the seeded pattern crosses a variation")
        val up = assertIs<Milestone.VariationUp>(earned[0])
        assertEquals(subject, up.pattern)
        assertEquals(2, up.variation)
        // The name must come from the NEW variation, not the one just left.
        assertEquals(Library.name(subject, 2), up.exercise)
    }

    /** The probe is the only door: standing on the ceiling and entering
     *  nothing crosses nothing, and nothing is announced. */
    @Test
    fun anUnresolvedProbeEarnsNothing() {
        val subject = session(atCounter = 0).exercises[0].pattern
        val store = seededStore(atCeiling = listOf(subject))

        val earned = store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        assertTrue(earned.isEmpty(), "an unresolved probe is not a milestone")
        assertEquals(1, store.engineState.vars[subject])
    }

    @Test
    fun setBandMilestoneOnTheTopVariation() {
        val subject = session(atCounter = 0).exercises[0].pattern
        val store = seededStore(atTopVariation = listOf(subject))

        val earned = store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        assertEquals(1, earned.size)
        val band = assertIs<Milestone.SetBand>(earned[0])
        assertEquals(subject, band.pattern)
        assertEquals(4, band.sets)
    }

    /** From the floor of a variation one "hard" only takes a set off, so the
     *  drop comes from the deload on the third shortfall, seeded with a
     *  streak of two. A step down is never announced. */
    @Test
    fun droppingAVariationIsNotAMilestone() {
        val subject = session(atCounter = 0).exercises[0].pattern
        val store = seededStore(atFloorOfSecond = listOf(subject),
                                failStreak = mapOf(subject to EngineConfig.failsToDeload - 1))

        val earned = store.completeWorkout(session = store.nextSession, result = FeedbackResult.less)

        assertEquals(1, store.engineState.vars[subject], "the movement really did fall back a variation")
        assertTrue(earned.isEmpty(), "a step down is never announced")
    }

    @Test
    fun skippedPatternEarnsNothing() {
        val subject = session(atCounter = 0).exercises[0].pattern
        val store = seededStore(atCeiling = listOf(subject))
        val session = store.nextSession

        val earned = store.completeWorkout(session = session, result = FeedbackResult.plan,
                                           skipped = setOf(subject), probes = passing(session))

        assertEquals(1, store.engineState.vars[subject], "a skip changes nothing")
        assertTrue(earned.isEmpty())
    }

    /** "A neighbour that stays put must not swallow this movement's
     *  milestone"; what keeps the neighbour put here is a SKIP. */
    @Test
    fun aMovementThatStaysPutDoesNotSwallowAMilestone() {
        val subject = session(atCounter = 9).exercises[0].pattern
        val stillOther = session(atCounter = 9).exercises[1].pattern
        val store = seededStore(counter = 9, atCeiling = listOf(subject))
        val session = store.nextSession

        val earned = store.completeWorkout(session = session, result = FeedbackResult.plan,
                                           skipped = setOf(stillOther), probes = passing(session))

        assertEquals(2, earned.size, "the new variation and the jubilee both land")
        assertEquals(subject, assertIs<Milestone.VariationUp>(earned[0]).pattern)
        assertEquals(Milestone.Jubilee(workouts = 10), earned[1])
        assertEquals(Dose.grid(Library.unit(stillOther, 1)).min, store.engineState.doses[stillOther],
                     "the movement that stayed put stayed put")
        assertEquals(0, store.engineState.sub[stillOther] ?: 0, "and it collected no sub-step either")
    }

    // MARK: - The acceptance case: a hard session earns nothing

    @Test
    fun sessionRatedLessEarnsNoMilestones() {
        val store = seededStore(counter = 3)           // 4 is not a jubilee
        assertTrue(store.completeWorkout(session = store.nextSession, result = FeedbackResult.less).isEmpty())
    }

    // MARK: - Jubilees

    @Test
    fun jubileeAtTheTenthWorkout() {
        val store = seededStore(counter = 9)
        assertEquals(listOf<Milestone>(Milestone.Jubilee(workouts = 10)),
                     store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan))
    }

    /** A jubilee fires on one exact counter value and never again, so a
     *  harder result earns it exactly the same. */
    @Test
    fun jubileeSurvivesAHardSession() {
        val store = seededStore(counter = 9)
        assertEquals(listOf<Milestone>(Milestone.Jubilee(workouts = 10)),
                     store.completeWorkout(session = store.nextSession, result = FeedbackResult.less))
    }

    @Test
    fun jubileeSchedule() {
        for (counter in listOf(10, 25, 50, 100, 150, 200)) {
            assertTrue(MilestoneDetector.isJubilee(counter), "$counter is a jubilee")
        }
        for (counter in listOf(0, 1, 9, 11, 24, 26, 49, 75, 99, 101, 125)) {
            assertFalse(MilestoneDetector.isJubilee(counter), "$counter is not")
        }
    }

    // MARK: - Several at once

    @Test
    fun newVariationsAreListedAboveTheJubilee() {
        val subject = session(atCounter = 9).exercises[0].pattern
        val store = seededStore(counter = 9, atCeiling = listOf(subject))
        val session = store.nextSession

        val earned = store.completeWorkout(session = session, result = FeedbackResult.plan, probes = passing(session))

        assertEquals(2, earned.size)
        assertIs<Milestone.VariationUp>(earned[0], "the new variation belongs on top")
        assertEquals(Milestone.Jubilee(workouts = 10), earned[1])
    }

    @Test
    fun severalNewVariationsInOneWorkout() {
        val patterns = session(atCounter = 0).exercises.take(3).map { it.pattern }
        val store = seededStore(atCeiling = patterns)
        val session = store.nextSession

        val earned = store.completeWorkout(session = session, result = FeedbackResult.plan, probes = passing(session))

        assertEquals(3, earned.size)
        assertEquals(3, earned.map { it.id }.toSet().size, "rows must be distinct")
    }
}
