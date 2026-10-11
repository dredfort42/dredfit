//
//  The words of a split position's two halves. Lives in
//  ios/Dredfit/Views/Workout/BlockScreens.swift beside the screens; here it
//  is a file of its own because the flow announces these words and the flow
//  is plain Kotlin — the screens of phase 2c read it from here.
//
//  "Switch sides" over a circle about to be reversed is the defect this
//  distinction exists to prevent.
//

package com.dredfit.workout

data class SplitStageWords(val halves: WarmupHalves) {

    val switching: Words
        get() = when (halves) {
            WarmupHalves.sides -> Words.of("Switch sides")
            WarmupHalves.directions -> Words.keyed("warmup.switchDirection", "Switch direction")
        }

    val secondHalf: Words
        get() = when (halves) {
            WarmupHalves.sides -> Words.of("second side")
            WarmupHalves.directions -> Words.keyed("warmup.otherWay", "the other way")
        }

    val everyHalf: Words
        get() = when (halves) {
            // A `cooldown.` key read by the warm-up too — see BlockScreens.swift.
            WarmupHalves.sides -> Words.keyed("cooldown.perSide", "15 s per side")
            WarmupHalves.directions -> Words.keyed("warmup.perDirection", "15 s each way")
        }
}
