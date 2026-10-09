//
//  Port of ios/DredfitTests/SkipConfirmationTests.swift: the question a skip
//  asks. Pinned here rather than only in the UI suite because the rules worth
//  breaking are about WORDS — read here as the catalog keys the screen
//  resolves (`Words.key`) and their English.
//

package com.dredfit

import com.dredfit.ui.workout.SkipConfirmation
import com.dredfit.ui.workout.SkipConfirmation.Kind
import com.dredfit.workout.Words
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class SkipConfirmationTest {

    private val all = Kind.entries

    private fun make(kind: Kind) = SkipConfirmation(kind) {}

    @Test
    fun everyKindCarriesATitleAMessageAndAConfirmLabel() {
        for (kind in all) {
            val skip = make(kind)
            assertFalse(skip.title.english.isEmpty(), "$kind asks nothing")
            assertFalse(skip.message.english.isEmpty(), "$kind says nothing about what is lost")
            assertFalse(skip.confirmTitle.english.isEmpty(), "$kind offers no way to say yes")
        }
    }

    /** Two buttons reading the same words are one button to a test query and
     *  to TalkBack — the one that matters is the one inside the alert. */
    @Test
    fun theConfirmLabelIsNeverTheLabelOfTheControlThatRaisedIt() {
        val controls = listOf(Words.of("Skip this set"), Words.of("Skip remaining sets"), Words.of("Skip exercise"))
        for (kind in all) {
            assertFalse(make(kind).confirmTitle in controls, "$kind answers itself with the words already on screen")
        }
    }

    /** ONE label for all four, so the alert's layout cannot differ between
     *  two controls that sit at equal weight; the titles tell them apart. */
    @Test
    fun allFourAnswerToTheSameButton() {
        assertEquals(1, all.map { make(it).confirmTitle }.toSet().size, "a per-kind confirm label")
        assertEquals(3, all.map { make(it).title }.toSet().size,
                     "the two set-level skips share a question; the other two do not")
    }

    @Test
    fun theFourQuestionsDifferOnlyInWhatTheySay() {
        val shapes = all.map(::make)
        for (skip in shapes) {
            assertTrue(skip.title.english.endsWith("?"), "${skip.kind} does not read as a question")
            assertFalse(skip.confirmTitle.english.isEmpty())
        }
        assertEquals(shapes.size, shapes.map { it.message }.toSet().size,
                     "two skips promise the same thing about different acts")
    }

    /** The set-level questions say exactly what the controls' accessibility
     *  hints say: one promise, one wording. */
    @Test
    fun theSetLevelMessagesAreTheHintsThemselves() {
        assertEquals(Words.of("The plan keeps this set off next time. Nothing else about the movement changes."),
                     make(Kind.workingSet).message)
        assertEquals(Words.of("The probe just comes back next time. The working sets lose nothing."),
                     make(Kind.probeSet).message)
        assertEquals(SkipConfirmation.workingSetHint, make(Kind.workingSet).message)
        assertEquals(SkipConfirmation.probeHint, make(Kind.probeSet).message)
    }

    @Test
    fun theProbeIsNotToldTheWorkingSetsPromise() {
        assertNotEquals(make(Kind.probeSet).message, make(Kind.workingSet).message)
    }

    /** The tap that raised the question is the tap that runs. */
    @Test
    fun confirmingRunsTheActionTheQuestionWasRaisedWith() {
        var ran = 0
        val skip = SkipConfirmation(Kind.exercise) { ran += 1 }
        assertEquals(0, ran, "building the question must not perform it")
        skip.perform()
        assertEquals(1, ran)
    }
}
