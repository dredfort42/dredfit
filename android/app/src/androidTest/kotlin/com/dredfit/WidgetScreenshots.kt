//
//  Frames of the home-screen widget at each size, for comparing with iOS's
//  small, medium and large: placed through WidgetHost (the RemoteViews a
//  launcher inflates), photographed from the screen and cut to each widget.
//  Runs only when asked, like ScreenshotWalk:
//
//    adb shell am instrument -w -e class com.dredfit.WidgetScreenshots \
//      -e screens widget com.dredfit.dredfit.test/androidx.test.runner.AndroidJUnitRunner
//
//  It sets the per-app language itself (en, then ru), and the mode per
//  widget (the launcher's — the system's — not the app's Appearance). The
//  PNGs land in the app's external files dir, `screens/`:
//  `<prefix>-<lang>-<light|dark>-<small|medium|large>.png`, plus the rest and
//  done days in English light.
//

package com.dredfit

import android.app.LocaleManager
import android.graphics.Bitmap
import android.os.Build
import android.os.LocaleList
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.core.FeedbackResult
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.swiftWeekday
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.file.Files
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunsAlone
@RunWith(AndroidJUnit4::class)
class WidgetScreenshots {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val app = instrumentation.targetContext.applicationContext as DredfitApp

    private enum class Day { workout, rest, done }

    /** This week as a person three workouts in: Monday and yesterday done,
     *  the rest missed, Wednesday and Sunday resting — every mark the strip
     *  draws. `day` decides today. */
    private fun seed(day: Day) {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val rest = buildSet {
            add(swiftWeekday(DayOfWeek.SUNDAY))
            if (today.dayOfWeek != DayOfWeek.WEDNESDAY) add(swiftWeekday(DayOfWeek.WEDNESDAY))
            if (day == Day.rest) add(swiftWeekday(today.dayOfWeek))
        }
        app.resetForTests({ instrumentation.runOnMainSync(it) }) { path ->
            Files.deleteIfExists(path)
            val store = AppStore(path)
            store.update { it.copy(settings = it.settings.copy(onboardingCompleted = true, restWeekdays = rest)) }
            val done = listOf(monday, today.minusDays(1)).distinct().filter { it < today }
            for (d in done) {
                store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                                      date = d.atTime(18, 0).atZone(zone).toInstant())
            }
            if (day == Day.done) store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        }
        val loaded = CountDownLatch(1)
        instrumentation.runOnMainSync { app.withStore { loaded.countDown() } }
        check(loaded.await(20, TimeUnit.SECONDS)) { "the store never loaded" }
    }

    private fun language(tag: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val locales = app.getSystemService(LocaleManager::class.java)
        instrumentation.runOnMainSync { locales.applicationLocales = LocaleList.forLanguageTags(tag) }
        // The app's resources follow on the next configuration pass.
        val end = System.currentTimeMillis() + 10_000
        while (app.resources.configuration.locales[0].language != tag && System.currentTimeMillis() < end) Thread.sleep(100)
        check(app.resources.configuration.locales[0].language == tag) { "the app never took $tag" }
    }

    @Test
    fun captureTheWidget() {
        val prefix = InstrumentationRegistry.getArguments().getString("screens")
        assumeTrue("screenshots only on request (-e screens <prefix>)", prefix != null)
        val dir = File(app.getExternalFilesDir(null), "screens").apply { mkdirs() }
        try {
            for (lang in listOf("en", "ru")) {
                language(lang)
                seed(Day.workout)
                for (night in listOf(false, true)) shootSizes(dir, "$prefix-$lang-${if (night) "dark" else "light"}", night)
            }
            language("en")
            seed(Day.rest)
            shootSizes(dir, "$prefix-en-light-restday", night = false)
            seed(Day.done)
            shootSizes(dir, "$prefix-en-light-doneday", night = false)
        } finally {
            language("en")
        }
    }

    private fun shootSizes(dir: File, name: String, night: Boolean) {
        WidgetHost().use { host ->
            val small = host.place(WidgetHost.SMALL, night, top = 150)
            val medium = host.place(WidgetHost.MEDIUM, night, top = 630)
            val large = host.place(WidgetHost.LARGE, night, top = 1110)
            // Every size drawn before the photograph: the large's week line
            // is the last thing a session writes.
            host.awaitText(small, app.resources.getString(R.string.widgets_today_24345a14).uppercase())
            host.awaitText(medium, app.resources.getString(R.string.widgets_steps_6578912e))
            val end = System.currentTimeMillis() + 10_000
            while (host.texts(large).size < 8 && System.currentTimeMillis() < end) Thread.sleep(200)
            Thread.sleep(500)
            val screen = instrumentation.uiAutomation.takeScreenshot()
            for ((family, view) in listOf("small" to small, "medium" to medium, "large" to large)) {
                File(dir, "$name-$family.png").outputStream().use { crop(screen, view).compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
    }

    private fun crop(screen: Bitmap, view: View): Bitmap {
        val at = IntArray(2)
        instrumentation.runOnMainSync { view.getLocationOnScreen(at) }
        return Bitmap.createBitmap(screen, at[0], at[1], view.width.coerceAtMost(screen.width - at[0]),
                                   view.height.coerceAtMost(screen.height - at[1]))
    }
}
