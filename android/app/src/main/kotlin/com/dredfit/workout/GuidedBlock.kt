//
//  The warm-up and the cool-down run the same machine: a transition, then the
//  position held whole or in two halves with a switch between them — a counted
//  pause when a side is switched, a tone alone when a direction is — all on
//  one clock. Port of ios/Dredfit/GuidedBlock.swift.
//

package com.dredfit.workout

/** The two guided blocks of a workout. */
@Suppress("EnumEntryName")
enum class GuidedBlock {
    warmup, cooldown;

    /** The transition's length depends on the position it announces (#83). */
    fun stageSeconds(stage: GuidedStage, of: GuidedPosition): Int = when {
        // The fast flag collapses every stage of the cool-down; the warm-up
        // keeps its lengths and only its transitions collapse (GetReady).
        this == cooldown && UITestFlags.fast -> 1
        else -> unhurriedSeconds(stage, of)
    }

    private fun unhurriedSeconds(stage: GuidedStage, of: GuidedPosition): Int = when (stage) {
        GuidedStage.getReady -> GetReady.stageSeconds(needsSetup = of.needsSetup)
        GuidedStage.whole -> if (this == warmup) Warmup.moveSeconds else Cooldown.positionSeconds
        GuidedStage.firstHalf, GuidedStage.secondHalf ->
            if (this == warmup) Warmup.halfSeconds else Cooldown.sideSeconds
        // Only a side switch pauses, and the warm-up composes no position
        // with sides: one length, the cool-down's.
        GuidedStage.switchPause -> Cooldown.sideSwitchPauseSec
    }

    /** `entered` names the stage the audible boundary opened; index/stage/
     *  remaining are where the countdown landed. A long absence crosses
     *  several boundaries, so the two can disagree. */
    data class Advance(val entered: GuidedStage, val index: Int, val stage: GuidedStage, val remaining: Int)

    /** Whole stages an overshoot already covered are absorbed; null when the
     *  block is over, immediately or inside the overshoot. */
    fun advance(from: Step, overshoot: Int, positions: List<GuidedPosition>): Advance? {
        var landing = step(after = from, positions = positions) ?: return null
        val entered = landing.stage
        var remainder = overshoot
        while (remainder >= stageSeconds(landing.stage, positions[landing.index])) {
            remainder -= stageSeconds(landing.stage, positions[landing.index])
            landing = step(after = landing, positions = positions) ?: return null
        }
        return Advance(entered = entered, index = landing.index, stage = landing.stage,
                       remaining = stageSeconds(landing.stage, positions[landing.index]) - remainder)
    }

    /** Swift's `(index:, stage:)` tuple. */
    data class Step(val index: Int, val stage: GuidedStage)

    companion object {
        /** The stage after `step`; null when the block is over. */
        fun step(after: Step, positions: List<GuidedPosition>): Step? {
            if (after.index >= positions.size) return null
            return when (after.stage) {
                GuidedStage.getReady ->
                    Step(after.index, if (positions[after.index].halves == null) GuidedStage.whole else GuidedStage.firstHalf)
                GuidedStage.firstHalf -> {
                    // `halves` is there: only a split position has a first half.
                    val pauses = positions[after.index].halves?.pausesAtTheSwitch ?: true
                    Step(after.index, if (pauses) GuidedStage.switchPause else GuidedStage.secondHalf)
                }
                GuidedStage.switchPause -> Step(after.index, GuidedStage.secondHalf)
                GuidedStage.whole, GuidedStage.secondHalf -> {
                    val next = after.index + 1
                    if (next < positions.size) Step(next, GuidedStage.getReady) else null
                }
            }
        }
    }
}

/** What a guided block's stage machine reads off a position. */
interface GuidedPosition {
    val id: String
    val name: Words
    /** The transition into it pays the setup supplement (issue #83). */
    val needsSetup: Boolean
    /** null for a position held whole; otherwise what its two halves are. */
    val halves: WarmupHalves?
}

/** Every position opens with `getReady` (#52); one held whole runs `whole`,
 *  one with a halfway boundary `firstHalf` → `switchPause` → `secondHalf`
 *  when a SIDE is switched, and `firstHalf` → `secondHalf` when a direction
 *  is: a circle reverses on the move (`WarmupHalves.pausesAtTheSwitch`).
 *  HALF, not side: the warm-up's split moves switch a direction. */
@Suppress("EnumEntryName")
enum class GuidedStage { getReady, whole, firstHalf, switchPause, secondHalf }

/** Where a block stands. Swift's struct: `copy()` is `var b = a`. */
class GuidedBlockRun {
    var index: Int = 0
    var stage: GuidedStage = GuidedStage.getReady
    var clock: Countdown = Countdown()

    fun copy(): GuidedBlockRun = GuidedBlockRun().also { it.index = index; it.stage = stage; it.clock = clock.copy() }

    override fun equals(other: Any?): Boolean =
        other is GuidedBlockRun && index == other.index && stage == other.stage && clock == other.clock

    override fun hashCode(): Int = (index * 31 + stage.hashCode()) * 31 + clock.hashCode()

    override fun toString(): String = "GuidedBlockRun(index=$index, stage=$stage, clock=$clock)"
}
