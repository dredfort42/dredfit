//
//  The training reminder on a device, POST_NOTIFICATIONS granted (as the
//  whole suite has it — DredfitUITest.launch): the switch draws the window
//  of alarms the system then holds, a fired alarm posts iOS's words on the
//  reminder's channel with its generated sound, a tap opens Today, the alarm
//  really fires at its minute, and a clock or zone change rebuilds a window
//  that was lost. The refused paths need a permission never granted, so they
//  run alone (ReminderDeniedTest).
//
//  A reboot cannot be sent from here: BOOT_COMPLETED is a protected
//  broadcast, refused to the shell and to the app ("Permission Denial: not
//  allowed to send broadcast", user build, API 37). The same receiver and the
//  same rebuild answer TIME_SET and TIMEZONE_CHANGED, which `cmd alarm` makes
//  the SYSTEM send; the boot itself was checked by rebooting the emulator
//  (android/CLAUDE.md, Verified facts).
//

package com.dredfit

import android.app.NotificationChannel
import android.app.NotificationManager
import android.util.Log
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.onNodeWithTag
import androidx.core.app.NotificationCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import com.dredfit.reminders.ReminderChannel
import com.dredfit.reminders.ReminderScheduler
import com.dredfit.reminders.SystemNotificationScheduler
import com.dredfit.store.DeviceMark
import com.dredfit.store.setReminderEnabled
import com.dredfit.store.setReminderTime
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.time.ZoneId
import java.time.ZonedDateTime

@RunWith(AndroidJUnit4::class)
class ReminderTest : ReminderTestCase() {

    private var zoneToRestore: String? = null

    @After
    fun leaveNothingBehind() {
        zoneToRestore?.let { shell("cmd alarm set-timezone $it") }
        clearReminders()
    }

    @Test
    fun theSwitchDrawsTheWindowTheSystemHoldsAndTakesItDown() {
        launch(Seed.Clean, fast = false)
        tap(AX.settings)
        tap(TAG_TOGGLE)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOn()
        await(TAG_TIME)
        assertFalse("granted: no denied note", exists(TAG_DENIED))

        val expected = expectedSlots(hour = 9, minute = 0)
        assertTrue("the app holds the window", awaitTrue { pendingIds().size == expected })
        assertTrue("every id is a day slot of the window",
                   pendingIds().all { it.startsWith(ReminderScheduler.DAY_PREFIX) })
        assertEquals("and the system holds the same alarms", expected, systemAlarms().size)
        // Inexact: the system's own window for each (android/README.md).
        Log.i("ReminderTest", "system window per reminder alarm: ${systemAlarmWindow()}")

        tap(TAG_TOGGLE)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOff()
        assertTrue("off takes every alarm down", awaitTrue { pendingIds().isEmpty() })
        assertEquals(0, systemAlarms().size)
        assertFalse("the time row goes with the switch", exists(TAG_TIME))
    }

    /** What the alarm fires is the app's own PendingIntent: sent here, it is
     *  exactly the alarm going off. */
    @Test
    fun aFiredReminderSaysWhatIOSSaysOnItsChannelAndATapOpensToday() {
        launch(Seed.Clean, fast = false)
        // Today's slot, a few minutes ahead, fired early by hand: the alarm
        // checks its day, not its minute.
        val at = ZonedDateTime.now().plusMinutes(3)
        onStore {
            setReminderTime(at.hour, at.minute)
            setReminderEnabled(true)
        }
        val manager = app.getSystemService(NotificationManager::class.java)
        // A channel of an older sound version, left by an earlier build.
        manager.createNotificationChannel(NotificationChannel("reminder-v0", "Reminder", NotificationManager.IMPORTANCE_DEFAULT))

        // Another day's slot fired today (an alarm an hour late across
        // midnight) says nothing.
        checkNotNull(pendingIntent(pendingIds().last())) { "no alarm for the last day" }.send()
        Thread.sleep(2_000)
        assertNull("another day's reminder is dropped", reminder())

        val id = "${ReminderScheduler.DAY_PREFIX}0"
        checkNotNull(pendingIntent(id)) { "no alarm for $id" }.send()

        assertTrue("the reminder is posted", awaitTrue { reminder() != null })
        val posted = reminder()!!
        assertEquals("Dredfit", posted.extras.getCharSequence(NotificationCompat.EXTRA_TITLE).toString())
        assertEquals("Today's workout is ready", posted.extras.getCharSequence(NotificationCompat.EXTRA_TEXT).toString())
        assertEquals(ReminderChannel.id(branded = true), posted.channelId)
        assertEquals(NotificationCompat.CATEGORY_REMINDER, posted.category)

        assertNull("the older version's channel is deleted", manager.getNotificationChannel("reminder-v0"))
        val channel = manager.getNotificationChannel(posted.channelId)
        assertEquals("Reminder", channel.name.toString())
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channel.importance)
        assertEquals("the generated tone, through the FileProvider",
                     "content://${app.packageName}.share/sounds/dredfit_reminder_v1.wav", channel.sound.toString())
        // The system took the URI: a sound it cannot open is replaced with
        // the default one in the posted record ("Replacing … from").
        val record = shell("dumpsys notification --noredact").lines()
            .dropWhile { !it.contains("id=${SystemNotificationScheduler.NOTIFICATION_ID}") || !it.contains(app.packageName) }
            .take(200).filter { it.contains("ound") || it.contains("NotificationRecord") || it.contains("ttention") }.joinToString("\n")
        assertTrue("the posted record keeps the branded sound:\n$record", record.contains("dredfit_reminder_v1.wav"))

