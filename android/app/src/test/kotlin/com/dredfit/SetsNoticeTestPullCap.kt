//
//  Port of ios/DredfitTests/SetsNoticeTests+PullCap.swift: the push rows
//  under the pull slot's cap. A push never shows more sets than the weaker
//  pull branch stands on, so its count moves with the pulls while its own
//  position stands still — both directions announced on the push row.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.core.LoadUnit
import com.dredfit.core.pullCap
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.AppStore
import com.dredfit.store.aSetJustCameBack
import com.dredfit.store.nextSession
import com.dredfit.store.saveWorkoutSnapshot
import com.dredfit.store.setsJustHeldBackByThePulls
import com.dredfit.store.settleAbandonedWorkout
import com.dredfit.ui.today.ExerciseRow
import com.dredfit.workout.WorkoutSessionStore
import java.nio.file.Files
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SetsNoticeTestPullCap : SetsNoticeTestCase() {

    /** Rows 3×8 and push-ups 3×10, doses well under the ceiling so no probe
     *  takes a set. Workout 1 carries both pushes, 2 the vertical one, 3 the
     *  horizontal one — the pull slot in all, on the bar every other workout
     *  once the bar is on. */
    private fun pushStore(bar: Boolean = false, change: (EngineState) -> Unit = {}): AppStore {
        val seed = EngineState.initial
        seed.hasBar = bar
        seed.vars[Pattern.pull] = 4
        seed.doses[Pattern.pull] = 8
        seed.shown[Pattern.pull] = mutableMapOf(4 to 8)
        if (bar) {
            seed.vars[Pattern.pullBar] = 4
            seed.doses[Pattern.pullBar] = 5
            seed.shown[Pattern.pullBar] = mutableMapOf(4 to 5)
        }
        seed.vars[Pattern.pushH] = 3
        seed.doses[Pattern.pushH] = 10
        seed.shown[Pattern.pushH] = mutableMapOf(3 to 10)
        seed.vars[Pattern.pushV] = 3
        seed.doses[Pattern.pushV] = 8
        seed.shown[Pattern.pushV] = mutableMapOf(3 to 8)
        change(seed)
        Files.writeString(tempPath, AppData(engineState = seed, records = emptyList(), settings = AppSettings()).encode())
        val store = makeStore()
        assertEquals(seed, store.engineState, "the seed did not load — everything below would be about a clean start")
        return store
    }

    private fun pushH(session: Session): SessionExercise =
        assertNotNull(session.exercises.firstOrNull { it.pattern == Pattern.pushH },
                      "this workout must carry the horizontal push — the rotation moved")

    /** Workouts 1 and 2 trained, the second with one pull set skipped: the
     *  plan ahead is workout 3, whose push-ups the pull's two sets now cap. */
    private fun pushHeldBack(bar: Boolean = false): AppStore {
        val store = pushStore(bar = bar)
        train(store)
        train(store, setsSkipped = mapOf((if (bar) Pattern.pullBar else Pattern.pull) to 1))
        return store
    }

    // MARK: - Down

    @Test
    fun aPushThePullsHoldBackSaysSo() {
        val store = pushHeldBack()
        val row = pushH(store.nextSession)
        assertEquals(2, row.sets, "the pull's skipped set must cap the push — there is no drop to explain")
        assertTrue(store.setsJustHeldBackByThePulls(row), "a push the pulls held back lost a set without a word")
        assertFalse(store.aSetJustCameBack(row))
    }

    /** With the bar on, the cap is the WEAKER branch — usually the one not in
     *  today's plan. The line has to come from the cap, not a pull on screen. */
    @Test
    fun thePullBranchNotOnScreenCanHoldThePushBack() {
        val store = pushHeldBack(bar = true)
        val plan = store.nextSession
        assertEquals(listOf(Pattern.pull), plan.exercises.map { it.pattern }.filter { it in Pattern.pullSide },
                     "today's pull slot must be the row — the branch that lost the set sits it out")
        assertEquals(3, assertNotNull(plan.exercises.firstOrNull { it.pattern == Pattern.pull }).sets,
                     "the row on screen must stand on all its sets")
        val row = pushH(plan)
        assertEquals(2, row.sets, "the bar's two sets must cap the push")
        assertTrue(store.setsJustHeldBackByThePulls(row),
                   "the cap of a branch that is not on screen reached the push row without a word")
    }

    /** The push's own set skipped, then a pull set: the cap binds at exactly
     *  the push's own count and takes nothing. */
    @Test
    fun aPushThatLostItsOwnSetSaysNothingAboutThePulls() {
        val store = pushStore()
        train(store, setsSkipped = mapOf(Pattern.pushH to 1))
        train(store, setsSkipped = mapOf(Pattern.pull to 1))
        val row = pushH(store.nextSession)
        assertEquals(2, row.sets, "the push's own skipped set must still be off")
        val gate = assertNotNull(Engine.pullCap(on = Pattern.pushH, state = store.engineState))
        assertEquals(2, gate.own, "the push stands on two sets of its own")
        assertEquals(2, gate.cap, "and the pulls cap it at the same two")
        assertFalse(store.setsJustHeldBackByThePulls(row), "a set the push itself lost must not be put down to the pulls")
        assertFalse(store.aSetJustCameBack(row))
    }

    /** The pull starts a set short and sits workout 1 out whole. */
    private fun pullSitsOut(): AppStore {
        val store = pushStore { it.cut[Pattern.pull] = 1 }
        skipThePullWhole(store, workouts = 1)
        assertEquals(1, store.engineState.cutOf(Pattern.pull), "a pull skipped whole must keep its set off")
        return store
    }

    private fun pushV(exercises: List<SessionExercise>?): SessionExercise =
        assertNotNull(exercises?.firstOrNull { it.pattern == Pattern.pushV }, "the vertical push must be in this plan")

    /** A probe arriving under a cap that has not moved takes the last
     *  working set's slot: the probe's line says why, the pulls took nothing. */
    @Test
    fun aProbeArrivingUnderAStandingCapIsNotPutDownToThePulls() {
        val store = pushStore {
            it.cut[Pattern.pull] = 1
            it.doses[Pattern.pushH] = 15
            it.shown[Pattern.pushH] = mutableMapOf(3 to 15)
            it.lastHard = mutableSetOf(Pattern.pushH)
        }
        val first = pushH(store.nextSession)
        assertNull(first.probe, "the hard last answer must keep the probe away the first time")
        assertEquals(2, first.sets)
        skipThePullWhole(store, workouts = 2)
        val row = pushH(store.nextSession)
        assertNotNull(row.probe, "the probe must be offered now")
        assertEquals(1, row.sets, "one working set and the probe fill the two sets the cap allows")
        assertFalse(store.setsJustHeldBackByThePulls(row), "the working set went to the probe, not to the pulls")
    }

    /** A probe that leaves hands its slot back to a working set: under a cap
     *  that has not moved, no set back. */
    @Test
    fun aProbeLeavingUnderAStandingCapIsNoSetBack() {
        val store = pushStore {
            it.cut[Pattern.pull] = 1
            it.doses[Pattern.pushH] = 15
            it.shown[Pattern.pushH] = mutableMapOf(3 to 15)
        }
        val probing = pushH(store.nextSession)
        assertNotNull(probing.probe)
        assertEquals(1, probing.sets)
        // A number under the plan is a hard answer: the probe stays away next time.
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              overrides = mapOf(Pattern.pushH to 12.0), skipped = setOf(Pattern.pull), date = day(-300))
        assertEquals(true, store.records.last().heldBack?.contains(Pattern.pushH),
                     "one working set and the probe stood on three sets of the push's own")
        skipThePullWhole(store, workouts = 1)
        val row = pushH(store.nextSession)
        assertNull(row.probe, "the hard answer must keep the probe away")
        assertEquals(2, row.sets, "the probe's slot is a working set again, under the same cap")
        assertFalse(store.aSetJustCameBack(row), "no set came back: the cap still allows two")
    }

    /** The cap takes the slot a leaving probe hands back: the number stands,
     *  so nothing about fewer sets may be said. */
    @Test
    fun aCapTakingALeavingProbesSlotLeavesTheNumberAndSaysNothing() {
        val store = pushStore {
            it.doses[Pattern.pushH] = 15
            it.shown[Pattern.pushH] = mutableMapOf(3 to 15)
        }
        assertEquals(2, pushH(store.nextSession).sets, "two working sets and the probe")
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              overrides = mapOf(Pattern.pushH to 12.0), setsSkipped = mapOf(Pattern.pull to 1),
                              date = day(-300))
        skipThePullWhole(store, workouts = 1)
        val row = pushH(store.nextSession)
        assertNull(row.probe, "the hard answer must keep the probe away")
        assertEquals(2, row.sets, "the cap must hold the push at two working sets")
        assertEquals(true, Engine.pullCap(on = Pattern.pushH, state = store.engineState)?.let { it.cap < it.own },
                     "the cap must bind")
        assertFalse(store.setsJustHeldBackByThePulls(row), "the number did not drop, so nothing about fewer sets may be said")
    }

    /** The mirror: the cap lifts while a probe arrives to take the slot it
     *  frees — the working sets stand still, so no set is back. */
    @Test
    fun aCapLiftingIntoAnArrivingProbeIsNoSetBack() {
        val store = pushStore {
            it.cut[Pattern.pull] = 1
            it.doses[Pattern.pushH] = 15
            it.shown[Pattern.pushH] = mutableMapOf(3 to 15)
            it.lastHard = mutableSetOf(Pattern.pushH)
        }
        assertEquals(2, pushH(store.nextSession).sets, "held back to two, no probe yet")
        train(store)
        train(store)
        assertEquals(true, store.records.first().heldBack?.contains(Pattern.pushH))
        val row = pushH(store.nextSession)
        assertNotNull(row.probe, "the probe must be offered now")
        assertEquals(2, row.sets, "the lifted cap's set must have gone to the probe")
        assertFalse(store.aSetJustCameBack(row), "the working sets did not grow, so no set is back")
    }

    private fun day(offset: Long): Instant = Instant.now().plusSeconds(offset * 86_400)

    /** Workouts on plan with the pull sat out whole, so its set stays off. */
    private fun skipThePullWhole(store: AppStore, workouts: Int) {
        repeat(workouts) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                                  skipped = setOf(Pattern.pull), date = day(-298L + 2 * store.records.size))
        }
    }

    /** Held back appearance after appearance at the same count: the line is
     *  about the drop, not about the cap. */
    @Test
    fun aPushStillHeldBackAtTheSameCountSaysNothingMore() {
        val store = pullSitsOut()
        assertEquals(2, pushV(store.records.last().exercises).sets,
                     "the vertical push's last card must already have been held back")
        val row = pushV(store.nextSession.exercises)
        assertEquals(2, row.sets, "and the pulls must still hold it at two")
        assertFalse(store.setsJustHeldBackByThePulls(row), "a count that did not move has nothing to explain")
    }

    // MARK: - Up

    /** The pull's set comes back, and with it the push-ups' third. The
     *  push's own hold never armed, so only the journal can tell. */
    @Test
    fun aSetThePullsGiveBackIsAnnouncedOnThePush() {
        val store = pushHeldBack()
        assertEquals(2, pushH(store.nextSession).sets)
        train(store)
        val row = pushH(store.nextSession)
        assertEquals(3, row.sets, "the pull's set came back, so the cap must lift")
        assertNull(store.engineState.setsHold[Pattern.pushH], "the push's own hold must not be what speaks here")
        assertTrue(store.aSetJustCameBack(row), "the set the pulls gave back reached the push row without a word")
        assertFalse(store.setsJustHeldBackByThePulls(row))
    }

    /** More sets on another variation are not a set coming back. */
    @Test
    fun noSetComesBackAcrossAVariation() {
        val store = pushHeldBack()
        train(store)
        store.makeEasier(Pattern.pushH)
        val row = pushH(store.nextSession)
        assertEquals(2, row.variation, "the handle must have moved the push down a variation")
        assertEquals(3, row.sets, "with more sets than the held-back card")
        assertFalse(store.aSetJustCameBack(row), "more sets on another variation are not a set coming back")
    }

    /** A record from a build that did not stamp it claims nothing. */
    @Test
    fun aRecordWithoutTheStampClaimsNothing() {
        val store = pushHeldBack()
        train(store)
        val row = pushH(store.nextSession)
        assertTrue(store.aSetJustCameBack(row), "the stamped journal must announce the rise")

        store.update { s -> s.copy(records = s.records.map { it.copy(heldBack = null) }) }
        assertFalse("heldBack" in Files.readString(tempPath),
                    "the file must carry no stamp at all — the shape an older build wrote")
        val reloaded = makeStore()
        assertEquals(3, reloaded.records.size)
        assertFalse(reloaded.aSetJustCameBack(row), "a record without the stamp must claim nothing")
    }

    // MARK: - The stamp

    /** Held back is decided against the position the plan was BUILT from. */
    @Test
    fun theStampReadsThePositionThePlanWasBuiltFrom() {
        val store = pushStore {
            it.cut[Pattern.pushH] = 1
            it.cut[Pattern.pull] = 1
        }
        assertEquals(2, pushH(store.nextSession).sets)
        train(store)
        assertEquals(3, Engine.pullCap(on = Pattern.pushH, state = store.engineState)?.own,
                     "the rating must hand the push its own set back")
        assertEquals(setOf(Pattern.pushV), store.records.last().heldBack,
                     "only the vertical push showed fewer sets than it stood on")

        // A probe borrows a set rather than taking one.
        val probing = pushStore {
            it.doses[Pattern.pushH] = 15
            it.shown[Pattern.pushH] = mutableMapOf(3 to 15)
        }
        val row = pushH(probing.nextSession)
        assertNotNull(row.probe, "the push must be on its ceiling with the probe offered")
        assertEquals(2, row.sets)
        train(probing)
        assertNull(probing.records.last().heldBack, "the probe's slot is not a set held back")
    }

    /** A changed rating and a settled workout both go through
     *  `completeWorkout`, so both carry the stamp. */
    @Test
    fun aChangedOrSettledWorkoutKeepsTheStamp() {
        val store = pushHeldBack()
        train(store)
        assertEquals(setOf(Pattern.pushH), store.records.last().heldBack)
        store.changeLastRating(to = FeedbackResult.less)
        assertEquals(FeedbackResult.less, store.records.last().result, "the rating must have changed")
        assertEquals(setOf(Pattern.pushH), store.records.last().heldBack,
                     "the replayed record must keep what the card showed")

        val settling = pushHeldBack()
        val plan = settling.nextSession
        val savedAt = Instant.now().minus(WorkoutSessionStore.forgottenAfter).minusSeconds(60)
        settling.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = plan.sessionNumber, exIndex = plan.exercises.size, setIndex = 0,
            workoutStart = savedAt.minusSeconds(30 * 60), savedAt = savedAt,
            fingerprint = WorkoutSnapshot.fingerprint(plan), atFeedback = true))
        val relaunched = makeStore()
        assertTrue(relaunched.settleAbandonedWorkout())
        assertEquals(3, relaunched.records.size)
        assertEquals(setOf(Pattern.pushH), relaunched.records.last().heldBack,
                     "a workout settled on the athlete's behalf must carry the stamp too")
    }

    // MARK: - The row

    /** The pulls' line stands beside a probe's: one says why the working
     *  sets dropped, the other what the last set is. */
    @Test
    fun thePullsLineStandsBesideTheProbeLine() {
        val probe = SessionProbe(variation = 4, name = "Feet-elevated push-up", unit = LoadUnit.reps, load = 4,
                                 perSide = false)
        val row = SessionExercise(pattern = Pattern.pushH, name = "Push-up", variation = 3, unit = LoadUnit.reps,
                                  load = 15, perSide = false, sets = 1, restSetSec = 60, restExerciseSec = 90,
                                  loads = null, probe = probe)
        val line = assertNotNull(ExerciseRow.pullsNote(heldBack = true))
        val probeLine = assertNotNull(ExerciseRow.probeNote(row))
        assertFalse(line.english.isEmpty())
        assertNull(ExerciseRow.pullsNote(heldBack = false))
        assertEquals(listOf(line, probeLine), ExerciseRow.notes(row, setCameBack = false, heldBackByPulls = true),
                     "the pulls' line comes first, about the number; the probe's after it")
        assertEquals(listOf(probeLine), ExerciseRow.notes(row, setCameBack = false))
    }
}
