//
//  Frames of the screens a workout passes through, for comparing the port
//  with the iOS store frames — the same walk (WorkoutDriver) at real speed,
//  a full-screen capture the first time each screen is up. Runs only when
//  asked: `-e screens <prefix>` names the files, `-e appearance light|dark`
//  picks the theme the way Settings would; the language is the per-app one
//  set before the run (`adb shell cmd locale set-app-locales …`). The PNGs
//  land in the app's external files dir, `screens/`.
//

package com.dredfit

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.store.AppearanceChoice
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
        launch(Seed.Session2, fast = false, appearance = appearance)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(context.getExternalFilesDir(null), "screens").apply { mkdirs() }
        WorkoutDriver(this).completeWorkout(skipRests = true) { screen ->
            compose.waitForIdle()
            // Let a countdown's first redraw and any sheet animation settle.
            Thread.sleep(600)
            val shot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return@completeWorkout
            File(dir, "$prefix-${screen.name.lowercase()}.png").outputStream().use {
                shot.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        }
    }
}
