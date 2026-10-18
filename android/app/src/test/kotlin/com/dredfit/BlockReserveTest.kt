//
//  Port of ios/DredfitTests/BlockReserveTests.swift: the warm-up and
//  cool-down reserve, and the arithmetic that makes the transition length an
//  ENGINE constraint rather than an app preference.
//
//  `warmupMin + cooldownMin` is the whole budget the engine sets aside for the
//  two blocks. The worst pair leaves 100 s of it over (500 of 600), and every
//  second added to the transition costs twelve — six transitions per block —
//  so past 16 s the reserve breaks, which is a change to the engine.
//
//  SHORTENING it is the direction that does not break. The worst pair is 500 s
//  against 600, so the reserve is not the smallest whole minute that fits —
//  nine would hold it. The owner keeps ten rather than spend an engine change
//  and a minute off every announced duration to reclaim slack nobody is short
//  of. What is asserted below is therefore a floor and a ceiling, not an
//  equality: the blocks may never overrun the reserve, and the reserve may
//  never hold two spare minutes.
//
//  Everything below is computed from the app's own constants and from the real
//  composition rule, never from the spec's numbers restated. The worst case is
//  found by ENUMERATING the sets a session can actually produce rather than by
//  assuming which six positions are dearest: if the pool, the mapping or a hold
//  ever moves, this fails here instead of on somebody's stopwatch.
//
//  And it enumerates the axis the APP has: both composers take a `hiding` set,
//  and `Warmup.moves(sessionNumber, opening)` / `Cooldown.positions(performed)`
//  — the forms without it — are for the tests alone. The standing warm-up costs
//  the same whatever is set aside (every slot is a transition and thirty
//  seconds), but that is exactly the kind of claim the sweep exists to keep
//  true: under the floor pool a set-aside move widened the rotation onto a
//  fourth switch pause, and only the hiding axis saw it.
//
//  The last section reads the same composition rule the other way: where a
//  block that is RUNNING picks up when the athlete changes the composition
//  under it — forward, never reopening a move already done.
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.core.Pattern
import com.dredfit.store.MAX_HIDDEN_BLOCK_MOVES
import com.dredfit.workout.Cooldown
import com.dredfit.workout.CooldownPosition
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.Warmup
import com.dredfit.workout.WarmupMove
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.rebaseLanding
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BlockReserveTest {

    // MARK: - What one slot costs

    /** One warm-up move: every stage the block's own machine walks it through,
     *  transition included. Walked rather than written as "transition plus
     *  thirty", so a circle that got its switch pause back — one line in
     *  `GuidedBlock.step` — costs four more seconds here and the reserve
     *  asserts below go red, instead of staying green on a formula that no
     *  longer describes the block. GetReadyTest keeps the hand-written
     *  statement on purpose; two derivations that agree are the point. */
    private fun cost(move: WarmupMove): Int {
        var step: GuidedBlock.Step? = GuidedBlock.Step(0, GuidedStage.getReady)
        var seconds = 0
        while (step != null) {
            seconds += GuidedBlock.warmup.stageSeconds(step.stage, move)
            step = GuidedBlock.step(step, listOf(move))
        }
        return seconds
    }

    /** One cool-down position: its transition plus the hold. A per-side hold is
     *  two halves with the switch pause between them. */
    private fun cost(position: CooldownPosition): Int {
        val hold = if (position.perSide) {
            Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
        } else {
            Cooldown.positionSeconds
        }
        return GetReady.stageSeconds(needsSetup = position.needsSetup) + hold
    }

    // MARK: - The pools, and what can be set aside

    /** One opening per distinct lead-in, and none. The composition reads the
     *  opening only through `Warmup.leadIn`, so this is every opening there is
     *  — derived from the mapping rather than typed, so a pattern that gains a
     *  lead-in of its own joins the sweep by itself. */
    private val openings: List<Pattern?>
        get() {
            val seen = mutableSetOf<String>()
            return listOf<Pattern?>(null) + Pattern.allCases.filter { seen.add(Warmup.leadIn(it)) }
        }

    /** The fourteen ids of the warm-up pool, read off the compositions rather
     *  than typed here: `Warmup.pool` is private, and a hand-written copy would
     *  stop covering the pool the day a move is added to it. */
    private val warmupPoolIDs: List<String>
        get() {
            val ids = mutableListOf<String>()
            for (session in 1..Warmup.rotationPeriod) {
                for (opening in openings) {
                    for (move in Warmup.moves(sessionNumber = session, opening = opening)) {
                        if (move.id !in ids) ids += move.id
                    }
                }
            }
            return ids
        }

    /** The nine positions of the cool-down pool, likewise — one movement at a
     *  time, because a single pattern draws the two fixed positions, its own
     *  and two top-ups, so the union over the ten reaches every one. */
    private val cooldownPool: List<CooldownPosition>
        get() {
            val pool = mutableListOf<CooldownPosition>()
            for (pattern in Pattern.allCases) {
                for (position in Cooldown.positions(performed = listOf(pattern))) {
                    if (pool.none { it.id == position.id }) pool += position
                }
            }
            return pool
        }

    /** Every set the athlete can actually put in `hiddenBlockMoveIDs`. The cap
     *  is the app's, not a number chosen here — 470 subsets of fourteen. */
    private fun hiddenSets(ids: List<String>): List<Set<String>> =
        (0..MAX_HIDDEN_BLOCK_MOVES).flatMap { subsets(ids, sized = it) }

    private fun subsets(ids: List<String>, sized: Int): List<Set<String>> {
        if (sized <= 0) return listOf(emptySet())
        if (ids.size < sized) return emptyList()
        val out = mutableListOf<Set<String>>()
        for ((offset, id) in ids.withIndex()) {
            for (rest in subsets(ids.drop(offset + 1), sized = sized - 1)) {
                out += rest + id
            }
        }
        return out
    }

    // MARK: - The warm-up

    private fun warmupSec(session: Int, opening: Pattern?, hiding: Set<String>): Int =
        Warmup.moves(sessionNumber = session, opening = opening, hiding = hiding).sumOf { cost(it) }

    /** The dearest warm-up a session can draw with `hidden` set aside: every
     *  session of the rotation against every opening. "What the warm-up
     *  costs" is a claim about EVERY composition, even now that each one is
     *  six equal slots — that equality is what this keeps true. */
    private fun worstWarmupSec(hiding: Set<String>): Int =
        (1..Warmup.rotationPeriod).maxOf { session ->
            openings.maxOf { warmupSec(session = session, opening = it, hiding = hiding) }
        }

    /** …over every set the athlete can set aside: the whole shipped space, and
     *  the number the reserve has to hold. */
    private fun worstWarmupSec(): Int =
        hiddenSets(warmupPoolIDs).maxOfOrNull { worstWarmupSec(hiding = it) } ?: 0

    /** Every composition the app can draw — each set the athlete can set
     *  aside, against every session of the rotation and every opening — with
     *  a name that says which, for the failure message. */
    private fun forEveryComposition(check: (moves: List<WarmupMove>, hidden: Set<String>, named: String) -> Unit) {
        for (hidden in hiddenSets(warmupPoolIDs)) {
            for (session in 1..Warmup.rotationPeriod) {
                for (opening in openings) {
                    val moves = Warmup.moves(sessionNumber = session, opening = opening, hiding = hidden)
                    check(moves, hidden,
                          "session $session, opening ${opening?.rawValue ?: "none"}, set aside ${hidden.sorted()}")
                }
            }
        }
    }

    // MARK: - The cool-down

    /**
     * The dearest six the pool holds — a CEILING, and a tight one.
     *
     * Every composition is exactly six DISTINCT positions of the nine whatever
     * is set aside (`everyCompositionIsSixOfThePool` pins that), so nothing
     * the composer can draw costs more than the six dearest; and
     * `reachableCooldownSec()` shows a real session reaching it, which is what
     * makes this the worst case and not merely a bound.
     *
     * A ceiling rather than a cross product for cost alone: the cool-down's
     * other input is the workout, and 130 hidden sets against 1024 movement
     * subsets in two orders is a quarter of a million compositions. The
     * warm-up, whose only other input is the session number, is enumerated
     * outright above.
     */
    private fun worstCooldownSec(): Int =
        cooldownPool.map { cost(it) }.sortedDescending().take(Cooldown.positionCount).sum()

    /** What a session can actually draw with nothing set aside — every subset of
     *  the movements, in both orders, because the composition maps `performed`
     *  in order and tops up from the pool, so order is part of the input. */
    private fun reachableCooldownSec(): Int {
        var worst = 0
        val all = Pattern.allCases
        for (mask in 0 until (1 shl all.size)) {
            val performed = all.filterIndexed { offset, _ -> mask and (1 shl offset) != 0 }
            if (performed.isEmpty()) continue
            for (ordered in listOf(performed, performed.reversed())) {
                val sec = Cooldown.positions(performed = ordered).sumOf { cost(it) }
                worst = maxOf(worst, sec)
            }
        }
        return worst
    }

    /** The inputs the six-of-the-pool check walks: one movement (the maximum
     *  top-up, where the fixed frame and the pool order do all the work), and
     *  the whole session in both orders (the minimum). The cost of the block is
     *  pinned by the ceiling above; what these have to show is that the
     *  composer still fills six slots however much is set aside. */
    private val cooldownInputs: List<List<Pattern>>
        get() = Pattern.allCases.map { listOf(it) } + listOf(Pattern.allCases, Pattern.allCases.reversed())

    // MARK: - The reserve

    @Test
    fun theWorstCompositionFitsTheEngineReserve() {
        val reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        assertEquals(600, reserve, "the reserve is 10:00")
        assertTrue(worstWarmupSec() + worstCooldownSec() <= reserve,
                   "the worst composition of the two blocks overruns the engine's reserve")
    }

    /**
     * A reserve is whole minutes and the blocks are not, so there is no
     * equality to pin — and with no assert here nothing would watch the two
     * numbers at all. What is pinned is what the reserve still HAS to be.
     *
     * Nine minutes would hold the worst pair. **The owner keeps ten**: giving
     * the minute back is an engine change — `cooldownMin` 4 → 3 through the
     * whole reference chain — and it would take a minute off every announced
     * duration, off the onboarding line and off the store listing, to buy
     * slack nobody is short of.
     *
     * So two properties, and the names say which is which. The floor is
     * safety and is not negotiable: the blocks must never overrun what the
     * engine reserves. The ceiling is drift: one spare minute is a decision,
     * two would mean the reserve had quietly stopped being about the blocks.
     */
    @Test
    fun theReserveHoldsTheBlocksWithOneSpareMinuteAtMost() {
        val reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        val worst = worstWarmupSec() + worstCooldownSec()
        assertEquals(500, worst, "the worst pair the app can compose is 228 + 272")
        assertTrue(reserve - worst >= 0, "the blocks overrun what the engine reserves")
        assertTrue(reserve - worst < 120,
                   "two whole minutes of slack: the reserve is no longer " +
                       "sized against the blocks it exists for")
    }

    /** The two halves separately, so a failure says WHICH block moved. The
     *  warm-up's offer screen names a length before the person agrees to it,
     *  and the one thing it must never do is under-promise — a block that
     *  overruns what it said is worse than one that beats it.
     *
     *  Derived from the same composition the reserve above is, and over the same
     *  hiding axis: the offer screen reads `warmupMoves`, which is the hidden set
     *  applied, so a promise checked without it is a promise checked on another
     *  block. */
    @Test
    fun theWarmupOfferNeverPromisesLessThanTheBlockTakes() {
        forEveryComposition { moves, _, named ->
            val announced = Warmup.introMinutes(moves)
            val actual = moves.sumOf { cost(it) }
            assertTrue(announced * 60 >= actual,
                       "$named: the offer promises $announced min " +
                           "for a block that takes $actual s")
            // And not absurdly more: rounding up one minute, never two.
            assertTrue(announced * 60 < actual + 60, "$named: the offer overstates the block by a minute")
        }
    }

    /** Six slots, each a transition plus the move itself — the whole of a
     *  warm-up before any supplement or switch pause is added. */
    private val slotsSec: Int
        get() = Warmup.moveCount * (GetReady.seconds + Warmup.moveSeconds)

    @Test
    fun eachBlockCostsWhatTheSpecSays() {
        // EVERY composition, and written as arithmetic over the composition
        // rather than as a literal total, because a total hides the transition
        // length inside it, and changing the transition would break asserts
        // that are only ever about the composition. The slot cost belongs to
        // `GetReady`, and the test asks it.
        //
        // Six equal slots, whatever is set aside and whatever the session opens
        // on: no move pays the trip to the floor, and no circle pays a pause.
        forEveryComposition { moves, _, named ->
            assertEquals(0, moves.count { it.needsSetup }, "$named: a standing block pays no supplement")
            assertEquals(slotsSec, moves.sumOf { cost(it) }, named)
        }
        assertEquals(228, worstWarmupSec(hiding = emptySet()),
                     "with nothing set aside the warm-up is 228 s")
        assertEquals(228, worstWarmupSec(), "and with anything set aside, the same 228 s")
        assertEquals(272, worstCooldownSec(), "the worst cool-down the app can compose is 272 s")
        // The dearest six of the pool is the BOUND the reserve is measured
        // against, and a real session reaches it exactly — which is what makes
        // it the worst case and not merely a bound.
        assertEquals(272, reachableCooldownSec(), "the dearest cool-down a real session reaches")
        assertTrue(reachableCooldownSec() <= worstCooldownSec(),
                   "a real session cannot beat the ceiling the reserve " +
                       "is measured against")
    }

    /** The period the sweeps walk, pinned: a loop bound nothing pins is a loop
     *  that can quietly stop covering the compositions it claims to — any
     *  value of four or more kept every other assertion here green. Twenty is
     *  the least common multiple of the groups (1, 2, 5 and 4), and the
     *  rotation really does come round after it, for every opening. */
    @Test
    fun theRotationComesRoundAfterTwentySessions() {
        assertEquals(20, Warmup.rotationPeriod)
        for (session in 1..Warmup.rotationPeriod) {
            for (opening in openings) {
                assertEquals(
                    Warmup.moves(session, opening).map { it.id },
                    Warmup.moves(session + Warmup.rotationPeriod, opening).map { it.id },
                    "session $session, opening ${opening?.rawValue ?: "none"}")
            }
        }
        val distinct = (1..Warmup.rotationPeriod).map { s -> Warmup.moves(s, null).map { it.id } }.toSet()
        assertEquals(Warmup.rotationPeriod, distinct.size,
                     "no shorter period: every session of the twenty composes its own block")
    }

    /** Fourteen in the pool, six on screen, and every move gets its turn — a
     *  movement that never appears is a movement that is not in the app. The
     *  two lead-in-only moves appear only through the opening that calls for
     *  them, which is why the sweep walks the openings too. */
    @Test
    fun everyMoveInThePoolIsReachable() {
        val seen = mutableSetOf<String>()
        for (session in 1..Warmup.rotationPeriod) {
            for (opening in openings) {
                val moves = Warmup.moves(sessionNumber = session, opening = opening)
                assertEquals(Warmup.moveCount, moves.size, "session $session")
                assertEquals(moves.size, moves.map { it.id }.toSet().size, "session $session: no move twice")
                seen += moves.map { it.id }
            }
        }
        assertEquals(14, seen.size, "all fourteen moves of the pool are reachable")
    }

    /** The block's one specific part: the last move prepares the first
     *  exercise. Every pattern lands on a move of the pool, the four that open
     *  a session today on the move their own work calls for, and a lead-in set
     *  aside gives its slot back to the rotation rather than shortening the
     *  block. */
    @Test
    fun theLastMoveLeadsIntoTheFirstExercise() {
        val pool = warmupPoolIDs.toSet()
        for (pattern in Pattern.allCases) {
            assertTrue(Warmup.leadIn(pattern) in pool, "$pattern: no such move")
            for (session in 1..Warmup.rotationPeriod) {
                assertEquals(Warmup.leadIn(pattern), Warmup.moves(sessionNumber = session, opening = pattern).last().id,
                             "session $session, $pattern")
            }
        }
        assertEquals("half-squats", Warmup.leadIn(Pattern.squat))
        assertEquals("hip-hinges", Warmup.leadIn(Pattern.hinge))
        assertEquals("arm-swings", Warmup.leadIn(Pattern.pushH))
        assertEquals("reach-and-pull", Warmup.leadIn(Pattern.pull))
        val without = Warmup.moves(sessionNumber = 1, opening = Pattern.squat, hiding = setOf("half-squats"))
        assertEquals(Warmup.moveCount, without.size)
        assertFalse(without.map { it.id }.contains("half-squats"))
    }

    /** The reason the slots draw from GROUPS: every composition raises the
     *  pulse, moves the shoulders and moves the trunk, unless the athlete has
     *  set aside every move a group has. A single window over one list kept
     *  that only while the list's order was intact, and a set-aside move broke
     *  the order. */
    @Test
    fun everyGroupIsDrawnUnlessAllOfItIsSetAside() {
        val groups = listOf(
            "raise" to setOf("marching", "side-steps", "heels-to-glutes"),
            "upper" to setOf("arm-circles", "arm-swings", "reach-and-pull", "wrist-circles", "overhead-reaches"),
            "trunk" to setOf("torso-rotations", "side-bends", "hip-circles", "standing-cat-cow"),
        )
        forEveryComposition { moves, hidden, named ->
            val ids = moves.map { it.id }.toSet()
            for ((name, members) in groups) {
                if (hidden.containsAll(members)) continue
                assertTrue(ids.any { it in members }, "$named: no $name move")
            }
        }
    }

    /** Six on screen whatever is set aside — the `Warmup.honoured` guarantee.
     *  A block of five would still fit the reserve and still be wrong, and a
     *  block of none indexes out of bounds on its first screen, which is why
     *  this is asserted rather than left to the composer's arithmetic. */
    @Test
    fun theWarmupIsSixMovesWhateverIsSetAside() {
        forEveryComposition { moves, hidden, named ->
            assertEquals(Warmup.moveCount, moves.size, named)
            assertEquals(moves.size, moves.map { it.id }.toSet().size, "$named: no move twice")
            assertTrue(moves.all { it.id !in hidden }, "$named: a set-aside move came back")
        }
        // More than the block can afford: a state file from another build, an
        // imported backup or a future cap. `honoured` is where that is survived,
        // so it is asserted and not assumed — and what it must never do is
        // shorten the block.
        val pool = warmupPoolIDs.toSet()
        for (session in 1..Warmup.rotationPeriod) {
            for (opening in openings) {
                assertEquals(Warmup.moveCount,
                             Warmup.moves(sessionNumber = session, opening = opening, hiding = pool).size,
                             "session $session with the whole pool set aside")
            }
        }
    }

    /** The claim `worstCooldownSec()` rests on: whatever is set aside, the block
     *  is six distinct positions OF THE POOL, so the dearest six of the pool is
     *  a ceiling on what it can cost. */
    @Test
    fun everyCompositionIsSixOfThePool() {
        val pool = cooldownPool
        val ids = pool.map { it.id }
        assertEquals(9, ids.size, "nine in the cool-down pool")
        for (hidden in hiddenSets(ids)) {
            for (performed in cooldownInputs) {
                val composed = Cooldown.positions(performed = performed, hiding = hidden)
                val named = "${performed.size} movements, set aside ${hidden.sorted()}"
                assertEquals(Cooldown.positionCount, composed.size, named)
                assertEquals(composed.size, composed.map { it.id }.toSet().size, "$named: no position twice")
                assertTrue(ids.toSet().containsAll(composed.map { it.id }), "$named: a position from outside the pool")
                assertTrue(composed.all { it.id !in hidden }, "$named: a set-aside position came back")
            }
        }
        // The same overflow the warm-up survives, for the same reason.
        assertEquals(Cooldown.positionCount, Cooldown.positions(performed = Pattern.allCases, hiding = ids.toSet()).size,
                     "the whole pool set aside still composes a block")
    }

    // MARK: - Where a recomposed block picks up
    //
    // The same composition rule read the other way. A block running when the
    // athlete sets a move aside has to land somewhere in the list that comes
    // back, and `WorkoutSession.rebaseLanding` is the rule both blocks use.
    // The two scenarios below are the ones a clamp of the ordinal gets wrong.

    /** Session 4, opening on a squat, runs [marching, heels to glutes, wrist
     *  circles, overhead reaches, standing cat-cow, half squats]. Setting
     *  overhead reaches aside on slot 3 does not delete a slot: the shoulders'
     *  rotation passes its turn on to arm circles, which the pool lists FIRST,
     *  so arm circles arrive at slot 2 and wrist circles slide to 3. Clamping
     *  the ordinal would therefore close the sheet onto a transition for wrist
     *  circles — a move finished a minute earlier. */
    @Test
    fun hidingTheMoveOnScreenNeverReopensOneAlreadyDone() {
        val before = Warmup.moves(sessionNumber = 4, opening = Pattern.squat).map { it.id }
        assertEquals(listOf("marching", "heels-to-glutes", "wrist-circles",
                            "overhead-reaches", "standing-cat-cow", "half-squats"), before,
                     "the composition this was measured on")
        val after = Warmup.moves(sessionNumber = 4, opening = Pattern.squat,
                                 hiding = setOf("overhead-reaches")).map { it.id }
        // The passed set is the prefix of the list that WAS running: slots 0…2,
        // the athlete standing on slot 3.
        val passed = before.take(3).toSet()
        assertTrue(after[3] in passed, "the ordinal the clamp kept names a move already done")
        val landing = assertNotNull(WorkoutSession.rebaseLanding(after, after = passed))
        assertEquals("standing-cat-cow", after[landing])
        assertFalse(after[landing] in passed, "the block reopened a finished move")
    }

    /** The cool-down's twin, and the one the athlete cannot even see coming:
     *  "Bring back" does not dismiss the technique sheet. A cool-down composed
     *  with the wall stretch set aside is [hip flexors, forward fold, lat, wrists,
     *  lying twist, rest pose]; restoring it on slot 5 re-inserts into the
     *  opening and pushes everything after it one slot right, so a clamped
     *  ordinal would name the wrists — already done. */
    @Test
    fun bringingAPositionBackNeverReopensOneAlreadyDone() {
        val performed = listOf(Pattern.squat, Pattern.pull, Pattern.pushH, Pattern.coreRot)
        val before = Cooldown.positions(performed = performed, hiding = setOf("chest-wall")).map { it.id }
        assertEquals(listOf("hip-flexors", "forward-fold", "lat-stretch",
                            "wrists", "lying-twist", "rest-pose"), before)
        val after = Cooldown.positions(performed = performed, hiding = emptySet()).map { it.id }
        val passed = before.take(4).toSet()
        assertTrue(after[4] in passed, "the ordinal the clamp kept names a position already done")
        val landing = assertNotNull(WorkoutSession.rebaseLanding(after, after = passed))
        assertEquals("rest-pose", after[landing])
        assertFalse(after[landing] in passed, "the block reopened a finished stretch")
    }

    /** The rule itself, at its three ends. Forward-only is the invariant: a
     *  landing behind the athlete would be replayed slot by slot by the ordinal
     *  machine that advances from it, and a block whose every slot is behind
     *  them is over rather than repeated. */
    @Test
    fun theLandingIsForwardOnlyAndEndsTheBlockWhenNothingIsLeft() {
        val ids = listOf("a", "b", "c")
        assertEquals(0, WorkoutSession.rebaseLanding(ids, after = emptySet()),
                     "nothing behind the athlete: the block opens where it is")
        assertEquals(1, WorkoutSession.rebaseLanding(ids, after = setOf("a")))
        // Measured from the LAST id behind them, not from the first one that is
        // not: "b" sits between two passed slots, and landing on it would put
        // the ordinal machine back through "c".
        assertNull(WorkoutSession.rebaseLanding(ids, after = setOf("a", "c")),
                   "every slot is behind the athlete: the block is over")
        assertEquals(0, WorkoutSession.rebaseLanding(ids, after = setOf("x")),
                     "a set-aside id that is not in the list moves nothing")
        assertNull(WorkoutSession.rebaseLanding(emptyList(), after = emptySet()))
    }

    /** Pinned by value on purpose: these two numbers are spent against a reserve
     *  the ENGINE owns, so neither may drift without the arithmetic above being
     *  re-read. */
    @Test
    fun theTransitionIsEightSecondsAndTheSupplementIsFour() {
        assertEquals(8, GetReady.seconds)
        assertEquals(4, GetReady.setupSupplementSec)
        assertEquals(8, GetReady.stageSeconds(needsSetup = false))
        assertEquals(12, GetReady.stageSeconds(needsSetup = true))
    }

    /** The side-switch pause does not follow the transition: it is a pause
     *  inside one position, not travel to another. Four seconds is on trial.
     *  Pinned by value so the revert is a red test and not a shrug: the pause
     *  is judged in use, and a number under trial has to be visible when it
     *  moves. */
    @Test
    fun theSideSwitchPauseIsOnTrialAtFour() {
        assertEquals(4, Cooldown.sideSwitchPauseSec)
        // The warm-up owns no pause of its own: its circles reverse on the
        // move, and a second constant for a gesture it does not make would
        // only wait for someone to wire it back in.
        assertEquals(Cooldown.sideSwitchPauseSec,
                     GuidedBlock.warmup.stageSeconds(GuidedStage.switchPause,
                                                     Warmup.moves(sessionNumber = 1, opening = Pattern.squat)[0]))
        assertEquals(Warmup.moveSeconds / 2, Warmup.halfSeconds)
        assertEquals(Cooldown.sideSeconds, Warmup.halfSeconds, "both blocks split a 30 s slot the same way")
    }
}
