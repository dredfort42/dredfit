//
//  Health Connect against permissions never granted, through its own
//  permission screen (API 37): its privacy-policy link opens the policy;
//  "Don't allow" leaves the switch off; a grant of the workout write alone
//  saves the workout and drops its calories, as HealthKit's per-type answers
//  do on iOS; "Allow" turns the switch on.
//
//  ONE method, in order, because the order is the subject: Health Connect
//  stops showing its screen after enough refusals, and a revoke would kill
//  the process the instrumentation runs in. RUNS ALONE, on a fresh install
//  (uninstall first — a connected run reinstalls over an app that is there):
//
//    adb uninstall app.dredfit
//    ./gradlew :app:connectedDebugAndroidTest \
//      -Pandroid.testInstrumentationRunnerArguments.class=com.dredfit.HealthDeniedTest \
//      -Pandroid.testInstrumentationRunnerArguments.notAnnotation=org.junit.Ignore
//

package com.dredfit

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.text.Spanned
import android.text.style.ClickableSpan
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.onNodeWithTag
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import com.dredfit.core.FeedbackResult
import com.dredfit.health.HealthConnectWriter
import com.dredfit.store.healthBackfillCount
import com.dredfit.store.nextSession
import com.dredfit.store.setBodyMass
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunsAlone
@RunWith(AndroidJUnit4::class)
class HealthDeniedTest : HealthTestCase() {

    @After
    fun leaveNothingBehind() = deleteOwnRecords()

    /** A node of Health Connect's screen, through the instrumentation's own
     *  accessibility connection (`uiautomator dump` cannot run beside it). */
    private fun sheetNode(id: String): AccessibilityNodeInfo? =
        instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByViewId("$SHEET:id/$id")?.firstOrNull()

    private fun tapSheetButton(vararg ids: String) {
        check(awaitTrue(timeoutMs = 10_000) {
            ids.firstNotNullOfOrNull { sheetNode(it)?.takeIf { node -> node.isEnabled } }
                ?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
        }) { "no Health Connect permission screen with ${ids.toList()} on screen" }
    }

    @Test
    fun refusedTheSwitchStaysOffPartlyGrantedTheWorkoutGoesWithoutItsCalories() {
        launch(Seed.Clean, fast = false)
        check(granted().isEmpty()) { "Health Connect permissions already granted: run this class alone on a fresh install (header)" }

        // 1. The switch asks: Health Connect's own screen comes up.
        tap(AX.settings)
        tapOnce("health-toggle")
        assertTrue("Health Connect's permission screen", awaitTrue(10_000) { sheetNode("primary_button_outline") != null })

        // 2. Its privacy-policy link opens the policy (the link is the end of
        //    the line "…handles your data in their privacy policy").
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_VIEW)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            // The link is a span in the line's text; accessibility hands it
            // over as a span whose click goes back to the screen, as TalkBack
            // follows a link.
            val line = checkNotNull(sheetNode("privacy_policy")) { "no privacy-policy line on the screen" }
            val text = line.text as Spanned
            val link = text.getSpans(0, text.length, ClickableSpan::class.java).single()
            instrumentation.runOnMainSync { link.onClick(View(app)) }
            assertTrue("the policy was opened", awaitTrue(10_000) {
                Intents.getIntents().any { it.action == Intent.ACTION_VIEW && it.dataString == "https://dredfit.com/privacy.html" }
            })
        } finally {
            Intents.release()
        }

        // 3. "Don't allow": the switch stays off.
        tapSheetButton("secondary_button")
        awaitStage(Stage.RESUMED)
        await("health-toggle")
        assertTrue("the switch settles off", awaitTrue(10_000) { !readStore { settings.healthEnabled } })
        compose.onNodeWithTag("health-toggle").assertIsOff()
        assertFalse("nothing was granted", HealthConnectWriter.WRITE_EXERCISE in granted())

        // 4. The workout write alone (and the suite's read-back): the workout
        //    reaches Health Connect, its calories do not — the one transaction
        //    must not carry a record it may not write.
        grant(setOf(HealthConnectWriter.WRITE_EXERCISE, "android.permission.health.READ_EXERCISE",
                    "android.permission.health.READ_ACTIVE_CALORIES_BURNED"))
        onStore { update { it.copy(settings = it.settings.copy(healthEnabled = true)) } }
        onStore { setBodyMass(80.0) }
        onStore { completeWorkout(session = nextSession, result = FeedbackResult.plan, durationSec = 35 * 60) }
        assertTrue("the workout went out", awaitTrue(15_000) { readStore { healthBackfillCount == 0 } })
        val record = readStore { records.last() }
        assertEquals(record.id, own(ExerciseSessionRecord::class).single().metadata.clientRecordId)
        assertTrue("no calories without their permission", own(ActiveCaloriesBurnedRecord::class).isEmpty())

        // 5. "Allow all", then "Allow", on the screen: everything granted,
        //    the switch on.
        onStore { update { it.copy(settings = it.settings.copy(healthEnabled = false)) } }
        tapOnce("health-toggle")
        tapSheetButton("settingslib_main_switch_bar")
        tapSheetButton("primary_button", "primary_button_outline")
        awaitStage(Stage.RESUMED)
        assertTrue("the switch is on", awaitTrue(10_000) { readStore { settings.healthEnabled } })
        compose.onNodeWithTag("health-toggle").assertIsOn()
        assertTrue("everything the switch asks for", granted().containsAll(HealthConnectWriter.permissions))
    }

    private companion object {
        /** Health Connect's permission screen on Android 14+ (the platform's
         *  controller); Android 10–13 show the Health Connect app's own. */
        const val SHEET = "com.android.healthconnect.controller"
    }
}
