//
//  The widget's tap opens the app as it was left (owner decision, 11.10.2026:
//  as on iOS, whose widget sets no `widgetURL`) — a workout in flight stays in
//  front, Settings stays open, and no second MainActivity is stacked on the
//  first. The app is started as the system starts it (the launcher's intent,
//  or a reminder's), the widget is tapped on WidgetHost's home screen of its
//  own, and the screen that comes back is read. No Swift twin: XCUITest
//  cannot tap a widget.
//

package com.dredfit

import android.content.ComponentName
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WidgetTapTest : DredfitUITest() {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    /** What the launcher's icon sends. */
    private val fromTheLauncher: Intent
        get() = Intent.makeMainActivity(ComponentName(context, MainActivity::class.java))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)

    /** The MainActivity in front, if one is. */
    private fun resumedMain(): MainActivity? {
        var resumed: MainActivity? = null
        instrumentation.runOnMainSync {
            resumed = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                .filterIsInstance<MainActivity>().firstOrNull()
        }
        return resumed
    }

    /** The resumed MainActivity once the tap has brought it back. */
    private fun awaitResumedMain(): MainActivity {
        val end = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < end) {
            resumedMain()?.let { return it }
            Thread.sleep(200)
        }
        throw AssertionError("the tap brought no MainActivity back")
    }

    /** Puts the widget on the suite's home screen in front of the app, taps
     *  it, and hands back the activity that answered. */
    private fun tapTheWidget(): MainActivity {
        WidgetHost().use { host ->
            val widget = host.place(WidgetHost.SMALL)
            host.awaitText(widget, "TODAY")
            assertNull("the app is behind the home screen", resumedMain())
            host.tap(widget)
            return awaitResumedMain()
        }
    }

    @Test
    fun fromSettingsTheTapReturnsToSettings() {
        launch(Seed.Clean, fast = false, via = fromTheLauncher)
        tap(AX.settings)
        await(AX.settingsDone)

        val back = tapTheWidget()
        await(AX.settingsDone)
        assertEquals("one MainActivity, the one left", 1, mainActivities().size)
        assertNotEquals("not Today's door", MainActivity.ACTION_OPEN_TODAY, back.intent.action)
    }

    @Test
    fun fromARunningWorkoutTheTapReturnsToTheWorkout() {
        launch(Seed.Clean, fast = false, via = fromTheLauncher)
        WorkoutDriver(this).tapUntilGone(AX.startWorkout)
        await(AX.warmupIntroSkip)

        tapTheWidget()
        await(AX.warmupIntroSkip)
        assertEquals("one MainActivity, the one left", 1, mainActivities().size)
    }

    /** A task the reminder started has a root intent unlike the launcher's;
     *  the app still comes back as it was, not as a second activity on top. */
    @Test
    fun afterAReminderStartedTheAppTheTapStillReturnsToIt() {
        launch(Seed.Clean, fast = false, via = MainActivity.openToday(context))
        tap(AX.settings)
        await(AX.settingsDone)

        tapTheWidget()
        await(AX.settingsDone)
        assertEquals("one MainActivity, the one left", 1, mainActivities().size)
    }
}
