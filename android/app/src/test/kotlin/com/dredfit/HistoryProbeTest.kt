//
//  Port of ios/DredfitTests/HistoryProbeTests.swift: what the history sheet
//  says about a probe — and what it may not claim. All six tests; the line
//  is `HistorySheet.probeLine` (ui/progress/HistorySheet.kt), read as the
//  English it prints.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.journal.RecordedPosition
import com.dredfit.journal.WorkoutRecord
import com.dredfit.ui.progress.HistorySheet
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HistoryProbeTest {

    private val probe = SessionProbe(variation = 4, name = "Inverted row (table)", unit = LoadUnit.reps, load = 4, perSide = false)

    private fun exercise(withProbe: Boolean = true) = SessionExercise(
        pattern = Pattern.pull, name = "Mid-height inverted row", variation = 3, unit = LoadUnit.reps, load = 15,
        perSide = false, sets = 2, restSetSec = 60, restExerciseSec = 90, loads = null, probe = if (withProbe) probe else null)

    /** `variationAfter` is what the session ENDED on — the only thing the
     *  app may read the verdict off. */
    private fun record(variationAfter: Int, probes: Map<Pattern, Int>? = null, positions: Boolean = true) = WorkoutRecord(
        sessionNumber = 4, date = Instant.ofEpochSecond(1_000), result = FeedbackResult.plan,
        exercises = listOf(exercise()), probes = probes,
        positionsAfter = if (positions) mapOf(Pattern.pull to RecordedPosition(variation = variationAfter, sets = 3, dose = 4)) else null)

    private fun line(ex: SessionExercise, record: WorkoutRecord): String = assertNotNull(HistorySheet.probeLine(ex, record)).english

    // MARK: - With the number the probe showed

    @Test
    fun aPassedProbeNamesTheMovementAndWhatWasShown() {
        val line = line(exercise(), record(variationAfter = 4, probes = mapOf(Pattern.pull to 5)))
        assertTrue(line.contains("Inverted row (table)"), line)
        assertTrue(line.contains("5"), "the number the probe showed is the point: $line")
        assertTrue(line.contains("passed"), line)
    }

    @Test
    fun aProbeThatDidNotLandSaysSoWithoutBlame() {
        val line = line(exercise(), record(variationAfter = 3, probes = mapOf(Pattern.pull to 2)))
        assertTrue(line.contains("2"), line)
        assertTrue(line.contains("not this time"), "the same neutral words the work screen uses: $line")
        assertFalse(line.contains("passed"), line)
    }

    // MARK: - Without it

    /** No `probes` is either an old record or a probe never performed; the
     *  line drops the number and keeps the verdict, true of both. */
    @Test
    fun anOlderRecordStillGetsItsVerdictFromThePositionItEndedOn() {
        val passed = line(exercise(), record(variationAfter = 4))
        assertTrue(passed.contains("passed"), passed)
        assertTrue(passed.contains("Inverted row (table)"), passed)
        val unresolved = line(exercise(), record(variationAfter = 3))
        assertTrue(unresolved.contains("not this time"), unresolved)
    }

    // MARK: - When it must say nothing

    @Test
    fun anExerciseWithoutAProbeGetsNoLine() {
        assertNull(HistorySheet.probeLine(exercise(withProbe = false), record(variationAfter = 3, probes = mapOf(Pattern.pull to 4))))
    }

    /** No position on record is no evidence, and a verdict without evidence
     *  is a guess. */
    @Test
    fun aRecordWithoutPositionsClaimsNothing() {
        assertNull(HistorySheet.probeLine(exercise(), record(variationAfter = 4, positions = false)))
    }

    /** The stored name is frozen in the language of its day; the line
     *  resolves it through the library. */
    @Test
    fun theNameIsResolvedThroughTheLibraryNotReadFromTheSnapshot() {
        val stale = SessionProbe(variation = 4, name = "a name from another build", unit = LoadUnit.reps, load = 4, perSide = false)
        val ex = SessionExercise(pattern = Pattern.pull, name = "Mid-height inverted row", variation = 3, unit = LoadUnit.reps,
                                 load = 15, perSide = false, sets = 2, restSetSec = 60, restExerciseSec = 90, loads = null,
                                 probe = stale)
        val line = line(ex, WorkoutRecord(sessionNumber = 4, date = Instant.ofEpochSecond(1_000), result = FeedbackResult.plan,
                                          exercises = listOf(ex), probes = mapOf(Pattern.pull to 4),
                                          positionsAfter = mapOf(Pattern.pull to RecordedPosition(variation = 4, sets = 3, dose = 4))))
        assertFalse(line.contains("a name from another build"), line)
        assertTrue(line.contains(Library.name(Pattern.pull, 4)), line)
    }
}
