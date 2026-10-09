//
//  A whole workout on the device, and the way back into one that was left —
//  the counterparts of the iOS walks in DredfitUITests.swift and
//  DredfitUITests+Resume.swift, both through the one WorkoutDriver.
//

package com.dredfit

import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkoutWalkTest : DredfitUITest() {

    /** Workout 2: the warm-up, every set — the two hold movements among
     *  them — the rating, and Today's completed state. */
    @Test
    fun aWholeWorkoutWithHoldsReachesTheRatingAndToday() {
        launch(Seed.Session2, fast = true)
        val seen = WorkoutDriver(this).completeWorkout()
        assertTrue("the walk passed a hold: $seen", WorkoutDriver.Screen.Hold in seen)
        assertTrue("and a hold's summary: $seen", WorkoutDriver.Screen.Summary in seen)
        assertTrue(WorkoutDriver.Screen.Done in seen)
        // The completed day offers no Start.
        assertTrue(!exists(AX.startWorkout))
    }

    /**
     * "Finish later" keeps the workout, and the file is enough to come back
     * to it: the store is dropped and read again from disk — what a process
     * death leaves — and Today offers "Continue the workout?", which opens
     * the flow at the set after the one logged.
     */
    @Test
    fun aWorkoutLeftForLaterComesBackFromTheFile() {
        launch(Seed.Session2, fast = true)
        val driver = WorkoutDriver(this)
        driver.tapUntilGone(AX.startWorkout)
        driver.tapUntilGone(AX.warmupIntroSkip)
        driver.tapUntilGone(AX.exerciseDone)
        // The one-second rest runs out by itself; the second set is up.
        await(AX.exerciseDone)
        // The header's Exit stays on screen under its question.
        driver.tapUntilGone(AX.workoutExit) { exists(AX.exitFinishLater) }
        driver.tapUntilGone(AX.exitFinishLater)
        await(AX.resumeContinue)

        relaunchFromDisk()
        driver.tapUntilGone(AX.resumeContinue)
        await(AX.exerciseDone)
        // The first exercise, its SECOND set: the logged one stayed logged.
        // (The suite runs in the device's English, as the iOS one does. The
        // caption and the spoken announcement both say the set.)
        assertEquals(1, compose.onAllNodesWithText("1 / ", substring = true).fetchSemanticsNodes().size)
        assertTrue(compose.onAllNodesWithText("set 2 of", substring = true).fetchSemanticsNodes().isNotEmpty())
        assertTrue(compose.onAllNodesWithText("set 1 of", substring = true).fetchSemanticsNodes().isEmpty())
    }
}
