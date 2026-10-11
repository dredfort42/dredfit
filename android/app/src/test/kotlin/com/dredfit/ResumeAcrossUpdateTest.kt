//
//  Port of ios/DredfitTests/ResumeAcrossUpdateTests.swift: a workout in
//  progress while the app updates to the build that keeps the pull-cap
//  memory. The build before held a push the pulls had once capped at the
//  count it showed then, and the first plan drawn without that memory hands
//  the push its sets back. The snapshot of the workout is keyed on the plan it
//  was started on, so the plan drawn now no longer matches it: without care
//  the resume card disappears and the work done so far is never recorded.
//
//  Every Swift test is ported. The snapshot's dates pass through
//  `SwiftJson.swiftDate`, the grid a Swift `Date` lives on, so the snapshot
//  equals itself read back from the file as it does on iOS.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.SwiftJson
import com.dredfit.core.generateSession
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.AppStore
import com.dredfit.store.barToggleWouldDiscardWorkout
import com.dredfit.store.clearWorkoutSnapshot
import com.dredfit.store.nextSession
import com.dredfit.store.resumableWorkout
import com.dredfit.store.settleAbandonedWorkout
import com.dredfit.store.unfinishedWorkoutAwaitingAnswer
import com.dredfit.workout.WorkoutSessionStore
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ResumeAcrossUpdateTest : AppStoreTestCase() {

    /** The state a build without the memory left: the horizontal push stands
     *  on its top variation's five sets and was last shown at four, under a
     *  pull that stood on four. The pull has five since, and nothing says what
     *  the push was capped at. Workout 1 carries the pull slot and both pushes. */
    private fun frozenPushState(barTop: Boolean = false): EngineState {
        val seed = EngineState.initial
        val pullTop = Library.count(Pattern.pull)
        val pushTop = Library.count(Pattern.pushH)
        val pullDose = Dose.grid(Library.unit(Pattern.pull, pullTop)).min
        val pushDose = Dose.grid(Library.unit(Pattern.pushH, pushTop)).max
        seed.vars[Pattern.pull] = pullTop
        seed.sets[Pattern.pull] = 4
        seed.doses[Pattern.pull] = pullDose
        seed.shown[Pattern.pull] = mutableMapOf(pullTop to pullDose)
        if (barTop) {
            val barTopVar = Library.count(Pattern.pullBar)
            val barDose = Dose.grid(Library.unit(Pattern.pullBar, barTopVar)).min
            seed.vars[Pattern.pullBar] = barTopVar
            seed.sets[Pattern.pullBar] = 5
            seed.doses[Pattern.pullBar] = barDose
            seed.shown[Pattern.pullBar] = mutableMapOf(barTopVar to barDose)
        }
        seed.vars[Pattern.pushH] = pushTop
        seed.sets[Pattern.pushH] = 5
        seed.doses[Pattern.pushH] = pushDose
        seed.shown[Pattern.pushH] = mutableMapOf(pushTop to pushDose)
        val legacy = Engine.recordShown(state = seed, session = Engine.generateSession(seed))
        legacy.sets[Pattern.pull] = 5
        legacy.shownCap = mutableMapOf()
        legacy.shownOwn = mutableMapOf()
        legacy.shownSkip = mutableSetOf()
        return legacy
    }

    /** The plan the build before drew from that state: the same plan with no
     *  push handed anything back. Drawn here by marking both pushes as having
     *  lost a set since their showing — the one mark under which the repair
     *  lifts nothing — rather than by the query the store uses, so the test
     *  does not grade the fix with the fix. */
    private fun planBeforeTheUpdate(state: EngineState): Session {
        val held = state.copy()
        held.shownSkip = mutableSetOf(Pattern.pushH, Pattern.pushV)
        return Engine.generateSession(held)
    }

    private fun pushH(session: Session): SessionExercise =
        assertNotNull(session.exercises.firstOrNull { it.pattern == Pattern.pushH },
                      "workout 1 must carry the horizontal push — the rotation moved")

    /** Two exercises behind and a set into the third, saved `age` ago. */
    private fun snapshot(plan: Session, age: Duration): WorkoutSnapshot {
        val now = Instant.now()
        return WorkoutSnapshot(sessionNumber = plan.sessionNumber,
                               exIndex = 2,
                               setIndex = 1,
                               workoutStart = SwiftJson.swiftDate(now.minus(age).minusSeconds(20 * 60)),
                               savedAt = SwiftJson.swiftDate(now.minus(age)),
                               fingerprint = WorkoutSnapshot.fingerprint(plan))
    }

    /** The store as the new build opens it: the old state and the workout it
     *  had in progress, read from the file. */
    private fun launch(state: EngineState, pending: WorkoutSnapshot): AppStore {
        Files.writeString(tempPath, AppData(engineState = state, records = emptyList(),
                                            settings = AppSettings(), pendingWorkout = pending).encode())
        val store = makeStore()
        assertEquals(state, store.engineState,
                     "the seed did not load — everything below would be about a clean start")
        assertEquals(pending, store.pendingWorkout, "the workout in progress did not load")
        return store
    }

    @Test
    fun theSeedIsAPushTheUpdateWouldHandItsSetBack() {
        val state = frozenPushState()
        assertEquals(4, pushH(planBeforeTheUpdate(state)).sets,
                     "the build before must hold the push at the four sets it showed")
        assertEquals(5, pushH(Engine.generateSession(state)).sets,
                     "the plan drawn now must hand the push its fifth set back")
    }

    @Test
    fun aWorkoutInProgressAcrossTheUpdateIsStillOfferedBack() {
        val state = frozenPushState()
        val started = planBeforeTheUpdate(state)
        val snap = snapshot(started, age = Duration.ofMinutes(5))
        val store = launch(state, snap)

        assertEquals(snap, store.resumableWorkout(),
                     "the workout in progress across the update must still be offered back")
        assertEquals(snap.fingerprint, WorkoutSnapshot.fingerprint(store.nextSession),
                     "it carries on as it was started — the snapshot's indices belong to that plan")
        assertEquals(4, pushH(store.nextSession).sets,
                     "no set appears under the person's hands in the middle of the workout")
    }

    /** Today records every plan it puts on screen, and the plan on screen
     *  beside the card is the one in progress. That plan is not a new showing:
     *  the build before wrote it down when it drew it. Written again, it would
     *  carry a cap memory that says the cap allowed what it held back. */
    @Test
    fun thePlanHeldForTheWorkoutIsNotWrittenDownAgain() {
        val state = frozenPushState()
        val snap = snapshot(planBeforeTheUpdate(state), age = Duration.ofMinutes(5))
        val store = launch(state, snap)

        store.recordPlanShown(store.nextSession)
        assertEquals(state, store.engineState, "the held plan must leave the state as the build before left it")
        assertEquals(snap, store.resumableWorkout(), "and the workout must still be offered back")
    }

    @Test
    fun pastTheOccasionTheCardStillAsks() {
        val state = frozenPushState()
        val snap = snapshot(planBeforeTheUpdate(state), age = WorkoutSessionStore.resumeWindow.plusSeconds(60))
        val store = launch(state, snap)

        assertNull(store.resumableWorkout(), "the occasion is over — it is not offered to carry on")
        assertEquals(snap, store.unfinishedWorkoutAwaitingAnswer(),
                     "but the person must still be asked whether to keep it")
    }

    /** A workout nobody came back to is recorded with what was done — on the
     *  plan that was trained, not cleared as a snapshot of a plan nobody has. */
    @Test
    fun aForgottenWorkoutIsRecordedOnThePlanItWasTrainedOn() {
        val state = frozenPushState()
        val snap = snapshot(planBeforeTheUpdate(state), age = WorkoutSessionStore.forgottenAfter.plusSeconds(60))
        val store = launch(state, snap)

        assertTrue(store.settleAbandonedWorkout(), "the workout happened and must be settled")
        assertEquals(1, store.records.size, "it must exist in the journal")
        val pushRecord = assertNotNull(store.records.lastOrNull()?.exercises?.firstOrNull { it.pattern == Pattern.pushH })
        assertEquals(4, pushRecord.sets, "recorded on the four sets that were trained")
        assertNull(store.pendingWorkout)
    }

    /** Only the workout in progress keeps its plan. Started over from the card
     *  — after Today has put the held plan on screen, as it always has by then
     *  — the plan is the one drawn now, with the set handed back, and the
     *  showing of it writes the memory that keeps it. */
    @Test
    fun startingOverRunsThePlanDrawnNow() {
        val state = frozenPushState()
        val store = launch(state, snapshot(planBeforeTheUpdate(state), age = Duration.ofMinutes(5)))
        store.recordPlanShown(store.nextSession)

        store.clearWorkoutSnapshot()
        assertEquals(5, pushH(store.nextSession).sets,
                     "starting over runs the plan drawn now, and the push has its set back")
        store.recordPlanShown(store.nextSession)
        assertEquals(5, store.engineState.shownCap[Pattern.pushH], "that showing remembers the cap it was shown under")
        assertEquals(5, pushH(store.nextSession).sets, "and the set stays")
    }

    /** A snapshot that is not this state's workout in progress holds nothing
     *  back, though it was taken on the plan the build before drew: the plan
     *  is the one drawn now. */
    @Test
    fun aSnapshotOfAnotherWorkoutLeavesThePlanDrawnNow() {
        val state = frozenPushState()
        val taken = snapshot(planBeforeTheUpdate(state), age = Duration.ofMinutes(5))
        val stale = taken.copy(sessionNumber = taken.sessionNumber + 1)
        val store = launch(state, stale)

        assertNull(store.resumableWorkout(), "a snapshot of another workout is not offered back")
        assertEquals(5, pushH(store.nextSession).sets,
                     "and it must not keep the push off the set the plan drawn now hands back")
    }

    /** The settings row asks before the bar switch throws a workout away, and
     *  it must ask about the plan the workout is actually on. Here the bar
     *  stands on five sets too, so switching it on moves nothing in this plan. */
    @Test
    fun theBarSwitchKnowsTheWorkoutSurvivesIt() {
        val state = frozenPushState(barTop = true)
        val snap = snapshot(planBeforeTheUpdate(state), age = Duration.ofMinutes(5))
        val store = launch(state, snap)

        assertNotNull(store.resumableWorkout(), "the workout must be resumable to begin with")
        assertFalse(store.barToggleWouldDiscardWorkout(true),
                    "the switch keeps this workout's plan, and the warning would be false")
    }

    /** The other side: the bar's branch stands on three sets, so switching it
     *  on caps the push at three — the workout's plan would change under it,
     *  and the row has to ask. */
    @Test
    fun theBarSwitchKnowsWhenItWouldDiscardTheWorkout() {
        val state = frozenPushState()
        val snap = snapshot(planBeforeTheUpdate(state), age = Duration.ofMinutes(5))
        val store = launch(state, snap)

        assertNotNull(store.resumableWorkout(), "the workout must be resumable to begin with")
        assertTrue(store.barToggleWouldDiscardWorkout(true),
                   "a bar on three sets caps the push, and the workout in progress would be lost")
    }
}
