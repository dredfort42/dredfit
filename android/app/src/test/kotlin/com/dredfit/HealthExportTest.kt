//
//  Port of ios/DredfitTests/HealthExportTests.swift: the store's backfill —
//  one flag per confirmed save, journal order, stopping at the first failure,
//  never a duplicate — and the switch that follows the permission. Every
//  Swift test is ported; the extensions are HealthExportTestEnergy and
//  HealthExportTestBlocks. The backup is bytes on this side. Two Android
//  tests at the end: a grant Health Connect cannot answer for, and the
//  backfill question held by the store.
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.SwiftJson
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.backfillHealth
import com.dredfit.store.disableHealth
import com.dredfit.store.enableHealth
import com.dredfit.store.exportBackup
import com.dredfit.store.healthBackfillCount
import com.dredfit.store.importBackup
import com.dredfit.store.nextSession
import com.dredfit.store.skipHealthBackfill
import com.dredfit.store.turnHealthOn
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Test
import kotlin.math.floor
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HealthExportTest : AppStoreTestCase() {

    /** Runs `backfillHealth` beside the test and returns once the spy's gated
     *  save is actually in flight (suspended inside the gate). */
    private suspend fun CoroutineScope.startBackfillAndWaitForGatedSave(store: AppStore, spy: HealthSpy): Job {
        val backfill = launch { store.backfillHealth() }
        var spins = 0
        while (spy.callCount < (spy.gateAtCall ?: 0) && spins < 10_000) {
            spins += 1
            yield()
        }
        assertEquals(spy.gateAtCall, spy.callCount, "the gated save must be in flight")
        return backfill
    }

    private fun seconds(span: SavedWorkout): Double = com.dredfit.workout.Countdown.seconds(span.start, span.end)

    /** The estimate reserves the ENGINE's warm-up and cool-down: a copy of
     *  either block's length here would disagree with the engine and fail. */
    @Test
    fun anEstimatedDurationUsesTheEngineSBlockLengths() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()

        val session = store.nextSession
        store.completeWorkout(session = session, result = FeedbackResult.plan)   // no durationSec
        store.healthExportJob?.join()

        assertEquals(1, spy.saved.size, "the workout was exported")
        var work = 0.0
        for (ex in session.exercises) {
            val sides = if (ex.perSide) 2.0 else 1.0
            val perSet = if (ex.unit == LoadUnit.reps) ex.load * sides * 2.5 else ex.load * sides
            work += ex.sets * perSet + (ex.sets - 1) * ex.restSetSec.toDouble() + ex.restExerciseSec
        }
        val blocks = ((EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60).toDouble()
        assertEquals(floor(work + blocks), seconds(spy.saved[0]), 1.0,
                     "the estimate must reserve the engine's own warm-up and cool-down")
    }

    @Test
    fun healthFailedSaveKeepsWorkoutRetriable() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        spy.allFail = true
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 30 * 60)
        store.healthExportJob?.join()
        assertEquals(1, spy.saved.size, "the save was attempted")
        assertEquals(1, store.healthBackfillCount, "a failed save must not mark the workout exported")
        spy.allFail = false
        store.backfillHealth()
        assertEquals(0, store.healthBackfillCount, "the retry exported the missed workout")
        assertEquals(2, spy.saved.size)
    }

    /** A failed export of workout N followed by a successful N+1 must not
     *  leave N stuck with no chance to retry. */
    @Test
    fun healthLaterSuccessDoesNotLoseEarlierFailedExport() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()

        spy.allFail = true
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.healthExportJob?.join()
        assertEquals(1, store.healthBackfillCount, "workout 1 stays pending")

        spy.allFail = false
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))
        store.healthExportJob?.join()
        assertEquals(0, store.healthBackfillCount, "the next workout's export must retry the failed one first")
        assertEquals(3, spy.saved.size, "one failed attempt plus both real exports")
        assertEquals(date(2026, 7, 14), spy.saved[1].end, "the older workout exports before the newer one")
        assertEquals(date(2026, 7, 16), spy.saved[2].end)
    }

    @Test
    fun resetProgressKeepsRecordIdentityAndHealthStateSound() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 10))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 12))
        store.enableHealth()
        store.backfillHealth()
        assertEquals(2, spy.saved.size)

        store.resetProgress()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))
        assertEquals(1, store.records.lastOrNull()?.sessionNumber, "after the reset the journal reuses session numbers")
        assertEquals(store.records.size, store.records.map { it.id }.toSet().size, "record ids must stay unique across a reset")

        store.healthExportJob?.join()
        assertEquals(0, store.healthBackfillCount)
        assertEquals(3, spy.saved.size, "only the new workout exports — no duplicates")
        store.skipHealthBackfill()
        store.backfillHealth()
        assertEquals(3, spy.saved.size, "skip must never re-export handled workouts")
    }

    @Test
    fun healthBackfillStopsAtFirstFailure() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        for (day in 14..16) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, day))
        }
        store.enableHealth()

        spy.failFromCall = 2               // session 1 exports, session 2 fails
        store.backfillHealth()
        assertEquals(2, store.healthBackfillCount, "backfill must stop at the first failure, not mark the tail exported")

        spy.failFromCall = null            // resume
        store.backfillHealth()
        assertEquals(0, store.healthBackfillCount, "the resumed backfill exports the rest")
    }

    /** Replacing the journal while a save is suspended must not flag, by a
     *  stale index, a record that was never exported. */
    @Test
    fun importDuringInFlightBackfillDoesNotMisflagByStaleIndex() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        for (day in listOf(10, 12, 14, 16)) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, day))
        }
        store.enableHealth()

        // A donor backup: three records, Health never enabled there.
        val donor = makeStore(path = tempDir.resolve("donor.json"))
        for (day in 1..3) {
            donor.completeWorkout(session = donor.nextSession, result = FeedbackResult.plan, date = date(2026, 7, day))
        }
        val backup = donor.exportBackup()

        val gate = CompletableDeferred<Unit>()
        spy.gate = gate
        spy.gateAtCall = 3
        val backfill = startBackfillAndWaitForGatedSave(store, spy)
        store.importBackup(backup)
        gate.complete(Unit)
        backfill.join()

        assertEquals(3, store.records.size, "the imported journal must be intact")
        assertEquals(3, spy.saved.size, "no further exports against the replaced journal")
        assertNotEquals(true, store.records.lastOrNull()?.healthExported, "a record that was never saved must not be flagged exported")
        assertEquals(3, store.healthBackfillCount, "every imported workout stays pending for a real export")
    }

    @Test
    fun disablingHealthStopsAnInFlightBackfill() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        for (day in listOf(10, 12, 14)) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, day))
        }
        store.enableHealth()

        val gate = CompletableDeferred<Unit>()
        spy.gate = gate
        spy.gateAtCall = 2
        val backfill = startBackfillAndWaitForGatedSave(store, spy)
        store.disableHealth()
        gate.complete(Unit)
        backfill.join()

        // The save in flight lands — it did reach Health Connect — but the
        // third record must not follow it after the switch went off.
        assertEquals(2, spy.saved.size, "no exports after the toggle went off")
        assertEquals(1, store.healthBackfillCount, "the tail stays pending for a re-enable")
    }

    @Test
    fun negativeDurationDoesNotPoisonHealthBackfill() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = -20 * 60,
                              date = date(2026, 7, 14))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))
        store.enableHealth()
        store.backfillHealth()

        assertEquals(0, store.healthBackfillCount, "both records must export")
        assertTrue(spy.saved.all { it.start < it.end }, "every exported interval must move forward")
    }

    /** An older backup of the SAME journal (no mark) must not move the mark
     *  backwards — re-enabling would write workouts already there again. */
    @Test
    fun importKeepsHealthMarkMonotonic() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.more, date = date(2026, 7, 16))
        store.enableHealth()
        store.backfillHealth()
        assertEquals(0, store.healthBackfillCount, "both workouts start out exported")

        val t1 = SwiftJson.sinceReference(date(2026, 7, 14))
        val t2 = SwiftJson.sinceReference(date(2026, 7, 16))
        val old = """
            {"engineState":{"counter":2,
              "levels":["squat",2,"push_h",2,"hinge",2,"pull",4,"push_v",2,"lunge",2,
                        "core_anti_ext",1,"core_rot",1,"calf",1],
              "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                            "core_anti_ext",0,"core_rot",0,"calf",0]},
             "records":[
               {"sessionNumber":1,"date":$t1,"result":"plan","totalLevelAfter":12},
               {"sessionNumber":2,"date":$t2,"result":"more","totalLevelAfter":18}],
             "settings":{"restWeekdays":[1],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        store.importBackup(old.toByteArray())

        assertEquals(0, store.healthBackfillCount, "an old backup must not reset the mark and re-export handled workouts")
    }

    /** An unrelated journal must not inherit this device's mark (#103). */
    @Test
    fun unrelatedImportDoesNotInheritTheHealthMark() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))
        store.enableHealth()
        store.backfillHealth()
        assertEquals(0, store.healthBackfillCount, "this journal starts fully exported")

        val donor = makeStore(path = tempDir.resolve("foreign.json"))
        donor.completeWorkout(session = donor.nextSession, result = FeedbackResult.plan, date = date(2026, 6, 1))
        donor.completeWorkout(session = donor.nextSession, result = FeedbackResult.plan, date = date(2026, 6, 3))

        store.importBackup(donor.exportBackup())
        assertEquals(2, store.healthBackfillCount, "no foreign workout may be silently excluded from Health Connect")
        store.enableHealth()
        store.backfillHealth()
        assertEquals(0, store.healthBackfillCount)
        assertEquals(4, spy.saved.size, "both foreign workouts really export")
    }

    @Test
    fun unrelatedImportRespectsItsOwnFlags() = runHealth {
        val donorSpy = HealthSpy()
        val donor = makeStore(path = tempDir.resolve("flagged.json"), health = donorSpy)
        donor.completeWorkout(session = donor.nextSession, result = FeedbackResult.plan, date = date(2026, 6, 1))
        donor.enableHealth()
        donor.backfillHealth()
        donor.completeWorkout(session = donor.nextSession, result = FeedbackResult.plan, date = date(2026, 6, 3))
        donor.healthExportJob?.join()
        assertEquals(0, donor.healthBackfillCount, "the donor is fully exported")
        val backup = donor.exportBackup()

        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.importBackup(backup)
        assertEquals(0, store.healthBackfillCount, "the donor's own flags say everything is exported — believe them")
        store.backfillHealth()
        assertTrue(spy.saved.isEmpty(), "nothing may re-export on this device")
    }

    @Test
    fun resetThenReloadDoesNotStampTheNewJournal() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 10))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 12))
        store.enableHealth()
        store.backfillHealth()
        store.disableHealth()

        store.resetProgress()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))
        assertEquals(1, store.records.lastOrNull()?.sessionNumber)
        assertNull(store.records.lastOrNull()?.healthExported, "not exported: Health is off")

        val reloaded = makeStore(health = HealthSpy())
        assertNull(reloaded.records.lastOrNull()?.healthExported, "a reload must not stamp the post-reset session 1 by the old mark")
        assertEquals(1, reloaded.healthBackfillCount, "the new workout stays visible to a future backfill")
    }

    @Test
    fun healthDenialLeavesToggleOff() = runHealth {
        val spy = HealthSpy()
        spy.grant = false
        val store = makeStore(health = spy)
        val granted = store.enableHealth()
        assertFalse(granted)
        assertFalse(store.settings.healthEnabled, "denial must leave the toggle off")
    }

    /** A write taken back in Health Connect turns the switch off on the next
     *  return; one still granted leaves it alone. On Android this is also the
     *  re-check after the system's own restore onto a new phone. */
    @Test
    fun revokedShareTurnsTheToggleOffOnActivation() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.activate()
        assertTrue(store.settings.healthEnabled)
        spy.shareGranted = false
        store.activate()
        assertFalse(store.settings.healthEnabled, "the switch follows the permission")
    }

    @Test
    fun healthBackfillExportsOnceAndNeverDuplicates() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))

        val granted = store.enableHealth()
        assertTrue(granted)
        assertEquals(2, store.healthBackfillCount)
        store.backfillHealth()
        assertEquals(2, spy.saved.size, "the backfill must export both past workouts")
        assertEquals(0, store.healthBackfillCount)

        store.disableHealth()
        store.enableHealth()
        assertEquals(0, store.healthBackfillCount, "re-enabling must not duplicate")

        val last = spy.saved.last()
        assertEquals(date(2026, 7, 16), last.end)
        assertTrue(seconds(last) > 10 * 60)
    }

    @Test
    fun healthSkipBackfillMarksHistoryHandled() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.enableHealth()
        store.skipHealthBackfill()
        assertEquals(0, store.healthBackfillCount)
        assertTrue(spy.saved.isEmpty(), "\"only new ones\" must not export the past")

        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 40 * 60,
                              date = date(2026, 7, 16))
        store.healthExportJob?.join()
        assertEquals(1, spy.saved.size, "a completed workout must land in Health Connect")
        assertEquals(40.0 * 60, seconds(spy.saved[0]), 1.0, "the actual duration must be used")
    }

    /** The loop SELECTS an unexported record and FLAGS one by id; two records
     *  sharing an id sent every flag to the first, and the loop never ended.
     *  `failFromCall` is the fail-safe, not the subject. */
    @Test
    fun duplicateJournalIDsDoNotLoopTheBackfill() = runHealth {
        val spy = HealthSpy()
        spy.failFromCall = 5
        val store = makeStore(health = spy)
        val stamp = SwiftJson.swiftDate(date(2026, 7, 10))
        store.update(refreshWidget = false) {
            it.copy(records = listOf(WorkoutRecord(1, stamp, FeedbackResult.plan), WorkoutRecord(1, stamp, FeedbackResult.plan)))
        }
        assertEquals(store.records[0].id, store.records[1].id, "the fixture is only a fixture if the ids really collide")
        store.enableHealth()

        store.backfillHealth()

        assertEquals(2, spy.saved.size, "one export per record, and then it stops")
        assertEquals(0, store.healthBackfillCount, "both records end up flagged")
    }

    // MARK: - Android only

    /** On Android 10–13 the grants are read over IPC from another app; a
     *  Health Connect that cannot answer once has not taken anything back,
     *  and the switch stays on. A definite "no" still turns it off. */
    @Test
    fun aGrantHealthConnectCannotAnswerForLeavesTheSwitchOn() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        spy.shareGranted = null
        store.activate()
        assertTrue(store.settings.healthEnabled, "no answer is not a refusal")
        spy.shareGranted = false
        store.activate()
        assertFalse(store.settings.healthEnabled)
    }

    /** The question after the switch went on lives in the store, so a screen
     *  rebuilt while Health Connect's screen was up still asks it — and only
     *  when there is a past to add and the write was granted. */
    @Test
    fun turningHealthOnOffersThePastOnceAndOnlyWhenThereIsOne() = runHealth {
        val spy = HealthSpy()
        val empty = makeStore(path = tempDir.resolve("empty.json"), health = spy)
        empty.turnHealthOn {}
        assertFalse(empty.healthBackfillOffered, "nothing to add")

        val refused = HealthSpy().also { it.grant = false }
        val withHistory = makeStore(path = tempDir.resolve("refused.json"), health = refused)
        withHistory.completeWorkout(session = withHistory.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        withHistory.turnHealthOn {}
        assertFalse(withHistory.healthBackfillOffered, "refused: nothing is offered")

        val store = makeStore(health = spy)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        var answered: Boolean? = null
        store.turnHealthOn { answered = it }
        assertEquals(true, answered)
        assertTrue(store.healthBackfillOffered)
        assertTrue(spy.saved.isEmpty(), "offered, not written")
        store.offerHealthBackfill(false)
        assertFalse(store.healthBackfillOffered)
    }
}
