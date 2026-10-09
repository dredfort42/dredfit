//
//  Frames of the screens a workout passes through (`captureTheWalk`) and of
//  the screens outside it (`captureTheScreens`), for comparing the port
//  with the iOS store frames — the same walk (WorkoutDriver) at real speed,
//  a full-screen capture the first time each screen is up. Runs only when
//  asked: `-e screens <prefix>` names the files, `-e appearance light|dark`
//  picks the theme the way Settings would; the language is the per-app one
//  set before the run (`adb shell cmd locale set-app-locales …`). The PNGs
//  land in the app's external files dir, `screens/`.
//

package com.dredfit

import android.graphics.Bitmap
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.store.AppearanceChoice
import com.dredfit.ui.progress.ShareCardFactory
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ScreenshotWalk : DredfitUITest() {

    @Test
    fun captureTheWalk() {
        val args = InstrumentationRegistry.getArguments()
        val prefix = args.getString("screens")
        assumeTrue("screenshots only on request (-e screens <prefix>)", prefix != null)
        val appearance = if (args.getString("appearance") == "dark") AppearanceChoice.dark else AppearanceChoice.light
        launch(Seed.Session2, fast = false, appearance = appearance, keepLanguage = true)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(context.getExternalFilesDir(null), "screens").apply { mkdirs() }
        WorkoutDriver(this).completeWorkout(skipRests = true) { screen ->
            shoot(dir, "$prefix-${screen.name.lowercase()}")
        }
    }

    /** The screens outside the workout, on the History seed: Progress (the
     *  total, then one movement projected), Calendar, a record, the share
     *  card itself, Settings top and bottom, How it works — and the
     *  onboarding of a fresh install. */
    @Test
    fun captureTheScreens() {
        val args = InstrumentationRegistry.getArguments()
        val prefix = args.getString("screens")
        assumeTrue("screenshots only on request (-e screens <prefix>)", prefix != null)
        val appearance = if (args.getString("appearance") == "dark") AppearanceChoice.dark else AppearanceChoice.light
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(context.getExternalFilesDir(null), "screens").apply { mkdirs() }
        launch(Seed.History, fast = true, appearance = appearance, keepLanguage = true)

        tap(AX.tab("progress"))
        await(AX.totalSteps)
        // The share button stands once the card is rendered and written.
        await(AX.shareProgress)
        shoot(dir, "$prefix-progress")
        // The card the share button would send, as rendered.
        ShareCardFactory.file(context, ShareCardFactory.Slot.progress).takeIf { it.exists() }
            ?.copyTo(File(dir, "$prefix-sharecard.png"), overwrite = true)
        tap(AX.progressRow("squat"))
        await(AX.progressMilestone)
        shoot(dir, "$prefix-progress-squat")

        tap(AX.tab("calendar"))
        await(AX.day(1))
        shoot(dir, "$prefix-calendar")
        tap(AX.tab("today"))
        tap(AX.todayRecord)
        await(AX.historyDone)
        shoot(dir, "$prefix-history")
        tap(AX.historyDone)
        compose.waitUntil(3_000) { !exists(AX.historyDone) }

        tap(AX.settings)
        await(AX.settingsRhythm)
        shoot(dir, "$prefix-settings")
        compose.onAllNodesWithTag("version-line")[0].performScrollTo()
        shoot(dir, "$prefix-settings-bottom")
        compose.onAllNodesWithTag(AX.howItWorks)[0].performScrollTo()
        tap(AX.howItWorks)
        await(AX.howItWorksDone)
        shoot(dir, "$prefix-howitworks")

        launch(Seed.FreshInstall, fast = true, appearance = appearance, keepLanguage = true)
        await(AX.onboardingPrimary)
        shoot(dir, "$prefix-onboarding")
        tap(AX.onboardingSkip)
        await(AX.onboardingCare)
        shoot(dir, "$prefix-onboarding-care")
    }

    private fun shoot(dir: File, name: String) {
        compose.waitForIdle()
        // Let a countdown's first redraw and any sheet animation settle.
        Thread.sleep(800)
        val shot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        File(dir, "$name.png").outputStream().use { shot.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
