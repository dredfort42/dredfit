//
//  DredfitCoreTests
//
//  The rung the push-up ladder was missing. Of the
//  forty transitions in the library exactly one asked for a new SKILL rather
//  than more strength — pike straight into a wall handstand, entered by
//  kicking up at near-full bodyweight. The elevated pike now sits between
//  them, the handstand moved up a tier, and the chest-to-wall variation left.
//  Nothing numeric changed: the encoding, the plans and golden are untouched,
//  which is exactly what these tests pin.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV218Tests: XCTestCase {

    private func variation(_ level: Int) -> String {
        let d = Level.decode(level)
        return ExerciseLibrary.entry(for: .pushV).variations[d.tier - 1].name
    }

    // MARK: - The ladder

    func testTheElevatedPikeSitsBetweenThePikeAndTheHandstand() {
        XCTAssertEqual(variation(8), "Pike push-up")
        XCTAssertEqual(variation(16), "Feet-elevated pike push-up",
                       "the tier the audit found missing (#131)")
        XCTAssertEqual(variation(24), "Wall handstand push-up",
                       "the handstand moved up one tier")
    }

    func testTheChestToWallVariationLeftTheLibrary() {
        let names = ExerciseLibrary.entry(for: .pushV).variations.map(\.name)
        XCTAssertFalse(names.contains { $0.contains("Chest-to-wall") },
                       "it needed the same entry and stood even higher")
        XCTAssertEqual(names.count, EngineConfig.tiers)
    }

    /// The handstand is the one movement whose danger is in getting in and
    /// out, not in the press. Both belong on the sheet — including the bail.
    func testTheHandstandSheetTeachesTheEntryAndTheWayOut() {
        let handstand = ExerciseLibrary.entry(for: .pushV).variations[3]
        XCTAssertTrue(handstand.steps[0].hasPrefix("Getting in:"))
        XCTAssertTrue(handstand.steps[2].hasPrefix("Getting out:"))
        XCTAssertTrue(handstand.steps[2].contains("bail"),
                      "and what to do when a rep has to be abandoned")
        XCTAssertFalse(handstand.steps.joined().lowercased().contains("kick up"),
                       "walking up is the same position without the moment you cannot stop")
    }

    // MARK: - Nothing numeric moved

    /// The migration is "the number stays" (owner's decision 19.08.2026), so
    /// every level must still decode to exactly what it decoded to before —
    /// only the movement's name at tiers 3 and 4 is different.
    func testTheEncodingIsUntouched() {
        for level in 0...EngineConfig.levelMax {
            let d = Level.decode(level)
            let band = level / EngineConfig.stepsPerTier
            XCTAssertEqual(d.tier, min(EngineConfig.tiers, 1 + band),
                           "level \(level): tier moved")
            XCTAssertEqual(d.sets,
                           EngineConfig.setsBase + max(0, band - (EngineConfig.tiers - 1)),
                           "level \(level): sets moved")
        }
    }

    /// Anyone above tier 2 meets an EASIER movement at the same level — the
    /// safe direction for the error, and the reason no migration is needed.
    func testNobodyIsHandedAHarderPlanThanTheyClosedWith() {
        for level in 16...EngineConfig.levelMax {
            var state = EngineState.initial
            state.levels[.pushV] = level
            let session = Engine.generateSession(state)
            guard let ex = session.exercises.first(where: { $0.pattern == .pushV }) else { continue }
            XCTAssertEqual(ex.load, Level.decode(level).reps,
                           "level \(level): the dose is the level's, unchanged by the reshuffle")
            XCTAssertEqual(ex.name, variation(level))
        }
    }

    /// Overhead pressing near bodyweight stays a place where the model takes
    /// one step per session, elevated pike included.
    func testGrowthOnTheTopTiersIsStillOneStepPerSession() {
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pushV, tier: 3), 1)
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pushV, tier: 4), 1)
    }
}
