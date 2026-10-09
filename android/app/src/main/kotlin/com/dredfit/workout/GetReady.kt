//
//  The transition before every guided position (issue #52): eight seconds,
//  plus a supplement for a position that has to be walked to or got down into
//  (issue #83). Port of ios/Dredfit/GetReady.swift — every number below is
//  spent against the engine's reserve, and GetReady.swift says how.
//
//  The DEBUG overrides of the UI suite (`--uitest-fast`,
//  `--uitest-long-transition`) are not ported: no unit test reads them, and
//  the Android UI suite is a later phase.
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
    const val countInSeconds = 4

    /** The two lengths a transition can have. */
    fun stageSeconds(needsSetup: Boolean): Int = if (needsSetup) seconds + setupSupplementSec else seconds

    val stageSeconds: Int get() = stageSeconds(needsSetup = false)
}
