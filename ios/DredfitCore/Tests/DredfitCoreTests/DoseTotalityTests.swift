//
//  Dose arithmetic is total: a persisted number at the edge of `Int` must not
//  trap. `Dose.rung` holds its input to ±`EngineConfig.countMax`; below that
//  range it is the identity, so every other test pins the valid domain.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class DoseTotalityTests: XCTestCase {

    func testSnapSaturatesInsteadOfTrapping() {
        for unit in [LoadUnit.reps, .hold] {
            XCTAssertEqual(Dose.snap(unit, .min), Dose.snap(unit, -EngineConfig.countMax))
            XCTAssertEqual(Dose.snap(unit, .max), Dose.snap(unit, EngineConfig.countMax))
            XCTAssertEqual(Dose.snapToInt(unit, .nan), Dose.snapToInt(unit, 0))
            XCTAssertEqual(Dose.snapToInt(unit, -.infinity), Dose.snapToInt(unit, 0),
                           "a non-finite fact reads as 0, as sanitizeActual rules")
            XCTAssertEqual(Dose.snapToInt(unit, -.greatestFiniteMagnitude),
                           Dose.snapToInt(unit, -Double(EngineConfig.countMax)))
        }
    }

    func testSnapIsUnchangedOnTheValidDomain() {
        for unit in [LoadUnit.reps, .hold] {
            let g = Dose.grid(unit)
            for d in (g.min - 3 * g.step)...(g.max + 3 * g.step) {
                XCTAssertEqual(Dose.rung(unit, dose: d), Dose.floorDiv(d - g.min, g.step))
            }
        }
    }

    /// A corrupted state file: extreme doses and journal values reach the
    /// sanitizer and the session generator — the Today screen's first render.
    func testExtremePersistedDosesDoNotTrap() {
        var state = EngineState.initial
        for p in Pattern.allCases {
            state.doses[p] = .min
            state.shown[p] = [1: .min, 2: .max]
        }
        let session = Engine.generateSession(state)
        XCTAssertFalse(session.exercises.isEmpty)
        let clean = state.sanitized()
        for p in Pattern.allCases {
            let dose = clean.doses[p] ?? 0
            XCTAssertLessThan(abs(dose), EngineConfig.countMax)
        }
    }
}
