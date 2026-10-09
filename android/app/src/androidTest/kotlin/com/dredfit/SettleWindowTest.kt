//
//  The 350 ms settle window, pinned on a device — the gap the Verified facts
//  of android/CLAUDE.md recorded: iOS pins it only through XCUITest, which
//  cannot tell 350 from 50 ms. Here the frame clock is the test's, so the
//  window is measured to the frame: a tap 300 ms after a screen change does
//  nothing, one at 360 ms lands, and a redraw of the SAME screen opens no
//  window at all.
//

package com.dredfit

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.dredfit.ui.workout.settleWindow
import com.dredfit.workout.SettleWindowLength
import com.dredfit.workout.UITestFlags
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SettleWindowTest {

    @get:Rule
    val compose = createComposeRule()

    private var screen by mutableIntStateOf(0)
    private var redraw by mutableIntStateOf(0)
    private var taps = 0

    @Before
    fun setUp() {
        UITestFlags.fast = false
        compose.mainClock.autoAdvance = false
        compose.setContent {
            // Read so a change redraws without changing the screen.
            check(redraw >= 0)
            Box(Modifier.settleWindow(screen)) {
                Box(Modifier.size(120.dp).clickable { taps += 1 }.testTag("target"))
            }
        }
        compose.mainClock.advanceTimeByFrame()
    }

    private fun tap() {
        compose.onNodeWithTag("target").performClick()
        compose.mainClock.advanceTimeByFrame()
    }

    private fun changeScreen() {
        screen += 1
        // One frame recomposes and starts the wait, the next installs the lock.
        compose.mainClock.advanceTimeByFrame()
        compose.mainClock.advanceTimeByFrame()
    }

    @Test
    fun theFirstScreenIsNotLocked() {
        assertFalse(UITestFlags.fast)
        tap()
        assertEquals(1, taps)
    }

    @Test
    fun aTapInsideTheWindowAfterAScreenChangeDoesNothing() {
        assertEquals(350, SettleWindowLength.value.toMillis())
        changeScreen()
        tap()
        assertEquals("the second tap of a double tap must not act on the new screen", 0, taps)
        compose.mainClock.advanceTimeBy(300)
        tap()
        assertEquals("300 ms is still inside the window", 0, taps)
        compose.mainClock.advanceTimeBy(60)
        tap()
        assertEquals("past 350 ms the screen takes taps again", 1, taps)
    }

    /** Keyed by the screen, never by what it shows: "+15 s" redraws the rest
     *  and must not lock the button for the next tap. */
    @Test
    fun aRedrawOfTheSameScreenOpensNoWindow() {
        redraw += 1
        compose.mainClock.advanceTimeByFrame()
        compose.mainClock.advanceTimeByFrame()
        tap()
        assertEquals(1, taps)
    }
}
