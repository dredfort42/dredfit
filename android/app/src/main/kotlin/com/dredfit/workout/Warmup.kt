//
//  The warm-up block as data: a pool of fourteen standing moves, six of them
//  per session, 30 s each. Port of ios/Dredfit/Warmup.swift — the reasoning
//  behind the pool (every move standing, none of them strength work), the
//  groups and the reserve is there; `BlockReserveTest` computes the figures
//  from these constants and is what actually fails.
//
//  Six SLOTS, each drawn from its own group, the last chosen by the session's
//  first exercise (`leadIn`). A circle REVERSES halfway and the clock does
//  not stop for it: a tone marks the midpoint. Only a side switch that
//  re-sets the body — changing the front leg of a lunge — keeps its counted
//  pause (`WarmupHalves.pausesAtTheSwitch`).
//

package com.dredfit.workout

import com.dredfit.core.Pattern
import com.dredfit.core.Session
import kotlin.math.ceil

/** What the two halves of a split position are.
 *
 *  The warm-up's split moves all reverse a DIRECTION; sides belong to the
 *  cool-down's per-side stretches and the work screen's per-side holds, which
 *  share the type through `GuidedPosition`. */
@Suppress("EnumEntryName")
enum class WarmupHalves {
    /** A side switch that re-sets the body — the front leg of a kneeling lunge
     *  changed, the feet stepped over. */
    sides,
    /** A side switch made where the body already is: the other wrist, the
     *  knees dropped the other way, the hands walked to the other side. */
    sidesOnTheSpot,
    directions;

    /** Whether the switch between the halves stops the clock. A re-set gets
     *  the pause (`Cooldown.sideSwitchPauseSec`); a switch on the spot and a
     *  circle reversing on the move do not — a pause there would stop a
     *  movement for nothing, and the tone alone marks the half. */
    val pausesAtTheSwitch: Boolean
        get() = when (this) {
            sides -> true
            sidesOnTheSpot, directions -> false
        }
}

data class WarmupMove(
    override val id: String,
    override val name: Words,
    /** The move reverses direction halfway — a circle whose steps say so.
     *  A property of the movement, and it decides the WORDS and the tone,
     *  never the seconds: the two halves are the 30 s slot with nothing
     *  between them. */
    val reverses: Boolean,
    val steps: List<Words>,
) : GuidedPosition {
    /** Two halves with the switch between them, or one continuous slot. */
    override val halves: WarmupHalves? get() = if (reverses) WarmupHalves.directions else null

    /** Every move is standing, so no transition is a trip to the floor or to
     *  a wall: the supplement of issue #83 is never paid in this block. */
    override val needsSetup: Boolean get() = false
}

object Warmup {

    const val moveSeconds = 30
    /** Six on screen. The pool behind them is fourteen. */
    const val moveCount = 6

    /** One 30 s slot split in half — with no pause between them the two
     *  halves ARE the slot. */
    val halfSeconds: Int get() = moveSeconds / 2

    // MARK: - The pool of fourteen

