//
//  Port of ios/DredfitTests/EnergyEstimateTests.swift: the calorie model,
//  pinned to arithmetic rather than to "about right" — a calorie estimate
//  reads in Health Connect exactly like a measured one, so every constant is
//  asserted against a hand-computed figure, and the resting ladder by WHICH
//  rung answered. Every Swift test is ported.
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.journal.BlockRun
import com.dredfit.workout.BodyProfile
import com.dredfit.workout.BodySex
import com.dredfit.workout.EnergyEstimate
import com.dredfit.workout.RestingRate
import com.dredfit.workout.RestingSource
import com.dredfit.workout.SessionSegments
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EnergyEstimateTest {

    /** 35 minutes: 5 warm-up, 9 of repetitions, 17 of rest, 4 of cool-down.
     *  Literals ON PURPOSE (the Swift file says why). */
    private val control = SessionSegments(warmupSec = 300.0, repWorkSec = 540.0, holdWorkSec = 0.0,
                                          restSec = 1020.0, cooldownSec = 240.0)
    private val kg = 80.0

    private fun standardResting(kg: Double): RestingRate =
        EnergyEstimate.resting(basalKcal = null, minutes = 35.0, bodyMassKg = kg, profile = BodyProfile.unknown)

    // MARK: - The number itself

    /** Gross = 111.3 MET-minutes × 1.4 = 155.82 kcal; resting 1.4 × 35 = 49. */
    @Test
    fun controlSessionAtEightyKilograms() {
        val kcal = assertNotNull(EnergyEstimate.activeKcal(control, kg, standardResting(kg)))
        assertEquals(155.82 - 49, kcal, 0.01)
    }

    @Test
    fun restingIsSubtractedNotIgnored() {
        val kcal = assertNotNull(EnergyEstimate.activeKcal(control, kg, standardResting(kg)))
        assertTrue(kcal < 155.82 * 0.75, "an estimate that ignores rest lands near the gross figure")
    }

    /** Mifflin for a 30-year-old man of 180 cm and 80 kg: 1780 kcal/day. */
    @Test
    fun mifflinRestingChangesTheAnswer() {
        val profile = BodyProfile(heightCm = 180.0, ageYears = 30.0, sex = BodySex.male)
        val resting = EnergyEstimate.resting(null, 35.0, kg, profile)
        assertEquals(RestingSource.mifflin, resting.source)
        val kcal = assertNotNull(EnergyEstimate.activeKcal(control, kg, resting))
        assertEquals(155.82 - 1780.0 / 1440 * 35, kcal, 0.01)
    }

    @Test
    fun theEstimateIsLinearInBodyMass() {
        val light = assertNotNull(EnergyEstimate.activeKcal(control, 60.0, standardResting(60.0)))
        val heavy = assertNotNull(EnergyEstimate.activeKcal(control, 120.0, standardResting(120.0)))
        assertEquals(light * 2, heavy, 0.01)
    }

    @Test
    fun anImpossibleBodyMassYieldsNothing() {
        for (mass in listOf(0.0, -80.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertNull(EnergyEstimate.activeKcal(control, mass, standardResting(80.0)), "$mass kg is not a body")
        }
    }

    @Test
    fun anImplausibleSegmentationYieldsNothing() {
        val broken = control.copy(restSec = -600.0)
        assertNull(EnergyEstimate.activeKcal(broken, kg, standardResting(kg)))
    }

    @Test
    fun holdsCostLessThanRepetitionsForTheSameSeconds() {
        val dynamic = control.copy(repWorkSec = 600.0)
        val isometric = control.copy(repWorkSec = 0.0, holdWorkSec = 600.0)
        val moving = assertNotNull(EnergyEstimate.activeKcal(dynamic, kg, standardResting(kg)))
        val holding = assertNotNull(EnergyEstimate.activeKcal(isometric, kg, standardResting(kg)))
        assertTrue(holding < moving)
    }

    // MARK: - The resting ladder

    @Test
    fun theRestingLadderPrefersHealthThenFormulaThenConstant() {
        val full = BodyProfile(heightCm = 180.0, ageYears = 30.0, sex = BodySex.male)
        val fromHealth = EnergyEstimate.resting(42.0, 35.0, kg, full)
        assertEquals(RestingSource.healthBasal, fromHealth.source)
        assertEquals(1.2, fromHealth.kcalPerMin, 0.0001)
        assertEquals(RestingSource.mifflin, EnergyEstimate.resting(null, 35.0, kg, full).source)
        assertEquals(RestingSource.standardMET, EnergyEstimate.resting(null, 35.0, kg, BodyProfile.unknown).source)
    }

    @Test
    fun anImplausibleBasalSumFallsThroughToTheNextRung() {
        val full = BodyProfile(heightCm = 180.0, ageYears = 30.0, sex = BodySex.male)
        assertEquals(RestingSource.mifflin, EnergyEstimate.resting(5.0, 35.0, kg, full).source)
        assertEquals(RestingSource.standardMET, EnergyEstimate.resting(5000.0, 35.0, kg, BodyProfile.unknown).source)
    }

    /** Half a profile is not a profile — and on Android the profile has no
     *  age at all (Health Connect has no date of birth), so the first of these
     *  is every Android phone: the ladder goes from the recorded rate
     *  straight to the constant. */
    @Test
    fun aPartialProfileDoesNotReachTheFormula() {
        for (profile in listOf(BodyProfile(heightCm = 180.0, ageYears = null, sex = BodySex.male),
                               BodyProfile(heightCm = null, ageYears = 30.0, sex = BodySex.male))) {
            assertEquals(RestingSource.standardMET, EnergyEstimate.resting(null, 35.0, kg, profile).source)
        }
    }

    @Test
    fun anUnstatedSexTakesTheMeanOfBothEquations() {
        val male = assertNotNull(EnergyEstimate.mifflinKcalPerMin(kg, 180.0, 30.0, BodySex.male))
        val female = assertNotNull(EnergyEstimate.mifflinKcalPerMin(kg, 180.0, 30.0, BodySex.female))
        for (unstated in listOf(BodySex.other, null)) {
            val mean = assertNotNull(EnergyEstimate.mifflinKcalPerMin(kg, 180.0, 30.0, unstated))
            assertEquals((male + female) / 2, mean, 0.000_001)
        }
        assertNotEquals(male, female, "the sex term must actually do something")
    }

    // MARK: - Segmentation

    private fun exercise(pattern: Pattern, unit: LoadUnit = LoadUnit.reps, load: Int, perSide: Boolean = false,
                         sets: Int, restSetSec: Int = 60, restExerciseSec: Int = 60): SessionExercise =
        SessionExercise(pattern = pattern, name = "x", variation = 1, unit = unit, load = load, perSide = perSide,
                        sets = sets, restSetSec = restSetSec, restExerciseSec = restExerciseSec, loads = null, probe = null)

    private fun segments(exercises: List<SessionExercise>, skipped: Set<Pattern> = emptySet(),
                         warmupSec: Int? = null, cooldownSec: Int? = null): SessionSegments =
        assertNotNull(EnergyEstimate.segments(exercises, skipped, warmupSec, cooldownSec))

    @Test
    fun segmentsReadTheEngineSBlockLengths() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)))
        assertEquals((EngineConfig.warmupMin * 60).toDouble(), seg.warmupSec)
        assertEquals((EngineConfig.cooldownMin * 60).toDouble(), seg.cooldownSec)
    }

    @Test
    fun segmentsCountWorkRestAndSides() {
        val plain = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3, restSetSec = 60, restExerciseSec = 90)))
        assertEquals(3 * 10 * 2.5, plain.repWorkSec)
        assertEquals((2 * 60 + 90).toDouble(), plain.restSec)

        val sided = segments(listOf(exercise(Pattern.lunge, load = 10, perSide = true, sets = 3,
                                             restSetSec = 60, restExerciseSec = 90)))
        assertEquals(plain.repWorkSec * 2, sided.repWorkSec)
        assertEquals(plain.restSec, sided.restSec)
    }

    @Test
    fun holdsLandInTheirOwnSegment() {
        val seg = segments(listOf(exercise(Pattern.coreAntiExt, unit = LoadUnit.hold, load = 30, sets = 3)))
        assertEquals(90.0, seg.holdWorkSec)
        assertEquals(0.0, seg.repWorkSec)
    }

    @Test
    fun aSkippedExerciseIsNotCharged() {
        val exercises = listOf(exercise(Pattern.squat, load = 10, sets = 3), exercise(Pattern.pushH, load = 10, sets = 3))
        val whole = segments(exercises)
        val partial = segments(exercises, skipped = setOf(Pattern.pushH))
        assertTrue(partial.totalSec < whole.totalSec)
        assertEquals(whole.repWorkSec / 2, partial.repWorkSec)
    }

    @Test
    fun noExercisesMeansNoSegmentation() {
        assertNull(EnergyEstimate.segments(emptyList(), emptySet(), null, null))
    }

    // MARK: - Blocks that did not happen

    @Test
    fun declinedBlocksAreNotCharged() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)), warmupSec = 0, cooldownSec = 0)
        assertEquals(0.0, seg.warmupSec)
        assertEquals(0.0, seg.cooldownSec)
    }

    @Test
    fun aPartlyDoneBlockIsChargedForWhatItRan() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)), warmupSec = 120, cooldownSec = 60)
        assertEquals(120.0, seg.warmupSec)
        assertEquals(60.0, seg.cooldownSec)
    }

    @Test
    fun aBlockCannotBillMoreThanItsPlan() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)), warmupSec = 99 * 60, cooldownSec = 99 * 60)
        assertEquals((EngineConfig.warmupMin * 60).toDouble(), seg.warmupSec)
        assertEquals((EngineConfig.cooldownMin * 60).toDouble(), seg.cooldownSec)
    }

    @Test
    fun aNegativeBlockMeasurementReadsAsZero() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)), warmupSec = -600, cooldownSec = -1)
        assertEquals(0.0, seg.warmupSec)
        assertEquals(0.0, seg.cooldownSec)
    }

    @Test
    fun aSessionWithNoWorkPerformedYieldsNoCalorie() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)), skipped = setOf(Pattern.squat))
        assertTrue(seg.totalSec > 0, "the blocks still took time")
        assertNull(EnergyEstimate.activeKcal(seg, kg, standardResting(kg)),
                   "a workout entry claiming calories for no work is a claim about training that did not happen")
    }

    @Test
    fun workWithoutBlocksStillCosts() {
        val seg = segments(listOf(exercise(Pattern.squat, load = 10, sets = 3)), warmupSec = 0, cooldownSec = 0)
        assertNotNull(EnergyEstimate.activeKcal(seg, kg, standardResting(kg)))
    }

    // MARK: - The wall clock as a ceiling

    @Test
    fun aPausedSessionDoesNotBillThePause() {
        assertEquals(1.0, EnergyEstimate.actualityFactor(2100.0, 4200))
        assertEquals(1.0, EnergyEstimate.actualityFactor(2100.0, null))
    }

    @Test
    fun aSessionCutShortCostsLess() {
        assertEquals(0.5, EnergyEstimate.actualityFactor(2100.0, 1050), 0.000_001)
    }

    @Test
    fun aCorruptDurationLeavesThePlanAlone() {
        assertEquals(1.0, EnergyEstimate.actualityFactor(2100.0, -600))
    }

    // MARK: - What a block ending resolves to

    @Test
    fun aDeclinedBlockResolvesToZeroNotToUnknown() {
        assertEquals(0, BlockRun.seconds(null, Instant.ofEpochSecond(1000)))
    }

    @Test
    fun aBlockResolvesToTheSecondsItRan() {
        val began = Instant.ofEpochSecond(1000)
        assertEquals(185, BlockRun.seconds(began, began.plusSeconds(185)))
    }

    @Test
    fun aBackwardsClockResolvesToZero() {
        val began = Instant.ofEpochSecond(1000)
        assertEquals(0, BlockRun.seconds(began, began.minusSeconds(90)))
    }

    // MARK: - The revision, and what obliges it to move

    /** If this fails and the change was deliberate: bump
     *  `EnergyEstimate.modelRevision` — on Android the energy record's
     *  `clientRecordVersion` — then update the numbers below. */
    @Test
    fun theModelConstantsArePinnedToTheRevision() {
        val bump = "the model changed — bump EnergyEstimate.modelRevision, then update this test"
        assertEquals(1, EnergyEstimate.modelRevision, bump)
        assertEquals(2.5, EnergyEstimate.secondsPerRep, bump)
        assertEquals(listOf(3.5, 6.0, 4.0, 1.8, 2.3),
                     listOf(EnergyEstimate.warmupMET, EnergyEstimate.repWorkMET, EnergyEstimate.holdWorkMET,
                            EnergyEstimate.restMET, EnergyEstimate.cooldownMET), bump)
        assertEquals(0.5..3.0, EnergyEstimate.plausibleRestingKcalPerMin, bump)
        assertEquals(1.4, EnergyEstimate.standardRestingKcalPerMin(80.0), 0.000_001, bump)
        val kcal = assertNotNull(EnergyEstimate.activeKcal(control, kg, standardResting(kg)))
        assertEquals(106.82, kcal, 0.01, bump)
    }
}
