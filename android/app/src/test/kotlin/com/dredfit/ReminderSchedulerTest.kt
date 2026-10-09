//
//  Port of ios/DredfitTests/ReminderSchedulerTests.swift — the reminder
//  window on its own: what is removed, what is added, and which days are left
//  out — all four Swift tests. The rest are Android-only: an alarm is an
//  INSTANT where an iOS calendar trigger is a wall time, so the instant each
//  wall time becomes has to be right across a DST change, a skipped and a
//  repeated hour, and a zone change (which ReminderRescheduleReceiver turns
//  into a rebuild).
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.reminders.NotificationScheduling
import com.dredfit.reminders.ReminderScheduler
import com.dredfit.store.nextSession
import com.dredfit.store.rescheduleReminders
import com.dredfit.store.setReminderEnabled
import com.dredfit.store.swiftWeekday
import com.dredfit.workout.Words
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReminderSchedulerTest : AppStoreTestCase() {

    private class Pending : NotificationScheduling {
        val ids = mutableListOf<String>()
        val at = mutableMapOf<String, Instant>()
        val removed = mutableListOf<List<String>>()
        val bodies = mutableListOf<Words>()
        override fun requestAuthorization(answer: (Boolean) -> Unit) = answer(true)
        override fun removePendingRequests(ids: List<String>) {
            removed += ids
            this.ids.removeAll { it in ids }
        }
        override fun addReminder(id: String, title: String, body: Words, fireAt: Instant) {
            ids += id
            at[id] = fireAt
            bodies += body
        }
    }

    private val zone: ZoneId = ZoneId.systemDefault()

    /** 10:00 today, so a 09:00 slot today has already passed and an 11:00
     *  one has not. */
    private val tenToday: Instant get() = LocalDate.now(zone).atTime(10, 0).atZone(zone).toInstant()

    @Test
    fun theWholeWindowIsRebuiltFromScratch() {
        val pending = Pending()
        pending.ids += listOf("reminder-wd-3", "reminder-day-5")
        ReminderScheduler(pending).reschedule(enabled = true, hour = 11, minute = 0, now = tenToday, zone = zone,
                                              remindsOn = { true })
        assertEquals(1, pending.removed.size)
        assertTrue("reminder-wd-3" in pending.removed.first(), "the old weekly series is still cleared")
        assertEquals(ReminderScheduler.WINDOW_DAYS, pending.ids.size)
    }

    @Test
    fun aSlotThatAlreadyPassedTodayIsLeftOut() {
        val pending = Pending()
        ReminderScheduler(pending).reschedule(enabled = true, hour = 9, minute = 0, now = tenToday, zone = zone,
                                              remindsOn = { true })
        assertFalse("reminder-day-0" in pending.ids, "it would never fire, and sit in the list")
        assertEquals(ReminderScheduler.WINDOW_DAYS - 1, pending.ids.size)
    }

    @Test
    fun onlyTheDaysTheRuleAcceptsGetOne() {
        val pending = Pending()
        val today = LocalDate.now(zone)
        ReminderScheduler(pending).reschedule(enabled = true, hour = 11, minute = 0, now = tenToday, zone = zone,
                                              remindsOn = { it.atZone(zone).toLocalDate() != today })
        assertFalse("reminder-day-0" in pending.ids)
        assertTrue("reminder-day-1" in pending.ids)
    }

    @Test
    fun switchedOffItOnlyRemoves() {
        val pending = Pending()
        pending.ids += "reminder-day-0"
        ReminderScheduler(pending).reschedule(enabled = false, hour = 11, minute = 0, now = tenToday, zone = zone,
                                              remindsOn = { true })
        assertTrue(pending.ids.isEmpty())
    }

    // MARK: - Android-only: the instant behind each wall time

    private val berlin: ZoneId = ZoneId.of("Europe/Berlin")

    private fun berlin(y: Int, m: Int, d: Int, h: Int, min: Int = 0): Instant =
        LocalDateTime.of(y, m, d, h, min).atZone(berlin).toInstant()

    private fun windowFrom(now: Instant, hour: Int, minute: Int = 0, zone: ZoneId = berlin): Pending =
        Pending().also {
            ReminderScheduler(it).reschedule(enabled = true, hour = hour, minute = minute, now = now, zone = zone,
                                             remindsOn = { true })
        }

    /** The day before Berlin springs forward (29.03.2026) and the day after:
     *  09:00 on the wall both times — 08:00Z, then 07:00Z. */
    @Test
    fun acrossTheSpringForwardTheWallTimeStays() {
        val pending = windowFrom(now = berlin(2026, 3, 28, 6), hour = 9)
        assertEquals(Instant.parse("2026-03-28T08:00:00Z"), pending.at["reminder-day-0"])
        assertEquals(Instant.parse("2026-03-29T07:00:00Z"), pending.at["reminder-day-1"])
        assertTrue(pending.at.values.all { it.atZone(berlin).hour == 9 && it.atZone(berlin).minute == 0 },
                   "every slot of the window at 09:00 Berlin time")
        assertEquals(ReminderScheduler.WINDOW_DAYS, pending.ids.size)
    }

    /** …and back in autumn (25.10.2026): 07:00Z the day before, 08:00Z after. */
    @Test
    fun acrossTheFallBackTheWallTimeStays() {
        val pending = windowFrom(now = berlin(2026, 10, 24, 6), hour = 9)
        assertEquals(Instant.parse("2026-10-24T07:00:00Z"), pending.at["reminder-day-0"])
        assertEquals(Instant.parse("2026-10-25T08:00:00Z"), pending.at["reminder-day-1"])
    }

    /** 02:30 does not exist on 29.03.2026 in Berlin: the slot fires as late
     *  as the gap, 03:30 CEST — one slot that day, not none. */
    @Test
    fun aTimeTheSpringForwardSkipsFiresAsLateAsTheGap() {
        val pending = windowFrom(now = berlin(2026, 3, 28, 6), hour = 2, minute = 30)
        assertEquals(Instant.parse("2026-03-29T01:30:00Z"), pending.at["reminder-day-1"])
        assertEquals(ReminderScheduler.WINDOW_DAYS - 1, pending.ids.size, "only the 28th's own 02:30, already gone, is left out")
    }

    /** 02:30 happens twice on 25.10.2026 in Berlin: one slot, at the first —
     *  the moment the clock first shows the time. */
    @Test
    fun aTimeTheFallBackRepeatsFiresOnceAtItsFirstOccurrence() {
        val pending = windowFrom(now = berlin(2026, 10, 24, 6), hour = 2, minute = 30)
        assertEquals(Instant.parse("2026-10-25T00:30:00Z"), pending.at["reminder-day-1"])
        assertEquals(1, pending.at.values.count { it.atZone(berlin).toLocalDate() == LocalDate.of(2026, 10, 25) })
    }

    /** A zone change rebuilds the window (the receiver), and the rebuild puts
     *  09:00 on the NEW wall: the same ids, other instants. */
    @Test
    fun aZoneChangeMovesEverySlotToTheNewWallTime() {
        val now = Instant.parse("2026-06-10T03:00:00Z")   // 05:00 Berlin, 12:00 Tokyo
        val tokyo = ZoneId.of("Asia/Tokyo")
        val before = windowFrom(now = now, hour = 9, zone = berlin)
        val after = windowFrom(now = now, hour = 9, zone = tokyo)
        assertTrue(after.at.values.all { it.atZone(tokyo).hour == 9 }, "every slot at 09:00 in the new zone")
        assertFalse("reminder-day-0" in after.ids, "09:00 Tokyo has already passed at 12:00 Tokyo")
        assertTrue("reminder-day-0" in before.ids, "09:00 Berlin is still ahead at 05:00 Berlin")
        assertEquals(Instant.parse("2026-06-11T00:00:00Z"), after.at["reminder-day-1"])
    }

    /** The rule is asked about each day's START in the zone — the instant
     *  `isRestDay` and `isDone` read a calendar day off. */
    @Test
    fun theRuleIsAskedAboutEachDaysStartInTheZone() {
        val asked = mutableListOf<Instant>()
        ReminderScheduler(Pending()).reschedule(enabled = true, hour = 9, minute = 0, now = berlin(2026, 3, 28, 6),
                                                zone = berlin, remindsOn = { asked += it; true })
        assertEquals(ReminderScheduler.WINDOW_DAYS, asked.size)
        assertTrue(asked.all { it.atZone(berlin).toLocalTime().toSecondOfDay() == 0 }, "midnights, DST day included")
        assertEquals(berlin(2026, 3, 29, 0), asked[1])
    }

    @Test
    fun theReminderSaysWhatIOSSays() {
        val pending = windowFrom(now = berlin(2026, 3, 28, 6), hour = 9)
        assertTrue(pending.bodies.all { it == Words.of("Today's workout is ready") })
        assertEquals("Dredfit", ReminderScheduler.TITLE)
    }

    /** Through the store, on a pinned Berlin clock: rest weekdays read in
     *  the trainee's zone, the done day by the journal — at 23:30 UTC on a
     *  Sunday it is already Monday (a default rest day) in Berlin. */
    @Test
    fun theStoreAsksItsRuleInTheTraineesZone() {
        val now = Instant.parse("2026-06-14T23:30:00Z")   // Sun 23:30 UTC = Mon 01:30 Berlin
        val pending = Pending()
        val store = makeStore(clock = Clock.fixed(now, berlin), notifications = pending)
        store.setReminderEnabled(true)
        store.rescheduleReminders(now = now)
        assertFalse("reminder-day-0" in pending.ids, "Monday in Berlin is a rest day")
        assertTrue(pending.at.values.none { swiftWeekday(it.atZone(berlin).dayOfWeek) in setOf(2, 4, 6) })
        assertEquals(16, pending.ids.size)

        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = now)
        store.rescheduleReminders(now = now)
        assertEquals(16, pending.ids.size, "a workout on a rest day takes no training day's slot")
        val tuesday = ZonedDateTime.of(2026, 6, 16, 9, 0, 0, 0, berlin).toInstant()
        assertEquals(tuesday, pending.at["reminder-day-1"])
    }
}
