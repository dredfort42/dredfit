//
//  Calendar, Progress, the history sheet and Settings on a device. Ports of
//  the matching tests of ios/DredfitUITests/DredfitUITests.swift — the
//  calendar's history, the progress total, the rest-day chip, settings from
//  every tab, how it works — seeded rather than walked (WorkoutWalkTest is
//  the walk), plus what Android does through the system: the export's file
//  picker and the share sheet, both stubbed with Espresso-Intents so the
//  test sees the intent go out without a picker it cannot drive.
//
//  Differences from the iOS twins: the calendar's record is seeded, not
//  walked, so iOS's exact "Actual: 3×3" becomes "one named actual line" on
//  today's seeded shortfall (`todaysDoorOpensTodaysRecord`); the progress
//  total is 6 after one "on plan" (iOS walks "easy" and reads 12).
//

package com.dredfit

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.hamcrest.Matchers.allOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

@RunWith(AndroidJUnit4::class)
class TabsAndSettingsTest : DredfitUITest() {

    private fun shows(text: String, substring: Boolean = false) =
        compose.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty()

    // MARK: - Calendar and history

    /** The day of a completed workout opens its record; the walk steps to
     *  the one before it and back. */
    @Test
    fun calendarShowsHistoryAndWalksTheJournal() {
        launch(Seed.History, fast = true)
        tap(AX.tab("calendar"))
        compose.waitUntil(5_000) { shows("Completed today ✓") }
        tap(AX.day(LocalDate.now(ZoneId.systemDefault()).dayOfMonth))
        await(AX.historyDone)
        val last = DredfitUITest.HISTORY_DAYS.size
        assertTrue("history did not open on today's record", shows("Workout $last"))
        tap(AX.historyEarlier)
        compose.waitUntil(3_000) { shows("Workout ${last - 1}") }
        tap(AX.historyLater)
        compose.waitUntil(3_000) { shows("Workout $last") }
        tap(AX.historyDone)
        compose.waitUntil(3_000) { !exists(AX.historyDone) }
    }

    /** The card under the grid follows the week as it is NOW: tomorrow made
     *  a rest day in Settings, the card stops saying "tomorrow" (it kept the
     *  old words while it read the store object — skeptic finding). */
    @Test
    fun theDoneCardFollowsARestDayChangedInSettings() {
        launch(Seed.History, fast = true)
        tap(AX.tab("calendar"))
        compose.waitUntil(5_000) { shows("· tomorrow", substring = true) }
        val tomorrow = LocalDate.now(ZoneId.systemDefault()).plusDays(1).dayOfWeek.value % 7 + 1
        tap(AX.settings)
        tap(AX.weekday(tomorrow))
        tap(AX.settingsDone)
        compose.waitUntil(3_000) { !exists(AX.settingsRhythm) }
        compose.waitUntil(3_000) { !shows("· tomorrow", substring = true) }
        assertTrue(shows("Completed today ✓"))
    }

