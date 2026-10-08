//
//  Dose arithmetic is total: a persisted number at the edge of `Int` must not
//  trap. `Dose.rung` holds its input to ±`EngineConfig.countMax`; below that
//  range it is the identity, so every other test pins the valid domain.
//
//  The port of DoseTotalityTests.swift.
//

package com.dredfit.core

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DoseTotalityTest {

    @Test
    fun snapSaturatesInsteadOfTrapping() {
        for (unit in listOf(LoadUnit.reps, LoadUnit.hold)) {
            assertEquals(Dose.snap(unit, -EngineConfig.countMax), Dose.snap(unit, Int.MIN_VALUE))
            assertEquals(Dose.snap(unit, EngineConfig.countMax), Dose.snap(unit, Int.MAX_VALUE))
            assertEquals(Dose.snapToInt(unit, 0.0), Dose.snapToInt(unit, Double.NaN))
            assertEquals(Dose.snapToInt(unit, 0.0), Dose.snapToInt(unit, Double.NEGATIVE_INFINITY),
                         "a non-finite fact reads as 0, as sanitizeActual rules")
            assertEquals(Dose.snapToInt(unit, -EngineConfig.countMax.toDouble()),
                         Dose.snapToInt(unit, -Double.MAX_VALUE))
        }
    }

    @Test
    fun snapIsUnchangedOnTheValidDomain() {
        for (unit in listOf(LoadUnit.reps, LoadUnit.hold)) {
            val g = Dose.grid(unit)
            for (d in (g.min - 3 * g.step)..(g.max + 3 * g.step)) {
                assertEquals(Dose.floorDiv(d - g.min, g.step), Dose.rung(unit, dose = d))
            }
        }
    }

    /** A corrupted state file: extreme doses and journal values reach the
     *  sanitizer and the session generator — the Today screen's first render. */
    @Test
    fun extremePersistedDosesDoNotTrap() {
        val state = EngineState.initial
        for (p in Pattern.allCases) {
            state.doses[p] = Int.MIN_VALUE
            state.shown[p] = mutableMapOf(1 to Int.MIN_VALUE, 2 to Int.MAX_VALUE)
        }
        val session = Engine.generateSession(state)
        assertFalse(session.exercises.isEmpty())
        val clean = state.sanitized()
        for (p in Pattern.allCases) {
            val dose = clean.doses[p] ?: 0
            assertTrue(abs(dose) < EngineConfig.countMax, "$p: $dose")
        }
    }
}