    /** In DISPLAY order, group by group, with the two lead-in-only moves last. */
    private val pool: List<WarmupMove>
        get() = listOf(
            // Raise the pulse.
            move("marching", Words.of("Marching in place"), reverses = false, steps = listOf(
                Words.keyed("warmup.marching.step1", "March at an easy pace, lifting the knees to hip height."),
                Words.keyed("warmup.marching.step2", "Swing the arms freely and keep the shoulders relaxed."),
            )),
            move("side-steps", Words.of("Side steps"), reverses = false, steps = listOf(
                Words.keyed("warmup.sideSteps.step1", "Step one foot out to the side as both arms swing up overhead."),
                Words.keyed("warmup.sideSteps.step2", "Bring the feet together as the arms come down, then step to the other side — no jumping."),
            )),
            move("heels-to-glutes", Words.of("Heels to glutes"), reverses = false, steps = listOf(
                Words.keyed("warmup.heelsToGlutes.step1", "Walk in place, bringing each heel up toward the glutes."),
                Words.keyed("warmup.heelsToGlutes.step2", "Stay light on the balls of the feet — no jumping, no hurry."),
            )),
            // Shoulders and arms.
            move("arm-circles", Words.of("Arm circles"), reverses = true, steps = listOf(
                Words.keyed("warmup.armCircles.step1", "Circle straight arms forward — big, slow circles."),
                Words.keyed("warmup.armCircles.step2", "Halfway through, switch direction and circle backward."),
            )),
            move("arm-swings", Words.of("Arm swings"), reverses = false, steps = listOf(
                Words.keyed("warmup.armSwings.step1", "Open the arms wide at chest height, then swing them in to hug yourself."),
                Words.keyed("warmup.armSwings.step2", "Keep it loose; switch which arm crosses on top each time."),
            )),
            move("reach-and-pull", Words.of("Reach and pull back"), reverses = false, steps = listOf(
                Words.keyed("warmup.reachPull.step1", "Reach both arms forward at shoulder height, letting the shoulder blades spread."),
                Words.keyed("warmup.reachPull.step2", "Pull the elbows back past the ribs and squeeze the shoulder blades together."),
            )),
            move("wrist-circles", Words.of("Wrist circles"), reverses = true, steps = listOf(
                Words.keyed("warmup.wristCircles.step1", "Make loose fists and circle the wrists slowly, elbows still."),
                Words.keyed("warmup.wristCircles.step2", "Halfway through, switch direction."),
            )),
            move("overhead-reaches", Words.of("Overhead reaches"), reverses = false, steps = listOf(
                Words.keyed("warmup.overheadReaches.step1", "Reach one arm up high, lengthening that side, then the other."),
                Words.keyed("warmup.overheadReaches.step2", "Draw each elbow down toward the ribs on the way back; keep the lower back still."),
            )),
            // The trunk.
            move("torso-rotations", Words.of("Torso rotations"), reverses = false, steps = listOf(
                Words.keyed("warmup.torsoRotations.step1", "Feet planted, hips facing forward; turn the torso side to side."),
                Words.keyed("warmup.torsoRotations.step2", "Let the arms swing loose — momentum, not force."),
            )),
            move("side-bends", Words.of("Side bends"), reverses = false, steps = listOf(
                Words.keyed("warmup.sideBends.step1", "Feet hip-width; slide one hand down the side of the thigh as you bend to that side."),
                Words.keyed("warmup.sideBends.step2", "Come up through the middle and bend to the other side — no leaning forward."),
            )),
            move("hip-circles", Words.of("Hip circles"), reverses = true, steps = listOf(
                Words.keyed("warmup.hipCircles.step1", "Hands on the hips, feet shoulder-width; draw slow circles with the hips."),
                Words.keyed("warmup.hipCircles.step2", "Keep the knees soft and switch direction halfway."),
            )),
            move("standing-cat-cow", Words.of("Standing cat-cow"), reverses = false, steps = listOf(
                Words.keyed("warmup.standingCatCow.step1", "Knees slightly bent, hands on the thighs; exhale, round the back and tuck the chin."),
                Words.keyed("warmup.standingCatCow.step2", "Inhale, arch gently and open the chest — one slow wave per breath."),
            )),
            // Lead-ins only (`leadIn`).
            move("hip-hinges", Words.of("Hip hinges"), reverses = false, steps = listOf(
                Words.keyed("warmup.hipHinges.step1", "Hands on the hips, knees soft; push the hips back as the chest leans forward."),
                Words.keyed("warmup.hipHinges.step2", "Keep the back flat and go only as far as is comfortable, then stand tall."),
            )),
            // Slow, and said so: thirty seconds at an easy pace is fifteen to
            // twenty half squats — more than a first working set of 3×4 —
            // and the block is meant to leave the legs fresh for that set.
            move("half-squats", Words.of("Half squats"), reverses = false, steps = listOf(
                Words.keyed("warmup.halfSquats.step1", "Heels down, sit back to half depth with the arms reaching forward for balance."),
                Words.keyed("warmup.halfSquats.step2", "Slow and easy — about ten in all; rise without locking the knees."),
            )),
        )

    /** No default for `reverses`, deliberately: an omitted argument would be a
     *  circle running thirty seconds in one direction with no switch
     *  announced. */
    private fun move(id: String, name: Words, reverses: Boolean, steps: List<Words>): WarmupMove =
        WarmupMove(id = id, name = name, reverses = reverses, steps = steps)

    // MARK: - Composition

    /** The first five slots and where each draws from, in display order. Each
     *  group's rotation runs over its WHOLE list and advances one move per
     *  session; a move set aside — or the one the lead-in took — passes its
     *  turn to the next in its group, so the period is the same whatever is
     *  set aside (`rotationPeriod`). Marching is a group of its own: it opens
     *  every block cold. */
    private class Group(val ids: List<String>, val slots: Int)

    private val groups: List<Group> = listOf(
        Group(listOf("marching"), 1),
        Group(listOf("side-steps", "heels-to-glutes"), 1),
        Group(listOf("arm-circles", "arm-swings", "reach-and-pull", "wrist-circles", "overhead-reaches"), 2),
        Group(listOf("torso-rotations", "side-bends", "hip-circles", "standing-cat-cow"), 1),
    )