        // Away from Today, Settings open over it, then the tap.
        tap(AX.tab("calendar"))
        tap(AX.settings)
        await(AX.settingsDone)
        posted.contentIntent.send()
        awaitStage(Stage.RESUMED)
        compose.waitUntil(10_000) { !exists(AX.settingsDone) }
        compose.waitUntil(10_000) {
            runCatching { compose.onNodeWithTag(AX.tab("today")).assertIsSelected() }.isSuccess
        }
    }

    /** The alarm itself, at its minute: inexact, so the test allows the
     *  minutes Android may take — never an hour, on an idle emulator. */
    @Test
    fun theAlarmItselfPostsTheReminder() {
        launch(Seed.Clean, fast = false)
        // A minute boundary 70–130 s ahead: the slot cannot already be gone.
        val at = ZonedDateTime.now().plusSeconds(130).withSecond(0).withNano(0)
        onStore {
            setReminderTime(at.hour, at.minute)
            setReminderEnabled(true)
        }
        assertTrue(pendingIds().isNotEmpty())
        assertTrue("the alarm posted the reminder", awaitTrue(timeoutMs = 6 * 60_000L) { reminder() != null })
        val late = System.currentTimeMillis() - at.toInstant().toEpochMilli()
        assertTrue("never before its time (${late} ms)", late >= 0)
        Log.i("ReminderTest", "the alarm posted the reminder $late ms after its minute")
        assertEquals("Today's workout is ready",
                     reminder()!!.extras.getCharSequence(NotificationCompat.EXTRA_TEXT).toString())
    }

    /** The window lost (what a reboot does to every alarm), then a zone
     *  change the SYSTEM broadcasts: the manifest receiver rebuilds it from
     *  the store, at 09:00 on the new wall; then the same through TIME_SET. */
    @Test
    fun aZoneOrClockChangeRebuildsALostWindow() {
        launch(Seed.Clean, fast = false)
        onStore { setReminderEnabled(true) }
        assertTrue(pendingIds().isNotEmpty())

        zoneToRestore = ZoneId.systemDefault().id
        val other = if (zoneToRestore == "Asia/Tokyo") "America/New_York" else "Asia/Tokyo"
        app.reminders.removePendingRequests(ReminderScheduler.ids)
        assertTrue(pendingIds().isEmpty())
        shell("cmd alarm set-timezone $other")
        assertTrue("TIMEZONE_CHANGED rebuilt the window",
                   awaitTrue(timeoutMs = 90_000) { pendingIds().size == expectedSlots(9, 0, ZoneId.of(other)) })
        assertEquals(expectedSlots(9, 0, ZoneId.of(other)), systemAlarms().size)

        app.reminders.removePendingRequests(ReminderScheduler.ids)
        assertTrue(pendingIds().isEmpty())
        // A clock moved by a minute and back: the system broadcasts TIME_SET
        // only when the clock really moves. 90 s, because a system broadcast
        // to a manifest receiver queues behind others: after the whole suite
        // TIME_SET missed a 20 s wait, and BOOT_COMPLETED arrived 34 s after
        // the boot (android/CLAUDE.md).
        val moved = System.currentTimeMillis()
        shell("cmd alarm set-time ${moved + 60_000}")
        shell("cmd alarm set-time ${System.currentTimeMillis() - 60_000}")
        assertTrue("TIME_SET rebuilt the window", awaitTrue(timeoutMs = 90_000) { pendingIds().isNotEmpty() })
    }

    /** Android's own restore onto a phone that allows notifications: the
     *  first launch (no device mark) re-checks, the reminder stays on, and
     *  the window is drawn. ReminderDeniedTest has the refusing phone. */
    @Test
    fun aRestoredReminderOnAnAllowingPhoneStaysOn() {
        launch(Seed.Clean, fast = false)
        onStore { setReminderEnabled(true) }
        val mark = DeviceMark.file(app.noBackupFilesDir)
        assertTrue(mark.exists())
        clearReminders()
        assertTrue(mark.delete())
        relaunchFromDisk()
        assertTrue("the check ran", awaitTrue(timeoutMs = 10_000) { mark.exists() })
        assertTrue(readStore { settings.reminderEnabled })
        assertTrue("the window is drawn", awaitTrue { pendingIds().size == expectedSlots(9, 0) })
        tap(AX.settings)
        await(TAG_TIME)
        assertFalse(exists(TAG_DENIED))
    }

    companion object {
        const val TAG_TOGGLE = "reminder-toggle"
        const val TAG_TIME = "reminder-time"
        const val TAG_DENIED = "reminder-denied"
        const val TAG_OPEN_SETTINGS = "reminder-open-settings"
    }
}
