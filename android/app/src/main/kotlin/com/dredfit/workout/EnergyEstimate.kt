//
//  What a session costs, in the unit Health Connect accepts for it. Port of
//  ios/Dredfit/EnergyEstimate.swift — the sources of every constant and the
//  reasoning behind the model's shape are there.
//
//  App layer on purpose: the engine never sees a body, and a calorie is a
//  fact about a person, not about a ladder. Its readers: the Health export
//  (health/HealthExporter.kt) for the calories, and the history sheet for the
//  plan its wall clock is held against ("Took N min in the app").
//

package com.dredfit.workout

import com.dredfit.core.EngineConfig
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise

/** What the store of health data can tell about the body doing the work,
 *  beyond its mass. Every field independently absent: a refused read and a
 *  profile nobody filled in are the same empty answer. On Android it is
 *  always empty — see `WorkoutHealthWriting.profile`. */
data class BodyProfile(
    val heightCm: Double? = null,
    val ageYears: Double? = null,
    val sex: BodySex? = null,
) {
    companion object {
        val unknown = BodyProfile()
    }
}

enum class BodySex { female, male, other }

/** The seconds a planned session spends in each state it can be in — the
 *  ONE home of the session-duration arithmetic. */
data class SessionSegments(
    val warmupSec: Double = 0.0,
    val repWorkSec: Double = 0.0,
    val holdWorkSec: Double = 0.0,
    val restSec: Double = 0.0,
    val cooldownSec: Double = 0.0,
) {
    val totalSec: Double get() = warmupSec + repWorkSec + holdWorkSec + restSec + cooldownSec

    /** The journal is an input: a hand-edited record can produce a negative
     *  rest or an infinity here. Energy refuses to guess on it. */
    val isPlausible: Boolean
        get() {
            val all = listOf(warmupSec, repWorkSec, holdWorkSec, restSec, cooldownSec)
            if (!all.all { it.isFinite() && it >= 0 }) return false
            return totalSec > 0 && totalSec <= 24 * 3600
        }
}

/** Which rung of the resting ladder produced a number — named so a test can
 *  assert the ladder DEGRADED in the right order. */
enum class RestingSource { healthBasal, mifflin, standardMET }

data class RestingRate(val kcalPerMin: Double, val source: RestingSource)

object EnergyEstimate {

    // MARK: - The constants (sources in the Swift file)

    /** Which revision of THIS model produced a calorie. Bump it whenever any
     *  number below moves or the segmentation changes shape;
     *  `theModelConstantsArePinnedToTheRevision` is that obligation. On
     *  Android it travels as the energy record's `clientRecordVersion`. */
    const val modelRevision = 1

    /** Seconds one repetition is under way — the engine's own figure. */
    const val secondsPerRep = 2.5

    /** Compendium of Physical Activities (Ainsworth 2011) — GROSS METs. */
    const val warmupMET = 3.5
    const val repWorkMET = 6.0
    const val holdWorkMET = 4.0
    const val restMET = 1.8
    const val cooldownMET = 2.3

    /** 1 MET = 3.5 ml O2/kg/min, a litre of O2 ≈ 5 kcal. */
    private const val mlO2PerKgMinPerMET = 3.5
    private const val kcalDivisor = 200.0

    /** A resting rate outside this band is a hole in the data, not a body at
     *  rest, and falls through to the next rung. */
    val plausibleRestingKcalPerMin = 0.5..3.0

    // MARK: - Segmentation

    /** Null when there is nothing to segment. `warmupSec`/`cooldownSec` are
     *  what the blocks ACTUALLY ran; null falls back to the plan, zero means
     *  declined. Neither carries a default, as in Swift. */
    fun segments(exercises: List<SessionExercise>, skipped: Set<Pattern>,
                 warmupSec: Int?, cooldownSec: Int?): SessionSegments? {
        if (exercises.isEmpty()) return null
        var repWork = 0.0
        var holdWork = 0.0
        var rest = 0.0
        for (ex in exercises) {
            if (ex.pattern in skipped) continue
            val sides = if (ex.perSide) 2.0 else 1.0
            val sets = ex.sets.toDouble()
            // In Double throughout: these come back out of the journal
            // unclamped.
            if (ex.unit == LoadUnit.reps) repWork += sets * ex.load.toDouble() * sides * secondsPerRep
            else holdWork += sets * ex.load.toDouble() * sides
            rest += (sets - 1) * ex.restSetSec.toDouble() + ex.restExerciseSec.toDouble()
        }
        return SessionSegments(
            warmupSec = performed(warmupSec, planned = EngineConfig.warmupMin * 60),
            repWorkSec = repWork, holdWorkSec = holdWork, restSec = rest,
            cooldownSec = performed(cooldownSec, planned = EngineConfig.cooldownMin * 60))
    }

