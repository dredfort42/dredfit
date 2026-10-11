//
//  Port of ios/DredfitTests/WeakLinkPromptTests.swift: the movement the
//  trainee never names. Someone who only knows the one-tap gesture rates
//  "tough" whenever the pushes come up; the journal has seen the correlation
//  all along, and this asks one question about it.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.canMakeEasier
import com.dredfit.store.dismissSuspectPrompt
import com.dredfit.store.nextSession
import com.dredfit.store.shouldAskAboutSuspect
import com.dredfit.store.unnamedLessSuspect
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WeakLinkPromptTest : AppStoreTestCase() {

    /** `count` sessions, each an unnamed "tough" when it carried `culprit`
     *  and "on plan" otherwise — seeded UP THE SCALE on purpose: the prompt
     *  routes into the easier-variation handle and stays silent where that
     *  handle could do nothing (`aMovementWithNoHandleLeftIsNotSuggested`). */
    private fun naiveStore(sessions: Int, culprit: Pattern = Pattern.pushV, variation: Int = 3): AppStore {
        fun at(p: Pattern) = minOf(variation, Library.count(p))
        // The journal of what was shown: the handle lands under it, and a
        // persona without one would find an easier variation that offers 3×4.
        val shown = Pattern.allCases.joinToString(",") { p ->
            val rows = (1..at(p)).joinToString(",") { "\"$it\":${Dose.grid(Library.unit(p, it)).max}" }
            "\"${p.rawValue}\",{$rows}"
        }
        val store = storeFrom("""
            {"engineState":{"counter":0,"vars":[${pairs { at(it) }}],
                            "doses":[${pairs { Dose.grid(Library.unit(it, at(it))).min + 2 }}],
                            "shown":[$shown],"failStreak":[${pairs { 0 }}]},
             "records":[],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
        repeat(sessions) {
            val session = store.nextSession
            val carries = session.exercises.any { it.pattern == culprit }
            store.completeWorkout(session = session, result = if (carries) FeedbackResult.less else FeedbackResult.plan)
        }
        return store
    }

    @Test
    fun thePromptNamesTheMovementThatKeepsLandingUnderTough() {
        val store = naiveStore(sessions = 12)
        assertEquals(Pattern.pushV, store.unnamedLessSuspect())
        assertTrue(store.shouldAskAboutSuspect())
    }

    @Test
    fun anHonestTraineeIsNeverAsked() {
        val store = makeStore()
        repeat(12) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan) }
        assertNull(store.unnamedLessSuspect(), "nothing is failing — nothing to ask about")
        assertFalse(store.shouldAskAboutSuspect())
    }

    /** The way to name a movement is an exact number below the plan — the
     *  answer the prompt is trying to reach. */
    @Test
    fun aTraineeWhoAlreadyNamesTheMovementIsNeverAsked() {
        val store = makeStore()
        repeat(12) {
            val session = store.nextSession
            val carried = session.exercises.firstOrNull { it.pattern == Pattern.pushV }
            val overrides = if (carried != null) mapOf(Pattern.pushV to maxOf(0, carried.load - 2).toDouble()) else emptyMap()
            store.completeWorkout(session = session,
                                  result = if (carried != null) FeedbackResult.less else FeedbackResult.plan,
                                  overrides = overrides)
        }
        assertNull(store.unnamedLessSuspect())
    }

    @Test
    fun theQuestionIsAskedOncePerSession() {
        val store = naiveStore(sessions = 12)
        assertTrue(store.shouldAskAboutSuspect())
        store.dismissSuspectPrompt()
        assertFalse(store.shouldAskAboutSuspect(), "a question, not a campaign")

        // The next workout is a new session, so the question may return.
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.less)
        assertTrue(store.shouldAskAboutSuspect())
    }

    /** Dismissing the question changes no plan: no engine state, and the
     *  movement's next appearance takes no set off. */
    @Test
    fun dismissingTheQuestionChangesNothingAboutThePlan() {
        val store = naiveStore(sessions = 12)
        val suspect = assertNotNull(store.unnamedLessSuspect())
        val before = store.engineState.copy()
        store.dismissSuspectPrompt()
        assertFalse(store.shouldAskAboutSuspect(), "asked once per session")
        assertEquals(before, store.engineState, "a dismissal touches no engine state")

        var applied = false
        for (i in 0 until 8) {
            if (applied) break
            val session = store.nextSession
            val carries = session.exercises.any { it.pattern == suspect }
            store.completeWorkout(session = session, result = FeedbackResult.plan)
            if (carries) {
                applied = true
                assertEquals(0, store.engineState.cutOf(suspect), "nothing was pulled, so no set came off")
            }
        }
        assertTrue(applied)
    }

    // MARK: - The answer is a handle, not a diagnosis

    /** "Make it easier" acts AT ONCE and on the movement named: the variation
     *  changes now, and nothing else moves. */
    @Test
    fun makingItEasierActsAtOnceOnTheNamedMovement() {
        val store = naiveStore(sessions = 12)
        val suspect = assertNotNull(store.unnamedLessSuspect())
        val before = store.engineState.position(suspect)
        val stepsBefore = Engine.progress(store.engineState, suspect)
        val othersBefore = Pattern.allCases.associateWith { store.engineState.position(it) }

        store.makeSuspectEasier(suspect)

        val after = store.engineState.position(suspect)
        assertTrue(Engine.progress(store.engineState, suspect) < stepsBefore,
                   "the named movement drops to an easier variation")
        assertTrue(after.variation < before.variation, "and it is the VARIATION that dropped, not just the rung")
        for ((pattern, position) in othersBefore) {
            if (pattern == suspect) continue
            assertEquals(position, store.engineState.position(pattern), "$pattern was not named and must not move")
        }
        assertFalse(store.shouldAskAboutSuspect(), "the question is answered for this session")
    }

    /** And the movement stays IN the plan: an easier variation of it, never
     *  weeks without it. */
    @Test
    fun theMovementStaysInThePlanAfterTheHandle() {
        val store = naiveStore(sessions = 12)
        val suspect = assertNotNull(store.unnamedLessSuspect())
        store.makeSuspectEasier(suspect)

        var seen = false
        for (i in 0 until 8) {
            if (seen) break
            val session = store.nextSession
            if (session.exercises.any { it.pattern == suspect }) seen = true
            store.completeWorkout(session = session, result = FeedbackResult.plan)
        }
        assertTrue(seen, "the movement is still in the rotation")
    }

    /** Nothing to suggest when the handle the prompt offers would do nothing:
     *  on the first variation the question would route into a dead control. */
    @Test
    fun aMovementWithNoHandleLeftIsNotSuggested() {
        val store = naiveStore(sessions = 12)
        val suspect = assertNotNull(store.unnamedLessSuspect())
        while (store.canMakeEasier(suspect)) store.makeEasier(suspect)
        assertFalse(store.canMakeEasier(suspect), "seeding: the easier handle is spent")
        assertNull(store.unnamedLessSuspect(), "with the handle spent there is nothing left to offer")
    }
}
