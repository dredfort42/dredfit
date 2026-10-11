//
//  The reminder after Android's own restore (auto backup): the state file
//  comes back with the switch ON, the permission may not — re-checked on the
//  first launch on the new device, exactly as after an import (owner
//  decision, 09.10.2026). Android-only: iOS has no restore of its own that
//  brings the file back without the app's import. The trigger — no device
//  mark beside the state file — is MainActivity's; ReminderDeniedTest drives
//  it on a device.
//

package com.dredfit

import com.dredfit.reminders.NotificationScheduling
import com.dredfit.store.DeviceMark
import com.dredfit.store.recheckRemindersOnANewDevice
import com.dredfit.store.rescheduleReminders
import com.dredfit.store.setReminderEnabled
import com.dredfit.workout.Words
import java.io.File
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class ReminderRestoreTest : AppStoreTestCase() {

    private class Phone(var grant: Boolean) : NotificationScheduling {
        var asked = 0
        val pending = mutableSetOf<String>()
        override fun requestAuthorization(answer: (Boolean) -> Unit) {
            asked += 1
            answer(grant)
        }
        override fun removePendingRequests(ids: List<String>) {
            pending.removeAll(ids.toSet())
        }
        override fun addReminder(id: String, title: String, body: Words, fireAt: Instant) {
            pending += id
        }
    }

    /** The old phone's state file, reminder on, as a restore puts it back. */
    private fun restoredOnto(phone: Phone) = run {
        makeStore(notifications = Phone(grant = true)).setReminderEnabled(true)
        makeStore(notifications = phone)
    }

    @Test
    fun onAPhoneThatRefusesTheRestoredReminderTurnsOffWithTheNote() {
        val phone = Phone(grant = false)
        val store = restoredOnto(phone)
        assertTrue(store.settings.reminderEnabled, "restored as it was")
        // The activation runs first and draws the window from the restored flag.
        store.rescheduleReminders()
        assertTrue(phone.pending.isNotEmpty())

        assertTrue(store.recheckRemindersOnANewDevice())
        assertEquals(1, phone.asked, "asked, as an import asks")
        assertFalse(store.settings.reminderEnabled, "never a switched-on reminder that cannot post")
        assertTrue(store.reminderRefused, "the denied note says why")
        assertTrue(phone.pending.isEmpty(), "and the window drawn from the restored flag is gone")
        assertFalse(makeStore().settings.reminderEnabled, "and the file says so for the next launch")
    }

    @Test
    fun onAPhoneThatAllowsItTheReminderStaysOnAndIsScheduled() {
        val phone = Phone(grant = true)
        val store = restoredOnto(phone)
        assertTrue(store.recheckRemindersOnANewDevice())
        assertTrue(store.settings.reminderEnabled)
        assertFalse(store.reminderRefused)
        assertTrue(phone.pending.isNotEmpty())
    }

    @Test
    fun aRestoredReminderThatWasOffAsksNothing() {
        val phone = Phone(grant = false)
        val store = makeStore(notifications = phone)
        assertTrue(store.recheckRemindersOnANewDevice())
        assertEquals(0, phone.asked, "nothing to check: no question out of nowhere")
        assertFalse(store.reminderRefused)
    }

    /** A journal that could not be read holds the empty state's settings:
     *  the check is not spent on it, so the next return makes it. */
    @Test
    fun aFrozenJournalLeavesTheCheckForLater() {
        assumeNotRoot()
        val phone = Phone(grant = false)
        restoredOnto(phone)
        setPermissions(tempPath, "---------")
        try {
            val frozen = makeStore(notifications = phone)
            assertFalse(frozen.recheckRemindersOnANewDevice(), "not run — the mark must not be written")
            assertEquals(0, phone.asked)
        } finally {
            setPermissions(tempPath, "rw-r--r--")
        }
    }

    /** The mark lives where a backup never reaches, under a name of its own. */
    @Test
    fun theMarkIsTheDevicesOwn() {
        val dir = File("/data/user/0/com.dredfit.dredfit/no_backup")
        assertEquals(File(dir, "state-seen-here"), DeviceMark.file(dir))
        assertNotEquals(com.dredfit.ongoing.NotificationAsk.mark(dir), DeviceMark.file(dir),
                        "not the ask's mark: a restore of a workout-asked phone is still a new device")
    }
}
