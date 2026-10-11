//
//  Health Connect for real, on the emulator's own (API 37): what the export
//  writes and how often, what the app reads back into Settings, what it
//  refuses to read, and the two Android-only doors — Health Connect missing,
//  and its privacy-policy link. Every permission is granted up front (the
//  shell's grant); the refusal and a partial grant are HealthDeniedTest's,
//  alone on a fresh install. No Swift twin: iOS's Health suites run against
//  a spy only, because HealthKit in a simulator hangs (#164).
//

package com.dredfit

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onNodeWithTag
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Power
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.anyIntent
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.espresso.intent.matcher.IntentMatchers.hasData
import androidx.test.espresso.intent.matcher.IntentMatchers.toPackage
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.dredfit.core.FeedbackResult
import com.dredfit.health.HealthConnectWriter
import com.dredfit.health.HealthPrivacyActivity
import com.dredfit.store.healthBackfillCount
import com.dredfit.store.nextSession
import com.dredfit.store.setBodyMass
import com.dredfit.store.startHealthBackfill
import kotlinx.coroutines.runBlocking
import org.hamcrest.Matchers.allOf
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.ZoneOffset

@RunWith(AndroidJUnit4::class)
class HealthConnectTest : HealthTestCase() {

    @Before
    fun grantEverythingAndStartClean() {
        grant(HealthConnectWriter.permissions + testPermissions)
        deleteOwnRecords()
    }

    @After
    fun leaveNothingBehind() {
        HealthConnectWriter.statusForTests = null
        deleteOwnRecords()
    }

    private fun turnOn() = onStore { update { it.copy(settings = it.settings.copy(healthEnabled = true)) } }

    private fun awaitExported() {
        assertTrue("the export never finished", awaitTrue(15_000) { readStore { healthBackfillCount == 0 } })
    }

    /** A finished workout reaches Health Connect as ONE calisthenics session
     *  and ONE active-calories record over the same minutes, both carrying the
     *  journal record's id; a second save of the same record — the flag lost
     *  after Health Connect took it — replaces them instead of adding copies. */
    @Test
    fun aFinishedWorkoutReachesHealthConnectOnceWithItsCalories() {
        launch(Seed.Clean, fast = false)
        turnOn()
        onStore { setBodyMass(80.0) }
        onStore { completeWorkout(session = nextSession, result = FeedbackResult.plan, durationSec = 35 * 60) }
        awaitExported()

        val record = readStore { records.last() }
        val session = own(ExerciseSessionRecord::class).single()
        assertEquals(record.id, session.metadata.clientRecordId)
        assertEquals(ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS, session.exerciseType)
        assertEquals(record.date.toEpochMilli(), session.endTime.toEpochMilli())
        assertEquals(record.date.minusSeconds(35 * 60L).toEpochMilli(), session.startTime.toEpochMilli())
        assertEquals(Metadata.RECORDING_METHOD_ACTIVELY_RECORDED, session.metadata.recordingMethod)

        val energy = own(ActiveCaloriesBurnedRecord::class).single()
        assertEquals(record.id, energy.metadata.clientRecordId)
        assertEquals("the model revision is the record's version", 1L, energy.metadata.clientRecordVersion)
        assertEquals(session.startTime, energy.startTime)
        assertEquals(session.endTime, energy.endTime)
        assertTrue("a bodyweight session's calories: ${energy.energy}", energy.energy.inKilocalories in 30.0..400.0)

        // The flag lost, the record exported again.
        onStore { update { st -> st.copy(records = st.records.map { it.copy(healthExported = null) }) } }
        onStore { startHealthBackfill() }
        awaitExported()
        assertEquals("a second save replaced the session", 1, own(ExerciseSessionRecord::class).size)
        assertEquals("and its calories", 1, own(ActiveCaloriesBurnedRecord::class).size)
    }