    /** The last slot: the move that prepares the session's first exercise.
     *  Total over `Pattern`, with no default: a new pattern is a compile error
     *  here rather than a session that silently opens without a lead-in. */
    fun leadIn(pattern: Pattern): String = when (pattern) {
        Pattern.squat, Pattern.lunge, Pattern.calf -> "half-squats"
        Pattern.hinge -> "hip-hinges"
        Pattern.pushH -> "arm-swings"
        Pattern.pushV -> "overhead-reaches"
        Pattern.pull, Pattern.pullBar -> "reach-and-pull"
        Pattern.coreAntiExt -> "standing-cat-cow"
        Pattern.coreRot -> "torso-rotations"
    }

    /** The six moves of session `sessionNumber` opening on `opening`, `hiding`
     *  set aside. Deterministic in its three inputs alone, which is what lets
     *  a restored snapshot recompute the same list instead of carrying it. */
    fun moves(sessionNumber: Int, opening: Pattern?, hiding: Set<String>): List<WarmupMove> {
        // `pool` builds fourteen localized moves, so it is read ONCE here.
        val whole = pool
        val setAside = honoured(hiding, whole)
        val lead = opening?.let { leadIn(it) }?.takeIf { it !in setAside }
        val taken = setAside.toMutableSet()
        if (lead != null) taken.add(lead)
        val chosen = mutableSetOf<String>()
        for (group in groups) {
            val drawn = draw(group.slots, group.ids, sessionNumber, taken)
            chosen.addAll(drawn)
            taken.addAll(drawn)
        }
        // A group whose every move is set aside leaves its slot empty, and the
        // block is six whatever is set aside: the first moves of the pool not
        // yet taken fill in, in pool order.
        val bodyCount = moveCount - (if (lead == null) 0 else 1)
        for (move in whole) {
            if (chosen.size < bodyCount && move.id !in taken) chosen.add(move.id)
        }
        return whole.filter { it.id in chosen } + whole.filter { it.id == lead }
    }

    /** The block's own rule with nothing set aside. The app never calls it,
     *  and the reserve gate only for claims explicitly about "before anything
     *  was set aside". */
    fun moves(sessionNumber: Int, opening: Pattern?): List<WarmupMove> =
        moves(sessionNumber, opening, hiding = emptySet())

    /** `slots` moves of `ids`, starting where session `session` puts the
     *  group's rotation and passing over anything in `passing`. */
    private fun draw(slots: Int, ids: List<String>, session: Int, passing: Set<String>): List<String> {
        if (ids.isEmpty()) return emptyList()
        // Nonnegative modulo: a hand-edited session number can be anything.
        val start = ((session - 1) % ids.size + ids.size) % ids.size
        val turn = (0 until ids.size).map { ids[(start + it) % ids.size] }
        return turn.filter { it !in passing }.take(slots)
    }

    /** As many of `hidden` as the block can afford, in pool order — the
     *  guarantee that a block never empties lives here, not in the settings
     *  that hold the list. Six of fourteen are shown, so at most eight go. */
    private fun honoured(hidden: Set<String>, whole: List<WarmupMove>): Set<String> {
        val affordable = maxOf(whole.size - moveCount, 0)
        if (hidden.size <= affordable) return hidden
        return whole.map { it.id }.filter { it in hidden }.take(affordable).toSet()
    }

    /** The composition of the session in front of the person. No default for
     *  `hiding`, deliberately. */
    fun moves(session: Session, hiding: Set<String>): List<WarmupMove> =
        moves(sessionNumber = session.sessionNumber, opening = session.exercises.firstOrNull()?.pattern, hiding = hiding)

    /** The name behind an id; null for an id from the cool-down's pool, and
     *  for a move an earlier build had and this one does not. */
    fun nameOfMove(id: String): Words? = pool.firstOrNull { it.id == id }?.name

    /** How many sessions before the compositions repeat: the least common
     *  multiple of the group sizes, fixed whatever is set aside. */
    val rotationPeriod: Int
        get() = groups.map { it.ids.size }.fold(1) { period, size ->
            var a = period
            var b = size
            while (b != 0) { val t = a % b; a = b; b = t }
            period / a * size
        }

    /** What the offer screen promises, DERIVED and rounded up. */
    fun introMinutes(moves: List<WarmupMove>): Int {
        val seconds = moves.sumOf { GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, it) + moveSeconds }
        return maxOf(1, ceil(seconds.toDouble() / 60).toInt())
    }
}
