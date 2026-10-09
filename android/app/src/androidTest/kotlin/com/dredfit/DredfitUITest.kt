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
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.generateSession
import com.dredfit.store.AppStore
import com.dredfit.store.AppearanceChoice
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
    }

    /** Whether a node with `tag` is in the tree right now. */
    fun exists(tag: String): Boolean =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** Waits until `tag` is in the tree; fails with the tag's name. */
    fun await(tag: String, timeoutMs: Long = 10_000) {
        compose.waitUntil(timeoutMs) { exists(tag) }
    }
}
