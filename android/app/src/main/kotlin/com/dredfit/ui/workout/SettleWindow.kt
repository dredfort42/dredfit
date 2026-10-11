//
//  Taps that land in the first moments after the screen changes do nothing.
//  Port of the `settleWindow` modifier of
//  ios/Dredfit/Views/Workout/SettleWindow.swift; the length is
//  workout/SettleWindow.kt (`SettleWindowLength`), pinned by
//  SettleWindowTest (androidTest).
//
//  Consecutive screens of the workout put different buttons in the same
//  place — "Start the warm-up" on the offer and "Skip warm-up" on the block it
//  opens, "Done" on a hold's summary and "Skip rest" on the rest after it — so
//  the second tap of a double tap meant for the first screen would act on the
//  second. Keyed by the SCREEN, never by what it shows: "+15 s" changes the
//  rest's total, not the screen, and must not lock the button for the next tap.
//

package com.dredfit.ui.workout

import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import com.dredfit.workout.SettleWindowLength
import kotlinx.coroutines.delay

/**
 * Swallows every pointer event inside the window, in the INITIAL pass — before
 * any control under it sees the touch — which is SwiftUI's
 * `.allowsHitTesting(false)`. The first composition is not a change: the
 * window opens on a screen change only, as `onChange` does on iOS.
 */
fun Modifier.settleWindow(screen: Any): Modifier = composed {
    var settled by remember { mutableStateOf(true) }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(screen) {
        if (first) {
            first = false
            return@LaunchedEffect
        }
        settled = false
        // A newer screen cancels this wait and starts its own, which is the
        // one that unlocks — a cancelled wait never leaves the screen locked.
        delay(SettleWindowLength.value.toMillis())
        settled = true
    }
    pointerInput(settled) {
        if (settled) return@pointerInput
        awaitPointerEventScope {
            while (true) {
                awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
            }
        }
    }
}
