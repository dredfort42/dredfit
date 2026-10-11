//
//  Port of ios/DredfitTests/AbandonedWorkoutTests.swift: a workout that was
//  trained and never rated. Putting the phone down on "How did it go?" and
//  letting the system kill the process must not erase the session: the
//  snapshot it leaves behind is what gets it into the journal.
//
//  Three bands: inside three hours the card offers to carry on; past it and
//  up to twelve hours the athlete is ASKED whether to continue or to finish
//  and rate it; only a workout nobody came back to for twelve hours is
//  recorded without being asked.
//
//  Every Swift test is ported; none of them asserts on Health.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.nextSession
import com.dredfit.store.resumableWorkout
import com.dredfit.store.saveWorkoutSnapshot
import com.dredfit.store.settleAbandonedWorkout
import com.dredfit.store.unfinishedWorkoutAwaitingAnswer
import com.dredfit.workout.Absence
import com.dredfit.workout.Countdown
import com.dredfit.workout.SetFacts
import com.dredfit.workout.WorkoutSessionStore
import com.dredfit.workout.awayGained
import com.dredfit.workout.settlement
import java.time.Instant
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AbandonedWorkoutTest : AppStoreTestCase() {

    private val window = WorkoutSessionStore.resumeWindow
    private val forgotten = WorkoutSessionStore.forgottenAfter

    /** A snapshot parked on the rating screen: every exercise behind, nothing
     *  left to do but answer. */
    private fun atFeedback(store: AppStore, savedAt: Instant): WorkoutSnapshot =
        WorkoutSnapshot(sessionNumber = 1,
                        exIndex = store.nextSession.exercises.size,
                        setIndex = 0,
                        setActuals = mapOf(Pattern.pushH to listOf(12, 9)),
                        workoutStart = savedAt.minusSeconds(30 * 60),
                        savedAt = savedAt,
                        fingerprint = WorkoutSnapshot.fingerprint(store.nextSession),
                        atFeedback = true)

    /** Swift's `XCTAssertEqual(a, b, accuracy: 1)` on two dates. */
    private fun assertWithinASecond(expected: Instant, actual: Instant, message: String? = null) {
        assertTrue(abs(Countdown.seconds(expected, actual)) <= 1.0, "${message ?: ""} — expected $expected, got $actual")
    }

    // MARK: - The defect itself

    @Test
    fun aWorkoutLeftOnTheRatingIsRecordedAfterTheOccasionPasses() {
        val store = makeStore()
        val last = Instant.now().minus(forgotten).minusSeconds(60)
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = last))

        val relaunched = makeStore()
        assertNull(relaunched.resumableWorkout(), "the occasion is over — it is not offered back")
        assertTrue(relaunched.settleAbandonedWorkout())
        assertEquals(1, relaunched.records.size, "the workout happened; it must exist in the journal")
        assertEquals(FeedbackResult.plan, relaunched.records.firstOrNull()?.result, "an unrated workout counts as on plan")
        assertNull(relaunched.pendingWorkout, "settled means no longer pending")
    }

    /** The half of the fix that is easy to leave out: rating yesterday's
     *  session this morning must not move it into today. */
    @Test
    fun theSettledWorkoutKeepsTheDayItHappenedOn() {
        val store = makeStore()
        val lastNight = Instant.now().minus(forgotten).minusSeconds(2 * 60 * 60)
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = lastNight))

        val relaunched = makeStore()
        assertTrue(relaunched.settleAbandonedWorkout())
        val record = assertNotNull(relaunched.records.firstOrNull())
        assertWithinASecond(lastNight, record.date,
                            "dated where it ended (savedAt), not from the moment it was noticed")
        // A record's date is its END, as the Health export reads it: the
        // interval it spans starts at workoutStart, not half an hour early.
        val duration = assertNotNull(record.durationSec).toLong()
        assertWithinASecond(lastNight.minusSeconds(30 * 60), record.date.minusSeconds(duration))
    }

    /** What the flow carried to the rating reaches the settled record too:
     *  the movement it was cut short on, the probe's number, the steps added
     *  for next time and the warm-up's length. Settling stands in for a tap
     *  nobody made; it must not quietly drop what was already decided. */
    @Test
    fun aSettledWorkoutKeepsWhatTheFlowCarriedToTheRating() {
        val store = makeStore()
        val exercises = store.nextSession.exercises
        val first = exercises.first().pattern
        val last = exercises.last().pattern
        val savedAt = Instant.now().minus(forgotten).minusSeconds(60)
        store.saveWorkoutSnapshot(atFeedback(store, savedAt).copy(
            probes = mapOf(first to 6), interrupted = last, warmupSec = 240, raisedSteps = mapOf(first to 1)))

        val relaunched = makeStore()
        assertTrue(relaunched.settleAbandonedWorkout())
        val record = assertNotNull(relaunched.records.firstOrNull())
        assertEquals(last, record.interrupted, "the movement the workout was cut short on")
        assertEquals(mapOf(first to 6), record.probes, "the number the probe showed")
        assertEquals(mapOf(first to 1), record.raisedSteps, "the steps added for next time")
        assertEquals(240, record.warmupSec, "the warm-up as it ran")
    }

    @Test
    fun aFreshSnapshotIsLeftAloneToBeResumed() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now()))

        val relaunched = makeStore()
        assertFalse(relaunched.settleAbandonedWorkout(), "inside the window it is the same occasion — offer it back")
        assertNotNull(relaunched.pendingWorkout)
        assertTrue(relaunched.records.isEmpty())
    }

    /** The guards that make the numbers meaningful: a snapshot describing a
     *  plan the engine would no longer hand out has nothing honest to record. */
    @Test
    fun aSnapshotOfADifferentPlanIsDroppedRatherThanRecorded() {
        val store = makeStore()
        val last = Instant.now().minus(forgotten).minusSeconds(60)
        val snap = atFeedback(store, savedAt = last).copy(fingerprint = "not the plan on offer")
        store.saveWorkoutSnapshot(snap)

        val relaunched = makeStore()
        assertFalse(relaunched.settleAbandonedWorkout())
        assertTrue(relaunched.records.isEmpty(), "a plan nobody trained must not reach the journal")
        assertNull(relaunched.pendingWorkout, "and it must not linger either")
    }

    @Test
    fun aSnapshotWithoutProgressRecordsNothing() {
        val store = makeStore()
        val last = Instant.now().minus(forgotten).minusSeconds(60)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 0, setIndex = 0,
            workoutStart = last.minusSeconds(60), savedAt = last,
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)))

        val relaunched = makeStore()
        assertFalse(relaunched.settleAbandonedWorkout())
        assertTrue(relaunched.records.isEmpty())
    }

    /** `activate()` is the one entry point both a cold launch and a
     *  foreground run through, and the settlement has to happen there — and
     *  BEFORE the day re-anchors, or the decay measures a gap to a workout
     *  that had not been written yet. */
    @Test
    fun activateSettlesTheAbandonedWorkout() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now().minus(forgotten).minusSeconds(60)))

        val relaunched = makeStore()
        relaunched.activate()
        assertEquals(1, relaunched.records.size)
    }

    /**
     * `activate()` runs on EVERY foreground, and the workout flow is a screen
     * over one that stays alive underneath it — so a return to the app a day
     * into an idle session must not settle the workout out from under the
     * athlete still standing in it. The counter would advance, the rating
     * they then gave would fail `completeWorkout`'s replay guard, and the
     * session would stand recorded "on plan" with the honest answer dropped
     * in silence.
     *
     * Every other test here settles through a freshly built store — process
     * death only — so without this one the live-app case is green by omission.
     */
    @Test
    fun aWorkoutStillOnScreenIsNeverSettledUnderneathIt() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now().minus(forgotten).minusSeconds(60)))
        store.workoutFlowAppeared()

        store.activate()
        assertTrue(store.records.isEmpty(), "the flow owns this snapshot and will finish the workout itself")
        assertNotNull(store.pendingWorkout)
        assertEquals(0, store.engineState.counter, "advancing the counter is what silently invalidated the rating")

        // And once the flow is gone, the same snapshot settles as it should.
        store.workoutFlowDisappeared()
        store.activate()
        assertEquals(1, store.records.size)
    }

    // MARK: - The band where the athlete is asked

    /** Three hours is a long lunch, not a lost session. Past the occasion the
     *  card stops offering to carry on and starts ASKING — and nothing is
     *  written until the answer comes. */
    @Test
    fun pastTheOccasionTheWorkoutIsOfferedForAnAnswerAndNotRecorded() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now().minus(window).minusSeconds(60)))

        val relaunched = makeStore()
        assertNull(relaunched.resumableWorkout(), "not the same occasion any more")
        assertNotNull(relaunched.unfinishedWorkoutAwaitingAnswer(),
                      "but not forgotten either — it is a question, not a verdict")
        relaunched.activate()
        assertTrue(relaunched.records.isEmpty(), "recording it unasked is exactly what the owner removed")
        assertNotNull(relaunched.pendingWorkout)
    }

    /** The store deliberately has NO way to record a workout in this band:
     *  answering the card opens the flow on its rating screen, and the athlete
     *  says how it went themselves. The only thing decided for them is a
     *  workout nobody came back to for twelve hours. */
    @Test
    fun nothingInThisBandCanBeRecordedWithoutTheAthlete() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now().minus(window).minusSeconds(60)))

        val relaunched = makeStore()
        // Every automatic path there is, run twice for good measure.
        relaunched.activate()
        assertFalse(relaunched.settleAbandonedWorkout())
        relaunched.activate()
        assertTrue(relaunched.records.isEmpty())
        assertNotNull(relaunched.unfinishedWorkoutAwaitingAnswer(), "the question has to still be there to be answered")
    }

    /** Twelve hours is the line, and it is elapsed time rather than the
     *  midnight `trainingDays` counts: a session left at 23:30 and opened at
     *  00:30 is one midnight and one hour, and one hour is not "forgotten". */
    @Test
    fun theQuestionStandsUntilTheWorkoutIsForgotten() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now().minus(forgotten).plusSeconds(60)))

        val relaunched = makeStore()
        assertNotNull(relaunched.unfinishedWorkoutAwaitingAnswer(), "a minute short of the threshold is still a question")
        assertFalse(relaunched.settleAbandonedWorkout())
        assertTrue(relaunched.records.isEmpty())
    }

    /** Once it IS forgotten, the question is gone — the card must not offer an
     *  answer to something already recorded. */
    @Test
    fun aForgottenWorkoutIsNoLongerOfferedAsAQuestion() {
        val store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(store, savedAt = Instant.now().minus(forgotten).minusSeconds(60)))

        val relaunched = makeStore()
        assertNull(relaunched.unfinishedWorkoutAwaitingAnswer())
        assertTrue(relaunched.settleAbandonedWorkout())
    }

    // MARK: - Time charged to an absence

    /** An absence the process lived through (locked overnight, not killed):
     *  charged from the moment of leaving, a running rest still owed, and the
     *  stamp spent once. */
    @Test
    fun aLivedThroughAbsenceIsChargedOnceFromTheMomentOfLeaving() {
        // Swift's `Date(timeIntervalSinceReferenceDate: 800_000_000)`.
        val t = Instant.ofEpochSecond(978_307_200L + 800_000_000L)
        val absence = Absence()
        assertEquals(0, absence.comeBack(now = t), "nothing stamped, nothing owed")

        absence.leave(now = t, restEndDate = null)
        absence.leave(now = t.plusSeconds(600), restEndDate = null)   // the first leaving wins
        assertEquals(11 * 3600, absence.comeBack(now = t.plusSeconds(11 * 3600)))
        assertEquals(0, absence.comeBack(now = t.plusSeconds(12 * 3600)), "spent")

        absence.leave(now = t, restEndDate = t.plusSeconds(90))
        assertEquals(0, absence.comeBack(now = t.plusSeconds(85)), "inside the rest")
        absence.leave(now = t, restEndDate = t.plusSeconds(90))
        assertEquals(2910, absence.comeBack(now = t.plusSeconds(3000)))
    }

    /** The rule the away time rests on: a rest running on schedule is
     *  training whether or not the process survived it. */
    @Test
    fun aScheduledRestIsTrainingEvenWhenTheProcessDies() {
        val restStart = Instant.now().minusSeconds(3600)
        val restEnd = restStart.plusSeconds(90)

        // Locked at the top of a 90 s rest, opened five seconds before its end:
        // the athlete was resting the whole time, and none of it is absence.
        assertEquals(0, SetFacts.awayGained(savedAt = restStart, restEndDate = restEnd, now = restStart.plusSeconds(85)))
        // Back long after it: only what is past the rest's end counts.
        assertEquals(2910, SetFacts.awayGained(savedAt = restStart, restEndDate = restEnd,
                                               now = restStart.plusSeconds(3000)))
        // Exactly at the end is still nothing owed.
        assertEquals(0, SetFacts.awayGained(savedAt = restStart, restEndDate = restEnd, now = restEnd))
    }

    /** Off a rest there is no end date to lean on, so the whole gap counts —
     *  the known floor of the rule, written down so a later change to it is a
     *  decision rather than a surprise. */
    @Test
    fun withoutARestTheWholeGapIsAbsence() {
        val saved = Instant.now().minusSeconds(600)
        val gained = SetFacts.awayGained(savedAt = saved, restEndDate = null, now = Instant.now())
        assertTrue(abs(gained - 600) <= 1, "expected 600 ± 1, got $gained")
        // A clock that moved backwards must not hand back a negative.
        assertEquals(0, SetFacts.awayGained(savedAt = Instant.now(), restEndDate = null,
                                            now = Instant.now().minusSeconds(500)))
    }

    // MARK: - What an interruption amounts to

    /** The summary of a finished hold is the same fact as the rest after a
     *  last set — every set is behind. Catalogued as unfinished, it would hand
     *  a fully performed movement to the engine as a skip and erase the
     *  seconds that screen exists to confirm. */
    @Test
    fun aFinishedMovementOnItsSummaryIsNotASkip() {
        val exercises = makeStore().nextSession.exercises
        val settled = SetFacts.settlement(exercises,
                                          exIndex = 0,
                                          setsBehind = exercises[0].sets,
                                          currentIsDone = true,
                                          alreadySkipped = emptyMap())
        assertFalse(exercises[0].pattern in settled.skipped, "every set is done — it was trained")
        assertNull(settled.interrupted)
        assertEquals(0, settled.setsSkipped[exercises[0].pattern] ?: 0)
    }

    /** Both numbers come off disk, and a negative index must not trap inside
     *  `activate()` on every launch: it reads as the first exercise. */
    @Test
    fun aNegativeSnapshotIndexSettlesLikeTheFirstExercise() {
        val exercises = makeStore().nextSession.exercises
        for (done in listOf(false, true)) {
            val clamped = SetFacts.settlement(exercises, exIndex = -3, setsBehind = -5,
                                              currentIsDone = done, alreadySkipped = emptyMap())
            val first = SetFacts.settlement(exercises, exIndex = 0, setsBehind = 0,
                                            currentIsDone = done, alreadySkipped = emptyMap())
            assertEquals(first, clamped)
        }
    }

    /** "Finish now" promises to keep what you have done. A movement with
     *  enough sets behind keeps its numbers, and the sets never reached travel
     *  as skipped SETS — the statement an in-workout skip makes. */
    @Test
    fun aMovementWithEnoughSetsBehindKeepsItsNumbers() {
        // Built rather than borrowed from session 1: the rule is about the
        // arithmetic of sets, and a plan that happens to ship three of them
        // would make this test pass or fail for an unrelated reason.
        val deep = SessionExercise(pattern = Pattern.pushH, name = "Push-up", variation = 1,
                                   unit = LoadUnit.reps, load = 8, perSide = false, sets = 4,
                                   restSetSec = 60, restExerciseSec = 90,
                                   loads = null, probe = null)
        val settled = SetFacts.settlement(listOf(deep),
                                          exIndex = 0,
                                          setsBehind = 2,
                                          currentIsDone = false,
                                          alreadySkipped = emptyMap())
        assertFalse(Pattern.pushH in settled.skipped, "two sets performed is a trained movement, not a skip")
        assertNull(settled.interrupted)
        assertEquals(2, settled.setsSkipped[Pattern.pushH], "the two sets never reached are the ones taken off")
    }

    /** Below the floor there is no movement to keep, and it is named as
     *  unfinished rather than quietly counted. */
    @Test
    fun aSingleSetIntoAMovementLeavesItUnfinished() {
        val exercises = makeStore().nextSession.exercises
        val settled = SetFacts.settlement(exercises,
                                          exIndex = 1,
                                          setsBehind = 1,
                                          currentIsDone = false,
                                          alreadySkipped = emptyMap())
        assertEquals(exercises[1].pattern, settled.interrupted)
        assertTrue(exercises[1].pattern in settled.skipped,
                   "to the engine it is still a skip — only the label differs")
    }

    @Test
    fun movementsNeverReachedAreSkips() {
        val exercises = makeStore().nextSession.exercises
        val settled = SetFacts.settlement(exercises,
                                          exIndex = 1,
                                          setsBehind = 0,
                                          currentIsDone = false,
                                          alreadySkipped = emptyMap())
        for (ex in exercises.drop(1)) {
            assertTrue(ex.pattern in settled.skipped, "${ex.pattern} was never reached")
        }
        assertFalse(exercises[0].pattern in settled.skipped, "the one behind us was trained")
    }

    /** The journal has to be able to say which movement was left half-done —
     *  "not finished" and "skipped" are different facts to a person even
     *  though the engine freezes the ladder either way. */
    @Test
    fun theJournalNamesTheUnfinishedMovement() {
        val store = makeStore()
        val session = store.nextSession
        store.completeWorkout(session = session, result = FeedbackResult.plan,
                              skipped = setOf(session.exercises[2].pattern),
                              interrupted = session.exercises[2].pattern)
        val record = assertNotNull(store.records.firstOrNull())
        assertEquals(session.exercises[2].pattern, record.interrupted)
    }

    @Test
    fun theUnfinishedMovementSurvivesARelaunch() {
        val store = makeStore()
        val session = store.nextSession
        store.completeWorkout(session = session, result = FeedbackResult.plan,
                              skipped = setOf(session.exercises[2].pattern),
                              interrupted = session.exercises[2].pattern)

        val relaunched = makeStore()
        val record = assertNotNull(relaunched.records.firstOrNull())
        assertEquals(session.exercises[2].pattern, record.interrupted,
                     "a persisted field that does not come back is not persisted")
    }
}
