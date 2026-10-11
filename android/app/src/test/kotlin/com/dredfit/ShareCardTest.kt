//
//  Port of ios/DredfitTests/ShareCardTests.swift, its wording half: the
//  headlines (`ShareCardFactory`, ui/progress/ShareCard.kt) as the English
//  they print. The ten tests about the RENDER — pixel size, the PNG file,
//  the two slots, light whatever the theme, the curve and the fit of every
//  headline — need Android's Canvas and StaticLayout, so they run on a
//  device: androidTest/…/ShareCardRenderTest.kt.
//

package com.dredfit

import com.dredfit.core.Pattern
import com.dredfit.ui.progress.ShareCardFactory
import com.dredfit.workout.Milestone
import kotlin.test.Test
import kotlin.test.assertEquals

class ShareCardTest {

    @Test
    fun headlineForEachMilestoneKind() {
        assertEquals("Unlocked: Pistol squat",
                     ShareCardFactory.headline(Milestone.VariationUp(Pattern.squat, 3, "Pistol squat")).english)
        assertEquals("Workout #100", ShareCardFactory.headline(Milestone.Jubilee(100)).english)
        assertEquals("Now 4 sets", ShareCardFactory.headline(Milestone.SetBand(Pattern.pushH, 4, "Push-up")).english)
    }

    @Test
    fun headlineNamesEveryUnlockedVariation() {
        val headline = ShareCardFactory.headline(listOf(
            Milestone.VariationUp(Pattern.lunge, 2, "Bulgarian split squat"),
            Milestone.VariationUp(Pattern.pushH, 2, "Push-up"),
            Milestone.VariationUp(Pattern.hinge, 2, "Single-leg glute bridge"),
        ))
        assertEquals("Unlocked: Bulgarian split squat, Push-up, Single-leg glute bridge", headline.english,
                     "sharing three unlocks must not send only the first")
    }

    @Test
    fun headlineForASingleUnlockIsUnchangedByTheList() {
        assertEquals("Unlocked: Pistol squat",
                     ShareCardFactory.headline(listOf(Milestone.VariationUp(Pattern.squat, 3, "Pistol squat"))).english)
    }

    /** A set band and a jubilee are each one fact — there is no list. */
    @Test
    fun headlineFallsBackToTheFirstMilestoneWhenNothingUnlocked() {
        assertEquals("Now 4 sets", ShareCardFactory.headline(listOf(Milestone.SetBand(Pattern.pushH, 4, "Push-up"),
                                                                    Milestone.Jubilee(50))).english)
    }

    @Test
    fun unlocksLeadTheHeadlineOverSetBandsAndJubilees() {
        val headline = ShareCardFactory.headline(listOf(
            Milestone.VariationUp(Pattern.squat, 2, "Split squat"),
            Milestone.SetBand(Pattern.pushH, 4, "Push-up"),
            Milestone.Jubilee(50),
        ))
        assertEquals("Unlocked: Split squat", headline.english)
    }

    @Test
    fun summaryHeadlineCarriesOnlyTotals() {
        assertEquals("42 workouts · 137 steps", ShareCardFactory.summaryHeadline(workouts = 42, totalSteps = 137).english)
    }
}
