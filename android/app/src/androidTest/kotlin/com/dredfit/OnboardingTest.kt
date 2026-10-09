//
//  The first run. Port of ios/DredfitUITests/DredfitUITests+Onboarding.swift:
//  what a fresh install opens on, and that a skip still routes through the
//  one card it cannot skip past (#101).
//

package com.dredfit

import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OnboardingTest : DredfitUITest() {

    private fun shows(text: String) = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun awaitText(text: String) = compose.waitUntil(5_000) { shows(text) }

    /** Today, whichever face the weekday gives it: the plan or the rest day. */
    private fun awaitToday() = compose.waitUntil(5_000) { exists(AX.startWorkout) || exists(AX.trainAnyway) }

    @Test
    fun onboardingAppearsOnFirstRunAndFinishes() {
        launch(Seed.FreshInstall, fast = true)
        awaitText("Training at home. No questionnaires.")
        tap(AX.onboardingPrimary)
        awaitText("It adjusts like a thermostat.")
        tap(AX.onboardingPrimary)
        awaitText("One tap after the workout.")
        tap(AX.onboardingPrimary)
        awaitToday()
        assertFalse("the onboarding must be gone", shows("Training at home. No questionnaires."))
    }

    /** Skip jumps TO the care card, never past it, and only its explicit
     *  button completes the onboarding — remembered across a relaunch. */
    @Test
    fun onboardingSkipLandsOnTheCareCardAndIsRemembered() {
        launch(Seed.FreshInstall, fast = true)
        tap(AX.onboardingSkip)
        awaitText("One tap after the workout.")
        assertTrue("the care note is on the card skip lands on", exists(AX.onboardingCare))
        assertFalse("nothing was completed by the skip", exists(AX.startWorkout) || exists(AX.trainAnyway))
        tap(AX.onboardingPrimary)
        awaitToday()

        relaunchFromDisk()
        awaitToday()
        assertFalse("an acknowledged onboarding must not come back", exists(AX.onboardingPrimary))
    }
}
