//
//  The ONE way the UI tests drive a workout to the rating. Port of
//  ios/DredfitUITests/WorkoutDriver.swift: two copies of this walk would
//  drift, and on iOS the last drift cost the nightly six red runs (I-5).
//
//  Load-independent by the same design: only stable controls are tapped
//  (Done and Start leave the screen only once acted on), every tap is
//  confirmed by waiting for its control to go, and a tap whose control has
//  already gone is never made — the flow stacks its primary control in one
//  bottom slot on every screen, so a late tap would land on the NEXT screen's.
//

package com.dredfit

import android.util.Log
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performClick

class WorkoutDriver(private val test: DredfitUITest) {

    /** The screens a walk passes through, as the screenshot run names them. */
    enum class Screen { Today, Set, Rest, Hold, Summary, Rating, Done }

    /** Taps `tag` if it is there right now, and waits for it to go. A tap
     *  that lands inside a fresh screen's settle window does nothing — which
     *  is what the window is for — so the callers loop on their goal and the
     *  next pass taps again. */
    fun tapIfThere(tag: String, timeoutMs: Long = 1_500, gone: () -> Boolean = { !test.exists(tag) }): Boolean {
        val nodes = test.compose.onAllNodesWithTag(tag)
        if (nodes.fetchSemanticsNodes().isEmpty()) return false
        Log.i(LOG, "tap $tag")
        nodes[0].performClick()
        return runCatching { test.compose.waitUntil(timeoutMs) { gone() } }.isSuccess
    }

    /** Taps `tag` until the tap took — it went, or `took` holds — for a
     *  control with no loop around it. ONE tap that takes, never two: the
     *  same control is often back a second later on the next screen. */
    fun tapUntilGone(tag: String, attempts: Int = 8, took: () -> Boolean = { !test.exists(tag) }) {
        test.await(tag)
        repeat(attempts) {
            if (tapIfThere(tag, gone = took)) return
        }
        check(took()) { "$tag did not take through $attempts taps" }
    }

    /**
     * Start → the warm-up (begun, then left by its footer escape, so both of
     * its screens are walked) → every set, holds included → the cool-down
     * declined → the rating, rated "on plan" → Today's completed state.
     *
     * `skipRests`: tap "Skip rest" when a rest shows — the screenshot run,
     * which walks at real speed. `observe` sees each kind of screen once,
     * the first time it is up.
     */
    fun completeWorkout(skipRests: Boolean = false, deadlineMs: Long = 420_000,
                        observe: (Screen) -> Unit = {}): Set<Screen> {
        val seen = mutableSetOf<Screen>()
        fun saw(screen: Screen) {
            if (seen.add(screen)) {
                Log.i(LOG, "first $screen")
                observe(screen)
            }
        }
        test.await(AX.startWorkout)
        saw(Screen.Today)
        tapUntilGone(AX.startWorkout)

        // The warm-up is offered; taking it and leaving it by the block's
        // own escape walks the offer, the transition and the footer.
        tapUntilGone(AX.warmupStart)
        tapUntilGone(AX.skipWarmup)

        val started = System.currentTimeMillis()
        while (!test.exists(AX.ratingPlan)) {
            check(System.currentTimeMillis() - started < deadlineMs) {
                "did not reach the rating after ${(System.currentTimeMillis() - started) / 1000} s — a walk that " +
                    "spent the whole budget ran out of runner, not out of flow"
            }
            when {
                test.exists(AX.summaryHeld) -> {
                    saw(Screen.Summary)
                    tapIfThere(AX.exerciseDone)
                }
                test.exists(AX.exerciseDone) -> {
                    saw(Screen.Set)
                    tapIfThere(AX.exerciseDone)
                }
                // ONE tap per hold exercise: the sets after the first start on
                // their rest's own go.
                test.exists(AX.holdStartExercise) -> tapIfThere(AX.holdStartExercise)
                test.exists(AX.holdStart) -> tapIfThere(AX.holdStart)
                test.exists(AX.holdStop) -> {
                    saw(Screen.Hold)
                    test.compose.waitUntil(60_000) { !test.exists(AX.holdStop) }
                }
                test.exists(AX.skipRest) -> {
                    saw(Screen.Rest)
                    if (skipRests) tapIfThere(AX.skipRest) else Thread.sleep(300)
                }
                // The cool-down asks first; declining answers the question.
                test.exists(AX.cooldownStart) -> tapIfThere(AX.cooldownIntroSkip)
                // Resting, counting in or mid-transition: each moves on its own.
                else -> Thread.sleep(300)
            }
        }
        saw(Screen.Rating)
        tapUntilGone(AX.ratingPlan)
        // A milestone, when the workout earned one, stands between the
        // rating and Today.
        test.compose.waitUntil(10_000) { test.exists(AX.milestoneDone) || test.exists(AX.nextWorkout) }
        if (test.exists(AX.milestoneDone)) tapUntilGone(AX.milestoneDone)
        test.await(AX.nextWorkout)
        saw(Screen.Done)
        Log.i(LOG, "walk done in ${(System.currentTimeMillis() - started) / 1000} s")
        return seen
    }

    private companion object {
        const val LOG = "WorkoutDriver"
    }
}
