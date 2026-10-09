//
//  The UI suite's `--uitest-fast`: every countdown the full-flow walk would
//  otherwise wait out collapses to a second, so the walk never depends on how
//  fast the runner taps. iOS reads it from the launch arguments of a DEBUG
//  build (GetReady.swift, Cooldown.swift, GuidedBlock.swift, BlockPause.swift,
//  WorkoutSession+Rest.swift, SettleWindow.swift); the instrumentation tests
//  run inside the app's own process, so here the suite sets it directly before
//  it opens the activity.
//
//  NOTHING in the app writes it — only androidTest does (grep) — so a
//  release build reads `false` forever and every length below is the real
//  one. It is not a setting and is never persisted.
//

package com.dredfit.workout

object UITestFlags {
    /** Collapses the rest, the transitions, the count-in, every cool-down
     *  stage and the side-switch pause to one second, and the settle window
     *  to 50 ms — the same set `--uitest-fast` collapses on iOS. */
    @Volatile
    var fast: Boolean = false
}