    /** Today's completed state carries the door to what was just done. */
    @Test
    fun todaysDoorOpensTodaysRecord() {
        launch(Seed.History, fast = true)
        tap(AX.todayRecord)
        await(AX.historyDone)
        assertTrue(shows("Workout ${DredfitUITest.HISTORY_DAYS.size}"))
        // The seed ran today's first movement one short: the row names the
        // fact, in the plan's own spelling — iOS's "Actual: 3×3" check.
        val actual = compose.onAllNodes(SemanticsMatcher("an actual line") {
            it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("history-actual-") == true
        }, useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals("one movement went differently", 1, actual.size)
        assertTrue("the line is named, not a bare number",
                   shows("Actual: ", substring = true) || shows("Held: ", substring = true))
    }

    // MARK: - Progress

    /** One workout rated "on plan" from a clean start is a step on each of
     *  its six movements; "1 workout" in the singular. */
    @Test
    fun progressReflectsCompletedWorkout() {
        launch(Seed.Session2, fast = true)
        tap(AX.tab("progress"))
        await(AX.totalSteps)
        compose.onNodeWithTag(AX.totalSteps).assertTextEquals("6")
        assertTrue("\"1 workout\" must use the singular", shows("1 workout"))
    }

    /** A row projects the chart and opens what its ladder promises next;
     *  "Show all" goes back to the total. */
    @Test
    fun aMovementRowProjectsTheChartAndSaysWhatComesNext() {
        launch(Seed.History, fast = true)
        tap(AX.tab("progress"))
        await(AX.totalSteps)
        assertFalse(exists(AX.progressMilestone))
        tap(AX.progressRow("squat"))
        await(AX.progressMilestone)
        compose.onNodeWithTag(AX.progressRow("squat")).assertIsSelected()
        tap(AX.showAll)
        compose.waitUntil(3_000) { !exists(AX.progressMilestone) }
        compose.onNodeWithTag(AX.progressRow("squat")).assertIsNotSelected()
        // The break of the seed is explained under the chart.
        assertTrue(shows("A break of 12 days.", substring = true))
    }

    /** TalkBack reads the chart as Swift Charts gives it to VoiceOver: one
     *  element per workout, its date as the axis prints it and its value,
     *  and activating one opens THAT workout's record. */
    @Test
    fun theChartSpeaksEachPointAndOpensItsRecord() {
        launch(Seed.History, fast = true)
        tap(AX.tab("progress"))
        await(AX.totalSteps)
        val count = DredfitUITest.HISTORY_DAYS.size
        val nodes = compose.onAllNodes(SemanticsMatcher("a chart point") {
            it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("chart-point-") == true
        }).fetchSemanticsNodes()
        assertEquals("one element per plotted workout", count, nodes.size)
        val today = LocalDate.now(ZoneId.systemDefault())
        val format = java.time.format.DateTimeFormatter.ofPattern(
            android.text.format.DateFormat.getBestDateTimePattern(java.util.Locale.ENGLISH, "MMMd"), java.util.Locale.ENGLISH)
        val last = compose.onNodeWithTag("chart-point-${count - 1}").fetchSemanticsNode()
            .config[SemanticsProperties.ContentDescription].single()
        assertTrue("date then value: $last", last.startsWith(format.format(today) + ", ") && last.endsWith(" steps"))
        compose.onNodeWithTag("chart-point-0").performSemanticsAction(SemanticsActions.OnClick)
        await(AX.historyDone)
        assertTrue("the first point opens workout 1", shows("Workout 1"))
        tap(AX.historyDone)
        compose.waitUntil(3_000) { !exists(AX.historyDone) }
        compose.onNodeWithTag("chart-point-${count - 1}").performSemanticsAction(SemanticsActions.OnClick)
        await(AX.historyDone)
        assertTrue("the last point opens workout $count", shows("Workout $count"))
    }

    /** The share sheet receives the rendered card as a PNG stream. */
    @Test
    fun shareHandsTheCardToTheShareSheet() {
        launch(Seed.History, fast = true)
        tap(AX.tab("progress"))
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_CHOOSER)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            tap(AX.shareProgress)
            intended(allOf(hasAction(Intent.ACTION_CHOOSER)))
            val chooser = Intents.getIntents().last { it.action == Intent.ACTION_CHOOSER }
            @Suppress("DEPRECATION")
            val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
            assertEquals(Intent.ACTION_SEND, send.action)
            assertEquals("image/png", send.type)
            @Suppress("DEPRECATION")
            val stream = send.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)!!
            assertEquals("content", stream.scheme)
            val bytes = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
                .openInputStream(stream)!!.use { it.readBytes() }
            assertEquals("a PNG, by its magic number", listOf(0x89, 0x50, 0x4E, 0x47), bytes.take(4).map { it.toInt() and 0xFF })
        } finally {
            Intents.release()
        }
    }

    // MARK: - Settings

    /** The chip CHANGES STATE (selected, not a colour), and the state is the
     *  file's: it survives closing the sheet. */
    @Test
    fun settingsTogglesRestDay() {
        launch(Seed.Clean, fast = true)
        tap(AX.settings)
        await(AX.settingsRhythm)
        val monday = AX.weekday(2)
        compose.onNodeWithTag(monday).assertIsNotSelected()
        tap(monday)
        compose.onNodeWithTag(monday).assertIsSelected()
        tap(AX.settingsDone)
        compose.waitUntil(3_000) { !exists(AX.settingsRhythm) }
        tap(AX.settings)
        await(monday)
        compose.onNodeWithTag(monday).assertIsSelected()
        tap(monday)
        compose.onNodeWithTag(monday).assertIsNotSelected()
        tap(AX.settingsDone)
        // Closing settings returns to Today.
        await(AX.startWorkout)
    }

    @Test
    fun settingsReachableFromEveryTab() {
        launch(Seed.Clean, fast = true)
        for (tab in listOf("calendar", "progress")) {
            tap(AX.tab(tab))
            tap(AX.settings)
            await(AX.settingsRhythm)
            tap(AX.settingsDone)
            compose.waitUntil(3_000) { !exists(AX.settingsRhythm) }
        }
    }

    @Test
    fun howItWorksOpensFromSettings() {
        launch(Seed.Clean, fast = true)
        tap(AX.settings)
        tap(AX.howItWorks)
        compose.waitUntil(3_000) { shows("Variation and dose") }
        for (section in listOf("What your answer does", "Deload", "Rotation", "Weekly rhythm", "Trying the next variation",
                               "Skips", "Why there are no questionnaires")) {
            assertTrue("section \"$section\" is missing", shows(section))
        }
        tap(AX.howItWorksDone)
        compose.waitUntil(3_000) { !exists(AX.howItWorksDone) }
        assertTrue("closing the explainer returns to settings", exists(AX.settingsRhythm))
    }

    /** The one switch every signal answers to; the silent-mode row stands
     *  only under an ON switch. */
    @Test
    fun soundsSwitchTakesTheSilentModeRowWithIt() {
        launch(Seed.Clean, fast = true)
        tap(AX.settings)
        await(AX.silentModeToggle)
        tap(AX.soundsToggle)
        compose.waitUntil(3_000) { !exists(AX.silentModeToggle) }
        tap(AX.settingsDone)
        relaunchFromDisk()
        tap(AX.settings)
        await(AX.soundsToggle)
        assertFalse("the OFF switch is the file's, not the sheet's", exists(AX.silentModeToggle))
        tap(AX.soundsToggle)
        await(AX.silentModeToggle)
    }

    /** OFF says what silent mode does to the tones; ON says Android's own
     *  sentence (the phone's sound mode), not iOS's ringer switch. */
    @Test
    fun theSilentModeCaptionFollowsTheSwitch() {
        launch(Seed.Clean, fast = true)
        tap(AX.settings)
        val off = "In Silent mode the tones go quiet — the vibration keeps going."
        val on = "The tones play even when the phone is set to silent or vibrate."
        compose.waitUntil(5_000) { shows(off) }
        assertFalse(shows(on))
        tap(AX.silentModeToggle)
        compose.waitUntil(3_000) { shows(on) }
        assertFalse("one caption at a time", shows(off))
    }

    /** The shipped sheet keeps About's Play rows out until the listing is
     *  live (`BuildConfig.PLAY_LISTING_LIVE`; AboutSectionTest has both states). */
    @Test
    fun settingsShowNoPlayRowsBeforeTheListingIsLive() {
        launch(Seed.Clean, fast = true)
        tap(AX.settings)
        await("version-line")
        assertFalse(exists("rate-app"))
        assertFalse(exists("recommend-app"))
    }

    /** Export builds the file at the tap and writes it where the picker
     *  points — here a file the stub hands back. */
    @Test
    fun exportWritesTheBackupWhereThePickerPoints() {
        launch(Seed.Session2, fast = true)
        val target = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "export-test.json")
        target.delete()
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_CREATE_DOCUMENT))
                .respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(Uri.fromFile(target))))
            tap(AX.settings)
            tap(AX.exportHistory)
            intended(hasAction(Intent.ACTION_CREATE_DOCUMENT))
            compose.waitUntil(5_000) { target.length() > 0 }
            val text = target.readText()
            assertTrue("the backup is the store's JSON: ${text.take(80)}", text.startsWith("{") && text.contains("\"records\""))
        } finally {
            Intents.release()
            target.delete()
        }
    }
}
