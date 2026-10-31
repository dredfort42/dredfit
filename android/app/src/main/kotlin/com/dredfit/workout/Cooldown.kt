//
//  The cool-down block as data: six positions × 30 s plus their transitions,
//  from standing DOWN to lying, one zone of the body each. Port of
//  ios/Dredfit/Cooldown.swift — why the block goes one way down, why every
//  session gets the same zones, and why a side changes on the spot is there;
//  `BlockReserveTest` holds the arithmetic.
//
//  Two positions standing, then a single descent — onto one knee, onto both
//  knees, onto the back — and nobody gets up again until the block is over.
//  Two of the six zones alternate their variant from session to session. A
//  side changes ON THE SPOT, on a tone with the clock running; the pause stays
//  only where the body has to re-set (`WarmupHalves.pausesAtTheSwitch`).
//

package com.dredfit.workout

import com.dredfit.workout.CooldownPosition.Level

data class CooldownPosition(
    override val id: String,
    override val name: Words,
    val level: Level,
    /** null: held whole. Otherwise one 30 s slot split into 15 s per side — a
     *  per-side position does not get twice the time — and whether the switch
     *  between them stops the clock (`WarmupHalves.pausesAtTheSwitch`). */
    override val halves: WarmupHalves?,
    /** The transition into it carries the supplement of issue #83. COMPUTED
     *  by the composition, never written by hand: the supplement pays for the
     *  one trip down to the floor, so only the first position below standing
     *  carries it. */
    override val needsSetup: Boolean,
    val steps: List<Words>,
) : GuidedPosition {
    /** Where the body is. The block only ever moves DOWN this order. */
    @Suppress("EnumEntryName")
    enum class Level { standing, halfKneeling, kneeling, lying }

    val perSide: Boolean get() = halves != null
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

    /** What the position itself takes, its transition excluded: the slot, plus
     *  the switch pause when its halves stop the clock. ONE function for the
     *  offer screen, the header that counts what is left, and the reserve
     *  tests — copies of a formula agree only until one of them is edited. */
    fun slotSeconds(position: CooldownPosition): Int =
        positionSeconds + if (position.halves?.pausesAtTheSwitch == true) sideSwitchPauseSec else 0

    // MARK: - The pool of ten

    /** In the ORDER THE BLOCK RUNS: standing first, the kneeling lunge as the
     *  one trip down, then kneeling, then lying. The composition sorts what it
     *  draws by level and then by this order, so a position refilled into an
     *  emptied zone still lands on its own level and the block never climbs.
     *  The standing lunge is last: it is the hip flexors' fallback and nothing
     *  else's (`fallbackOnly`). */
    private val pool: List<CooldownPosition>
        get() = listOf(chestOpener, wrists, halfFold, hipFlexors, childSideReach, restPose,
                       lyingFigureFour, kneesToChest, lyingTwist, standingHipFlexors)

    private val chestOpener: CooldownPosition
        get() = position("chest-opener", "cooldown.chestOpener", "Chest opener", Level.standing, halves = null,
                         steps = listOf("Stand tall with the palms on the lower back, fingers pointing down.",
                                        "Draw the elbows back toward each other and open the chest; keep the shoulders down.",
                                        "Breathe slowly and keep the lower back still."))
    private val wrists: CooldownPosition
        get() = position("wrists", "cooldown.wrists", "Wrists and forearms", Level.standing,
                         halves = WarmupHalves.sidesOnTheSpot,
                         steps = listOf("Arm straight, palm down; gently pull the fingers down and toward you.",
                                        "Then turn the palm up and repeat the gentle pull.",
                                        "Pull only to a stretch — ease off at anything sharp or tingling."))
    /** HALF, and with the hands on the thighs: a full fold puts the head below
     *  the heart straight after the effort, which is when a standing body is
     *  most likely to feel light-headed. */
    private val halfFold: CooldownPosition
        get() = position("half-fold", "cooldown.halfFold", "Half forward fold", Level.standing, halves = null,
                         steps = listOf("Feet hip-width, knees soft, hands on the thighs.",
                                        "Hinge forward with a flat back until the backs of the thighs stretch; head in line with the back.",
                                        "Come up slowly, pressing the hands into the thighs."))
    /** The one position whose switch keeps the pause: changing the front leg
     *  of a kneeling lunge is a whole re-set of the body. */
    private val hipFlexors: CooldownPosition
        get() = position("hip-flexors", "cooldown.hipFlexors", "Hip flexor stretch", Level.halfKneeling,
                         halves = WarmupHalves.sides,
                         steps = listOf("Kneel on one knee, the other foot planted in front; pad the knee if the floor is hard.",
                                        "Tuck the pelvis and shift it slightly forward until the front of the hip stretches.",
                                        "Hold steady and breathe — no bouncing."))
    private val childSideReach: CooldownPosition
        get() = position("child-side-reach", "cooldown.childSideReach", "Rest pose, side reach", Level.kneeling,
                         halves = WarmupHalves.sidesOnTheSpot,
                         steps = listOf("Kneel, sit back toward the heels and walk both hands forward on the floor.",
                                        "Walk the hands to one side until the side of the back stretches.",
                                        "Knees wider apart if the knees or hips object."))
    private val restPose: CooldownPosition
        get() = position("rest-pose", "cooldown.restPose", "Rest pose", Level.kneeling, halves = null,
                         steps = listOf("Knees on the floor and a little apart, sit back toward the heels.",
                                        "Fold forward, arms stretched ahead, forehead down.",
                                        "Breathe slowly, sending the breath into the back."))
    /** Lying rather than seated: sitting tall on the floor is hard with tight
     *  hips and loads the knee, and lying keeps the head down after the
     *  kneeling positions instead of bringing it back up. */
    private val lyingFigureFour: CooldownPosition
        get() = position("lying-figure-four", "cooldown.lyingFigureFour", "Figure-four stretch, lying", Level.lying,
                         halves = WarmupHalves.sidesOnTheSpot,
                         steps = listOf("On your back, knees bent; cross one ankle over the opposite knee.",
                                        "Draw the supporting thigh toward the chest until the crossed hip stretches.",
                                        "Head and shoulders stay on the floor."))
    private val kneesToChest: CooldownPosition
        get() = position("knees-to-chest", "cooldown.kneesToChest", "Knees to chest", Level.lying, halves = null,
                         steps = listOf("On your back, hug both knees toward the chest.",
                                        "Let the lower back settle into the floor and breathe slowly."))
    /** The block's last position, and its close: lying, breathing slowly, and
     *  told how to get up. */
    private val lyingTwist: CooldownPosition
        get() = position("lying-twist", "cooldown.lyingTwist", "Lying twist", Level.lying,
                         halves = WarmupHalves.sidesOnTheSpot,
                         steps = listOf("On your back, knees bent; drop both knees to one side.",
                                        "Shoulders stay on the floor, head turns the other way.",
                                        "Let the knees sink on their own and breathe slowly; to get up, roll onto your side first."))
    /** The hip flexors' fallback for someone who cannot kneel. Standing, so it
     *  keeps the block's one-way order; stepping the feet over is a re-set, so
     *  it keeps the pause too. */
    private val standingHipFlexors: CooldownPosition
        get() = position("standing-hip-flexors", "cooldown.standingHipFlexors", "Hip flexor stretch, standing",
                         Level.standing, halves = WarmupHalves.sides,
                         steps = listOf("Stand in a long split stance, back heel lifted, hands on the hips.",
                                        "Tuck the pelvis under until the front of the back hip stretches.",
                                        "Hold steady and breathe — no bouncing."))

    /** No default for `halves`, deliberately: an omitted argument would be a
     *  one-sided stretch held thirty seconds on one side, with no switch
     *  announced — or a re-set with no pause to make it in. */
    private fun position(id: String, key: String, name: String, level: Level, halves: WarmupHalves?,
                         steps: List<String>): CooldownPosition =
        CooldownPosition(id = id, name = Words.keyed(key, name), level = level, halves = halves, needsSetup = false,
                         steps = steps.mapIndexed { i, s -> Words.keyed("$key.step${i + 1}", s) })

    // MARK: - Composition

    /** A zone is a slot: its ids in order of preference, and whether it
     *  alternates its variant from session to session or always opens on the
     *  first one it can. */
    private class Zone(val ids: List<String>, val rotates: Boolean)

    private val zones: List<Zone> = listOf(
        Zone(listOf("chest-opener", "wrists"), rotates = true),
        Zone(listOf("half-fold"), rotates = false),
        Zone(listOf("hip-flexors", "standing-hip-flexors"), rotates = false),
        Zone(listOf("child-side-reach", "rest-pose"), rotates = true),
        Zone(listOf("lying-figure-four", "knees-to-chest"), rotates = false),
        Zone(listOf("lying-twist"), rotates = false),
    )

    /** Positions that stand in for their own zone's first choice and are never
     *  drawn to refill another one. */
    private val fallbackOnly: Set<String> = setOf("standing-hip-flexors")

    /**
     * The six positions of session `sessionNumber` with `hiding` set aside.
     *
     * Deterministic in its two inputs alone. A rotating zone advances one
     * variant per session over its WHOLE list, so a set-aside variant passes
     * its turn to the next one; any other zone opens on its first variant
     * still available. A zone whose every variant is set aside leaves its slot
     * empty, and the first positions of the pool not yet drawn fill it — the
     * block is six whatever is set aside, which is also what keeps the cap of
     * three (`MAX_HIDDEN_BLOCK_MOVES`) a floor argument. What is drawn is then
     * put in order, level by level, so the block only ever goes down.
     *
     * `hiding` exists because a position can fall in every session, and
     * without it the only way to say "not this one" — no floor to kneel on, a
     * knee that objects — would be the same tap, every workout, forever.
     */
    fun positions(sessionNumber: Int, hiding: Set<String>): List<CooldownPosition> {
        // `pool` builds ten localized positions, so it is read ONCE here.
        val whole = pool
        val setAside = honoured(hiding, whole)
        val level = whole.associate { it.id to it.level }
        val chosen = mutableListOf<String>()
        fun isOpen(id: String) = id !in setAside && id !in chosen
        val emptied = mutableListOf<Level>()
        for (zone in zones) {
            val turn = if (zone.rotates) {
                // Nonnegative modulo: a hand-edited session number can be anything.
                val count = zone.ids.size
                val start = ((sessionNumber - 1) % count + count) % count
                (0 until count).map { zone.ids[(start + it) % count] }
            } else {
                zone.ids
            }
            val pick = turn.firstOrNull { isOpen(it) }
            if (pick != null) {
                chosen += pick
            } else {
                zone.ids.firstOrNull()?.let { level[it] }?.let { emptied += it }
            }
        }
        // A zone set aside entirely is refilled from its OWN level first — the
        // finishing twist gives its slot to another position lying down, not
        // to one standing up — and only then from anywhere in the pool. Never
        // with a zone's own fallback, which would stretch the same muscle
        // twice: the standing lunge stands in for the kneeling one and for
        // nothing else.
        val refills = whole.filter { it.id !in fallbackOnly }
        for (zoneLevel in emptied) {
            refills.firstOrNull { it.level == zoneLevel && isOpen(it.id) }?.let { chosen += it.id }
        }
        for (position in refills) {
            if (chosen.size < positionCount && isOpen(position.id)) chosen += position.id
        }
        val order = whole.withIndex().associate { (index, position) -> position.id to index }
        val composed = whole.filter { it.id in chosen }
            .sortedWith(compareBy<CooldownPosition>({ it.level }, { order[it.id] ?: 0 }))
            .toMutableList()
        // Only the trip DOWN pays the supplement: one per block, on the first
        // position below standing. Charging every floor position would spend
        // reserve on moves nobody makes.
        val first = composed.indexOfFirst { it.level > Level.standing }
        if (first >= 0) composed[first] = composed[first].copy(needsSetup = true)
        return composed
    }

    /** The block's own rule with nothing set aside. The app never calls it,
     *  and the reserve gate only for claims explicitly about "before anything
     *  was set aside". */
    fun positions(sessionNumber: Int): List<CooldownPosition> = positions(sessionNumber, hiding = emptySet())

    /** How many sessions before the compositions repeat: the least common
     *  multiple of the rotating zones' sizes, fixed whatever is set aside
     *  because each rotation runs over its whole list. */
    val rotationPeriod: Int
        get() = zones.filter { it.rotates }.map { it.ids.size }.fold(1) { period, size ->
            var a = period
            var b = size
            while (b != 0) { val t = a % b; a = b; b = t }
            period / a * size
        }

    /** As many of `hidden` as the block can afford, in pool order — the twin
     *  of `Warmup.honoured`: the guarantee that a block never empties lives
     *  here, not in the settings that hold the list. Ten in the pool against
     *  six on screen, less the fallback that refills no other zone, so three. */
    private fun honoured(hidden: Set<String>, whole: List<CooldownPosition>): Set<String> {
        val affordable = maxOf(whole.size - fallbackOnly.size - positionCount, 0)
        if (hidden.size <= affordable) return hidden
        return whole.map { it.id }.filter { it in hidden }.take(affordable).toSet()
    }

    /** The name behind an id; null for an id from the warm-up's pool, and for
     *  a position an earlier build had and this one does not. */
    fun nameOfPosition(id: String): Words? = pool.firstOrNull { it.id == id }?.name
}
