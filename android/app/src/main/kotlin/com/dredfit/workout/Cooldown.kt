//
//  Six positions × 30 s plus their transitions, composed from what was
//  actually performed. Port of ios/Dredfit/Cooldown.swift.
//

package com.dredfit.workout

import com.dredfit.core.Pattern

data class CooldownPosition(
    override val id: String,
    override val name: Words,
    /** One 30 s slot split into 15 s per side; the switch rides on top. */
    val perSide: Boolean,
    /** Starts on the floor or at a wall: its transition carries the
     *  supplement of issue #83. */
    override val needsSetup: Boolean,
    val steps: List<Words>,
) : GuidedPosition {
    /** No stretch of the pool reverses, so the halves are always `sides`. */
    override val halves: WarmupHalves? get() = if (perSide) WarmupHalves.sides else null
}

object Cooldown {

    const val positionSeconds = 30
    const val positionCount = 6

    /** The re-set pause between sides — shared by the cool-down and the
     *  workout's per-side holds. Four is ON TRIAL (Cooldown.swift). */
    const val sideSwitchPauseSec = 4

    val sideSeconds: Int get() = positionSeconds / 2

    /** The workout's per-side holds play the same pause — and collapse under
     *  the UI suite's fast flag with everything else (UITestFlags.kt). */
    val switchPauseSeconds: Int get() = if (UITestFlags.fast) 1 else sideSwitchPauseSec

    // MARK: - The pool of nine

    private fun position(id: String, key: String, name: String, perSide: Boolean, needsSetup: Boolean,
                         steps: List<String>): CooldownPosition =
        CooldownPosition(id = id, name = Words.keyed(key, name), perSide = perSide, needsSetup = needsSetup,
                         steps = steps.mapIndexed { i, s -> Words.keyed("$key.step${i + 1}", s) })

    private val hipFlexors: CooldownPosition
        get() = position("hip-flexors", "cooldown.hipFlexors", "Hip flexor stretch", perSide = true, needsSetup = true,
                         steps = listOf("Kneel on one knee, the other foot planted in front.",
                                        "Tuck the pelvis and shift it slightly forward until the front of the hip stretches.",
                                        "Hold steady and breathe — no bouncing."))
    private val chestWall: CooldownPosition
        get() = position("chest-wall", "cooldown.chestWall", "Chest and shoulders at the wall", perSide = true, needsSetup = true,
                         steps = listOf("Forearm on the wall, elbow at shoulder height.",
                                        "Turn the chest away from the wall until the front of the shoulder stretches.",
                                        "Keep the shoulder down, away from the ear — turn to a stretch, not into pain."))
    private val restPose: CooldownPosition
        get() = position("rest-pose", "cooldown.restPose", "Rest pose", perSide = false, needsSetup = true,
                         steps = listOf("Knees on the floor, sit back onto the heels.",
                                        "Fold forward, arms stretched ahead, forehead down.",
                                        "Breathe slowly, sending the breath into the back."))
    private val forwardFold: CooldownPosition
        get() = position("forward-fold", "cooldown.forwardFold", "Forward fold", perSide = false, needsSetup = false,
                         steps = listOf("Feet hip-width; fold forward from the hips, knees soft.",
                                        "Let the head and arms hang heavy — no reaching for the floor.",
                                        "To come up, unroll the spine slowly, one vertebra at a time."))
    private val latStretch: CooldownPosition
        get() = position("lat-stretch", "cooldown.latStretch", "Lat stretch with support", perSide = false, needsSetup = false,
                         steps = listOf("Hold a support at hip height with both hands, feet under the hips.",
                                        "Sit the hips back on straight arms until the sides of the back stretch.",
                                        "Keep the head between the arms and breathe."))
    private val wrists: CooldownPosition
        get() = position("wrists", "cooldown.wrists", "Wrists and forearms", perSide = true, needsSetup = false,
                         steps = listOf("Arm straight, palm down; gently pull the fingers down and toward you.",
                                        "Then turn the palm up and repeat the gentle pull.",
                                        "Pull only to a stretch — ease off at anything sharp or tingling."))
    private val lyingTwist: CooldownPosition
        get() = position("lying-twist", "cooldown.lyingTwist", "Lying twist", perSide = true, needsSetup = true,
                         steps = listOf("On your back, knees bent; drop both knees to one side.",
                                        "Shoulders stay on the floor, head turns the other way.",
                                        "Let the weight sink on its own — don't push the knees down."))
    private val calfWall: CooldownPosition
        get() = position("calf-wall", "cooldown.calfWall", "Calf stretch at the wall", perSide = true, needsSetup = true,
                         steps = listOf("Hands on the wall, one leg stepped back, heel on the floor.",
                                        "Back knee straight; lean toward the wall until the calf stretches.",
                                        "Keep the heel down — no bouncing."))
    private val seatedGlute: CooldownPosition
        get() = position("seated-glute", "cooldown.seatedGlute", "Seated glute stretch", perSide = true, needsSetup = true,
                         steps = listOf("Sit tall; place one ankle over the opposite knee.",
                                        "Lean forward from the hips with a straight back until the glute stretches.",
                                        "The knee falls open on its own — don't press it down."))

