//
//  Port of ios/DredfitTests/WorkoutSnapshotTests.swift: the workout in
//  progress as the store keeps it — what survives a relaunch, which snapshot
//  is still offered back, and what may never take the journal down with it.
//
//  Not ported: `testSnapshotWritesDoNotTouchTheWidget` — its subject is the
//  widget snapshot file (`widgetSnapshotURL`), and widgets arrive in phase 3.
//
//  The state file here is compact JSON (`AppData.encode`), where iOS writes
//  it pretty-printed: `testASnapshotWithTheCancelledKeyStillResumes` splices
//  the cancelled key into the compact form, and checks that the splice took.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.clearWorkoutSnapshot
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.store.nextSession
import com.dredfit.store.resumableWorkout
import com.dredfit.store.saveWorkoutSnapshot
import com.dredfit.workout.WorkoutSessionStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.nio.file.Files
import java.time.Instant
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSnapshotTest : AppStoreTestCase() {

    /** A mid-workout snapshot the way the flow would write it: real progress,
     *  and a fingerprint of the session the store would offer. */
    private fun makeSnapshot(store: AppStore, sessionNumber: Int = 1,
                             savedAt: Instant = Instant.now()): WorkoutSnapshot =
        WorkoutSnapshot(sessionNumber = sessionNumber,
                        exIndex = 4, setIndex = 1,
                        restEndDate = null, restTotalSec = null,
                        setActuals = mapOf(Pattern.pushH to listOf(12, 9)), skipped = setOf(Pattern.coreAntiExt),
                        workoutStart = savedAt.minusSeconds(20 * 60),
                        savedAt = savedAt,
                        fingerprint = WorkoutSnapshot.fingerprint(store.nextSession))

    // MARK: - The point of the feature

    @Test
    fun snapshotSurvivesRelaunch() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))

        val relaunched = makeStore()
        val resumed = relaunched.resumableWorkout()
        assertNotNull(resumed, "a fresh snapshot must be offered after a cold start")
        assertEquals(4, resumed.exIndex)
        assertEquals(mapOf(Pattern.pushH to listOf(12, 9)), resumed.facts,
                     "which set ran at which number is the progress, not just the last one")
        assertEquals(setOf(Pattern.coreAntiExt), resumed.skipped)
    }

    /** A snapshot written before a fact belonged to its own set carried one
     *  number for the whole exercise. That number was in force from the first
     *  set on, which is exactly what a one-element array says — and it must
     *  resume rather than take the file down. */
    @Test
    fun aSnapshotFromTheOneNumberShapeStillResumes() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 4, setIndex = 1,
            actuals = mapOf(Pattern.pushH to 9),
            workoutStart = Instant.now().minusSeconds(20 * 60), savedAt = Instant.now(),
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)))

        val resumed = makeStore().resumableWorkout()
        assertNotNull(resumed, "a lone old-shape fact is still progress worth offering")
        assertEquals(mapOf(Pattern.pushH to listOf(9)), resumed.facts)
    }

    @Test
    fun clearedSnapshotStaysClearedAcrossRelaunch() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))
        store.clearWorkoutSnapshot()

        assertNull(makeStore().resumableWorkout(), "a discarded workout must not come back")
    }

    // MARK: - Validity gates

    @Test
    fun staleSnapshotIsNotOffered() {
        val store = makeStore()
        val saved = Instant.now()
        store.saveWorkoutSnapshot(makeSnapshot(store, savedAt = saved))

        val justInside = saved.plus(WorkoutSessionStore.resumeWindow).minusSeconds(60)
        assertNotNull(store.resumableWorkout(now = justInside))

        val justPast = saved.plus(WorkoutSessionStore.resumeWindow).plusSeconds(60)
        assertNull(store.resumableWorkout(now = justPast), "the resume offer must expire with the occasion")
    }

    @Test
    fun completingTheWorkoutClearsTheSnapshot() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        assertNull(store.pendingWorkout, "completion must clear the snapshot")
        assertNull(makeStore().pendingWorkout, "the cleared state must be the persisted one")
    }

    /** A snapshot whose session no longer matches the engine (feedback was
     *  applied, progress was reset) must never resume into the wrong workout. */
    @Test
    fun mismatchedSessionNumberIsNotOffered() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store, sessionNumber = 5))
        assertNull(store.resumableWorkout(), "session 5 does not belong to a counter at 0")
    }

    @Test
    fun barToggleInvalidatesTheSnapshot() {
        val store = makeStore()
        // Session 2 (odd counter) is the one the bar module rewrites.
        val yesterday = ZonedDateTime.now().minusDays(1).toInstant()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = yesterday)
        store.saveWorkoutSnapshot(makeSnapshot(store, sessionNumber = 2))
        assertNotNull(store.resumableWorkout(), "sanity: the snapshot is valid as saved")

        store.setHasBar(true)
        assertNull(store.resumableWorkout(),
                   "the bar toggle regenerated session 2 — the old snapshot must not resume into it")
    }

    @Test
    fun acceptedComebackInvalidatesTheSnapshot() {
        val store = makeStore()
        val longAgo = ZonedDateTime.now().minusDays(30).toInstant()
        // A real level to drop from, recorded a month back.
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.more, date = longAgo)
        store.saveWorkoutSnapshot(makeSnapshot(store, sessionNumber = 2))
        assertNotNull(store.resumableWorkout(), "sanity: the snapshot is valid as saved")

        store.acceptComeback()
        assertNull(store.resumableWorkout(),
                   "a comeback regenerates the plan — the old snapshot must not resume into it")
    }

    @Test
    fun snapshotWithNoProgressIsNotOffered() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 0, setIndex = 0,
            workoutStart = Instant.now(), savedAt = Instant.now(),
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)))
        assertNull(store.resumableWorkout(), "there is nothing to continue — the card must not show")
    }

    @Test
    fun firstSetRestSnapshotIsOffered() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 0, setIndex = 0,
            restEndDate = Instant.now().plusSeconds(45), restTotalSec = 60,
            workoutStart = Instant.now().minusSeconds(5 * 60), savedAt = Instant.now(),
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)))
        assertNotNull(store.resumableWorkout(), "a set was completed — this interruption is worth offering back")
    }

    @Test
    fun feedbackSnapshotIsOffered() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 5, setIndex = 2,
            actuals = mapOf(Pattern.pushH to 9),
            workoutStart = Instant.now().minusSeconds(30 * 60), savedAt = Instant.now(),
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession),
            atFeedback = true))
        val resumed = store.resumableWorkout()
        assertNotNull(resumed)
        assertEquals(true, resumed.atFeedback,
                     "the restore path needs the flag to land on the rating, not the last set")
    }

    /** A report of pain is progress worth offering back on its own — the
     *  workout must not come back with the report lost. */
    @Test
    fun discomfortAloneMakesASnapshotResumable() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 0, setIndex = 0,
            discomfort = setOf(Pattern.calf),
            workoutStart = Instant.now().minusSeconds(5 * 60), savedAt = Instant.now(),
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)))
        val resumed = store.resumableWorkout()
        assertNotNull(resumed, "something was reported — the card must show")
        assertEquals(setOf(Pattern.calf), resumed.discomfort)
    }

    /** A snapshot written before the field existed still decodes. */
    @Test
    fun snapshotWithoutTheDiscomfortFieldStillResumes() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))
        val raw = Files.readString(tempPath)
        assertFalse(raw.contains("\"discomfort\""), "an empty report must not be written at all")
        val reloaded = makeStore()
        assertNotNull(reloaded.resumableWorkout())
        assertNull(reloaded.resumableWorkout()?.discomfort)
    }

    /**
     * The three fields the hands-free hold wave added, round-tripped — the
     * declared time, the estimate marks and the landing on the summary.
     *
     * Nothing gated them when they shipped, which is exactly the class of
     * hole this file exists to close: they are optional, so a decode could
     * not fail, and a silent null after a relaunch would put the plan's
     * number back on the clock without saying so.
     */
    @Test
    fun theHoldFieldsSurviveARelaunch() {
        val store = makeStore()
        val snapshot = makeSnapshot(store).copy(holdDeclaredSec = 60, approxSets = listOf(0, 2),
                                                atExerciseSummary = true)
        store.saveWorkoutSnapshot(snapshot)

        val resumed = assertNotNull(makeStore().resumableWorkout())
        assertEquals(60, resumed.holdDeclaredSec, "a declared time must not be forgotten across a kill")
        assertEquals(setOf(0, 2), resumed.approximateSets)
        assertEquals(true, resumed.atExerciseSummary)
    }

    /** …and the estimate marks are held inside what an exercise can hold,
     *  like everything else that comes back off disk with no decoder of its
     *  own. */
    @Test
    fun estimateMarksOffDiskAreBounded() {
        val store = makeStore()
        val snapshot = makeSnapshot(store).copy(approxSets = listOf(-1, 0, 99))
        store.saveWorkoutSnapshot(snapshot)

        val resumed = assertNotNull(makeStore().resumableWorkout())
        assertEquals(setOf(0), resumed.approximateSets,
                     "an index no exercise can have is not a mark about anything")
    }

    /** A snapshot written BEFORE the wave still decodes and resumes: the three
     *  keys are simply absent, and absent must mean "nothing was declared,
     *  nothing was estimated, and the work screen is where this lands". */
    @Test
    fun aSnapshotWithoutTheHoldFieldsStillResumes() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))
        val raw = Files.readString(tempPath)
        for (key in listOf("holdDeclaredSec", "approxSets", "atExerciseSummary")) {
            assertFalse(raw.contains("\"$key\""), "$key must not be written when there is nothing to say")
        }
        val resumed = assertNotNull(makeStore().resumableWorkout())
        assertNull(resumed.holdDeclaredSec)
        assertNull(resumed.atExerciseSummary)
        assertTrue(resumed.approximateSets.isEmpty())
    }

    /** Re-marked from `testAPinAloneMakesASnapshotResumable`. The hold request
     *  is cancelled; a pain report is the remaining per-movement mark that is
     *  progress worth offering back on its own. */
    @Test
    fun aPainReportAloneMakesASnapshotResumable() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 0, setIndex = 0,
            discomfort = setOf(Pattern.squat),
            workoutStart = Instant.now().minusSeconds(5 * 60), savedAt = Instant.now(),
            fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)))
        val resumed = store.resumableWorkout()
        assertNotNull(resumed, "something was said — the card must show")
        assertEquals(setOf(Pattern.squat), resumed.discomfort)
    }

    /** A snapshot carrying the cancelled key still decodes: an unknown field
     *  is ignored, so a workout interrupted before the update comes back. */
    @Test
    fun aSnapshotWithTheCancelledKeyStillResumes() {
        val store = makeStore()
        val fingerprint = WorkoutSnapshot.fingerprint(store.nextSession)
        store.saveWorkoutSnapshot(makeSnapshot(store))
        var raw = Files.readString(tempPath)
        assertFalse(raw.contains("\"pinned\""), "the cancelled key is never written again")
        // Splice it back in the way an older build would have written it.
        val key = "\"fingerprint\":\"$fingerprint\""
        assertTrue(raw.contains(key), "the premise: the splice has a place to go")
        raw = raw.replace(key, "\"pinned\":[\"squat\"],$key")
        Files.writeString(tempPath, raw)
        val reloaded = makeStore()
        assertNotNull(reloaded.resumableWorkout(), "an unknown key must not take the snapshot down")
    }

    @Test
    fun snapshotWithoutFingerprintIsNotOffered() {
        val store = makeStore()
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber = 1, exIndex = 4, setIndex = 1,
            actuals = mapOf(Pattern.pushH to 9),
            workoutStart = Instant.now(), savedAt = Instant.now()))
        assertNull(store.resumableWorkout(), "no fingerprint means no proof the session still matches")
    }

    @Test
    fun resetProgressDropsTheSnapshot() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))
        store.resetProgress()
        assertNull(store.pendingWorkout, "restarted session numbers must not collide with an old snapshot")
    }

    @Test
    fun importedBackupCarriesNoSnapshot() {
        val store = makeStore()
        store.saveWorkoutSnapshot(makeSnapshot(store))
        val backup = store.exportBackup()

        store.importBackup(backup)
        assertNull(store.pendingWorkout)
    }

    // MARK: - Robustness

    /** A snapshot written by a newer version (or plain corruption) must
     *  degrade to "nothing to resume" — never quarantine the whole journal. */
    @Test
    fun corruptSnapshotDoesNotCostTheJournal() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        val json = Json.parseToJsonElement(Files.readString(tempPath)).jsonObject
        val corrupted = JsonObject(json + ("pendingWorkout" to JsonObject(mapOf("unexpected" to JsonPrimitive("shape")))))
        Files.writeString(tempPath, corrupted.toString())

        val reloaded = makeStore()
        assertEquals(1, reloaded.records.size, "the journal must survive an unreadable snapshot")
        assertNull(reloaded.pendingWorkout)
    }
}
