//
//  Port of ios/DredfitTests/RetrospectiveTests.swift: the "then → now" block
//  of an anniversary milestone — which movement it names, the lines it says,
//  and when it says nothing at all.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.journal.RecordedPosition
import com.dredfit.journal.WorkoutRecord
import com.dredfit.workout.Retrospective
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RetrospectiveTest {

    private fun record(daysAgo: Long, positionsAfter: Map<Pattern, RecordedPosition>?): WorkoutRecord =
        WorkoutRecord(
            sessionNumber = 1,
            date = ZonedDateTime.now(ZoneId.systemDefault()).minusDays(daysAgo).toInstant(),
            result = FeedbackResult.plan,
            totalProgressAfter = if (positionsAfter == null) null else 0,
            positionsAfter = positionsAfter)

    /** A flat baseline for every rotation pattern (no pull_bar by default —
     *  most journals predate the bar module). `variation` and `dose` are what
     *  a position IS: a scalar could not name one, because the measure has no
     *  inverse. */
    private fun base(variation: Int = 1, atCeiling: Boolean = false): MutableMap<Pattern, RecordedPosition> =
        Pattern.ordered.associateWith { p ->
            val grid = Dose.grid(Library.unit(p, variation))
            RecordedPosition(variation = variation, sets = 3, dose = if (atCeiling) grid.max else grid.min)
        }.toMutableMap()

    @Suppress("UNUSED_PARAMETER")
    private fun at(p: Pattern, variation: Int, dose: Int): RecordedPosition =
        RecordedPosition(variation = variation, sets = 3, dose = dose)

    // MARK: - Movement choice

    @Test
    fun picksTheLargestGain() {
        val current = base(variation = 1)
        current[Pattern.squat] = at(Pattern.squat, variation = 1, dose = 6)          // a few rungs
        current[Pattern.hinge] = at(Pattern.hinge, variation = 3, dose = 8)          // two variations up
        val retro = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = base())),
            current = current))
        assertTrue(retro.nowLine.english.contains(Library.name(Pattern.hinge, 3)),
                   "${retro.nowLine} should name the biggest gain (hinge)")
        assertTrue(retro.nowLine.english.contains("3×8"))
    }

    @Test
    fun tieBreaksInRotationOrder() {
        // squat and calf both gain the same number of rungs; squat comes first
        // in Pattern.allCases, which is the order the engine itself walks.
        val current = base()
        current[Pattern.squat] = at(Pattern.squat, variation = 1, dose = 8)
        current[Pattern.calf] = at(Pattern.calf, variation = 1, dose = 8)
        val retro = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = base())),
            current = current))
        assertTrue(retro.thenLine.english.contains(Library.name(Pattern.squat, 1)),
                   "tie must resolve to the earlier rotation slot")
    }

    /** The "then" line states the movement and the dose the plan actually
     *  asked for back then — not a number re-derived from a measure, which is
     *  the thing v3 cannot do. */
    @Test
    fun thenLineStatesThePositionItWasRecordedAt() {
        val start = base()
        start[Pattern.pushH] = at(Pattern.pushH, variation = 2, dose = 9)
        val current = base()
        current[Pattern.pushH] = at(Pattern.pushH, variation = 3, dose = 12)
        val retro = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = start)),
            current = current))
        assertTrue(retro.thenLine.english.contains(Library.name(Pattern.pushH, 2)),
                   "${retro.thenLine} must name the movement it was recorded at")
        assertTrue(retro.thenLine.english.contains("3×9"),
                   "${retro.thenLine} must state the dose it was recorded at")
    }

    @Test
    fun holdMovementFormatsAsSeconds() {
        val current = base()
        current[Pattern.coreAntiExt] = at(Pattern.coreAntiExt, variation = 2, dose = 30)
        val retro = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = base())),
            current = current))
        assertTrue(retro.nowLine.english.contains("3×30 s"),
                   "${retro.nowLine} should carry the hold in seconds")
    }

    // MARK: - Degradations

    @Test
    fun noSnapshotsMeansNoRetrospective() {
        assertNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = null)),
            current = base(variation = 2)))
        assertNull(Retrospective.make(records = emptyList(), current = base(variation = 2)))
    }

    @Test
    fun noGrowthMeansNoRetrospective() {
        assertNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = base(variation = 2))),
            current = base(variation = 2)),
            "standing still is not a story")
        assertNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = base(variation = 2))),
            current = base(variation = 1)),
            "a net drop must never be celebrated")
    }

    @Test
    fun baseIsTheFirstSnapshotNotTheFirstRecord() {
        // Record 1 predates the snapshot (nil) — which is also every record
        // written before v3. The base must be record 2, skipped silently.
        val retro = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 60, positionsAfter = null),
                             record(daysAgo = 40, positionsAfter = base())),
            current = base(variation = 2)))
        assertFalse(retro.thenLine.english.isEmpty())
    }

    @Test
    fun pullBarAbsentFromBaseIsExcluded() {
        // The bar module joined after the first workout: the current positions
        // have pull_bar, the base snapshot does not. Its big gain must not win.
        val current = base()
        current[Pattern.pullBar] = at(Pattern.pullBar, variation = 5, dose = 10)
        current[Pattern.lunge] = at(Pattern.lunge, variation = 2, dose = 5)    // the honest winner
        val retro = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 30, positionsAfter = base())),
            current = current))
        assertTrue(retro.thenLine.english.contains(Library.name(Pattern.lunge, 1)),
                   "${retro.thenLine}: a pattern without a base must not compete")
    }

    // MARK: - The since line

    @Test
    fun sinceLineSwitchesToMonthsAtNineWeeks() {
        val atEight = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 8L * 7, positionsAfter = base())),
            current = base(variation = 2)))
        assertTrue(atEight.sinceLine.english.contains("8"),
                   "${atEight.sinceLine} should still count weeks")

        val atNine = assertNotNull(Retrospective.make(
            records = listOf(record(daysAgo = 9L * 7, positionsAfter = base())),
            current = base(variation = 2)))
        assertTrue(atNine.sinceLine.english.contains("2"),
                   "${atNine.sinceLine} should have switched to months")
    }

    // MARK: - The sparse coordinates

    /** The delta that picks the movement is read off EVERY coordinate of the
     *  position, as the chart's `plot` is. The short `Engine.progress`
     *  overload drops `sub` and `cut`: read off it, growth that happened
     *  ENTIRELY in sub-steps would measure as zero, no pattern would beat the
     *  `> 0` bar, and the whole block would vanish for someone who had in fact
     *  grown. */
    @Test
    fun growthInSubStepsAloneIsSeen() {
        val flat = base(variation = 1)
        val current = flat.toMutableMap()
        val was = assertNotNull(flat[Pattern.squat])
        current[Pattern.squat] = RecordedPosition(variation = was.variation, sets = was.sets,
                                                  dose = was.dose, sub = 2)
        val retro = assertNotNull(
            Retrospective.make(records = listOf(record(daysAgo = 30, positionsAfter = flat)),
                               current = current),
            "two sub-steps are a gain — the block must not disappear")
        assertTrue(retro.nowLine.english.contains(Library.name(Pattern.squat, 1)),
                   "${retro.nowLine}: the movement that grew is the one to name")
    }

    /** The other direction of the same coordinate: a `cut` stands one step
     *  BELOW the position it was taken from. A base carrying one has grown by
     *  a step once the cut is gone — dropped, both sides would measure the same
     *  and the gain would be invisible. */
    @Test
    fun aCutOnTheBaseCountsAsGrowthOnceItIsGone() {
        val flat = base(variation = 1)
        val was = assertNotNull(flat[Pattern.squat])
        flat[Pattern.squat] = RecordedPosition(variation = was.variation, sets = was.sets,
                                               dose = was.dose, cut = 1)
        val retro = assertNotNull(
            Retrospective.make(records = listOf(record(daysAgo = 30, positionsAfter = flat)),
                               current = base(variation = 1)),
            "a set that was cut then and is not now is a step gained")
        assertTrue(retro.nowLine.english.contains(Library.name(Pattern.squat, 1)),
                   "${retro.nowLine}: the movement that grew is the one to name")
    }
}
