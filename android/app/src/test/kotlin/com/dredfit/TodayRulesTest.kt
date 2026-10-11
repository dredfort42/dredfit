//
//  The rules Today's iOS views keep beside their bodies, ported with the
//  Compose screens — Android's own file, no Swift twin: whether a plan row
//  says an easier variation stands there (`aVariationJustDropped`,
//  AppStore+Signals.swift), which thing the resume card says about an
//  interrupted workout (`pendingWorkoutCard`, ResumeCard.swift), and the
//  "easy" gate of a changed rating (`WorkoutRecord.didFullPlan`, DoneView.swift).
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.aVariationJustDropped
import com.dredfit.store.nextSession
import com.dredfit.ui.today.didFullPlan
import com.dredfit.ui.today.pendingWorkoutCard
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import java.time.Clock
import java.time.Duration
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TodayRulesTest : WorkoutSessionTestCase() {

    @Test
    fun aRowSaysItDroppedOnlyBelowWhatTheLastRecordLeft() {
        val store = makeStore()
        val first = store.nextSession.exercises[0]
        assertFalse(store.aVariationJustDropped(first), "no record, no claim")
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        // The record keeps every movement's position, trained today or not.
        assertFalse(store.aVariationJustDropped(first), "the same rung is no drop")
        assertTrue(store.aVariationJustDropped(first.copy(variation = first.variation - 1)))
        assertFalse(store.aVariationJustDropped(first.copy(variation = first.variation + 1)))
    }

    /** Inside the occasion the card offers to carry on; past it — but before
     *  the workout counts as forgotten — it asks. */
    @Test
    fun theResumeCardAsksOnlyPastTheOccasion() {
        val zone = ZoneId.systemDefault()
        val store = makeStore(clock = Clock.fixed(clock, zone))
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        val card = assertNotNull(store.pendingWorkoutCard)
        assertFalse(card.awaitingAnswer)

        val later = makeStore(clock = Clock.fixed(clock.plus(Duration.ofHours(4)), zone))
        assertEquals(true, later.pendingWorkoutCard?.awaitingAnswer)
        val forgotten = makeStore(clock = Clock.fixed(clock.plus(Duration.ofHours(13)), zone))
        assertNull(forgotten.pendingWorkoutCard, "past twelve hours it is settled, not asked about")
    }

    /** The same rule as the rating screen's, over the journal entry — and a
     *  record that cannot say what it held answers no, not a vacuous yes. */
    @Test
    fun aChangedRatingKeepsTheEasyGate() {
        val store = makeStore()
        val session = store.nextSession
        store.completeWorkout(session = session, result = FeedbackResult.plan)
        val full = store.records.last()
        assertTrue(full.didFullPlan)
        assertFalse(full.copy(setsSkipped = mapOf(session.exercises[0].pattern to 1)).didFullPlan)
        assertFalse(full.copy(exercises = null).didFullPlan)
    }
}
