//
//  Port of ios/DredfitTests/BlockReserveTests.swift: the warm-up and
//  cool-down reserve, and the arithmetic that makes the transition length an
//  ENGINE constraint rather than an app preference.
//
//  `warmupMin + cooldownMin` is the whole budget the engine sets aside for the
//  two blocks. The worst pair leaves 76 s of it over (464 of 540), and every
//  second added to the transition costs six per block. The cool-down binds
//  first: 236 s of its own 240 leave four, so a nine-second transition
//  overruns its minutes (`eachBlockFitsItsOwnShareOfTheReserve`) — a change to
//  the engine, because the reserve is the engine's.
//
//  SHORTENING is the direction that does not break, until the slack outgrows
//  what the reserve is for: once the cool-down stopped pausing on the spot,
//  ten minutes would have held 136 s spare, so the tenth minute went back to
//  every announced duration (`warmupMin` 6 → 5). What is asserted below is a
//  floor and a ceiling, not an equality: the blocks may never overrun the
//  reserve, and the reserve may never hold two spare minutes.
//
//  Everything below is computed from the app's own constants and from the real
//  composition rule, never from the spec's numbers restated. The worst case is
//  found by ENUMERATING the sets a session can actually produce rather than by
//  assuming which six positions are dearest: if the pool, the mapping or a hold
//  ever moves, this fails here instead of on somebody's stopwatch.
//
//  And it enumerates the axis the APP has: both composers take a `hiding` set,
//  and `Warmup.moves(sessionNumber, opening)` / `Cooldown.positions(sessionNumber)`
//  — the forms without it — are for the tests alone. The standing warm-up costs
//  the same whatever is set aside (every slot is a transition and thirty
//  seconds), but that is exactly the kind of claim the sweep exists to keep
//  true: a set-aside move changes which moves a session draws, and a claim
//  measured without the hiding axis is measured on compositions the app does
//  not draw.
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
import com.dredfit.workout.cooldownMinutes
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

    /** One cool-down position: every stage the block's machine walks it
     *  through, walked for the reason the warm-up's cost gives — a position
     *  whose switch started pausing again costs four more seconds here. */
    private fun cost(position: CooldownPosition): Int {
        var step: GuidedBlock.Step? = GuidedBlock.Step(0, GuidedStage.getReady)
        var seconds = 0
        while (step != null) {
            seconds += GuidedBlock.cooldown.stageSeconds(step.stage, position)
            step = GuidedBlock.step(step, listOf(position))
        }
        return seconds
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

    /** The ten positions of the cool-down pool, likewise — each position of
     *  session one set aside in turn, over the rotation, because a fallback
     *  only appears once its zone's first choice is gone. */
    private val cooldownPoolIDs: List<String>
        get() {
            val ids = mutableListOf<String>()
            val first = Cooldown.positions(sessionNumber = 1).map { it.id }
            for (hidden in listOf(emptyList<String>()) + first.map { listOf(it) }) {
                for (session in 1..Cooldown.rotationPeriod) {
                    for (position in Cooldown.positions(sessionNumber = session, hiding = hidden.toSet())) {
                        if (position.id !in ids) ids += position.id
                    }
                }
            }
            return ids
        }

    /** Every set the athlete can actually put in `hiddenBlockMoveIDs`. The cap
     *  is the app's, not a number chosen here — 470 subsets of fourteen for the
     *  warm-up, 176 of ten for the cool-down. */
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

    /** The dearest cool-down the app can compose, ENUMERATED: the block's only
     *  inputs are the session number and the hidden set, so every composition
     *  there is fits in 2 × 176. */
    private fun worstCooldownSec(): Int =
        hiddenSets(cooldownPoolIDs).flatMap { hidden ->
            (1..Cooldown.rotationPeriod).map { session ->
                Cooldown.positions(sessionNumber = session, hiding = hidden).sumOf { cost(it) }
            }
        }.maxOrNull() ?: 0

    /** …and with nothing set aside: what every session costs before anyone has
     *  said anything. */
    private fun plainCooldownSec(): List<Int> =
        (1..Cooldown.rotationPeriod).map { session ->
            Cooldown.positions(sessionNumber = session).sumOf { cost(it) }
        }

    // MARK: - The reserve

    @Test
    fun theWorstCompositionFitsTheEngineReserve() {
        val reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        assertEquals(540, reserve, "the reserve is 9:00")
        assertTrue(worstWarmupSec() + worstCooldownSec() <= reserve,
                   "the worst composition of the two blocks overruns the engine's reserve")
    }

    /**
     * A reserve is whole minutes and the blocks are not, so there is no
     * equality to pin — and with no assert here nothing would watch the two
     * numbers at all. What is pinned is what the reserve still HAS to be.
     *
     * Nine minutes is the smallest whole minute that holds the worst pair.
     * Ten held 136 s spare once the cool-down stopped pausing on the spot, so
     * the minute went back to every announced duration — through the
     * reference chain, because the reserve is the engine's.
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
        assertEquals(464, worst, "the worst pair the app can compose is 228 + 236")
        assertTrue(reserve - worst >= 0, "the blocks overrun what the engine reserves")
        assertTrue(reserve - worst < 120,
                   "two whole minutes of slack: the reserve is no longer " +
                       "sized against the blocks it exists for")
    }

    /** Each block inside its OWN minutes, not only the pair inside their sum.
     *  The energy estimate charges a block at most its own share of the
     *  reserve (`EnergyEstimate.segments`), so a cool-down that ran on the
     *  warm-up's spare seconds would be billed short of what it took. */
    @Test
    fun eachBlockFitsItsOwnShareOfTheReserve() {
        assertTrue(worstWarmupSec() <= EngineConfig.warmupMin * 60, "the warm-up overruns its own minutes")
        assertTrue(worstCooldownSec() <= EngineConfig.cooldownMin * 60, "the cool-down overruns its own minutes")
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

    /** The cool-down's offer, likewise over every composition the app can draw.
     *  Its minutes come from `WorkoutSession.cooldownMinutes`, a formula of its
     *  own, and the block's cost from the stage machine walked here: two
     *  derivations, so a rounding gone the wrong way shows. */
    @Test
    fun theCooldownOfferNeverPromisesLessThanTheBlockTakes() {
        for (hidden in hiddenSets(cooldownPoolIDs)) {
            for (session in 1..Cooldown.rotationPeriod) {
                val positions = Cooldown.positions(sessionNumber = session, hiding = hidden)
                val announced = WorkoutSession.cooldownMinutes(positions)
                val actual = positions.sumOf { cost(it) }
                val named = "session $session, set aside ${hidden.sorted()}"
                assertTrue(announced * 60 >= actual, "$named: the offer promises $announced min for $actual s")
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
        // Six slots, one trip down and the kneeling lunge's re-set. The
        // standing lunge replaces the kneeling one and refills nothing else,
        // so no composition plays two pauses — the worst is the plain block.
        assertEquals(listOf(236, 236), plainCooldownSec(),
                     "with nothing set aside every session of the rotation is 236 s")
        assertEquals(236, worstCooldownSec(), "and with anything set aside, never more")
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
     *  is six distinct positions of the pool, none of them set aside — so the
     *  sweep over sessions and hidden sets is every block there is. */
    @Test
    fun everyCompositionIsSixOfThePool() {
        val ids = cooldownPoolIDs
        assertEquals(10, ids.size, "ten in the cool-down pool")
        for (hidden in hiddenSets(ids)) {
            for (session in 1..Cooldown.rotationPeriod) {
                val composed = Cooldown.positions(sessionNumber = session, hiding = hidden)
                val named = "session $session, set aside ${hidden.sorted()}"
                assertEquals(Cooldown.positionCount, composed.size, named)
                assertEquals(composed.size, composed.map { it.id }.toSet().size, "$named: no position twice")
                assertTrue(ids.toSet().containsAll(composed.map { it.id }), "$named: a position from outside the pool")
                assertTrue(composed.all { it.id !in hidden }, "$named: a set-aside position came back")
            }
        }
        // The same overflow the warm-up survives, for the same reason.
        assertEquals(Cooldown.positionCount, Cooldown.positions(sessionNumber = 1, hiding = ids.toSet()).size,
                     "the whole pool set aside still composes a block")
    }

    // MARK: - Where a recomposed block picks up
    //
    // The same composition rule read the other way. A block running when the
    // athlete sets a move aside has to land somewhere in the list that comes
    // back, and `WorkoutSession.rebaseLanding` is the rule both blocks use.
    // The scenarios below are the ones a clamp of the ordinal gets wrong; the
    // cool-down's, with the floor its levels add, are in CooldownTest.

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
        val landing = assertNotNull(WorkoutSession.rebaseLanding(after, after = passed, notBefore = 0))
        assertEquals("standing-cat-cow", after[landing])
        assertFalse(after[landing] in passed, "the block reopened a finished move")
    }

    /** The warm-up's version of the dropped stand-in. A move set aside passes
     *  its group's turn to the next one, and bringing it back takes the turn
     *  back from a stand-in that may already be done: landing after the last
     *  move still in the list would run the brought-back move AND everything
     *  from the slot on screen on — seven moves in a block of six. */
    @Test
    fun bringingAMoveBackNeverLengthensTheWarmup() {
        for (id in warmupPoolIDs) {
            for (session in 1..Warmup.rotationPeriod) {
                val before = Warmup.moves(sessionNumber = session, opening = Pattern.squat, hiding = setOf(id))
                    .map { it.id }
                val after = Warmup.moves(sessionNumber = session, opening = Pattern.squat).map { it.id }
                if (after == before) continue
                for (slot in before.indices) {
                    val behind = before.take(slot)
                    val landing = WorkoutSession.rebaseLanding(after, after = behind.toSet(), notBefore = 0)
                    val run = behind + (landing?.let { after.drop(it) } ?: emptyList())
                    val named = "session $session, bringing $id back on slot $slot"
                    assertEquals(run.size, run.toSet().size, "$named: a move runs twice")
                    assertTrue(run.size <= Warmup.moveCount, "$named: the warm-up runs longer than it promised")
                }
            }
        }
    }

    /** The rule itself, at its ends. Forward-only is the invariant: a landing
     *  behind the athlete would be replayed slot by slot by the ordinal
     *  machine that advances from it, and a block whose every slot is behind
     *  them is over rather than repeated. */
    @Test
    fun theLandingIsForwardOnlyAndEndsTheBlockWhenNothingIsLeft() {
        val ids = listOf("a", "b", "c")
        assertEquals(0, WorkoutSession.rebaseLanding(ids, after = emptySet(), notBefore = 0),
                     "nothing behind the athlete: the block opens where it is")
        assertEquals(1, WorkoutSession.rebaseLanding(ids, after = setOf("a"), notBefore = 0))
        // Measured from the LAST id behind them, not from the first one that is
        // not: "b" sits between two passed slots, and landing on it would put
        // the ordinal machine back through "c".
        assertNull(WorkoutSession.rebaseLanding(ids, after = setOf("a", "c"), notBefore = 0),
                   "every slot is behind the athlete: the block is over")
        // A slot already used counts even when its move has left the list —
        // the stand-in a brought-back move replaces. Landing on "a" would run
        // four moves in a block of three.
        assertEquals(1, WorkoutSession.rebaseLanding(ids, after = setOf("x"), notBefore = 0),
                     "a move already done still took its slot")
        assertEquals(2, WorkoutSession.rebaseLanding(ids, after = emptySet(), notBefore = 2),
                     "the floor holds with nothing behind the athlete")
        assertNull(WorkoutSession.rebaseLanding(ids, after = emptySet(), notBefore = 3))
        assertNull(WorkoutSession.rebaseLanding(emptyList(), after = emptySet(), notBefore = 0))
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
