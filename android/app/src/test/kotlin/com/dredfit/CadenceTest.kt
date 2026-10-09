//
//  Port of ios/DredfitTests/CadenceTests.swift: the trainee's own rhythm is
//  not a break, and a training day is a calendar day in the local zone.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.SwiftJson
import com.dredfit.store.AppStore
import com.dredfit.store.gapDays
import com.dredfit.store.gapFraction
import com.dredfit.store.isRhythmBreak
import com.dredfit.store.nextSession
import com.dredfit.store.recentGaps
import com.dredfit.store.shouldOfferComeback
import com.dredfit.store.trainingDays
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CadenceTest : AppStoreTestCase() {

    private val zone: ZoneId = ZoneId.systemDefault()

    /** A fixed Monday (01.06.2026) plus `day`, at the given local time — every
     *  date here is deterministic no matter when the suite runs. */
    private fun date(day: Long, hour: Int = 12, minute: Int = 0): Instant =
        ZonedDateTime.of(2026, 6, 1, hour, minute, 0, 0, zone).plusDays(day).toInstant()

    /**
     * Seeded through the storage file, in the v3 shape — `vars` and `doses`,
     * no `levels` — so it loads as written rather than through the v2
     * migration: a seed the store silently replaced would make every assertion
     * below true for the wrong reason. The journal of what was shown is filled
     * in too: a descent out of a variation lands under it.
     */
    private fun store(workoutsAt: List<Instant>): AppStore {
        val dates = workoutsAt
        val records = dates.withIndex().joinToString(",") { (i, d) ->
            "{\"sessionNumber\":${i + 1},\"date\":${SwiftJson.sinceReference(d)}," +
                "\"result\":\"plan\",\"totalProgressAfter\":100}"
        }
        val store = storeFrom("""
            {"engineState":{"counter":${dates.size},"vars":[${pairs { 2 }}],"doses":[${pairs { SEEDED_DOSE }}],
                            "shown":[${pairs { "{\"1\":$SEEDED_DOSE,\"2\":$SEEDED_DOSE}" }}],"failStreak":[${pairs { 0 }}]},
             "records":[$records],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
        assertEquals(SEEDED_DOSE, store.engineState.doses[Pattern.pull],
                     "the seed must actually load — a state that failed to decode " +
                         "would start clean and make every assertion here vacuous")
        return store
    }

    private fun AppStore.pullDose() = engineState.doses[Pattern.pull]

    // MARK: - The training day (#147)

    /** CALENDAR days in the local zone, not whole elapsed 24-hour periods:
     *  elapsed-hours arithmetic reads Monday 23:00 → Tuesday 01:00 as ZERO. */
    @Test
    fun trainingDaysAreCalendarDays() {
        val start = date(day = 0, hour = 23)
        assertEquals(1, trainingDays(start, start.plusSeconds(2 * 3600), zone),
                     "23:00 Monday and 01:00 Tuesday are two different days")
        assertEquals(0, trainingDays(date(day = 0, hour = 0, minute = 30), date(day = 0, hour = 23, minute = 30), zone),
                     "almost a whole day inside one date is still no day at all")
        assertEquals(7, trainingDays(start, start.plusSeconds(7 * 86400), zone))
        assertEquals(20, trainingDays(date(day = 0, hour = 9), date(day = 20, hour = 9), zone),
                     "daytime training is counted as before")
        assertEquals(0, trainingDays(start, start.minusSeconds(3600), zone),
                     "a clock set backwards never yields a negative gap")
    }

    /** The autumn clock change makes one day 25 hours long and the spring one
     *  23. The zone is named — the test must not depend on the runner's. */
    @Test
    fun theClockChangeNeitherAddsNorEatsADay() {
        val berlin = ZoneId.of("Europe/Berlin")
        fun at(m: Int, d: Int) = ZonedDateTime.of(2026, m, d, 22, 0, 0, 0, berlin).toInstant()
        // 25.10.2026, 03:00 -> 02:00. Evening before to evening after.
        assertEquals(1, trainingDays(at(10, 24), at(10, 25), berlin), "the 25-hour day is exactly one day")
        // 29.03.2026, 02:00 -> 03:00 — the 23-hour day.
        assertEquals(1, trainingDays(at(3, 28), at(3, 29), berlin), "and so is the 23-hour one")
    }

    /** A flight west can put the later workout on an EARLIER local date; the
     *  gap is clamped at zero either way. */
    @Test
    fun aZoneChangeBetweenSessionsNeverGoesNegative() {
        val honolulu = ZoneId.of("Pacific/Honolulu")
        // Trained in Tokyo on the morning of the 2nd, then "the same evening"
        // in Honolulu — still the 1st there.
        val inTokyo = ZonedDateTime.of(2026, 6, 2, 9, 0, 0, 0, ZoneId.of("Asia/Tokyo")).toInstant()
        val afterFlight = inTokyo.plusSeconds(4 * 3600)
        assertEquals(0, trainingDays(inTokyo, afterFlight, honolulu), "a westward flight must not produce a negative gap")
        assertEquals(0, trainingDays(afterFlight, inTokyo, honolulu), "and neither must reading the journal backwards")
    }

    /** A true 6.0-day cadence drifting 23:00 <-> 01:00 reads 7/5 under
     *  calendar days; what keeps it out of the decay is the rhythm detector.
     *  The price is one decay on the FIRST such gap, before any rhythm exists. */
    @Test
    fun shiftWorkerRitualIsCarriedByTheRhythmNotByTheDayCount() {
        val dates = mutableListOf(date(day = 0, hour = 23))
        for (i in 0 until 4) {
            val drift = if (i % 2 == 0) 2L * 3600 else -2L * 3600
            dates += dates.last().plusSeconds(6 * 86400 + drift)
        }
        val s = store(workoutsAt = dates)
        // Five records, four gaps: the subject is the 5-7-5 ritual, not the
        // window's length (`aLifeCycleLongerThanThreeGapsIsARhythm` owns that).
        assertEquals(listOf(5, 7, 5), s.recentGaps.takeLast(3))
        val next = dates.last().plusSeconds(6 * 86400 + 2 * 3600)
        assertEquals(7, s.gapDays(now = next))
        assertTrue(s.isRhythmBreak(7), "a 7 among 7s is the ritual, not a break in it")
    }

    /** The window's length: "two close together, then ten days of nothing"
     *  never looks regular inside a three-gap window. */
    @Test
    fun aLifeCycleLongerThanThreeGapsIsARhythm() {
        val dates = mutableListOf(date(day = 0, hour = 10))
        for (gap in listOf(10L, 2, 2, 2, 10, 2, 2, 2)) dates += dates.last().plusSeconds(gap * 86400)
        val s = store(workoutsAt = dates)
        assertEquals(listOf(10, 2, 2, 2, 10, 2, 2, 2), s.recentGaps, "eight gaps, not three")
        assertEquals(listOf(2, 2, 2), s.recentGaps.takeLast(3), "and the three the old window saw hold no ten at all")

        assertTrue(s.isRhythmBreak(10), "the ten-day leg of the cycle is the rhythm, not a break in it")
        // Widening the memory must not turn the mechanism off.
        assertFalse(s.isRhythmBreak(21), "a real absence must still outgrow the ritual")
    }

    // MARK: - The fractional gap the engine reads

    /** `trainingDays` counts midnights; the engine's weekly window reads the
     *  real elapsed fraction. The two must not be confused. */
    @Test
    fun theFractionalGapKeepsWhatTheTrainingDayThrowsAway() {
        val s = store(workoutsAt = listOf(date(day = 0, hour = 8)))
        val sameEvening = date(day = 0, hour = 20)
        assertEquals(0, s.gapDays(now = sameEvening), "half a day is no training day")
        assertEquals(0.5, assertNotNull(s.gapFraction(now = sameEvening)), 1e-9)
        assertEquals(3.0, assertNotNull(s.gapFraction(now = date(day = 3, hour = 8))),
                     "and a whole gap is still the whole gap")
        assertEquals(0.0, assertNotNull(s.gapFraction(now = date(day = 0, hour = 2))),
                     "a clock set backwards never yields a negative gap")
    }

    @Test
    fun anEmptyJournalHasNoGapAtAll() {
        assertNull(makeStore().gapFraction(), "nothing to measure from")
    }

    /** Two workouts in one day must not hand the engine a gap of zero — the
     *  weekly window would never age. */
    @Test
    fun twoWorkoutsInOneDayStillAgeTheWeeklyWindow() {
        val s = store(workoutsAt = listOf(date(day = 0, hour = 8)))
        s.completeWorkout(session = s.nextSession, result = FeedbackResult.plan, date = date(day = 0, hour = 20))
        assertEquals(0.5, s.engineState.weekAgeDays, 1e-9, "the window ages by the half day that really passed")
    }

    // MARK: - The rhythm and the silent decay (#134)

    @Test
    fun weeklyRhythmSkipsSilentDecayAndLeavesNoStamp() {
        val s = store(workoutsAt = listOf(0L, 7, 14, 21).map { date(it) })
        s.applySilentDecayIfNeeded(now = date(28))
        assertEquals(SEEDED_DOSE, s.pullDose(), "a 7-day gap in a 7-day rhythm is not a break")
        assertNull(s.settings.silentDecayAppliedFor, "a skipped decay leaves no stamp")
    }

    @Test
    fun rhythmToleratesOneDayOfJitter() {
        val s = store(workoutsAt = listOf(0L, 7, 14, 21).map { date(it) })
        s.applySilentDecayIfNeeded(now = date(29))
        assertEquals(SEEDED_DOSE, s.pullDose(), "8 is within ±1 of the 7-day rhythm")

        val jittered = store(workoutsAt = listOf(0L, 6, 14, 21).map { date(it) })
        assertEquals(listOf(6, 8, 7), jittered.recentGaps)
        jittered.applySilentDecayIfNeeded(now = date(28))
        assertEquals(SEEDED_DOSE, jittered.pullDose(), "jitter 6-8 is still one rhythm")
    }

    /** The matching gap is NOT the most recent one — a rule that consulted
     *  only the last gap would decay here. */
    @Test
    fun rhythmIsRememberedThroughAnOutlier() {
        val s = store(workoutsAt = listOf(0L, 7, 14, 24).map { date(it) })
        assertEquals(listOf(7, 7, 10), s.recentGaps)
        s.applySilentDecayIfNeeded(now = date(31))
        assertEquals(SEEDED_DOSE, s.pullDose(), "gap 7 matches the weekly rhythm remembered through the 10-day slip")
    }

    /** A 10-day-cadence trainee opens the app on days 7-9 of the cycle: that
     *  silence has not yet outgrown the rhythm — no decay, no stamp. */
    @Test
    fun midCycleOpenIsNotABreak() {
        val s = store(workoutsAt = listOf(0L, 10, 20, 30).map { date(it) })
        for (day in listOf(37L, 38, 39)) s.applySilentDecayIfNeeded(now = date(day))
        assertEquals(SEEDED_DOSE, s.pullDose())
        assertNull(s.settings.silentDecayAppliedFor)
    }

    /** An every-three-weeks ritual: days 14-19 of the cycle must not show the
     *  card whose primary button lowers the plan. */
    @Test
    fun midCycleOpenDoesNotSummonTheCard() {
        val s = store(workoutsAt = listOf(0L, 21, 42, 63).map { date(it) })
        assertFalse(s.shouldOfferComeback(now = date(77)), "day 14 of the cycle")
        assertFalse(s.shouldOfferComeback(now = date(82)), "day 19 of the cycle")
        assertTrue(s.shouldOfferComeback(now = date(86)), "two days past the ritual the break is real")
    }

    /** The mid-cycle window comes only from REPEATING gaps: one 60-day
     *  vacation does not shield a later 30-day absence. */
    @Test
    fun oneVacationDoesNotShieldTheNextAbsence() {
        val s = store(workoutsAt = listOf(0L, 7, 14, 74).map { date(it) })
        assertEquals(listOf(7, 7, 60), s.recentGaps)
        assertTrue(s.shouldOfferComeback(now = date(104)))
    }

    @Test
    fun oneOffBreakInATwiceAWeekRhythmStillDecays() {
        val s = store(workoutsAt = listOf(0L, 3, 7, 10).map { date(it) })
        assertEquals(listOf(3, 4, 3), s.recentGaps)
        s.applySilentDecayIfNeeded(now = date(18))
        assertEquals(SEEDED_DOSE - 1, s.pullDose(), "an 8-day gap is a real one-off break here")
        assertNotNull(s.settings.silentDecayAppliedFor)
    }

    @Test
    fun sameBreakCanStillDecayAfterOutgrowingTheRhythm() {
        val s = store(workoutsAt = listOf(0L, 7, 14, 21).map { date(it) })
        s.applySilentDecayIfNeeded(now = date(29))
        assertEquals(SEEDED_DOSE, s.pullDose(), "gap 8 matched the rhythm")
        s.applySilentDecayIfNeeded(now = date(31))
        assertEquals(SEEDED_DOSE - 1, s.pullDose(),
                     "no stamp was left, so the same break decays once it outgrows the rhythm")
    }

    // MARK: - The rhythm and the comeback card (#134)

    @Test
    fun fortnightRhythmSilencesTheCard() {
        val s = store(workoutsAt = listOf(0L, 14, 28).map { date(it) })
        assertFalse(s.shouldOfferComeback(now = date(42)), "a steady 14-day rhythm gets no card at all")
        s.acceptComeback(now = date(42))
        assertEquals(SEEDED_DOSE, s.pullDose(), "and no drop through the guarded accept")
        assertEquals(0, s.engineState.returnRun)
    }

    @Test
    fun brokenRhythmStillOffersTheCard() {
        val weekly = store(workoutsAt = listOf(0L, 7, 14, 21).map { date(it) })
        assertTrue(weekly.shouldOfferComeback(now = date(41)), "a 20-day gap breaks the weekly rhythm — a real break")

        val firstEver = store(workoutsAt = listOf(date(0)))
        assertEquals(emptyList(), firstEver.recentGaps)
        assertTrue(firstEver.shouldOfferComeback(now = date(20)), "one workout has no rhythm yet")
    }

    @Test
    fun nonStackingSurvivesASkippedDecay() {
        val s = store(workoutsAt = listOf(0L, 7, 14, 21).map { date(it) })
        s.applySilentDecayIfNeeded(now = date(29))
        assertEquals(SEEDED_DOSE, s.pullDose(), "the decay was skipped")
        // No decay was taken for this break, so the comeback subtracts the
        // FULL amount — two rungs of dose.
        s.acceptComeback(now = date(36))
        assertEquals(SEEDED_DOSE - 2, s.pullDose(), "no silent decay was taken, so the comeback is the full table amount")
    }

    private companion object {
        /** The ceiling of `pull`'s second variation: one rung below it is
         *  what a silent decay costs, and the assertions count those rungs. */
        const val SEEDED_DOSE = 15
    }
}
