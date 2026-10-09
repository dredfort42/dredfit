//
//  WHERE the review ask happens, on the real screens: iOS asks from the
//  milestone's Done and nowhere else, so a rating that earns a milestone
//  asks when the milestone is left — by Done or, on Android, by Back, which
//  is that Done — and a rating that earns none asks nothing even past the
//  gate. Play is replaced by a counter (`DredfitApp.reviewPromptForTests`);
//  the rule itself is ReviewAskTest's (JVM), Play's half PlayReviewPromptTest's.
//

package com.dredfit

import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.ui.workout.ReviewPrompt
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class ReviewAskWalkTest : DredfitUITest() {

    private val asked = AtomicInteger()
    private val app: DredfitApp
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as DredfitApp

    @Before
    fun countTheAsks() {
        app.reviewPromptForTests = ReviewPrompt { asked.incrementAndGet() }
    }

    @After
    fun askPlayAgain() {
        app.reviewPromptForTests = null
    }

    /** Today's "Rate the workout", then "As planned". */
    private fun rateTheWaitingWorkout(driver: WorkoutDriver) {
        tap(AX.resumeContinue)
        driver.tapUntilGone(AX.ratingPlan)
        compose.waitUntil(10_000) { exists(AX.milestoneDone) || exists(AX.nextWorkout) }
    }

    @Test
    fun leavingAMilestoneByDoneAsksOnce() {
        launch(Seed.TenthAtRating, fast = true)
        val driver = WorkoutDriver(this)
        rateTheWaitingWorkout(driver)
        assertEquals("not before the milestone is left", 0, asked.get())
        driver.tapUntilGone(AX.milestoneDone)
        await(AX.nextWorkout)
        assertEquals(1, asked.get())
    }

    @Test
    fun leavingAMilestoneByBackAsksOnce() {
        launch(Seed.TenthAtRating, fast = true)
        rateTheWaitingWorkout(WorkoutDriver(this))
        await(AX.milestoneDone)
        Espresso.pressBack()
        await(AX.nextWorkout)
        assertEquals(1, asked.get())
    }

    /** The rating that earned the milestone outlives a recreated activity;
     *  forgotten, Done would meet a gate with no rating and ask nothing. */
    @Test
    fun aMilestoneLeftAfterTheActivityWasRecreatedStillAsks() {
        launch(Seed.TenthAtRating, fast = true)
        val driver = WorkoutDriver(this)
        rateTheWaitingWorkout(driver)
        await(AX.milestoneDone)
        recreate()
        driver.tapUntilGone(AX.milestoneDone)
        await(AX.nextWorkout)
        assertEquals(1, asked.get())
    }

    @Test
    fun aRatingWithoutAMilestoneAsksNothing() {
        launch(Seed.SixthAtRating, fast = true)
        rateTheWaitingWorkout(WorkoutDriver(this))
        await(AX.nextWorkout)
        assertFalse("the sixth workout earns no milestone", exists(AX.milestoneDone))
        assertEquals(0, asked.get())
    }
}