    /** A weigh-in logged in Health Connect is the weight Settings shows, with
     *  its origin — read on the return to the app, as on iOS. */
    @Test
    fun aWeightLoggedInHealthConnectReachesSettings() {
        val at = Instant.now().minusSeconds(60)
        runBlocking { client.insertRecords(listOf(WeightRecord(at, ZoneOffset.UTC, Mass.kilograms(72.5), Metadata.manualEntry()))) }
        launch(Seed.Clean, fast = false)
        turnOn()
        relaunchFromDisk()   // a return to the app reads the weight

        assertTrue("the weigh-in was adopted", awaitTrue(10_000) { readStore { settings.bodyMassKg == 72.5 } })
        assertTrue(readStore { settings.bodyMassFromHealth })
        tap(AX.settings)
        await("body-mass-row")
        // In the reader's unit: the suite runs in English, which ICU measures
        // in pounds (iOS's `.us`) — 72.5 kg is 159.8 lb.
        compose.onNodeWithTag("body-mass-value", useUnmergedTree = true).assertTextEquals("159.8 lb")
        compose.onNodeWithTag("body-mass-caption", useUnmergedTree = true).assertTextContains("From Health Connect, ", substring = true)
    }

    /** With no rate recorded, Health Connect's resting total answers anyway
     *  with one of its own making; the app reads none. A recorded rate is read
     *  over the very minutes asked for. */
    @Test
    fun restingEnergyIsReadOnlyWhereARateWasRecorded() {
        launch(Seed.Clean, fast = false)   // reads are allowed in the foreground
        val end = Instant.now()
        val start = end.minusSeconds(30 * 60)
        runBlocking {
            val invented = client.aggregate(androidx.health.connect.client.request.AggregateRequest(
                setOf(BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL),
                androidx.health.connect.client.time.TimeRangeFilter.between(start, end)))[BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL]
            assertNotNull("the premise: Health Connect answers with no rate recorded", invented)
            assertNull("no rate recorded, none read", app.health.restingKcal(start, end))

            client.insertRecords(listOf(BasalMetabolicRateRecord(end.minusSeconds(2 * 3600), ZoneOffset.UTC,
                                                                 Power.kilocaloriesPerDay(1440.0),
                                                                 Metadata.autoRecorded(Device(type = Device.TYPE_WATCH)))))
            val kcal = checkNotNull(app.health.restingKcal(start, end)) { "a recorded rate is read" }
            assertEquals("1440 kcal a day is a kcal a minute", 30.0, kcal, 0.5)
        }
    }

    /** The trap of the foreign sweep, on the real store: the app's own session
     *  is read back and is not another app's recording of it. */
    @Test
    fun ourOwnWorkoutIsNotAForeignOne() {
        launch(Seed.Clean, fast = false)
        val end = Instant.now().minusSeconds(60)
        runBlocking {
            assertTrue(app.health.saveWorkout(end.minusSeconds(30 * 60), end, null, "own-session"))
            assertEquals("the premise: the session is there", 1, own(ExerciseSessionRecord::class).size)
            assertEquals(emptyList<Any>(), app.health.foreignWorkoutIntervals(end.minusSeconds(3600), Instant.now()))
        }
    }

    /** The sweep finds a session that OVERLAPS the window, as HealthKit's
     *  predicate does — also one that began before it, which Health
     *  Connect's own time filter leaves out — and none that ended before.
     *  It reaches back a day and no further: a session begun earlier is not
     *  read at all. */
    @Test
    fun theSweepFindsEverySessionThatOverlapsTheWindow() {
        launch(Seed.Clean, fast = false)
        val now = Instant.now()
        runBlocking {
            assertTrue(app.health.saveWorkout(now.minusSeconds(40 * 60), now.minusSeconds(10 * 60), null, "began-before"))
            assertTrue(app.health.saveWorkout(now.minusSeconds(90 * 60), now.minusSeconds(60 * 60), null, "ended-before"))
            assertTrue(app.health.saveWorkout(now.minus(HealthConnectWriter.SESSION_LOOKBACK).minusSeconds(3600),
                                              now.minusSeconds(15 * 60), null, "began-past-the-reach"))
            val touching = checkNotNull(app.health.sessionsTouching(now.minusSeconds(20 * 60), now))
            assertEquals("the session that began before the window, alone",
                         listOf(now.minusSeconds(40 * 60).toEpochMilli()), touching.map { it.start.toEpochMilli() })
            assertEquals(app.packageName, touching.single().packageName)
        }
    }

