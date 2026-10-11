//
//  What the milestone's Done does with the review gate — iOS's
//  `WorkoutFlowView.askForReviewIfEarned`, which iOS pins through no test at
//  all (it calls StoreKit inline). Android's own file: the ask is plain
//  Kotlin against `ReviewPrompt`, so the Play call is a recorder here. The
//  gate itself is AppStoreTestOnboardingAndReviewGate's.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.SwiftJson
import com.dredfit.store.AppStore
import com.dredfit.store.REVIEW_MIN_WORKOUTS
import com.dredfit.store.nextSession
import com.dredfit.ui.workout.ReviewPrompt
import com.dredfit.ui.workout.askForReviewIfEarned
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ReviewAskTest : AppStoreTestCase() {

    /** Play, as far as the rule can see it: how often it was asked, and what
     *  the store's stamp said at the moment it was. */
    private class PlayRecorder(private val store: () -> AppStore) : ReviewPrompt {
        val stampsAtAsk = mutableListOf<Instant?>()
        override fun request() {
            stampsAtAsk += store().settings.lastReviewRequestAt
        }
    }

    private val now = Instant.ofEpochSecond(1_784_000_000)

    private fun store(workouts: Int): AppStore {
        val store = makeStore(clock = Clock.fixed(now, ZoneId.systemDefault()))
        repeat(workouts) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan) }
        return store
    }

    /** Past the gate: Play is asked once, and the stamp is already on the
     *  store when it is — written whether or not the card shows, so the
     *  60-day floor holds against an invisible Play quota. */
    @Test
    fun anEarnedAskStampsTheStoreThenCallsPlay() {
        val store = store(REVIEW_MIN_WORKOUTS)
        val play = PlayRecorder { store }
        store.askForReviewIfEarned(FeedbackResult.plan, play)
        assertEquals(listOf<Instant?>(SwiftJson.swiftDate(now)), play.stampsAtAsk)
        assertEquals(SwiftJson.swiftDate(now), makeStore().settings.lastReviewRequestAt, "the stamp is persisted")
    }

    /** The stamp the first ask wrote is the floor of the next one. */
    @Test
    fun aSecondMilestoneTheSameDayDoesNotAskAgain() {
        val store = store(REVIEW_MIN_WORKOUTS)
        val play = PlayRecorder { store }
        store.askForReviewIfEarned(FeedbackResult.more, play)
        store.askForReviewIfEarned(FeedbackResult.plan, play)
        assertEquals(1, play.stampsAtAsk.size)
    }

    /** A gate that says no asks nothing AND stamps nothing: a stamp without
     *  an ask would spend sixty days of the floor on a card never requested. */
    @Test
    fun aRefusedGateNeitherAsksNorStamps() {
        for ((workouts, result) in listOf(REVIEW_MIN_WORKOUTS to FeedbackResult.less,
                                          REVIEW_MIN_WORKOUTS to null,
                                          REVIEW_MIN_WORKOUTS - 1 to FeedbackResult.plan)) {
            val store = store(workouts)
            val play = PlayRecorder { store }
            store.askForReviewIfEarned(result, play)
            assertEquals(0, play.stampsAtAsk.size, "$workouts workouts, rated $result")
            assertNull(store.settings.lastReviewRequestAt, "$workouts workouts, rated $result")
            tempPath.toFile().delete()
        }
    }
}
