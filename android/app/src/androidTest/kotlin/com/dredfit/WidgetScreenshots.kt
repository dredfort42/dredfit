//
//  Frames of the home-screen widget at each size, for comparing with iOS's
//  small, medium and large: placed through WidgetHost (the RemoteViews a
//  launcher inflates), photographed from the screen and cut to each widget.
//  Runs only when asked, like ScreenshotWalk:
//
//    adb shell am instrument -w -e class com.dredfit.WidgetScreenshots \
//      -e screens widget com.dredfit.dredfit.test/androidx.test.runner.AndroidJUnitRunner
//
//  It sets the per-app language itself (en, then ru — or the list given as
//  `-e langs en,ru,es,pt-BR,de,fr,it`), and the mode per
//  widget (the launcher's — the system's — not the app's Appearance). The
//  PNGs land in the app's external files dir, `screens/`:
//  `<prefix>-<lang>-<light|dark>-<small|medium|large>.png`, plus the rest and
//  done days in English light.
//

package com.dredfit

import android.app.LocaleManager
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.LocaleList
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.core.FeedbackResult
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.swiftWeekday
import com.dredfit.widgets.WidgetSnapshot
import com.dredfit.widgets.WidgetSnapshot.DayStatus
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
     *  draws. `day` decides today: neither resting day is today unless `day`
     *  says rest (a Sunday run drew "Rest day" for the workout frames, and
     *  the Play listing's widget frame went out that way). */
    private fun seed(day: Day) {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val rest = buildSet {
            for (resting in listOf(DayOfWeek.WEDNESDAY, DayOfWeek.SUNDAY)) {
                if (today.dayOfWeek != resting) add(swiftWeekday(resting))
            }
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
        // A language, not the tag: `pt-BR` arrives as language "pt".
        val language = java.util.Locale.forLanguageTag(tag).language
        val end = System.currentTimeMillis() + 10_000
        while (app.resources.configuration.locales[0].language != language && System.currentTimeMillis() < end) Thread.sleep(100)
        check(app.resources.configuration.locales[0].language == language) { "the app never took $tag" }
    }

    @Test
    fun captureTheWidget() {
        val args = InstrumentationRegistry.getArguments()
        val prefix = args.getString("screens")
        assumeTrue("screenshots only on request (-e screens <prefix>)", prefix != null)
        val dir = File(app.getExternalFilesDir(null), "screens").apply { mkdirs() }
        // `-e langs en,de,…` for the store's seven; en and ru are the
        // comparison with iOS this run was written for.
        val langs = args.getString("langs")?.split(",") ?: listOf("en", "ru")
        try {
            for (lang in langs) {
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

    /**
     * The picker's preview on Android 10–14 (`previewImage`,
     * res/drawable-nodpi/widget_preview_image.png): the medium, light, in
     * English, on a neutral week rather than anyone's own — Monday, Thursday
     * and Friday done, Tuesday missed, Wednesday and Saturday resting, today
     * Workout 12 at 27 steps (the ring sits on the weekday it is rendered on).
     * The corners are cut to the system's widget radius and left
     * transparent; the size is the emulator's pixels (420 dpi). Run as
     * `-e class com.dredfit.WidgetScreenshots#captureThePreviewImage -e screens widget`.
     */
    @Test
    fun captureThePreviewImage() {
        assumeTrue("on request (-e screens <prefix>)", InstrumentationRegistry.getArguments().getString("screens") != null)
        val dir = File(app.getExternalFilesDir(null), "screens").apply { mkdirs() }
        language("en")
        val today = LocalDate.now()
        val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val week = listOf(DayStatus.done, DayStatus.unmarked, DayStatus.rest, DayStatus.done, DayStatus.done,
                          DayStatus.rest, DayStatus.workout)
        val days = (0L until 14L).map { i ->
            val date = monday.plusDays(i)
            val status = when {
                date == today -> DayStatus.workout
                date < today -> week[i.toInt() % 7].takeIf { it != DayStatus.workout } ?: DayStatus.unmarked
                else -> if (i % 7 == 2L || i % 7 == 5L) DayStatus.rest else DayStatus.workout
            }
            WidgetSnapshot.Day(date, status, sessionNumber = if (date == today) 12 else null, nextDate = null)
        }
        app.widgets.publish(WidgetSnapshot(days = days, totalSteps = 27, week = WidgetSnapshot.Week(3, 6),
                                           weekStart = monday, planSessionNumber = 12, plan = emptyList()))
        WidgetHost().use { host ->
            val medium = host.place(WidgetHost.MEDIUM, night = false, top = 150)
            host.awaitText(medium, "Workout 12")
            host.awaitText(medium, "27")
            Thread.sleep(500)
            val drawn = Bitmap.createBitmap(medium.width, medium.height, Bitmap.Config.ARGB_8888)
            instrumentation.runOnMainSync { medium.draw(Canvas(drawn)) }
            val radius = app.resources.getDimension(android.R.dimen.system_app_widget_background_radius)
            val cut = Bitmap.createBitmap(drawn.width, drawn.height, Bitmap.Config.ARGB_8888)
            Canvas(cut).drawRoundRect(RectF(0f, 0f, drawn.width.toFloat(), drawn.height.toFloat()), radius, radius,
                                      Paint(Paint.ANTI_ALIAS_FLAG).apply {
                                          shader = BitmapShader(drawn, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                                      })
            File(dir, "widget-preview.png").outputStream().use { cut.compress(Bitmap.CompressFormat.PNG, 100, it) }
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
