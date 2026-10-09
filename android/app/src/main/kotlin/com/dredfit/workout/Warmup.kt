//
//  The warm-up block as data: a pool of nine mobility moves, six of them per
//  session, 30 s each. Port of ios/Dredfit/Warmup.swift — the reasoning behind
//  the pool, the split moves and the reserve is there; `BlockReserveTest`
//  computes the figures from these constants and is what actually fails.
//

package com.dredfit.workout

import com.dredfit.core.Session
import com.dredfit.core.WarmupMovement
import com.dredfit.core.WarmupTechnique
import kotlin.math.ceil

/** What the two halves of a split warm-up move are. The cool-down knows
 *  only `sides`. */
@Suppress("EnumEntryName")
enum class WarmupHalves { sides, directions }

data class WarmupMove(
    override val id: String,
    override val name: Words,
    /** Coming DOWN to the floor earns the supplement; the composition
     *  decides who pays. */
    val onFloor: Boolean,
    /** The halfway boundary and what is switched at it; null is one
     *  continuous slot. It decides the WORDS, never the seconds. */
    override val halves: WarmupHalves?,
    /** COMPUTED by the composition, never written by hand. */
    override val needsSetup: Boolean,
    val steps: List<Words>,
) : GuidedPosition {
    val isSplit: Boolean get() = halves != null
}

object Warmup {

    const val moveSeconds = 30
    /** Six on screen. The pool behind them is nine. */
    const val moveCount = 6

    /** One 30 s slot split in half; the switch pause rides on TOP of it. */
    val halfSeconds: Int get() = moveSeconds / 2

    /** One beat, one length, shared with the cool-down and the holds. */
    val switchPauseSeconds: Int get() = Cooldown.sideSwitchPauseSec

    // MARK: - The pool of nine

    /** In DISPLAY order: standing work first, floor work last. */
    private val pool: List<WarmupMove>
        get() = listOf(
            move("marching", Words.of("Marching in place"), onFloor = false, halves = null, steps = listOf(
                Words.keyed("warmup.marching.step1", "March at an easy pace, lifting the knees to hip height."),
                Words.keyed("warmup.marching.step2", "Swing the arms freely and keep the shoulders relaxed."),
            )),
            move("arm-circles", Words.of("Arm circles"), onFloor = false, halves = WarmupHalves.directions, steps = listOf(
                Words.keyed("warmup.armCircles.step1", "Circle straight arms forward — big, slow circles."),
                Words.keyed("warmup.armCircles.step2", "Halfway through, switch direction and circle backward."),
            )),
            move("torso-rotations", Words.of("Torso rotations"), onFloor = false, halves = null, steps = listOf(
                Words.keyed("warmup.torsoRotations.step1", "Feet planted, hips facing forward; turn the torso side to side."),
                Words.keyed("warmup.torsoRotations.step2", "Let the arms swing loose — momentum, not force."),
            )),
            move("hip-circles", Words.of("Hip circles"), onFloor = false, halves = WarmupHalves.directions, steps = listOf(
                Words.keyed("warmup.hipCircles.step1", "Hands on the hips, feet shoulder-width; draw slow circles with the hips."),
                Words.keyed("warmup.hipCircles.step2", "Keep the knees soft and switch direction halfway."),
            )),
            move("half-squats", Words.of("Half squats"), onFloor = false, halves = null, steps = listOf(
                Words.keyed("warmup.halfSquats.step1", "Sit back to half depth, arms reaching forward for balance."),
                Words.keyed("warmup.halfSquats.step2", "Heels stay down; rise smoothly without locking the knees."),
            )),
            // The three defined in the core: their text is the CORE catalog's.
            fromLibrary(WarmupTechnique.singleLegDeadlift, onFloor = false, halves = WarmupHalves.sides),
            move("cat-cow", Words.of("Cat-cow"), onFloor = true, halves = null, steps = listOf(
                Words.keyed("warmup.catCow.step1", "On all fours: exhale, round the back and tuck the chin."),
                Words.keyed("warmup.catCow.step2", "Inhale, arch gently and look slightly up — one slow wave per breath."),
            )),
            fromLibrary(WarmupTechnique.birdDog, onFloor = true, halves = WarmupHalves.sides),
            fromLibrary(WarmupTechnique.ytw, onFloor = true, halves = null),
        )