    /** The plan is a CEILING: a block cut short was shorter, a declined one
     *  is zero, an unmeasured one is charged its plan. */
    private fun performed(measured: Int?, planned: Int): Double {
        if (measured == null) return planned.toDouble()
        return minOf(maxOf(measured, 0), planned).toDouble()
    }

    // MARK: - The resting ladder

    /** Top rung first, each falling through silently to the next: the
     *  store's own basal figure, then Mifflin-St Jeor, then one standard MET.
     *  `minutes` is the length of the interval the basal sum was read over. */
    fun resting(basalKcal: Double?, minutes: Double, bodyMassKg: Double, profile: BodyProfile): RestingRate {
        if (basalKcal != null && basalKcal.isFinite() && minutes > 0) {
            val rate = basalKcal / minutes
            if (rate in plausibleRestingKcalPerMin) return RestingRate(rate, RestingSource.healthBasal)
        }
        val cm = profile.heightCm
        val age = profile.ageYears
        if (cm != null && age != null) {
            mifflinKcalPerMin(bodyMassKg, cm, age, profile.sex)?.let { return RestingRate(it, RestingSource.mifflin) }
        }
        return RestingRate(standardRestingKcalPerMin(bodyMassKg), RestingSource.standardMET)
    }

    /** Mifflin-St Jeor (1990), per minute. An unset or non-binary answer
     *  takes the mean of the two published constants. */
    fun mifflinKcalPerMin(kg: Double, cm: Double, age: Double, sex: BodySex?): Double? {
        if (!(kg > 0 && cm > 0 && age >= 0 && kg.isFinite() && cm.isFinite() && age.isFinite())) return null
        val sexTerm = when (sex) {
            BodySex.male -> 5.0
            BodySex.female -> -161.0
            BodySex.other, null -> (5.0 - 161.0) / 2
        }
        val perDay = 10 * kg + 6.25 * cm - 5 * age + sexTerm
        if (!(perDay.isFinite() && perDay > 0)) return null
        return perDay / (24 * 60)
    }

    /** The bottom rung: one standard MET. */
    fun standardRestingKcalPerMin(kg: Double): Double = mlO2PerKgMinPerMET * kg / kcalDivisor

    // MARK: - The number that goes to Health Connect

    /** Active energy: the gross cost minus this person's resting cost over
     *  the same minutes. Null rather than zero when it cannot be computed —
     *  a workout with no energy record is honest, one with a zero is a claim
     *  that nothing was spent. No work, no calorie. */
    fun activeKcal(segments: SessionSegments, bodyMassKg: Double, resting: RestingRate): Double? {
        if (!(bodyMassKg > 0 && bodyMassKg.isFinite() && segments.isPlausible &&
              resting.kcalPerMin.isFinite() && resting.kcalPerMin >= 0)) return null
        if (!(segments.repWorkSec + segments.holdWorkSec > 0)) return null
        val perMETMinute = mlO2PerKgMinPerMET * bodyMassKg / kcalDivisor
        val metMinutes = segments.warmupSec / 60 * warmupMET +
            segments.repWorkSec / 60 * repWorkMET +
            segments.holdWorkSec / 60 * holdWorkMET +
            segments.restSec / 60 * restMET +
            segments.cooldownSec / 60 * cooldownMET
        val net = metMinutes * perMETMinute - segments.totalSec / 60 * resting.kcalPerMin
        if (!(net.isFinite() && net > 0)) return null
        return net
    }

    /** The wall clock is a CEILING, never a source: a shorter actual duration
     *  scales the plan down, a longer one (a pause) bills nothing more. */
    fun actualityFactor(planSec: Double, actualSec: Int?): Double {
        if (actualSec == null || !(planSec > 0) || !planSec.isFinite()) return 1.0
        val actual = actualSec.toDouble()
        if (!(actual.isFinite() && actual >= 0)) return 1.0
        return minOf(1.0, actual / planSec)
    }
}
