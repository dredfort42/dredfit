//
//  The transition before every guided position (issue #52): eight seconds,
//  plus a supplement for a position that has to be walked to or got down into
//  (issue #83). Port of ios/Dredfit/GetReady.swift — every number below is
//  spent against the engine's reserve, and GetReady.swift says how.
//
//  The UI suite's `--uitest-fast` collapses the transition and the count-in
//  (UITestFlags.kt); `--uitest-long-transition` has no Android test that
//  passes it, so it is not here — a hook nothing reaches is a branch the next
//  reader trusts.
//

package com.dredfit.workout

object GetReady {

    /** Eight: five is a rush, ten is longer than the change of posture takes. */
    const val seconds = 8

    /** On top of `seconds` for a position that changes the starting position
     *  or needs a prop. Past the engine's reserve a longer transition is an
     *  ENGINE change (`BlockReserveTest` holds the floor and the ceiling). */
    const val setupSupplementSec = 4

    /** The count-in a START TAP earns before any clock runs. Four holds the
     *  3-2-1 and nothing shorter does: a countdown never sounds the second it
     *  starts on (`Countdown.signals`), so from three it would be heard as
     *  2-1. Four is the floor, not a waypoint. */
    val countInSeconds: Int get() = if (UITestFlags.fast) 1 else 4

    /** The two lengths a transition can have. */
    fun stageSeconds(needsSetup: Boolean): Int = when {
        UITestFlags.fast -> 1
        needsSetup -> seconds + setupSupplementSec
        else -> seconds
    }

    val stageSeconds: Int get() = stageSeconds(needsSetup = false)
}
