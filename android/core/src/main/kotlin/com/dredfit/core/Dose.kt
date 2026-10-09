//
//  The dose grids.
//
//  TWO grids for the entire library: reps 4…15 by 1, holds 15…45 by 5. The
//  start of any variation is its grid's floor, and the smoothing of the steps
//  is done by the LADDER itself — the rungs stand at most ×1.50 apart.
//
//  Nothing here reads `w`. A dose is measured, never predicted.
//

package com.dredfit.core

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

data class DoseGrid(val min: Int, val max: Int, val step: Int)

object Dose {

    val reps = DoseGrid(min = 4, max = 15, step = 1)
    val hold = DoseGrid(min = 15, max = 45, step = 5)

    fun grid(unit: LoadUnit): DoseGrid = when (unit) {
        LoadUnit.reps -> reps
        LoadUnit.hold -> hold
    }

    /** How many rungs a grid has, floor included. */
    internal fun rungCount(unit: LoadUnit): Int {
        val g = grid(unit)
        return (g.max - g.min) / g.step + 1
    }

    /** The rung a dose sits on. Doses OUTSIDE `[min, max]` are legal as an
     *  INPUT and the rung then goes negative or past the top — clipping it is
     *  what broke monotonicity in #139. It IS held to ±countMax: a persisted
     *  dose reaches here before anything clamps it. */
    internal fun rung(unit: LoadUnit, dose: Int): Int {
        val d = EngineState.clamped(dose, -EngineConfig.countMax, EngineConfig.countMax)
        return floorDiv(d - grid(unit).min, grid(unit).step)
    }

    internal fun dose(unit: LoadUnit, atRung: Int): Int = grid(unit).min + atRung * grid(unit).step

    /** A fact is snapped DOWN to the grid ("do no harm"): 37 s at a step of 5
     *  is 35 s, not 40. Deliberately no round-to-nearest here. */
    internal fun snap(unit: LoadUnit, x: Int): Int = dose(unit, atRung = rung(unit, dose = x))

    internal fun clamped(unit: LoadUnit, d: Int): Int = min(max(d, grid(unit).min), grid(unit).max)

    /** The same two operations for a FRACTIONAL fact. `snapToInt` still floors
     *  to the grid — the fraction only decides whether the top set was taken. */
    internal fun clamped(unit: LoadUnit, d: Double): Double =
        min(max(d, grid(unit).min.toDouble()), grid(unit).max.toDouble())

    internal fun snapToInt(unit: LoadUnit, x: Double): Int {
        val g = grid(unit)
        // Finite and within ±countMax first: the conversion to Int below would
        // otherwise saturate where Swift traps, and neither is the model.
        val v = Engine.sanitizeActual(x)
        val r = floor((v - g.min.toDouble()) / g.step.toDouble()).toInt()
        return dose(unit, atRung = r)
    }

    /** Floor division. `/` truncates toward zero in Kotlin as in Swift, so
     *  `(11 - 15) / 5` is 0 where `Math.floor` gives −1 — and a hold reported
     *  as 11 s IS below the floor. */
    internal fun floorDiv(a: Int, b: Int): Int {
        val q = a / b
        val r = a % b
        return if (r != 0 && ((r < 0) != (b < 0))) q - 1 else q
    }
}
