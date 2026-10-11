//
//  Port of ios/DredfitTests/HardeningTests.swift — the day anchor, the
//  cold-launch activation and the ten reminder tests (the spy answers at once,
//  where iOS awaits `reminderAuthTask`), plus seven Android-only ones: the
//  import's other two outcomes, the refusal cleared by a granted ask, the
//  rebuilds the activation, a rest-day toggle, a time change and a second
//  read make by themselves, and a settled workout rebuilding from now. `morningWorkoutRemovesThatDaysReminder` and
//  `eveningWorkoutKeepsWindowIntact` run on a pinned clock; the Swift store
//  has no clock seam, so the Swift twins date the morning workout tomorrow
//  and rebuild the evening one at its own hour instead.
//  `testStaleDateArithmetic` is not ported: a notification has no stale
//  state to dim into — the ongoing notification drops a countdown whose end
//  has passed instead (OngoingNotificationTest), and goes at the resume
//  window (WorkoutBeatTest).
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.journal.RecordedPosition
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.doneToday
import com.dredfit.store.nextSession
import com.dredfit.store.positions
import com.dredfit.store.refreshDay
import com.dredfit.reminders.NotificationScheduling
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.store.rescheduleReminders
import com.dredfit.store.setReminderEnabled
import com.dredfit.store.setReminderTime
import com.dredfit.store.swiftWeekday
import com.dredfit.store.toggleRestDay
import com.dredfit.workout.Words
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.nio.file.Path
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HardeningTest : AppStoreTestCase() {

    // MARK: - Day anchor

    /** Crossing midnight while the process stays alive must re-anchor the
     *  UI's "today" — the tab must not stay stuck on yesterday's done state. */
    @Test
    fun refreshDayReanchorsAcrossMidnight() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        assertTrue(store.doneToday)

        store.refreshDay(now = ZonedDateTime.now().plusDays(1).toInstant())
        assertFalse(store.doneToday, "the new day must not inherit yesterday's done state")

        // Same-day activations must not move the anchor (no pointless renders).
        val anchor = store.today
        store.refreshDay(now = anchor.plusSeconds(60))
        assertEquals(anchor, store.today, "a same-day refresh must be a no-op")
    }

    /** A workout run across midnight: only the time-change pulse moves the
     *  anchor — and it moves nothing but the date (the decay stays with
     *  `activate()`). */
    @Test
    fun aWorkoutFinishedPastMidnightReadsDoneOnceTheDateMoves() {
        val store = makeStore()
        val pastMidnight = ZonedDateTime.now().plusDays(1).toInstant()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = pastMidnight)
        assertFalse(store.doneToday, "the stale anchor still reads yesterday")
        val state = store.engineState
        store.reanchorToday(now = pastMidnight)
        assertTrue(store.doneToday)
        assertEquals(state, store.engineState, "re-anchoring must not touch the plan")
    }

    // MARK: - Cold-launch activation (issue #93)

    /** A journal whose last workout was `daysAgo` days ago — four workouts —
     *  and the positions they left: what a decay is measured against. */
    private fun seedWorkout(daysAgo: Long, at: Path): Map<Pattern, RecordedPosition> {
        val store = makeStore(at)
        val date = ZonedDateTime.now().minusDays(daysAgo).toInstant()
        repeat(4) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date) }
        return positions(store.engineState)
    }

    /** A decay is one rung of DOSE, and on a grid's floor a set instead — so
     *  what is claimed is "the plan moved, and it never moved up". */
    private fun assertDecayed(store: AppStore, seeded: Map<Pattern, RecordedPosition>, message: String) {
        var moved = false
        for (p in Pattern.allCases) {
            val was = seeded[p] ?: continue
            val before = Engine.progress(p, variation = was.variation, sets = was.sets, dose = was.dose)
            val now = Engine.progress(store.engineState, p)
            assertTrue(now <= before, "$p: $message")
            if (now < before) moved = true
        }
        assertTrue(moved, message)
    }

    /** A cold launch renders already active, so the phase transition never
     *  fires — `activate()` must run the blind-zone decay, or a 7–13-day
     *  return trains on the pre-break plan. */
    @Test
    fun coldLaunchActivationAppliesSilentDecay() {
        val seeded = seedWorkout(daysAgo = 10, at = tempPath)

        val cold = makeStore()
        cold.activate()
        assertDecayed(cold, seeded, "the cold launch must see the decay")

        val once = positions(cold.engineState)
        cold.activate()
        assertEquals(once, positions(cold.engineState), "a second activation in the same break must not decay again")

        val relaunched = makeStore()
        relaunched.activate()
        assertEquals(once, positions(relaunched.engineState),
                     "the stamp persists — a relaunch inside the break must not decay again")
    }

    @Test
    fun coldLaunchActivationLeavesGapsOutsideTheBlindZoneAlone() {
        for (days in listOf(6L, 14)) {
            val path = tempDir.resolve("gap$days.json")
            seedWorkout(daysAgo = days, at = path)
            val cold = makeStore(path)
            val before = cold.engineState
            cold.activate()
            assertEquals(before, cold.engineState, "gap $days: outside [7, 14) activation must not touch the engine")
        }
    }

    /** The seam's order matters: a launch that could not read its journal
     *  must reload first and decay after — the other way round the decay
     *  finds no journal and silently skips the break. */
    @Test
    fun activationReloadsBeforeDecaying() {
        assumeNotRoot()
        val seeded = seedWorkout(daysAgo = 10, at = tempPath)
        setPermissions(tempPath, "---------")
        val frozen = makeStore()
        setPermissions(tempPath, "rw-r--r--")

        frozen.activate()
        assertDecayed(frozen, seeded, "one activate() must both reload the journal and decay it")
    }

    // MARK: - Reminders (injectable scheduler)

    private data class ScheduledReminder(val id: String, val fireAt: Instant)

    private class NotificationSpy : NotificationScheduling {
        var grant = true
        val scheduled = mutableListOf<ScheduledReminder>()
        override fun requestAuthorization(answer: (Boolean) -> Unit) = answer(grant)
        override fun removePendingRequests(ids: List<String>) {
            scheduled.removeAll { it.id in ids }
        }
        override fun addReminder(id: String, title: String, body: Words, fireAt: Instant) {
            scheduled += ScheduledReminder(id, fireAt)
        }
    }

    /** A concrete moment `days` from today at the given local time — the
     *  tests pin `now` explicitly so they never depend on when the suite runs. */
    private fun moment(days: Long = 0, hour: Int, minute: Int = 0): Instant =
        LocalDate.now().plusDays(days).atTime(hour, minute).atZone(ZoneId.systemDefault()).toInstant()

    private fun local(at: Instant) = at.atZone(ZoneId.systemDefault())

    private fun slots(spy: NotificationSpy, sameDayAs: Instant): List<ScheduledReminder> =
        spy.scheduled.filter { local(it.fireAt).toLocalDate() == local(sameDayAs).toLocalDate() }

    @Test
    fun enablingReminderSchedulesWindowOfTrainingDays() {
        val spy = NotificationSpy()
        val store = makeStore(notifications = spy)
        store.setReminderTime(hour = 8, minute = 15)
        store.setReminderEnabled(true)
        store.rescheduleReminders(now = moment(hour = 6))   // before reminder time

        // default rest days are Monday (2), Wednesday (4) and Friday (6) —
        // any 28-day span holds exactly 4 of each, so 28 − 12
        assertEquals(16, spy.scheduled.size)
        assertTrue(spy.scheduled.size < 64, "must stay under the iOS pending cap")
        assertFalse(spy.scheduled.any { swiftWeekday(local(it.fireAt).dayOfWeek) in setOf(2, 4, 6) },
                    "no reminder on a rest day")
        assertEquals(spy.scheduled.size, spy.scheduled.map { local(it.fireAt).toLocalDate() }.toSet().size,
                     "every slot is a one-shot for a concrete date, not a weekly series")
        assertTrue(spy.scheduled.all { local(it.fireAt).hour == 8 && local(it.fireAt).minute == 15 })
    }

    /** The clock is pinned to the morning. On the real clock, after 20:00
     *  today's slot is already past, the assertion holds
     *  with no rule behind it, and dropping the done-day filter — or the
     *  rebuild after a completion — survived the mutation run (09.10.2026). */
    @Test
    fun morningWorkoutRemovesThatDaysReminder() {
        val spy = NotificationSpy()
        val store = makeStore(clock = Clock.fixed(moment(hour = 7), ZoneId.systemDefault()), notifications = spy)
        // Every day trains — no rest-day interference. Read off the current
        // default rather than naming weekdays: named, they would turn this
        // into a rest-day fixture the moment the default moves.
        for (wd in store.settings.restWeekdays) store.toggleRestDay(wd)
        store.setReminderTime(hour = 20, minute = 0)
        store.setReminderEnabled(true)

        val morning = moment(hour = 7)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = morning)

        assertTrue(slots(spy, sameDayAs = morning).isEmpty(),
                   "a workout done before the reminder time must take today's slot down")
        val tomorrow = local(morning).plusDays(1).toInstant()
        assertFalse(slots(spy, sameDayAs = tomorrow).isEmpty(), "tomorrow's reminder must survive today's workout")
        assertEquals(27, spy.scheduled.size)   // 28-day window minus done today
    }

    /** Trained after the reminder already fired: nothing to cancel, and the
     *  rebuild must not schedule a new slot into today's past. */
    @Test
    fun eveningWorkoutKeepsWindowIntact() {
        val spy = NotificationSpy()
        val store = makeStore(clock = Clock.fixed(moment(hour = 21), ZoneId.systemDefault()), notifications = spy)
        for (wd in store.settings.restWeekdays) store.toggleRestDay(wd)   // as above
        store.setReminderTime(hour = 9, minute = 0)
        store.setReminderEnabled(true)

        val evening = moment(hour = 21)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = evening)

        assertTrue(slots(spy, sameDayAs = evening).isEmpty(), "no slot may be scheduled into today's past")
        val tomorrow = local(evening).plusDays(1).toInstant()
        assertFalse(slots(spy, sameDayAs = tomorrow).isEmpty())
    }

    @Test
    fun toggleRestDayReschedulesReminders() {
        val spy = NotificationSpy()
        val store = makeStore(notifications = spy)
        store.setReminderEnabled(true)

        store.toggleRestDay(3)   // Tuesday joins the default Mon+Wed+Fri
        store.rescheduleReminders(now = moment(hour = 6))
        assertEquals(12, spy.scheduled.size)   // 28 minus 4 each of Mon, Tue, Wed, Fri
        assertFalse(spy.scheduled.any { swiftWeekday(local(it.fireAt).dayOfWeek) == 3 },
                    "a stale Tuesday reminder must not survive the toggle")
    }

    @Test
    fun legacyWeeklySeriesIsClearedOnReschedule() {
        val spy = NotificationSpy()
        val store = makeStore(notifications = spy)
        spy.scheduled += ScheduledReminder("reminder-wd-3", Instant.EPOCH)

        store.rescheduleReminders(now = moment(hour = 6))
        assertTrue(spy.scheduled.isEmpty(), "the pre-1.8 weekly series must be removed and nothing added while disabled")
    }

    /** A relaunch rebuilds the window on activation, and a time change moves
     *  every slot — the schedule never drifts from the settings. */
    @Test
    fun windowSurvivesRestartAndTimeChange() {
        val first = makeStore(notifications = NotificationSpy())
        first.setReminderEnabled(true)

        val spy = NotificationSpy()
        val relaunched = makeStore(notifications = spy)
        relaunched.rescheduleReminders(now = moment(hour = 6))   // the activation path
        assertEquals(16, spy.scheduled.size, "a restart must rebuild the full window")

        relaunched.setReminderTime(hour = 7, minute = 45)
        relaunched.rescheduleReminders(now = moment(hour = 6))
        assertTrue(spy.scheduled.all { local(it.fireAt).hour == 7 && local(it.fireAt).minute == 45 },
                   "a time change must move every slot in the window")
    }

    @Test
    fun disablingReminderClearsEverything() {
        val spy = NotificationSpy()
        val store = makeStore(notifications = spy)
        store.setReminderEnabled(true)
        assertFalse(spy.scheduled.isEmpty())

        store.setReminderEnabled(false)
        assertTrue(spy.scheduled.isEmpty(), "disabling must remove every pending reminder")
    }

    @Test
    fun frozenLaunchKeepsThePendingReminderWindow() {
        assumeNotRoot()
        val spy = NotificationSpy()
        val seed = makeStore(notifications = spy)
        seed.setReminderEnabled(true)
        val pending = spy.scheduled.size
        assertTrue(pending > 0)

        setPermissions(tempPath, "---------")
        try {
            val frozen = makeStore(notifications = spy)
            frozen.rescheduleReminders()
            assertEquals(pending, spy.scheduled.size, "a frozen launch must not clear the reminders it cannot see")

            setPermissions(tempPath, "rw-r--r--")
            frozen.reloadIfNeeded()
            frozen.rescheduleReminders()
            assertEquals(pending, spy.scheduled.size, "the window is rebuilt once the journal is readable again")
        } finally {
            setPermissions(tempPath, "rw-r--r--")
        }
    }

    @Test
    fun reminderDenialFlipsToggleOff() {
        val spy = NotificationSpy()
        spy.grant = false
        val store = makeStore(notifications = spy)
        store.setReminderEnabled(true)
        assertFalse(store.settings.reminderEnabled, "denial must be reflected in the toggle")
        assertTrue(spy.scheduled.isEmpty())
        // Android: the store keeps the refusal for the note under the switch.
        assertTrue(store.reminderRefused, "the refusal must name itself")
    }

    /** A backup restored onto a device that never granted notifications must
     *  not let the imported reminderEnabled flag survive a denied
     *  authorization — and on Android the denied note says why, rather than
     *  the switch going quietly off (owner decision, 09.10.2026). */
    @Test
    fun importWithRemindersRerunsAuthorization() {
        val sourceSpy = NotificationSpy()
        val source = makeStore(notifications = sourceSpy)
        source.setReminderEnabled(true)
        val backup = source.exportBackup()

        val spy = NotificationSpy()
        spy.grant = false
        val fresh = makeStore(path = tempDir.resolve("dredfit-import.json"), notifications = spy)
        fresh.importBackup(backup)

        assertFalse(fresh.settings.reminderEnabled, "an imported reminderEnabled must not survive a denied authorization")
        assertTrue(spy.scheduled.isEmpty())
        assertTrue(fresh.reminderRefused, "the denied state must show, not a switch that quietly went off")
    }

    // Android-only: the other two ways out of an import.

    @Test
    fun importWithRemindersOnAGrantingPhoneKeepsTheFlagAndSchedules() {
        val source = makeStore(notifications = NotificationSpy())
        source.setReminderEnabled(true)
        val backup = source.exportBackup()

        val spy = NotificationSpy()
        val fresh = makeStore(path = tempDir.resolve("dredfit-import.json"), notifications = spy)
        fresh.importBackup(backup)

        assertTrue(fresh.settings.reminderEnabled, "the imported flag is kept as it came")
        assertFalse(spy.scheduled.isEmpty(), "and the window is drawn on this phone")
        assertFalse(fresh.reminderRefused)
    }

    @Test
    fun importWithoutRemindersClearsWhatThisPhoneHadPending() {
        val backup = makeStore(path = tempDir.resolve("source.json"), notifications = NotificationSpy()).exportBackup()
        val spy = NotificationSpy()
        val store = makeStore(notifications = spy)
        store.setReminderEnabled(true)
        assertFalse(spy.scheduled.isEmpty())

        store.importBackup(backup)
        assertFalse(store.settings.reminderEnabled)
        assertTrue(spy.scheduled.isEmpty(), "the imported OFF must clear the window left behind")
    }

    /** Android-only: the switch clears a refusal, so the note never outlives
     *  a fresh answer. */
    @Test
    fun aGrantedSecondAskClearsTheRefusal() {
        val spy = NotificationSpy()
        spy.grant = false
        val store = makeStore(notifications = spy)
        store.setReminderEnabled(true)
        assertTrue(store.reminderRefused)
        spy.grant = true
        store.setReminderEnabled(true)
        assertFalse(store.reminderRefused)
        assertTrue(store.settings.reminderEnabled)
        assertFalse(spy.scheduled.isEmpty())
    }

    /** Android-only: the writes rebuild the window BY THEMSELVES. The Swift
     *  tests call the rebuild by hand after a rest-day toggle and a time
     *  change, so a write that forgot it passed them (mutation run,
     *  09.10.2026); here the clock is pinned and nothing is called by hand. */
    @Test
    fun aRestDayToggleAndATimeChangeRebuildTheWindowByThemselves() {
        val spy = NotificationSpy()
        val store = makeStore(clock = Clock.fixed(moment(hour = 6), ZoneId.systemDefault()), notifications = spy)
        store.setReminderEnabled(true)
        assertEquals(16, spy.scheduled.size)

        store.toggleRestDay(3)
        assertEquals(12, spy.scheduled.size, "Tuesday's slots go with the toggle")

        store.setReminderTime(hour = 7, minute = 45)
        assertTrue(spy.scheduled.all { local(it.fireAt).hour == 7 && local(it.fireAt).minute == 45 },
                   "every slot moves with the time")
    }

    /** Android-only: a journal read on the second try rebuilds the window
     *  from what it holds, as `reloadIfNeeded` does on iOS. */
    @Test
    fun aJournalReadOnTheSecondTryRebuildsTheWindow() {
        assumeNotRoot()
        val spy = NotificationSpy()
        // One pinned clock for both rebuilds, so the counts compare.
        val clock = Clock.fixed(moment(hour = 6), ZoneId.systemDefault())
        makeStore(clock = clock, notifications = spy).setReminderEnabled(true)
        val pending = spy.scheduled.size
        setPermissions(tempPath, "---------")
        try {
            val frozen = makeStore(clock = clock, notifications = spy)
            spy.scheduled.clear()   // a window lost meanwhile (a reboot, a removal)
            setPermissions(tempPath, "rw-r--r--")
            frozen.reloadIfNeeded()
            assertEquals(pending, spy.scheduled.size, "the reload itself rebuilds it")
        } finally {
            setPermissions(tempPath, "rw-r--r--")
        }
    }

    /** Android-only: a workout settled on a later day (dated to yesterday)
     *  rebuilds from NOW, not from its date — scheduled from yesterday,
     *  today's 09:00, already gone, would pass the `fire > now` guard, and an
     *  alarm in the past fires at once. iOS's comment names the rule; no
     *  Swift test holds it (skeptic finding, 09.10.2026). */
    @Test
    fun aWorkoutDatedYesterdayRebuildsFromNow() {
        val spy = NotificationSpy()
        val now = moment(hour = 10)
        val store = makeStore(clock = Clock.fixed(now, ZoneId.systemDefault()), notifications = spy)
        for (wd in store.settings.restWeekdays) store.toggleRestDay(wd)
        store.setReminderTime(hour = 9, minute = 0)
        store.setReminderEnabled(true)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              date = local(now).minusDays(1).toInstant())
        assertTrue(slots(spy, sameDayAs = now).isEmpty(), "today's 09:00 is gone at 10:00")
        assertEquals(27, spy.scheduled.size)
    }

    /** Android-only: the activation rebuilds the window — the iOS sequence's
     *  last step, which the Swift tests drive by calling the rebuild by hand. */
    @Test
    fun activationRebuildsTheWindow() {
        val spy = NotificationSpy()
        val store = makeStore(notifications = spy)
        store.setReminderEnabled(true)
        spy.scheduled.clear()
        store.activate(now = moment(hour = 6))
        assertEquals(16, spy.scheduled.size)
    }
}