    /** No default for `halves`, deliberately (the rule `SetsHandle` keeps). */
    private fun move(id: String, name: Words, onFloor: Boolean, halves: WarmupHalves?, steps: List<Words>): WarmupMove =
        WarmupMove(id = id, name = name, onFloor = onFloor, halves = halves, needsSetup = false, steps = steps)

    private fun fromLibrary(movement: WarmupMovement, onFloor: Boolean, halves: WarmupHalves?): WarmupMove =
        WarmupMove(id = movement.id, name = Words.of(movement.name), onFloor = onFloor, halves = halves,
                   needsSetup = false, steps = movement.steps.map { Words.of(it) })

    /** Always in the block — about the ROTATION, not about the athlete: a
     *  permanent move can be set aside and gives its slot to a rotating one. */
    private val permanentIDs: Set<String> = setOf("marching", "arm-circles", "cat-cow")

    // MARK: - Composition

    /** The six moves of session `sessionNumber`, `hidden` set aside. Three
     *  fixed, three stepping through the other six by one per session;
     *  deterministic in the session number and the hidden set alone. */
    fun moves(sessionNumber: Int, hiding: Set<String>): List<WarmupMove> {
        val whole = pool
        val setAside = honoured(hiding, whole)
        val all = whole.filter { it.id !in setAside }
        val permanent = all.filter { it.id in permanentIDs }
        val rotating = all.filter { it.id !in permanentIDs }
        val slots = minOf(maxOf(moveCount - permanent.size, 0), rotating.size)
        var chosen: Set<String> = emptySet()
        if (slots > 0) {
            // Nonnegative modulo: a hand-edited session number can be anything.
            val n = rotating.size
            val start = ((sessionNumber - 1) % n + n) % n
            chosen = (0 until slots).map { rotating[(start + it) % n].id }.toSet()
        }
        val composed = all.filter { it.id in permanentIDs || it.id in chosen }.toMutableList()
        // Only the FIRST floor move pays the supplement: the trip down.
        val first = composed.indexOfFirst { it.onFloor }
        if (first >= 0) composed[first] = composed[first].copy(needsSetup = true)
        return composed
    }

    /** The block's own rule with nothing set aside. The app never calls it;
     *  a gate walking it would miss the dearest block (see Warmup.swift). */
    fun moves(sessionNumber: Int): List<WarmupMove> = moves(sessionNumber, hiding = emptySet())

    /** As many of `hidden` as the block can afford, in pool order — the
     *  guarantee that a block never empties lives here. */
    private fun honoured(hidden: Set<String>, whole: List<WarmupMove>): Set<String> {
        val affordable = maxOf(whole.size - moveCount, 0)
        if (hidden.size <= affordable) return hidden
        return whole.map { it.id }.filter { it in hidden }.take(affordable).toSet()
    }

    /** The composition of the session in front of the person. No default for
     *  `hiding`, deliberately. */
    fun moves(session: Session, hiding: Set<String>): List<WarmupMove> =
        moves(sessionNumber = session.sessionNumber, hiding = hiding)

    /** The name behind an id; null for an id from the cool-down's pool. */
    fun nameOfMove(id: String): Words? = pool.firstOrNull { it.id == id }?.name

    /** How many distinct compositions there are before they repeat. */
    val compositionCount: Int get() = pool.size - permanentIDs.size

    /** What the offer screen promises, DERIVED and rounded up. */
    fun introMinutes(moves: List<WarmupMove>): Int {
        val seconds = moves.sumOf { GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, it) + slotSeconds(it) }
        return maxOf(1, ceil(seconds.toDouble() / 60).toInt())
    }

    /** What the move itself takes, its transition excluded — ONE function for
     *  the offer screen and the reserve tests. */
    fun slotSeconds(move: WarmupMove): Int = if (move.isSplit) halfSeconds * 2 + switchPauseSeconds else moveSeconds
}
