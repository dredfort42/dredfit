//
//  The 59 (pattern, variation) → movement identities, pinned by value.
//
//  golden.json deliberately carries no English names — localized strings are
//  locale-fragile and the trace stays numeric — so without this table a
//  reordering of two rungs inside a ladder would pass every other test while
//  silently rewriting journal history, which re-resolves names from the
//  current library. The variation is POSITIONAL: the order IS the contract.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class LibraryPinTests: XCTestCase {

    /// The catalog, movement by movement, in ladder order — the
    /// source-language names the whole catalog is keyed by.
    private static let catalog: [Pattern: [String]] = [
        .squat: ["Squat", "Split squat", "Bulgarian split squat",
                 "Single-leg squat to a chair", "Pistol squat", "Shrimp squat"],
        .pushH: ["Knee push-up", "Incline push-up", "Push-up", "Feet-elevated push-up",
                 "Side-shift push-up", "Archer push-up"],
        .hinge: ["Glute bridge", "Assisted single-leg glute bridge", "Single-leg glute bridge",
                 "Sliding leg curl", "Negative single-leg sliding curl",
                 "Single-leg sliding leg curl", "Assisted Nordic curl"],
        .pull: ["Standing incline row", "High-bar inverted row", "Mid-height inverted row",
                "Inverted row (table)", "Feet-elevated inverted row",
                "Side-shift inverted row", "Archer inverted row"],
        .pushV: ["Wall push-up", "Pike push-up, hands on a table",
                 "Pike push-up, hands on a chair", "Pike push-up",
                 "Feet-elevated pike push-up", "Wall handstand negative",
                 "Wall handstand push-up"],
        .lunge: ["Static lunge", "Reverse lunge", "Paused lunge", "Jump lunge"],
        .coreAntiExt: ["Knee plank", "High plank", "Plank", "Hollow hold", "Long-lever plank"],
        .coreRot: ["Kneeling side plank", "Kneeling side plank, top leg extended",
                   "Side plank", "Side plank with leg raise", "Star side plank"],
        .calf: ["Calf raises", "Assisted single-leg calf raise", "Single-leg calf raise",
                "Single-leg calf raise with pause", "Single-leg calf raise on a step"],
        .pullBar: ["Bar hang", "Scapular hang", "Negative pull-up, both feet assisting",
                   "Negative pull-up, one foot assisting", "Negative pull-up",
                   "Partial pull-up", "Pull-up"],
    ]

    /// An assistance rung (kind `°` in §40.1) and the variation it assists.
    private struct Assist {
        let pattern: Pattern
        let rung: Int
        let base: Int
    }

    /// Nine of them.
    private static let assists: [Assist] = [
        Assist(pattern: .hinge, rung: 2, base: 3),
        Assist(pattern: .hinge, rung: 5, base: 6),
        Assist(pattern: .pull, rung: 3, base: 4),
        Assist(pattern: .pushV, rung: 2, base: 4),
        Assist(pattern: .pushV, rung: 3, base: 4),
        Assist(pattern: .coreRot, rung: 2, base: 1),
        Assist(pattern: .calf, rung: 2, base: 3),
        Assist(pattern: .pullBar, rung: 3, base: 5),
        Assist(pattern: .pullBar, rung: 4, base: 5),
    ]

    /// Every position, by value and in order. A swap of two rungs inside a
    /// ladder — invisible to golden — fails here by name. The expected side
    /// resolves the pinned keys through the library's own bundle, so the test
    /// holds in every test-runner locale, not only English.
    func testEveryVariationIdentityIsPinned() {
        for pattern in Pattern.allCases {
            let expected = Self.catalog[pattern]!
            let entry = ExerciseLibrary.entry(for: pattern)
            XCTAssertEqual(entry.count, expected.count, "\(pattern.rawValue): ladder length")
            for (index, key) in expected.enumerated() {
                let localized = String(localized: String.LocalizationValue(key),
                                       bundle: ExerciseLibrary.localizationBundle)
                XCTAssertEqual(entry.variations[index].name, localized,
                               "\(pattern.rawValue) v\(index + 1) must be “\(key)”")
            }
        }
    }

    /// The pin covers the whole library — a new pattern cannot slip past it,
    /// and the count is the spec's own: 59 positions (§40.1).
    func testTheCatalogCoversEveryPattern() {
        XCTAssertEqual(Set(Self.catalog.keys), Set(Pattern.allCases))
        XCTAssertEqual(Self.catalog.values.reduce(0) { $0 + $1.count }, 59)
    }

    /// Every position carries a full card: three steps and two mistakes.
    func testEveryPositionCarriesItsTechnique() {
        for pattern in Pattern.allCases {
            for (index, variation) in ExerciseLibrary.entry(for: pattern).variations.enumerated() {
                let ctx = "\(pattern.rawValue) v\(index + 1)"
                XCTAssertFalse(variation.name.isEmpty, "\(ctx): name")
                XCTAssertEqual(variation.steps.count, 3, "\(ctx): steps")
                XCTAssertEqual(variation.mistakes.count, 2, "\(ctx): mistakes")
                for line in variation.steps + variation.mistakes {
                    XCTAssertFalse(line.isEmpty, "\(ctx): empty technique line")
                }
            }
        }
    }

    /// An assistance rung inherits its base's technique with EXACTLY ONE line
    /// changed — the one where the assistance lives. Asserted by count so a
    /// copy-pasted card that drifted from its base cannot pass as inheritance,
    /// and a rung that changed nothing cannot pass as a rung.
    func testAssistanceRungsChangeExactlyOneLine() {
        for assist in Self.assists {
            let entry = ExerciseLibrary.entry(for: assist.pattern)
            let a = entry.variation(assist.rung)
            let b = entry.variation(assist.base)
            let ctx = "\(assist.pattern.rawValue) v\(assist.rung) assists v\(assist.base)"
            XCTAssertEqual(a.mistakes, b.mistakes, "\(ctx): mistakes are inherited whole")
            let same = zip(a.steps, b.steps).filter { $0 == $1 }.count
            XCTAssertEqual(same, 2, "\(ctx): exactly one step differs")
        }
    }

    /// И1 (§40.9): `w` rises along every ladder, and no step up is heavier
    /// than ×1.50. The single exception is the unit boundary, where the ratio
    /// is undefined — and the ladder is allowed at most one of those.
    func testDensityInvariantHolds() {
        for pattern in Pattern.allCases {
            let entry = ExerciseLibrary.entry(for: pattern)
            var boundaries = 0
            for v in 2...entry.count {
                let lower = entry.variation(v - 1)
                let upper = entry.variation(v)
                let ctx = "\(pattern.rawValue) v\(v - 1)→v\(v)"
                XCTAssertGreaterThan(upper.w, lower.w, "\(ctx): w must rise")
                if entry.probeOnly(variation: v) {
                    boundaries += 1
                    continue
                }
                XCTAssertLessThanOrEqual(upper.w / lower.w, 1.50, "\(ctx): density ×1.50")
            }
            XCTAssertLessThanOrEqual(boundaries, 1,
                                     "\(pattern.rawValue): at most one unit change per ladder")
        }
    }

    /// The three movements that left the strength ladders are still here, with
    /// their text — the warm-up reads them (§40.1, PROMPT-2 §5).
    func testWarmupMovementsSurvivedTheLadders() {
        XCTAssertEqual(WarmupTechnique.all.count, 3)
        for move in WarmupTechnique.all {
            XCTAssertFalse(move.name.isEmpty, "\(move.id): name")
            XCTAssertEqual(move.steps.count, 3, "\(move.id): steps")
            XCTAssertEqual(move.mistakes.count, 2, "\(move.id): mistakes")
        }
        // None of them may be back in a strength ladder.
        let ladderNames = Set(Pattern.allCases.flatMap {
            ExerciseLibrary.entry(for: $0).variations.map(\.name)
        })
        for move in WarmupTechnique.all {
            XCTAssertFalse(ladderNames.contains(move.name),
                           "\(move.id) belongs to the warm-up, not to a ladder")
        }
    }
}
