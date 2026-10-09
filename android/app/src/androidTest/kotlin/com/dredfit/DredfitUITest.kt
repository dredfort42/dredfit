//
//  The one way this suite starts: a clean state (iOS's `--uitest-reset`),
//  an optional seed, the fast flag, then the activity. The counterpart of
//  `seedLaunchArguments` in ios/DredfitUITests/AccessibilityID.swift — the
//  reset is part of every launch here, not something a test remembers.
//

package com.dredfit

import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.generateSession
import com.dredfit.store.AppStore
import com.dredfit.store.AppearanceChoice
import com.dredfit.store.nextSession
import com.dredfit.workout.UITestFlags
import org.junit.After
import org.junit.Rule
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

abstract class DredfitUITest {

    @get:Rule
    val compose: ComposeTestRule = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null

    private val app: DredfitApp
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as DredfitApp

    /** What a launch starts from. */
    enum class Seed {
        /** A fresh install past onboarding. */
        Clean,
        /** Workout 1 completed yesterday, so today offers workout 2 — the
         *  only deterministic way to reach the hold movements (iOS's
         *  `--uitest-session2`). */
        Session2,
        /** Nothing on disk at all: a genuinely new install, which meets the
         *  onboarding (iOS's `--uitest-onboarding`). */
        FreshInstall,
        /** Sixteen workouts over six weeks with a twelve-day break, the last
         *  one today — a chart with a band, a month with marks, a history to
         *  walk and Today's door to it. */
        History,
    }

    /**
     * Resets, seeds and launches. The rest days are cleared outright, as on
     * iOS: the suite must not depend on the weekday it runs on. `fast` is
     * `--uitest-fast`.
     */
    fun launch(seed: Seed, fast: Boolean, appearance: AppearanceChoice = AppearanceChoice.system) {
        scenario?.close()
        UITestFlags.fast = fast
        app.resetForTests({ InstrumentationRegistry.getInstrumentation().runOnMainSync(it) }) { path ->
            write(path, seed, appearance)
        }
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    /** The same state again from disk — a process death's view of the file. */
    fun relaunchFromDisk() {
        scenario?.close()
        app.resetForTests({ InstrumentationRegistry.getInstrumentation().runOnMainSync(it) }) {}
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    @After
    fun closeAndSlowDown() {
        scenario?.close()
        UITestFlags.fast = false
    }

    private fun write(path: Path, seed: Seed, appearance: AppearanceChoice) {
        Files.deleteIfExists(path)
        if (seed == Seed.FreshInstall) return
        // A throwaway store on the disk thread, inline: its writes are done
        // when it returns, and the app's store reads them next.
        val store = AppStore(path)
        store.update {
            it.copy(settings = it.settings.copy(onboardingCompleted = true, restWeekdays = emptySet(),
                                                appearance = appearance))
        }
        if (seed == Seed.Session2) {
            val yesterday: Instant = ZonedDateTime.now(ZoneId.systemDefault()).minusDays(1).toInstant()
            store.completeWorkout(session = Engine.generateSession(EngineState.initial), result = FeedbackResult.plan,
                                  date = yesterday)
        }
        if (seed == Seed.History) {
            val now = ZonedDateTime.now(ZoneId.systemDefault()).minusMinutes(1)
            for ((i, daysAgo) in HISTORY_DAYS.withIndex()) {
                // Mostly "on plan", an "easy" now and then — the curve climbs.
                val result = if (i % 4 == 3) FeedbackResult.more else FeedbackResult.plan
                store.completeWorkout(session = store.nextSession, result = result,
                                      date = now.minusDays(daysAgo).toInstant())
            }
        }
    }

    companion object {
        /** Days ago of the History seed's workouts, oldest first. */
        val HISTORY_DAYS = listOf(44L, 42, 40, 37, 35, 33, 21, 19, 16, 14, 12, 9, 7, 5, 2, 0)
    }

    /** Whether a node with `tag` is in the tree right now. */
    fun exists(tag: String): Boolean =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** Waits until `tag` is in the tree; fails with the tag's name. */
    fun await(tag: String, timeoutMs: Long = 10_000) {
        compose.waitUntil(timeoutMs) { exists(tag) }
    }

    /** Taps the first node tagged `tag` once it is there — for the screens
     *  outside the workout, where no settle window swallows a tap. */
    fun tap(tag: String) {
        await(tag)
        val node = compose.onAllNodesWithTag(tag)[0]
        // Settings' lower groups sit below the fold of their scroll; a node
        // outside any scroll has nothing to scroll and stays where it is.
        runCatching { node.performScrollTo() }
        node.performClick()
        compose.waitForIdle()
    }
}