    /** The switch on a phone that allows everything: Health Connect has
     *  nothing left to ask, the switch stays on, and the history is offered
     *  once — "Add all" writes it. */
    @Test
    fun theSwitchTurnsOnAndOffersThePast() {
        launch(Seed.Session2, fast = false)
        tap(AX.settings)
        tapOnce("health-toggle")
        await("health-backfill-all", timeoutMs = 15_000)
        tapOnce("health-backfill-all")
        awaitExported()
        assertTrue(readStore { settings.healthEnabled })
        assertEquals("yesterday's workout went out", 1, own(ExerciseSessionRecord::class).size)
        await("body-mass-row")
        await("watch-records-toggle")
    }

    /** Android 10–13 without Health Connect: the group offers to install it
     *  from Google Play (Google's documented link), and nothing else. Without
     *  Health Connect at all (a work profile), there is no group. */
    @Test
    fun withoutHealthConnectTheGroupOffersItOrIsNotThere() {
        HealthConnectWriter.statusForTests = HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED
        launch(Seed.Clean, fast = false)
        tap(AX.settings)
        await("health-install")
        assertFalse(exists("health-toggle"))
        compose.onNodeWithTag("health-install").assertTextContains("Install Health Connect")
        Intents.init()
        try {
            intending(anyIntent()).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            tapOnce("health-install")
            intended(allOf(hasAction(Intent.ACTION_VIEW), hasData(HealthConnectWriter.INSTALL_LINK),
                           toPackage("com.android.vending")))
        } finally {
            Intents.release()
        }

        HealthConnectWriter.statusForTests = HealthConnectClient.SDK_UNAVAILABLE
        relaunchFromDisk()
        tap(AX.settings)
        await("settings-backup")
        assertFalse("no group at all", exists("settings-health"))
    }

    /** Both doors Health Connect opens the privacy policy through lead to the
     *  one activity, and it shows the policy. */
    @Test
    fun thePrivacyPolicyLinkOpensThePolicy() {
        val pm = app.packageManager
        val rationale = pm.queryIntentActivities(
            Intent("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE").setPackage(app.packageName), 0).single()
        assertEquals(HealthPrivacyActivity::class.java.name, rationale.activityInfo.name)
        val usage = pm.queryIntentActivities(
            Intent("android.intent.action.VIEW_PERMISSION_USAGE").addCategory("android.intent.category.HEALTH_PERMISSIONS")
                .setPackage(app.packageName), 0).single()
        assertEquals(HealthPrivacyActivity::class.java.name, usage.activityInfo.targetActivity)
        assertEquals("only the system may open it", "android.permission.START_VIEW_PERMISSION_USAGE", usage.activityInfo.permission)

        launch(Seed.Clean, fast = false)
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_VIEW)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            // As Health Connect sends it: resolved, then aimed at the
            // component (the filter carries no DEFAULT category, as in
            // Google's own manifest, so a bare implicit start finds nothing).
            app.startActivity(Intent("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")
                                  .setClassName(app.packageName, rationale.activityInfo.name)
                                  .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue("the policy was opened", awaitTrue(10_000) {
                Intents.getIntents().any { it.action == Intent.ACTION_VIEW && it.dataString == "https://dredfit.com/privacy.html" }
            })
        } finally {
            Intents.release()
        }
    }
}