    private fun positionFor(pattern: Pattern): CooldownPosition = when (pattern) {
        Pattern.squat, Pattern.hinge -> forwardFold
        Pattern.pull, Pattern.pullBar -> latStretch
        Pattern.pushH, Pattern.pushV -> wrists
        Pattern.coreAntiExt, Pattern.coreRot -> lyingTwist
        Pattern.calf -> calfWall
        Pattern.lunge -> seatedGlute
    }

    /** Top-up order when the session maps to fewer distinct positions. */
    private val mappedPool: List<CooldownPosition>
        get() = listOf(forwardFold, latStretch, wrists, lyingTwist, calfWall, seatedGlute)

    // MARK: - Composition

    private val wholePool: List<CooldownPosition> get() = listOf(hipFlexors, chestWall, restPose) + mappedPool

    /** Two fixed positions, three from the session's movements (session
     *  order, deduplicated, topped up from the pool), rest pose last — minus
     *  anything in `hiding`; a hidden fixed position lets the middle grow.
     *  Empty input returns an empty cool-down — the flow skips the block. */
    fun positions(performed: List<Pattern>, hiding: Set<String>): List<CooldownPosition> {
        if (performed.isEmpty()) return emptyList()
        val setAside = honoured(hiding)
        val opening = listOf(hipFlexors, chestWall).filter { it.id !in setAside }
        val closing = listOf(restPose).filter { it.id !in setAside }
        val middleCount = maxOf(positionCount - opening.size - closing.size, 0)
        val mapped = mutableListOf<CooldownPosition>()
        for (pattern in performed) {
            if (mapped.size >= middleCount) break
            val candidate = positionFor(pattern)
            if (candidate.id in setAside || candidate in mapped) continue
            mapped += candidate
        }
        for (candidate in mappedPool) {
            if (mapped.size >= middleCount) break
            if (candidate.id in setAside || candidate in mapped) continue
            mapped += candidate
        }
        return opening + mapped + closing
    }

    /** The block's own rule with nothing set aside. */
    fun positions(performed: List<Pattern>): List<CooldownPosition> = positions(performed, hiding = emptySet())

    /** As many of `hidden` as the block can afford, in pool order. */
    private fun honoured(hidden: Set<String>): Set<String> {
        val whole = wholePool
        val affordable = maxOf(whole.size - positionCount, 0)
        if (hidden.size <= affordable) return hidden
        return whole.map { it.id }.filter { it in hidden }.take(affordable).toSet()
    }

    /** The name behind an id; null for an id from the warm-up's pool. */
    fun nameOfPosition(id: String): Words? = wholePool.firstOrNull { it.id == id }?.name
}
