//
//  The length of the window after a screen change in which taps do nothing.
//  Port of `SettleWindowLength` in ios/Dredfit/Views/Workout/SettleWindow.swift;
//  the modifier itself is a screen's (phase 2c). Consecutive workout screens
//  put different buttons in the same place, so the second tap of a double tap
//  meant for the first screen would act on the second. Keyed by the screen,
//  never by what it shows. The Compose modifier is ui/workout/SettleWindow.kt.
//

package com.dredfit.workout

import java.time.Duration

object SettleWindowLength {
    /** Long enough to swallow the second tap of a double tap, short enough
     *  that nobody reaches for a button inside it on purpose. The UI suite
     *  taps as soon as a screen appears, so under its fast flag the window
     *  all but closes, as under iOS's launch flags. */
    val value: Duration get() = Duration.ofMillis(if (UITestFlags.fast) 50 else 350)
}
