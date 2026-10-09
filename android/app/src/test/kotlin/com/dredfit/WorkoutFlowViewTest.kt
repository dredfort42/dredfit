//
//  The rules the iOS workout screens keep in their view bodies, moved to
//  plain Kotlin beside the Compose screens so a JVM test reaches them —
//  Android's own file, no Swift twin (iOS pins these only through the UI
//  suite: SetSkipUITests, DredfitUITests+HoldTimer, the rating walks):
//  which escape the work screen offers and what its question does
//  (WorkoutFlowViewSkips.kt), what the caption under the big number says
//  (WorkCaption), which screen a settle window is keyed by (settleScreen),
//  and what the rows under the rating cards are made of (FeedbackSummary).
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.core.Pattern
import com.dredfit.store.nextSession
import com.dredfit.ui.workout.FeedbackSummary
import com.dredfit.ui.workout.SettleScreen
import com.dredfit.ui.workout.SkipConfirmation.Kind
import com.dredfit.ui.workout.WorkCaption
import com.dredfit.ui.workout.exerciseEscape
import com.dredfit.ui.workout.perform
import com.dredfit.ui.workout.setSkipKind
import com.dredfit.ui.workout.settleScreen
import com.dredfit.workout.GetReady
import com.dredfit.workout.SettleWindowLength
import com.dredfit.workout.UITestFlags
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.extendRest
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.workNumber
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutFlowViewTest : WorkoutSessionTestCase() {

    // MARK: - The escapes

    /** First set of three: the set-level skip still leaves a trained
     *  movement, and the other escape takes the MOVEMENT — fewer than the
     *  floor have been performed, so "the remaining sets" would be all of it. */
    @Test
    fun theFirstSetOffersASetSkipAndTheMovement() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        assertEquals(3, flow.exercise.sets)
        assertEquals(Kind.workingSet, flow.setSkipKind())
        val escape = flow.exerciseEscape()
        assertEquals(Kind.exercise, escape?.kind)
        assertEquals("exercise-skip", escape?.identifier)
    }

    /** Past the floor and before the last set, the escape is "Skip remaining
     *  sets"; on the last set it collapses into the set-level skip. */
    @Test
    fun theRemainingSetsAreOfferedOnlyBetweenTheFloorAndTheLastSet() {
        val store = makeStore()
        val base = store.nextSession
        // Four sets on the first movement, so a set past the floor that is
        // not the last one exists.
        val session = base.copy(exercises = listOf(base.exercises[0].copy(sets = 4)) + base.exercises.drop(1))
        val flow = makeFlow(store, session)
        flow.declineWarmup()
        flow.setIndex = EngineConfig.setsFloor - 1
        assertEquals(Kind.exercise, flow.exerciseEscape()?.kind, "under the floor the escape takes the movement")
        flow.setIndex = EngineConfig.setsFloor
        assertEquals(Kind.restOfSets, flow.exerciseEscape()?.kind)
        assertEquals("exercise-skip-rest", flow.exerciseEscape()?.identifier)
        flow.setIndex = flow.totalSets - 1
        assertTrue(flow.isLastSet)
        assertNull(flow.exerciseEscape(), "on the last set the set-level skip already covers it")
    }

    /** On the probe set the working sets are behind: the probe can always be
     *  skipped, and there is no exercise-level escape. */
    @Test
    fun theProbeSetIsSkippableAndOffersNoEscape() {
        val flow = makeFlow(makeStore(), probeSession())
        flow.declineWarmup()
        flow.setIndex = flow.exercise.sets
        assertTrue(flow.onProbeSet)
        assertEquals(Kind.probeSet, flow.setSkipKind())
        assertNull(flow.exerciseEscape())
    }

    /** A confirmed question runs the skip it names, and only that one. */
    @Test
    fun aConfirmedQuestionRunsTheSkipItNames() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        val pattern = flow.exercise.pattern
        flow.perform(Kind.workingSet)
        assertEquals(1, flow.setsSkipped[pattern])
        assertTrue(pattern !in flow.skippedPatterns)
        flow.perform(Kind.exercise)
        assertTrue(pattern in flow.skippedPatterns)
    }

    // MARK: - The caption under the big number

    @Test
    fun theCaptionCarriesTheCountForReps() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        val words = WorkCaption.text(flow)
        assertEquals("%lld reps", words.key)
        assertEquals(listOf<Any>(flow.workNumber), words.args, "the word agrees with the number it does not print")
        assertEquals(WorkCaption.Emphasis.Plain, WorkCaption.emphasis(flow))
    }

    /** While the number is a countdown the slot names the STATE. */
    @Test
    fun aCountInNamesTheStateNotTheUnit() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        assertTrue(flow.holdCountingIn)
        assertEquals("Get ready", WorkCaption.text(flow).key)
        assertEquals(WorkCaption.Emphasis.State, WorkCaption.emphasis(flow))
        run(flow, GetReady.countInSeconds)
        assertTrue(flow.holding)
        assertEquals("s left", WorkCaption.text(flow).key)
        assertEquals(WorkCaption.Emphasis.Running, WorkCaption.emphasis(flow))
    }

    /** "per side" is the one word that changes what the number means. */
    @Test
    fun aPerSideHoldIsATierLouder() {
        val (flow, _) = holdFlow(Pattern.coreRot)
        assertTrue(flow.current.perSide)
        assertEquals("seconds per side", WorkCaption.text(flow).key)
        assertEquals(WorkCaption.Emphasis.PerSide, WorkCaption.emphasis(flow))
    }

    // MARK: - The settle window's key

    /** Keyed by the SCREEN: "+15 s" changes the rest's total, not the screen,
     *  so the next tap is not locked out; a probe hold's Stop turning into
     *  Done is a new screen although the phase is the same. */
    @Test
    fun theSettleKeyFollowsTheScreenAndNothingElse() {
        val flow = makeFlow(makeStore())
        assertEquals(SettleScreen.WarmupIntro, settleScreen(flow))
        flow.declineWarmup()
        assertEquals(SettleScreen.Work(settled = false), settleScreen(flow))
        flow.completeSet()
        assertIs<Phase.Rest>(flow.phase)
        val rest = settleScreen(flow)
        flow.extendRest()
        assertEquals(rest, settleScreen(flow), "an extended rest is the same screen")
        flow.phase = Phase.Work
        flow.holdSettled = true
        assertNotEquals(SettleScreen.Work(settled = false), settleScreen(flow))
    }

    /** The window's length: 350 ms in the app, and the UI suite's 50 only
     *  under its fast flag — which nothing in the app sets. The modifier that
     *  spends it is pinned on a device (SettleWindowTest, androidTest). */
    @Test
    fun theSettleWindowIsLongEnoughForADoubleTapAndShortOnlyForTheSuite() {
        assertFalse(UITestFlags.fast, "nothing outside the UI suite turns the fast flag on")
        assertEquals(350, SettleWindowLength.value.toMillis())
        UITestFlags.fast = true
        try {
            assertEquals(50, SettleWindowLength.value.toMillis())
            assertEquals(1, GetReady.countInSeconds)
        } finally {
            UITestFlags.fast = false
        }
        assertEquals(4, GetReady.countInSeconds)
    }

    // MARK: - The rows under the rating

    /** The rating's scope stated once: the session minus what was set aside
     *  minus what carries its own number; a movement left is never counted
     *  as trained short. */
    @Test
    fun theRatingAppliesToWhatCarriesNoNumberOfItsOwn() {
        val session = makeStore().nextSession
        val (a, b, c) = session.exercises.take(3).map { it.pattern }
        val summary = FeedbackSummary(session, overrides = mapOf(a to 5.0), setsSkipped = mapOf(b to 1, c to 2),
                                      skipped = setOf(c), raised = mapOf(c to 1))
        assertEquals(1, summary.adjusted)
        assertEquals(session.exercises.size - 1 - 1, summary.applies)
        assertEquals(listOf(b), summary.trainedShort.map { it.pattern }, "a movement left is not trained short")
        assertTrue(summary.raisedRows.isEmpty(), "a movement left carries no addition")
        assertTrue(summary.shows)
        val quiet = FeedbackSummary(session, emptyMap(), emptyMap(), emptySet(), emptyMap())
        assertTrue(!quiet.shows, "nothing to say, no card")
    }
}
