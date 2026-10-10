//
//  The home-screen widget placed for real (WidgetHost): the store's snapshot
//  reaching it at launch and after a change, the midnight it books and
//  unbooks, the receiver's own midnight, a new zone, the file a later process
//  reads, and the tap. No Swift twin — WidgetKit's reloads and timeline
//  switches are the system's on iOS, and no iOS test drives them.
//

package com.dredfit

import android.app.LocaleManager
import android.content.Intent
import android.os.LocaleList
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.dredfit.core.FeedbackResult
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.swiftWeekday
import com.dredfit.ui.Observed
import com.dredfit.ui.tr
import com.dredfit.widgets.TodayProvider
import com.dredfit.widgets.WidgetCenter
import com.dredfit.widgets.WidgetSnapshot
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse

import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class WidgetHostTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val app = instrumentation.targetContext.applicationContext as DredfitApp
    private lateinit var host: WidgetHost

    /** A fresh install past onboarding with no rest days (the suite must not
     *  depend on the weekday it runs on), loaded — its launch publishes. */
    private fun cleanStore(restWeekdays: Set<Int> = emptySet(), seed: (AppStore) -> Unit = {}): Observed<AppStore> {
        app.resetForTests({ instrumentation.runOnMainSync(it) }) { path ->
            Files.deleteIfExists(path)
            val store = AppStore(path)
            store.update {
                it.copy(settings = it.settings.copy(onboardingCompleted = true, restWeekdays = restWeekdays))
            }
            seed(store)
        }
        val loaded = CountDownLatch(1)
        var store: Observed<AppStore>? = null
        instrumentation.runOnMainSync { app.withStore { store = it; loaded.countDown() } }
        assertTrue("the store loads", loaded.await(20, TimeUnit.SECONDS))
        return checkNotNull(store)
    }

    @Before
    fun placeNothingYet() {
        host = WidgetHost()
    }

    @After
    fun removeEverything() {
        host.close()
        app.widgets.cancelMidnight()
    }

    // MARK: - The snapshot reaches the widget

    @Test
    fun theStoresDayReachesAPlacedWidgetAndFollowsAWorkout() {
        val store = cleanStore()
        val widget = host.place(WidgetHost.MEDIUM)
        host.awaitText(widget, "Workout 1")
        host.awaitText(widget, "TODAY")
        host.awaitText(widget, "steps")   // the medium, not the small

        // Within the first session's life: the feed, not a new session, must
        // carry the change (a session does not run provideGlance again).
        instrumentation.runOnMainSync { store.act { completeWorkout(session = nextSession, result = FeedbackResult.plan) } }
        host.awaitText(widget, "Done ✓")
    }

    @Test
    fun eachSizeDrawsItsOwnFamily() {
        cleanStore()
        val small = host.place(WidgetHost.SMALL)
        val medium = host.place(WidgetHost.MEDIUM, top = 480)
        val large = host.place(WidgetHost.LARGE, top = 960)
        host.awaitText(large, "This week · 0 workouts · +0 steps")
        host.awaitText(medium, "steps")
        host.awaitText(small, "Workout 1")
        assertFalse("the small has no steps", "steps" in host.texts(small))
        assertFalse("the medium has no week line", host.texts(medium).any { it.startsWith("This week") })
        // The large lists the plan: the first session's first movement.
        val first = checkNotNull(app.widgets.feed.value.snapshot).plan.first()
        host.awaitText(large, app.resources.tr(first.title, widget = true))
        host.awaitText(large, app.resources.tr(first.detail, widget = true))
        assertFalse("the small has no plan", app.resources.tr(first.title, widget = true) in host.texts(small))
    }

    /** The lines that shrink before they truncate are TextViews of their own
     *  (`FittedLine`): their words, read off the inflated widget — and a
     *  per-app language changed under a placed widget redraws it, though no
     *  broadcast says so (DredfitApp.onConfigurationChanged). */
    @Test
    fun aRestDaySaysItsWordsInEnglishThenInRussian() {
        val today = java.time.LocalDate.now()
        cleanStore(restWeekdays = setOf(swiftWeekday(today.dayOfWeek))) { store ->
            // Rest is rest FROM something: a workout yesterday makes today's
            // marked weekday a rest day rather than the first workout.
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                                  date = today.minusDays(1).atTime(18, 0).atZone(ZoneId.systemDefault()).toInstant())
        }
        val large = host.place(WidgetHost.LARGE)
        host.awaitText(large, "Rest day")
        host.awaitText(large, "Next: Workout 2 · tomorrow")
        assertTrue(host.texts(large).toString(), host.texts(large).any { it.startsWith("This week · ") })
        val first = checkNotNull(app.widgets.feed.value.snapshot).plan.first()
        host.awaitText(large, app.resources.tr(first.title, widget = true))

        val locales = app.getSystemService(LocaleManager::class.java)
        try {
            instrumentation.runOnMainSync { locales.applicationLocales = LocaleList.forLanguageTags("ru") }
            host.awaitText(large, "День отдыха")
            host.awaitText(large, "Следующая: тренировка 2 · завтра")
            assertTrue(host.texts(large).toString(), host.texts(large).any { it.startsWith("Эта неделя · ") })
        } finally {
            instrumentation.runOnMainSync { locales.applicationLocales = LocaleList.forLanguageTags("en") }
        }
    }

    // MARK: - Midnight

    /** A placed widget books the next local midnight — inexact, non-wakeup —
     *  and the last one removed takes it down. */
    @Test
    fun aPlacedWidgetBooksTheNextMidnightAndTheLastOneRemovedUnbooksIt() {
        cleanStore()
        val widget = host.place(WidgetHost.SMALL)
        host.awaitText(widget, "Workout 1")
        val expected = TodayProvider.nextMidnight(Instant.now(), ZoneId.systemDefault()).toEpochMilli()
        awaitMidnightAlarm(expected)

        host.remove(widget)
        val end = System.currentTimeMillis() + 15_000
        while (midnightAlarm() != null && System.currentTimeMillis() < end) Thread.sleep(300)
        assertNull("the last widget removed must take its midnight with it", midnightAlarm())
    }

    /** The midnight alarm itself: the receiver redraws and books the next one. */
    @Test
    fun theMidnightBroadcastRebooksTheNextMidnight() {
        cleanStore()
        val widget = host.place(WidgetHost.SMALL)
        host.awaitText(widget, "Workout 1")
        app.widgets.cancelMidnight()
        assertNull(midnightAlarm())

        app.sendBroadcast(Intent(WidgetCenter.ACTION_MIDNIGHT).setClass(app, com.dredfit.widgets.TodayStatusWidgetReceiver::class.java))
        awaitMidnightAlarm(TodayProvider.nextMidnight(Instant.now(), ZoneId.systemDefault()).toEpochMilli())
    }

    /** A new zone moves midnight: the reminders' receiver re-books it on the
     *  new wall (the system's TIMEZONE_CHANGED, from `cmd alarm`). */
    @Test
    fun aNewZoneMovesTheMidnight() {
        cleanStore()
        val widget = host.place(WidgetHost.SMALL)
        host.awaitText(widget, "Workout 1")
        val before = ZoneId.systemDefault().id
        val far = if (before == "Pacific/Kiritimati") "Pacific/Pago_Pago" else "Pacific/Kiritimati"
        try {
            WidgetHost.shell("cmd alarm set-timezone $far")
            awaitMidnightAlarm(TodayProvider.nextMidnight(Instant.now(), ZoneId.of(far)).toEpochMilli())
        } finally {
            WidgetHost.shell("cmd alarm set-timezone $before")
        }
    }

    // MARK: - The file, and what is not written twice

    /** A process that starts for the widget alone reads the file; a snapshot
     *  equal to the last one is not written (or drawn) again. */
    @Test
    fun theFileHoldsTheNewestSnapshotAndAnEqualOneIsNotWrittenAgain() {
        val file = File(app.noBackupFilesDir, WidgetSnapshot.FILE_NAME)
        val store = cleanStore()
        val published = checkNotNull(app.widgets.feed.value.snapshot)
        // Read until it is this launch's: the file outlives a test, and a
        // previous one may have left it (equal, or not yet replaced).
        fun fileSaysIt() = file.exists() && WidgetSnapshot.decode(file.readText()) == published
        val end = System.currentTimeMillis() + 10_000
        while (!fileSaysIt() && System.currentTimeMillis() < end) Thread.sleep(100)
        assertTrue("the file holds the launch's snapshot", fileSaysIt())

        assertTrue(file.delete())
        app.widgets.publish(published)
        Thread.sleep(1_000)
        assertFalse("an equal snapshot is not written again", file.exists())

        instrumentation.runOnMainSync { store.act { completeWorkout(session = nextSession, result = FeedbackResult.plan) } }
        awaitFile(file)
        assertEquals(WidgetSnapshot.DayStatus.done,
                     WidgetSnapshot.decode(file.readText())?.days?.first { it.date == java.time.LocalDate.now() }?.status)
    }

    // MARK: - The tap

    @Test
    fun aTapOpensToday() {
        cleanStore()
        val widget = host.place(WidgetHost.SMALL)
        host.awaitText(widget, "Workout 1")
        host.tap(widget)
        val end = System.currentTimeMillis() + 15_000
        var opened: MainActivity? = null
        while (opened == null && System.currentTimeMillis() < end) {
            instrumentation.runOnMainSync {
                opened = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                    .filterIsInstance<MainActivity>().firstOrNull()
            }
            if (opened == null) Thread.sleep(200)
        }
        val activity = checkNotNull(opened) { "the tap opened no MainActivity" }
        assertEquals(MainActivity.ACTION_OPEN_TODAY, activity.intent.action)
        instrumentation.runOnMainSync { activity.finish() }
    }

    // MARK: - Helpers

    /** The wall time of the widget's midnight alarm, or null — read off
     *  `dumpsys alarm`, which prints each pending alarm's head line with its
     *  `origWhen` and the tag on the next line. */
    private fun midnightAlarm(): Long? {
        val lines = WidgetHost.shell("dumpsys alarm").lines()
        val i = lines.indexOfFirst { "com.dredfit.widgets.MIDNIGHT" in it && "tag=" in it }
        if (i <= 0) return null
        return Regex("""origWhen (\d+)""").find(lines[i - 1])?.groupValues?.get(1)?.toLong()
    }

    private fun awaitMidnightAlarm(expected: Long) {
        val end = System.currentTimeMillis() + 15_000
        while (midnightAlarm() != expected && System.currentTimeMillis() < end) Thread.sleep(300)
        assertEquals("the widget's midnight", expected, midnightAlarm())
    }

    private fun awaitFile(file: File) {
        val end = System.currentTimeMillis() + 10_000
        while (!file.exists() && System.currentTimeMillis() < end) Thread.sleep(100)
        assertTrue("the snapshot file is written", file.exists())
    }
}
