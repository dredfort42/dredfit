//
//  Port of ios/DredfitTests/ComebackTests.swift: when the comeback card
//  appears, what its answers do, and a file old enough to migrate both halves.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.SwiftJson
import com.dredfit.store.AppStore
import com.dredfit.store.declineComeback
import com.dredfit.store.gapDays
import com.dredfit.store.nextSession
import com.dredfit.store.offersFreshStart
import com.dredfit.store.shouldOfferComeback
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ComebackTest : AppStoreTestCase() {

    /**
     * Midnights, not elapsed seconds (`daysAgo`, #172, DST): 13/14 and 89/90
     * are precisely the edges this suite is about. In the comebacks below,
     * `pull` — the one movement asserted on — stays inside variation 2; the
     * hold ladders, seeded on their 15 s floor, cross into variation 1.
     */
    private fun storeWithLastWorkout(days: Long): AppStore {
        val stamp = SwiftJson.sinceReference(daysAgo(days))
        val store = storeFrom("""
            {"engineState":{"counter":11,"vars":[${pairs { 2 }}],"doses":[${pairs { SEEDED_DOSE }}],
                            "shown":[${pairs { "{\"1\":$SEEDED_DOSE,\"2\":$SEEDED_DOSE}" }}],"failStreak":[${pairs { 0 }}]},
             "records":[{"sessionNumber":11,"date":$stamp,"result":"plan",
                         "totalProgressAfter":100}],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
        assertEquals(SEEDED_DOSE, store.engineState.doses[Pattern.pull],
                     "the seed must actually load — a state that failed to decode " +
                         "would start clean and make every assertion here vacuous")
        return store
    }

    // MARK: - When the card appears

    @Test
    fun noCardBelowTwoWeeks() {
        for (days in listOf(0L, 1, 7, 13)) {
            assertFalse(storeWithLastWorkout(days).shouldOfferComeback(), "$days days is not a break yet")
        }
    }

    @Test
    fun cardAppearsFromFourteenDays() {
        for (days in listOf(14L, 30, 200)) {
            assertTrue(storeWithLastWorkout(days).shouldOfferComeback(), "$days days should offer the card")
        }
    }

    @Test
    fun noCardWithoutHistory() {
        val store = makeStore()
        assertFalse(store.shouldOfferComeback(), "a fresh install has nothing to come back from")
        assertNull(store.gapDays())
    }

    /** `gapDays` counts the midnights in between, not whole elapsed days (#172). */
    @Test
    fun gapDays_afterTwentyCalendarDays_countsTheMidnights() {
        assertEquals(20, storeWithLastWorkout(20).gapDays(), "twenty midnights lie between the last workout and now")
    }

    // MARK: - What the answers do

    @Test
    fun startEasierLowersThePlanAndClosesTheQuestion() {
        val store = storeWithLastWorkout(35)
        store.acceptComeback()
        // 35 days is a three-rung drop, read where it lands: on the dose.
        assertEquals(SEEDED_DOSE - 3, store.engineState.doses[Pattern.pull])
        assertEquals(11, store.engineState.counter, "a comeback is not a workout")
        assertEquals(1, store.records.size, "nothing is written to the journal")
        assertFalse(store.shouldOfferComeback(), "the question is answered for this break")
    }

    @Test
    fun leaveAsItWasChangesNothingButStillCloses() {
        val store = storeWithLastWorkout(35)
        store.declineComeback()
        assertEquals(SEEDED_DOSE, store.engineState.doses[Pattern.pull], "the plan is untouched")
        assertFalse(store.shouldOfferComeback(), "but the card does not come back")
    }

    @Test
    fun decisionSurvivesRelaunch() {
        storeWithLastWorkout(40).declineComeback()
        assertFalse(makeStore().shouldOfferComeback(), "the answer is persisted, not just held in memory")
    }

    @Test
    fun theQuestionIsAskedAgainAfterTheNextWorkout() {
        val store = storeWithLastWorkout(40)
        store.declineComeback()
        assertFalse(store.shouldOfferComeback())

        // A workout, then another long break of a DIFFERENT length — a repeat
        // of the same gap is the trainee's rhythm (CadenceTest). Calendar
        // arithmetic, like the seed: a DST transition must not make it 29 or 31.
        val thirtyDaysAgo = ZonedDateTime.now().minusDays(30).toInstant()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = thirtyDaysAgo)
        assertTrue(store.shouldOfferComeback(), "a break off the rhythm is a new question")
    }

    // MARK: - Fresh start

    /** From a quarter away, "as it was" is blind enough that "from scratch"
     *  must be on the card. */
    @Test
    fun freshStartOnlyOfferedAfterANinetyDayBreak() {
        assertFalse(storeWithLastWorkout(89).offersFreshStart(), "89 midnights is one short of the offer")
        assertTrue(storeWithLastWorkout(90).offersFreshStart(), "90 midnights is the boundary, and it is inclusive")
    }

    @Test
    fun freshStartResetsProgressButKeepsHistoryAndTheBar() {
        val store = storeWithLastWorkout(200)
        store.setHasBar(true)

        store.resetProgress()

        assertEquals(1, store.engineState.vars[Pattern.pull], "back to the first variation")
        assertEquals(Dose.grid(Library.unit(Pattern.pull, 1)).min, store.engineState.doses[Pattern.pull],
                     "and to the floor of the grid")
        assertEquals(0, store.engineState.counter)
        assertEquals(1, store.records.size, "the journal survives")
        assertTrue(store.engineState.hasBar, "the pull-up bar did not disappear from the doorway")
    }

    // MARK: - Migration

    /** A file this old migrates both halves: what the person chose and what
     *  they earned. */
    @Test
    fun v14FileKeepsItsSettingsAndMigratesTheEngine() {
        val store = storeFrom("""
            {"engineState":{"counter":6,
              "levels":["squat",9,"push_h",8,"hinge",7,"pull",6,"push_v",5,"lunge",4,
                        "core_anti_ext",3,"core_rot",2,"calf",1,"pull_bar",0],
              "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",1,"push_v",0,"lunge",0,
                            "core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0]},
             "records":[],
             "settings":{"restWeekdays":[3],"soundsEnabled":false,
                         "reminderEnabled":true,"reminderHour":18,"reminderMinute":45,
                         "healthEnabled":true,"healthExportedThrough":5,
                         "onboardingCompleted":true}}
        """)

        assertEquals(setOf(3), store.settings.restWeekdays)
        assertEquals(18, store.settings.reminderHour)
        assertEquals(45, store.settings.reminderMinute)
        assertTrue(store.settings.healthEnabled)
        assertEquals(5, store.settings.healthExportedThrough)
        assertTrue(store.settings.onboardingCompleted)
        // Old level 6 is tier 1 at 3×14, and tier 1 of `pull` is variation 1 —
        // the dose is what makes it a migration and not a reset.
        assertEquals(1, store.engineState.vars[Pattern.pull])
        assertEquals(14, store.engineState.doses[Pattern.pull])
        // The streak is EVIDENCE: dropping it would make the person say
        // "hard" twice more before the engine takes anything off.
        assertEquals(1, store.engineState.failStreak[Pattern.pull])
        // Resetting the counter would restart the rotation under someone mid-cycle.
        assertEquals(6, store.engineState.counter)
        assertNull(store.settings.comebackDecidedFor)
    }

    @Test
    fun comebackFieldSurvivesReload() {
        val store = storeWithLastWorkout(30)
        store.acceptComeback()
        val stamped = store.settings.comebackDecidedFor
        assertEquals(stamped, makeStore().settings.comebackDecidedFor)
    }

    private companion object {
        /** The ceiling of `pull`'s second variation: above the dose floor a
         *  return is measured in rungs of dose, so the assertions read the dose. */
        const val SEEDED_DOSE = 15
    }
}
