//
//  Port of ios/DredfitTests/BlockReserveTests.swift: the warm-up and
//  cool-down reserve, and the arithmetic that makes the transition length an
//  ENGINE constraint rather than an app preference.
//
//  `warmupMin + cooldownMin` is the whole budget the engine sets aside for the
//  two blocks. The worst pair leaves 80 s of it over (520 of 600), and every
//  second added to the transition costs twelve — six transitions per block —
//  so past 14 s the reserve breaks, which is a change to the engine.
//
//  SHORTENING it is the direction that does not break. The worst pair is 520 s
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
//  and `Warmup.moves(sessionNumber)` / `Cooldown.positions(performed)` — the
//  forms without it — are for the tests alone. A move set aside widens the
//  rotation's window, and the widened window draws a fourth split move, so a
//  reserve measured without the hiding axis is measured on compositions the
//  app does not draw.
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

    /** One warm-up move: its transition plus the slot. A split move is two
     *  halves with the switch pause between them, which is what
     *  `slotSeconds` answers — asked of the production function rather than
     *  restated here, for the reason GetReadyTest gives about its cool-down
     *  twin: two spellings of one formula agree only until one is edited. */
    private fun cost(move: WarmupMove): Int =
        GetReady.stageSeconds(needsSetup = move.needsSetup) + Warmup.slotSeconds(move)

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

    /** The nine ids of the warm-up pool, read off the compositions rather than
     *  typed here: `Warmup.pool` is private, and a hand-written copy would stop
     *  covering the pool the day a move is added to it. */
    private val warmupPoolIDs: List<String>
        get() {
            val ids = mutableListOf<String>()
            for (session in 1..Warmup.compositionCount) {
                for (move in Warmup.moves(sessionNumber = session)) if (move.id !in ids) ids += move.id
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
     *  is the app's, not a number chosen here — 130 subsets of nine. */
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

    private fun warmupSec(session: Int, hiding: Set<String>): Int =
        Warmup.moves(sessionNumber = session, hiding = hiding).sumOf { cost(it) }

    /** The dearest warm-up a session can draw with `hidden` set aside. The block
     *  composes six moves out of nine, so "what the warm-up costs" is a claim
     *  about EVERY composition — and they do not all cost the same: four moves
     *  of the pool have a halfway boundary, the rotation's window draws some of
     *  them on top of the permanent arm circles, and each pays a switch pause. */
    private fun worstWarmupSec(hiding: Set<String>): Int =
        (1..Warmup.compositionCount).maxOfOrNull { warmupSec(session = it, hiding = hiding) } ?: 0

    /** …over every set the athlete can set aside: 130 subsets against six
     *  sessions. Small, and it is the whole shipped space — this is the number
     *  the reserve has to hold. */
    private fun worstWarmupSec(): Int =
        hiddenSets(warmupPoolIDs).maxOfOrNull { worstWarmupSec(hiding = it) } ?: 0

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
        assertEquals(520, worst, "the worst pair the app can compose is 248 + 272")
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
        for (hidden in hiddenSets(warmupPoolIDs)) {
            for (session in 1..Warmup.compositionCount) {
                val moves = Warmup.moves(sessionNumber = session, hiding = hidden)
                val announced = Warmup.introMinutes(moves)
                val actual = moves.sumOf { cost(it) }
                val named = "session $session, set aside ${hidden.sorted()}"
                assertTrue(announced * 60 >= actual,
                           "$named: the offer promises $announced min " +
                               "for a block that takes $actual s")
                // And not absurdly more: rounding up one minute, never two.
                assertTrue(announced * 60 < actual + 60, "$named: the offer overstates the block by a minute")
            }
        }
    }

    /** Six slots, each a transition plus the move itself — the whole of a
     *  warm-up before any supplement or switch pause is added. */
    private val slotsSec: Int
        get() = Warmup.moveCount * (GetReady.seconds + Warmup.moveSeconds)

    @Test
    fun eachBlockCostsWhatTheSpecSays() {
        // EVERY composition, not just one, and written as arithmetic over the
        // composition rather than as a table of six numbers, because a table
        // says nothing about WHY they differ.
        //
        // DERIVED from the transition constants, not from the spec's totals
        // restated: a total typed as a literal hides the transition length
        // inside it, and changing the transition would break asserts that are
        // only ever about the composition. The slot cost belongs to `GetReady`,
        // and the test asks it.
        for (session in 1..Warmup.compositionCount) {
            val split = Warmup.moves(sessionNumber = session).count { it.isSplit }
            assertEquals(slotsSec + GetReady.setupSupplementSec + split * Cooldown.sideSwitchPauseSec,
                         warmupSec(session = session, hiding = emptySet()),
                         "composition $session draws $split split moves")
            assertTrue(split >= 2,
                       "arm circles are permanent and cat-cow is not split, " +
                           "so every composition pays at least the circles")
        }
        // Once a move can be set aside the total splits in two: the six slots
        // with their transitions, and the trip down to the floor only when the
        // composition HAS a floor move — three of the nine are on the floor,
        // and hiding all three is inside the cap.
        for (hidden in hiddenSets(warmupPoolIDs)) {
            for (session in 1..Warmup.compositionCount) {
                val moves = Warmup.moves(sessionNumber = session, hiding = hidden)
                val split = moves.count { it.isSplit }
                val setup = moves.count { it.needsSetup }
                val named = "session $session, set aside ${hidden.sorted()}"
                assertEquals(if (moves.any { it.onFloor }) 1 else 0, setup,
                             "$named: only the FIRST floor move pays the supplement")
                assertEquals(slotsSec + setup * GetReady.setupSupplementSec + split * Cooldown.sideSwitchPauseSec,
                             warmupSec(session = session, hiding = hidden),
                             "$named: $split split moves, $setup trip to the floor")
            }
        }
        assertEquals(244, worstWarmupSec(hiding = emptySet()),
                     "with nothing set aside the dearest warm-up is 244 s")
        assertEquals(248, worstWarmupSec(),
                     "the dearest warm-up the APP can compose is 248 s — a set-aside move " +
                         "widens the rotation's window onto a fourth split move")
        assertEquals(272, worstCooldownSec(), "the worst cool-down the app can compose is 272 s")
        // The dearest six of the pool is the BOUND the reserve is measured
        // against, and a real session reaches it exactly — which is what makes
        // it the worst case and not merely a bound.
        assertEquals(272, reachableCooldownSec(), "the dearest cool-down a real session reaches")
        assertTrue(reachableCooldownSec() <= worstCooldownSec(),
                   "a real session cannot beat the ceiling the reserve " +
                       "is measured against")
    }

    /** Four of the nine, and a composition with nothing set aside holds at most
     *  three. Named by id: "how many split" is a fact about WHICH movements
     *  they are. */
    @Test
    fun theSplitMovesAreTheFourThePoolNames() {
        val seen = mutableSetOf<String>()
        var worstInOneComposition = 0
        for (session in 1..Warmup.compositionCount) {
            val split = Warmup.moves(sessionNumber = session).filter { it.isSplit }
            seen += split.map { it.id }
            worstInOneComposition = maxOf(worstInOneComposition, split.size)
        }
        assertEquals(setOf("single-leg-rdl", "bird-dog", "arm-circles", "hip-circles"), seen)
        assertEquals(3, worstInOneComposition,
                     "the permanent circles plus the window of three, and three pauses")
        // A set-aside move widens that window, and a widened window draws all
        // FOUR. This is where the dearest warm-up the app can compose comes
        // from, and it is the whole reason the reserve is measured on the
        // hiding axis.
        val widest = hiddenSets(warmupPoolIDs).flatMap { hidden ->
            (1..Warmup.compositionCount).map { session ->
                Warmup.moves(sessionNumber = session, hiding = hidden).count { it.isSplit }
            }
        }.maxOrNull()
        assertEquals(4, widest, "with a move set aside a composition draws every split move")
    }

    /** Nine in the pool, six on screen, and every rotating move gets its turn
     *  — a movement that never appears is a movement that is not in the app. */
    @Test
    fun everyMoveInThePoolIsReachable() {
        val seen = mutableSetOf<String>()
        for (session in 1..Warmup.compositionCount) {
            val moves = Warmup.moves(sessionNumber = session)
            assertEquals(Warmup.moveCount, moves.size, "session $session")
            assertEquals(moves.size, moves.map { it.id }.toSet().size, "session $session: no move twice")
            seen += moves.map { it.id }
        }
        assertEquals(9, seen.size, "all nine moves of the pool are reachable")
        assertTrue(seen.containsAll(setOf("y-t-w", "bird-dog", "single-leg-rdl")),
                   "the three movements the ladders leave to the warm-up are in the block")
    }

    /** Six on screen whatever is set aside — the `Warmup.honoured` guarantee.
     *  A block of five would still fit the reserve and still be wrong, and a
     *  block of none indexes out of bounds on its first screen, which is why
     *  this is asserted rather than left to the composer's arithmetic. */
    @Test
    fun theWarmupIsSixMovesWhateverIsSetAside() {
        val pool = warmupPoolIDs
        for (hidden in hiddenSets(pool)) {
            for (session in 1..Warmup.compositionCount) {
                val moves = Warmup.moves(sessionNumber = session, hiding = hidden)
                val named = "session $session, set aside ${hidden.sorted()}"
                assertEquals(Warmup.moveCount, moves.size, named)
                assertEquals(moves.size, moves.map { it.id }.toSet().size, "$named: no move twice")
                assertTrue(moves.all { it.id !in hidden }, "$named: a set-aside move came back")
            }
        }
        // More than the block can afford: a state file from another build, an
        // imported backup or a future cap. `honoured` is where that is survived,
        // so it is asserted and not assumed — and what it must never do is
        // shorten the block.
        for (session in 1..Warmup.compositionCount) {
            assertEquals(Warmup.moveCount, Warmup.moves(sessionNumber = session, hiding = pool.toSet()).size,
                         "session $session with the whole pool set aside")
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

    /** Session 4 runs [marching, arm circles, single-leg RDL, cat-cow, bird dog,
     *  Y-T-W]. Setting bird dog aside on slot 5 does not delete a slot: the
     *  rotation re-derives, torso rotations arrives at slot 3 and cat-cow slides
     *  to 5. Clamping the ordinal would therefore close the sheet onto a
     *  transition for cat-cow — a move finished a minute earlier — and torso
     *  rotations, which nobody had seen, would never run. */
    @Test
    fun hidingTheMoveOnScreenNeverReopensOneAlreadyDone() {
        val before = Warmup.moves(sessionNumber = 4).map { it.id }
        assertEquals(listOf("marching", "arm-circles", "single-leg-rdl",
                            "cat-cow", "bird-dog", "y-t-w"), before,
                     "the composition this was measured on")
        val after = Warmup.moves(sessionNumber = 4, hiding = setOf("bird-dog")).map { it.id }
        // The passed set is the prefix of the list that WAS running: slots 0…3,
        // the athlete standing on slot 4.
        val passed = before.take(4).toSet()
        assertTrue(after[4] in passed, "the ordinal the clamp kept names a move already done")
        val landing = assertNotNull(WorkoutSession.rebaseLanding(after, after = passed))
        assertEquals("y-t-w", after[landing])
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
        // And the warm-up reads that same constant rather than owning a second
        // one: it is the same gesture in both blocks, and two
        // constants for it would part company the first time either moved.
        assertEquals(Cooldown.sideSwitchPauseSec, Warmup.switchPauseSeconds)
        assertEquals(Warmup.moveSeconds / 2, Warmup.halfSeconds)
        assertEquals(Cooldown.sideSeconds, Warmup.halfSeconds, "both blocks split a 30 s slot the same way")
    }
}
