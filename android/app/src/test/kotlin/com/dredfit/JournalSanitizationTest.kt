//
//  Port of ios/DredfitTests/JournalSanitizationTests.swift. The journal is an
//  input too: the engine heals the state it is handed, but its own snapshots
//  come back out of the store file and go straight into arithmetic.
//
//  Not ported: `testACorruptExerciseSnapshotCannotTrapTheDurationEstimate`
//  (the Health backfill, which arrives with health/).
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.Position
import com.dredfit.journal.RecordedPosition
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.currentPositions
import com.dredfit.store.gapDays
import com.dredfit.store.recentGaps
import com.dredfit.store.shouldOfferComeback
import com.dredfit.store.trainingDays
import com.dredfit.store.weekSummary
import com.dredfit.workout.Retrospective
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JournalSanitizationTest : AppStoreTestCase() {

    private fun store(records: String): AppStore = storeFrom("""
        {"engineState":{"counter":11,"vars":[${pairs { 2 }}],"doses":[${pairs { 10 }}],
                        "failStreak":[${pairs { 0 }}]},
         "records":[$records],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
    """)

    // MARK: - Numbers that would trap the arithmetic downstream

    /** A stored POSITION outside any ladder cannot trap the retrospective,
     *  which measures it and subtracts. The DOSE is the coordinate that can:
     *  `Dose.rung` subtracts the grid floor from it, so the reader clamps it
     *  to the technical range first. Both ends are walked, `sub`/`cut` with them. */
    @Test
    fun aStoredPositionOutsideTheLaddersCannotTrapTheRetrospective() {
        val s = store("""
            {"sessionNumber":1,"date":0,"result":"plan","totalProgressAfter":180,
             "positionsAfter":["squat",{"variation":-9223372036854775808,"sets":3,"dose":4},
                               "pull",{"variation":9223372036854775807,"sets":99,"dose":99},
                               "hinge",{"variation":1,"sets":3,
                                        "dose":-9223372036854775808,
                                        "sub":-9223372036854775808,
                                        "cut":-9223372036854775808},
                               "lunge",{"variation":1,"sets":3,
                                        "dose":9223372036854775807,
                                        "sub":9223372036854775807,
                                        "cut":9223372036854775807}]}
        """)
        val recorded = assertNotNull(s.records.firstOrNull()?.positionsAfter)
        for (p in listOf(Pattern.squat, Pattern.pull, Pattern.hinge, Pattern.lunge)) assertNotNull(recorded[p])
        // Measured on the whole-`Position` form, which the chart and the
        // retrospective call: on the short one `sub`/`cut` are never read.
        for ((p, position) in recorded) {
            val steps = Engine.progress(p, Position(variation = position.variation, sets = position.sets,
                                                    dose = position.dose, sub = position.sub ?: 0,
                                                    cut = position.cut ?: 0))
            assertTrue(steps >= 0, "$p: $steps")
            assertTrue(steps <= Engine.ladderSpan(p), "$p: $steps")
        }
        // The screen that does the subtraction still renders.
        Retrospective.make(records = s.records, current = s.currentPositions)
    }

    @Test
    fun aTotalOutsideAnyRealHistoryCannotTrapTheWeekSummary() {
        val s = store("""
            {"sessionNumber":9223372036854775807,"date":0,"result":"plan",
             "totalProgressAfter":-9223372036854775808},
            {"sessionNumber":2,"date":1000,"result":"plan",
             "totalProgressAfter":9223372036854775807}
        """)
        assertEquals(0, s.records.first().totalProgressAfter)
        assertEquals(EngineConfig.countMax, s.records.first().sessionNumber)
        assertEquals(EngineConfig.countMax, s.records.last().totalProgressAfter)
        assertNotNull(s.weekSummary(Instant.now()))
    }

    /** A date of 1e300 seconds decodes cleanly, and the gap math must not
     *  trap on it. INTENTIONAL DIFFERENCE: Swift's `Date` holds -1e300 and
     *  the gap saturates at countMax; java.time cannot hold it, so
     *  `SwiftJson.date` clamps a stored date to the years 1…9999 (documented
     *  there) and the far-past gap is the ~739 000 days since year 1 — still
     *  a number inside the technical ceiling, which is the property. */
    @Test
    fun aCorruptDateCannotTrapTheGapMath() {
        val s = store("""{"sessionNumber":1,"date":1e300,"result":"plan","totalProgressAfter":180}""")
        assertNotNull(s.gapDays(), "a nonsense date yields a number, not a crash")
        assertEquals(0, s.gapDays(), "a workout in the far future is not a break")
        assertEquals(emptyList(), s.recentGaps)
        s.shouldOfferComeback()

        val past = store("""{"sessionNumber":1,"date":-1e300,"result":"plan","totalProgressAfter":180}""")
        val gap = assertNotNull(past.gapDays())
        assertEquals(trainingDays(Instant.parse("0001-01-01T00:00:00Z"), Instant.now(), past.zone), gap,
                     "a far-past date is held to year 1 on the way in")
        assertTrue(gap in 700_000..EngineConfig.countMax, "and the gap stays inside the technical ceiling")
    }

    // MARK: - The valid domain is untouched

    @Test
    fun anOrdinaryRecordDecodesExactlyAsBefore() {
        val s = store("""
            {"sessionNumber":12,"date":0,"result":"more","totalProgressAfter":180,
             "positionsAfter":["squat",{"variation":3,"sets":3,"dose":11}],
             "durationSec":2100,
             "actuals":["squat",14],"healthExported":true}
        """)
        val r = assertNotNull(s.records.firstOrNull())
        assertEquals(12, r.sessionNumber)
        assertEquals(FeedbackResult.more, r.result)
        assertEquals(180, r.totalProgressAfter)
        assertEquals(RecordedPosition(variation = 3, sets = 3, dose = 11), r.positionsAfter?.get(Pattern.squat))
        assertEquals(2100, r.durationSec)
        assertEquals(14, r.actuals?.get(Pattern.squat))
        assertEquals(true, r.healthExported)
    }

    /** The per-set detail is journal too: values clamped, and an array longer
     *  than any exercise has sets cut back. */
    @Test
    fun perSetFactsAreSanitizedLikeTheRest() {
        val s = store("""
            {"sessionNumber":3,"date":0,"result":"plan","totalProgressAfter":40,
             "actuals":["squat",13],
             "setActuals":["squat",[15,15,10,-9223372036854775808,7,7,7,7]]}
        """)
        val r = assertNotNull(s.records.firstOrNull())
        assertEquals(13, r.actuals?.get(Pattern.squat))
        assertEquals(listOf(15, 15, 10, 0, 7), r.setActuals?.get(Pattern.squat),
                     "cut to the sets an exercise can have, every value inside its range")
    }

    @Test
    fun aRecordWithoutPerSetFactsStillDecodes() {
        val s = store("""
            {"sessionNumber":4,"date":0,"result":"less","totalProgressAfter":30,
             "actuals":["squat",11]}
        """)
        val r = assertNotNull(s.records.firstOrNull())
        assertEquals(11, r.actuals?.get(Pattern.squat))
        assertNull(r.setActuals, "records written before the per-set shape keep reading true")
    }

    @Test
    fun aRecordRoundTripsThroughEncodeAndDecode() {
        val original = WorkoutRecord(sessionNumber = 7, date = Instant.ofEpochSecond(1_000),
                                     result = FeedbackResult.plan, totalProgressAfter = 99,
                                     actuals = mapOf(Pattern.squat to 13),
                                     setActuals = mapOf(Pattern.squat to listOf(15, 15, 10)),
                                     probes = mapOf(Pattern.pull to 4),
                                     positionsAfter = mapOf(Pattern.squat to RecordedPosition(variation = 3, sets = 3, dose = 11)),
                                     durationSec = 1800)
        // Through text, as the file carries it.
        assertEquals(original, WorkoutRecord.fromJson(Json.parseToJsonElement(original.toJson().toString())))
    }

    /** The `probes` field from both sides: a file written before it carries no
     *  key and keeps reading true; a hand-edited number is clamped. */
    @Test
    fun aProbeNumberIsReadBackAndAHandEditedOneIsClamped() {
        val s = store("""{"sessionNumber":4,"date":0,"result":"plan","probes":["pull",5]}""")
        assertEquals(5, assertNotNull(s.records.firstOrNull()).probes?.get(Pattern.pull))

        val older = store("""{"sessionNumber":4,"date":0,"result":"plan","actuals":["squat",11]}""")
        assertNull(assertNotNull(older.records.firstOrNull()).probes, "a record written before the field must not invent one")

        val absurd = store("""{"sessionNumber":4,"date":0,"result":"plan","probes":["pull",-9223372036854775808]}""")
        assertEquals(0, assertNotNull(absurd.records.firstOrNull()).probes?.get(Pattern.pull),
                     "a number out of range is clamped, not carried into arithmetic")
    }
}
