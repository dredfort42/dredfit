//
//  Port of ios/DredfitTests/SetSkipTests.swift: the skip that happens DURING
//  the workout — the app's half of the rule. That the app hands the skip over
//  through the one entry point that settles the order, that a movement it
//  could not record travels as a skipped exercise instead, and that neither
//  the journal nor an interrupted workout loses the count on the way.
//
//  Every test is ported. Swift's `tempURLPrefix` names the scratch file; the
//  @TempDir of AppStoreTestCase makes one per test here.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.applyFeedback
import com.dredfit.core.generateSession
import com.dredfit.core.setCut
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.workout.SetFacts
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SetSkipTest : AppStoreTestCase() {

    /**
     * Seeded through the state file, like the app's own load — in the v3
     * shape, so it loads as written rather than through the v2 migration: a
     * seed the store quietly replaced would make the assertions here true for
     * the wrong reason.
     *
     * `variation` rungs up every ladder, one rung BELOW the dose ceiling —
     * a ceiling would offer a PROBE, and a probe set is not a working set a
     * skip can take, so the plan under test would stop being a plan of
     * working sets. `sets` opens a band, which exists only on the top
     * variation.
     */
    private fun store(variation: Int, sets: Int = EngineConfig.setsBase): AppStore {
        fun at(p: Pattern): Int = minOf(variation, Library.count(p))
        fun dose(p: Pattern): Int {
            val grid = Dose.grid(Library.unit(p, at(p)))
            return grid.max - grid.step
        }
        val json = """
        {"engineState":{"counter":0,"vars":[${pairs { at(it) }}],"doses":[${pairs { dose(it) }}],
                        "sets":[${pairs { sets }}],"failStreak":[]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        return storeFrom(json)
    }

    /** Rotation does not show every movement every session, so "the next
     *  showing" is the nearest session that contains the movement at all. */
    private fun nextShown(store: AppStore, pattern: Pattern): SessionExercise? {
        val probe = store.engineState.copy()
        repeat(9) {   // eight sessions is one full turn of the rotation
            Engine.generateSession(probe).exercises.firstOrNull { it.pattern == pattern }?.let { return it }
            probe.counter += 1
        }
        return null
    }

    // MARK: - Rule 1: the order, from the app's side

    /**
     * The rule on two cases, walked through the STORE: a session completed
     * on plan with one set skipped comes back one set shorter.
     *
     * This is the app's half of rule 1 and it is a real guard, not a copy of
     * the engine's. The store cannot express the wrong order — it hands the
     * tally to the overload that settles it — and the assertion below is what
     * goes red if it ever starts writing the cut itself: with the cut written
     * BEFORE the rating, `riseBy` hands the set straight back and the plan
     * comes round unchanged. The second half of the test shows exactly that,
     * so the first half cannot be read as passing by luck.
     */
    @Test
    fun aSkippedSetReachesTheNextPlanThroughTheRating() {
        // The base band and a real band: a movement partway up its ladder,
        // and one at the very top of it, where the set bands open.
        for ((variation, sets) in listOf(2 to EngineConfig.setsBase,
                                         Library.count(Pattern.squat) to EngineConfig.setsMax)) {
            val store = store(variation = variation, sets = sets)
            val shown = assertNotNull(nextShown(store, Pattern.squat))
            assertEquals(sets, shown.sets,
                         "v$variation: the plan does not show the sets the seed wrote")
            assertNull(shown.probe, "v$variation: a probe set is not a working set")

            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                                  setsSkipped = mapOf(Pattern.squat to 1))

            assertEquals(1, store.engineState.cutOf(Pattern.squat),
                         "v$variation: the skip did not reach the state")
            val after = assertNotNull(nextShown(store, Pattern.squat))
            assertEquals(shown.sets - 1, after.sets,
                         "v$variation: the next showing kept the set that was skipped")

            // The order the store must never take, walked from the same
            // starting point and with the same gap the store had (none — this
            // is the first workout): the skip written in advance is eaten by
            // the very event that would have handed the set back later.
            val base = EngineState.initial
            for (pattern in Pattern.allCases) {
                val v = minOf(variation, Library.count(pattern))
                val grid = Dose.grid(Library.unit(pattern, v))
                base.vars[pattern] = v
                base.doses[pattern] = grid.max - grid.step
                base.sets[pattern] = sets
            }
            val early = Engine.setCut(state = base, pattern = Pattern.squat, cut = 1)
            val wrong = Engine.applyFeedback(state = early,
                                             session = Engine.generateSession(early),
                                             result = FeedbackResult.plan, overrides = emptyMap(),
                                             skipped = emptySet(), gapDays = null)
            assertEquals(0, wrong.cutOf(Pattern.squat),
                         "v$variation: the wrong order no longer loses the skip — rule 1 " +
                             "has stopped describing the engine")
        }
    }

    /** Every movement of the session at once, which is what a person short
     *  of time actually does — and the plan that comes back is shorter across
     *  the board rather than in the one place the walk happened to start. */
    @Test
    fun skipsOnEveryMovementAllLand() {
        val store = store(variation = 3, sets = EngineConfig.setsBase)
        val session = store.nextSession
        val skipped = session.exercises.associate { it.pattern to 1 }

        store.completeWorkout(session = session, result = FeedbackResult.plan, setsSkipped = skipped)

        for (ex in session.exercises) {
            assertEquals(1, store.engineState.cutOf(ex.pattern),
                         "${ex.pattern}: the skip was lost")
        }
        assertTrue(store.nextSession.estimatedTotalMin < session.estimatedTotalMin,
                   "a session with a set off every movement is not shorter")
    }

    // MARK: - Rule 2: what the app may record, and what it may not

    /** The arithmetic both escapes on the work screen read. A movement has
     *  to keep the floor's worth of sets to count as trained at all. */
    @Test
    fun theFloorIsWhereTheSkipStopsBeingASkippedSet() {
        // A plan of two is already on the floor: there is no set to take.
        assertFalse(SetFacts.skipFits(1, of = EngineConfig.setsFloor, alreadySkipped = 0),
                    "on the floor a skipped set cannot be recorded as one")
        // A plan of five gives three, and the fourth is the movement itself.
        for (gone in 0 until 3) {
            assertTrue(SetFacts.skipFits(1, of = 5, alreadySkipped = gone),
                       "5 sets with $gone gone still has one to give")
        }
        assertFalse(SetFacts.skipFits(1, of = 5, alreadySkipped = 3),
                    "the fourth skip of five would leave a single set")
        // And the same rule read the other way: what "skip the rest" may take
        // is whatever leaves the floor standing.
        assertTrue(SetFacts.skipFits(3, of = 5, alreadySkipped = 0),
                   "two sets performed and the other three skipped is one tap")
        assertFalse(SetFacts.skipFits(4, of = 5, alreadySkipped = 0),
                    "a single set performed is not a trained movement")
    }

    /**
     * A probing exercise never has more working sets than the shared floor,
     * so none of them can be skipped on its own and the work screen offers
     * "Skip exercise" in place of "Skip this set". That is what keeps the one
     * card a hold summary lets a person correct, the last working set, a set
     * the clock ran: the probe still ends on that summary, and a working set
     * skipped before it would stand on the card under a line saying what the
     * clock saw.
     *
     * The engine holds it by construction — a probe needs a variation below
     * the top, where the sets stay at the base band, the probe takes one of
     * them, and the pull slot's set count may only lower the push it caps —
     * so it is swept rather than taken on trust: every rung of every ladder
     * on its ceiling, every band asked for and one past the last, every cut,
     * a full turn of the rotation, both branches of the pull slot, and that
     * slot also on the top of its own ladder, in a band above any push that
     * can probe.
     */
    @Test
    fun theEngineNeverGivesAProbingExerciseThreeWorkingSets() {
        // Every movement on the ceiling of `rung` and journalled there; the
        // pull slot on the top of its own ladder instead when `pullOnTop`.
        fun onTheCeiling(rung: Int, sets: Int, cut: Int, pullOnTop: Boolean): EngineState {
            val state = EngineState.initial
            for (p in Pattern.allCases) {
                val v = if (pullOnTop && p in Pattern.pullSide) Library.count(p) else minOf(rung, Library.count(p))
                val ceiling = Dose.grid(Library.unit(p, v)).max
                state.vars[p] = v
                state.doses[p] = ceiling
                state.sets[p] = sets
                state.cut[p] = cut
                state.shown[p] = mutableMapOf(v to ceiling)
            }
            return state
        }
        val longestLadder = Pattern.allCases.maxOfOrNull { Library.count(it) } ?: 1
        val probing = mutableListOf<SessionExercise>()
        for (rung in 1..longestLadder) {
            for (sets in 1..EngineConfig.setsMax + 1) {
                for (cut in 0..EngineConfig.setsMax - EngineConfig.setsFloor) {
                    for (pullOnTop in listOf(false, true)) {
                        val state = onTheCeiling(rung = rung, sets = sets, cut = cut, pullOnTop = pullOnTop)
                        for (counter in 0 until 8) {   // eight sessions is one full turn of the rotation
                            state.counter = counter
                            for (hasBar in listOf(false, true)) {
                                state.hasBar = hasBar
                                probing += Engine.generateSession(state).exercises.filter { it.probe != null }
                            }
                        }
                    }
                }
            }
        }
        assertTrue(probing.any { it.unit == LoadUnit.hold },
                   "the sweep met no probing hold, so it says nothing about the summary")
        val widest = probing.maxByOrNull { it.sets }
        assertTrue((widest?.sets ?: 0) <= EngineConfig.setsFloor,
                   "${widest?.pattern?.rawValue ?: "?"} v${widest?.variation ?: 0} has " +
                       "${widest?.sets ?: 0} working sets beside its probe: one can be skipped alone")
    }

    /** What the app does instead, and the reason rule 2 exists: the movement
     *  travels as an ordinary skipped exercise, and NOT as a dose of 0. The
     *  engine costs one of them nothing and the other a whole variation. */
    @Test
    fun onTheFloorTheMovementTravelsAsASkipAndNotAsAZero() {
        val store = store(variation = 2, sets = EngineConfig.setsBase)
        // On the floor: every movement cut as far as the axis goes.
        val session = store.nextSession
        val onFloor = session.exercises.associate { it.pattern to 1 }
        store.completeWorkout(session = session, result = FeedbackResult.plan, setsSkipped = onFloor)
        val floored = assertNotNull(nextShown(store, Pattern.squat))
        assertEquals(EngineConfig.setsFloor, floored.sets, "the seed is not on the floor")

        val before = store.engineState.position(Pattern.squat)
        val cutBefore = store.engineState.cutOf(Pattern.squat)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              skipped = setOf(Pattern.squat), setsSkipped = emptyMap())

        assertEquals(before, store.engineState.position(Pattern.squat),
                     "a skip on the floor moved the position")
        assertEquals(cutBefore, store.engineState.cutOf(Pattern.squat),
                     "a skip on the floor moved the cut")
    }

    /** A movement recorded as skipped carries no skipped SETS with it: it was
     *  not trained, so there is no volume to take off it next time. The flow
     *  drops the tally when it takes the exercise; this is the claim that
     *  makes the drop matter. */
    @Test
    fun aSkippedMovementAndSkippedSetsAreNotBothRecorded() {
        val store = store(variation = 3, sets = EngineConfig.setsBase)
        val session = store.nextSession

        store.completeWorkout(session = session, result = FeedbackResult.plan, skipped = setOf(Pattern.squat))

        assertEquals(0, store.engineState.cutOf(Pattern.squat),
                     "a movement nobody trained lost sets from its plan")
        assertNull(store.records.lastOrNull()?.setsSkipped,
                   "nothing was skipped set-wise, so the journal must say nothing")
    }

    // MARK: - The journal and the interrupted workout

    /** What happened is what the journal keeps: a record that kept only the
     *  rating could not tell whether the mid-workout skip has become the
     *  dominant price. */
    @Test
    fun theJournalRemembersTheSkippedSetsAcrossARelaunch() {
        val store = store(variation = 3, sets = EngineConfig.setsBase)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              setsSkipped = mapOf(Pattern.squat to 2))

        val reloaded = makeStore()
        assertEquals(mapOf(Pattern.squat to 2), reloaded.records.lastOrNull()?.setsSkipped,
                     "the journal lost the sets that were skipped")
    }

    /** The tally survives process death the way the per-set facts do — it is
     *  in the snapshot, and it comes back sanitized. */
    @Test
    fun theSnapshotCarriesTheTallyAndHealsIt() {
        val snapshot = WorkoutSnapshot(
            sessionNumber = 1, exIndex = 1, setIndex = 2,
            setsSkipped = mapOf(Pattern.squat to 1, Pattern.pull to -3, Pattern.hinge to 99),
            workoutStart = Instant.now(), savedAt = Instant.now())
        val restored = WorkoutSnapshot.fromJson(snapshot.toJson())

        assertEquals(1, restored.setsSkipped?.get(Pattern.squat))
        assertEquals(mapOf(Pattern.squat to 1, Pattern.hinge to EngineConfig.setsMax), restored.skips,
                     "a hand-edited file must not reach the engine as it is")
    }

    /** A snapshot written before the skip existed still decodes — the field
     *  is optional for the same reason every field below it is. */
    @Test
    fun anOlderSnapshotStillDecodes() {
        val json = """
        {"sessionNumber":1,"exIndex":0,"setIndex":0,"actuals":[],"skipped":[],
         "workoutStart":0,"savedAt":0}
        """
        val snapshot = WorkoutSnapshot.fromJson(Json.parseToJsonElement(json))
        assertTrue(snapshot.skips.isEmpty(), "an older snapshot must read as no skips")
    }
}
