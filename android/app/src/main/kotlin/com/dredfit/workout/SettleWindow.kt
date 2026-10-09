//
//  The length of the window after a screen change in which taps do nothing.
//  Port of `SettleWindowLength` in ios/Dredfit/Views/Workout/SettleWindow.swift;
//  the modifier itself is a screen's (phase 2c). Consecutive workout screens
//  put different buttons in the same place, so the second tap of a double tap
//  meant for the first screen would act on the second. Keyed by the screen,
//  never by what it shows. (The UI suite's 50 ms is not ported — see
//  GetReady.kt.)
//

package com.dredfit.workout

import java.time.Duration

object SettleWindowLength {
    /** Long enough to swallow the second tap of a double tap, short enough
     *  that nobody reaches for a button inside it on purpose. */
    val value: Duration = Duration.ofMillis(350)
}
