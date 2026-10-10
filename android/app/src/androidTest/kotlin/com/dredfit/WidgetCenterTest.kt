//
//  WidgetCenter on its own, with a context of the test's: the day each draw
//  is for, a fresh process saying what the file already says, and a device
//  with no widget service. No Swift twin (WidgetKit does the first two, and
//  iOS degrades on a nil App Group URL).
//

package com.dredfit

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.core.LoadUnit
import com.dredfit.widgets.WidgetCenter
import com.dredfit.widgets.WidgetSnapshot
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.LocalDate
import java.util.concurrent.Executor

@RunWith(AndroidJUnit4::class)
class WidgetCenterTest {

    private val app: Context = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
    private val dir = File(app.cacheDir, "widget-center-test").apply { deleteRecursively(); mkdirs() }

    /** The app, with its no-backup files somewhere of the test's own — and,
     *  when asked, no widget service, as on TV or Automotive. */
    private fun context(widgets: Boolean = true): Context = object : ContextWrapper(app) {
        override fun getNoBackupFilesDir(): File = dir
        override fun getSystemService(name: String): Any? =
            if (!widgets && name == Context.APPWIDGET_SERVICE) null else super.getSystemService(name)
    }

    /** The disk thread inline: what it does is done when `publish` returns. */
    private val inline = Executor { it.run() }

    private val monday = LocalDate.of(2026, 10, 5)

    private fun snapshot(total: Int = 3) = WidgetSnapshot(
        days = (0L until 14L).map { WidgetSnapshot.Day(monday.plusDays(it), WidgetSnapshot.DayStatus.workout, null, null) },
        totalSteps = total, week = WidgetSnapshot.Week(0, 0), weekStart = monday, planSessionNumber = 1,
        plan = listOf(WidgetSnapshot.PlanRow("Squat", "3×8", LoadUnit.reps, perSide = false)))

    private val file get() = File(dir, WidgetSnapshot.FILE_NAME)

    @After
    fun clean() {
        dir.deleteRecursively()
    }

    /** The entry is chosen by the day of each draw: a publish, a new
     *  session's `prepare` and a refresh each take the day on the wall. */
    @Test
    fun eachDrawIsForTheDayOnTheWall() {
        var today = monday
        val center = WidgetCenter(context(), inline) { today }
        center.publish(snapshot())
        assertEquals(monday, center.feed.value.today)

        today = monday.plusDays(1)
        center.prepare()
        assertEquals("a session started after midnight", today, center.feed.value.today)

        today = monday.plusDays(2)
        val redraws = center.feed.value.redraws
        center.refresh()
        assertEquals("the midnight alarm", today, center.feed.value.today)
        assertEquals("and a live session is told", redraws + 1, center.feed.value.redraws)
    }

    /** A fresh process's first publish that says what the file says writes
     *  nothing (and draws nothing): every cold start would otherwise wake a
     *  widget session for the same picture. */
    @Test
    fun aFreshProcessSayingWhatTheFileSaysWritesNothing() {
        WidgetCenter(context(), inline).publish(snapshot())
        assertTrue(file.exists())
        assertTrue("the fixture must be able to date the file", file.setLastModified(0))

        WidgetCenter(context(), inline).publish(snapshot())
        assertEquals("the same words are not written again", 0L, file.lastModified())

        WidgetCenter(context(), inline).publish(snapshot(total = 4))
        assertNotEquals("new words are", 0L, file.lastModified())
        assertEquals(snapshot(total = 4), WidgetSnapshot.decode(file.readText()))
    }

    /** No widget service: `AppWidgetManager.getInstance` is null there, and
     *  the store publishes at every launch — nothing may throw, and nothing
     *  is written for a widget that cannot exist. */
    @Test
    fun aDeviceWithoutWidgetsNeitherCrashesNorWrites() {
        val center = WidgetCenter(context(widgets = false), inline)
        center.publish(snapshot())
        center.refresh()
        center.prepare()
        assertFalse(file.exists())
        assertEquals(snapshot(), center.feed.value.snapshot)
    }
}
