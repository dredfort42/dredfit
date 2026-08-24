//
//  DredfitCoreTests
//
//  The 40 (pattern, tier) → variation identities, pinned by value (#95,
//  audit A5-C6/A1-8). Golden deliberately carries no names — localized
//  strings are locale-fragile, and the trace stays numeric — so before this
//  table a reordering of variations inside a tier passed every test while
//  silently rewriting journal history, which re-resolves names from the
//  current library. Tier is positional (`variations[tier − 1]`): the order
//  IS the contract.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class LibraryPinTests: XCTestCase {

    /// The catalog, movement by movement, in tier order 1...4 — the
    /// source-language names the whole catalog is keyed by.
    private static let catalog: [Pattern: [String]] = [
        .squat: ["Squat", "Bulgarian split squat", "Pistol squat", "Shrimp squat"],
        .pushH: ["Knee push-up", "Push-up", "Feet-elevated push-up", "Archer push-up"],
        .hinge: ["Glute bridge", "Single-leg glute bridge",
                 "Single-leg Romanian deadlift", "Sliding leg curl"],
        .pull: ["Y-T-W raises", "Inverted row (table)",
                "Feet-elevated inverted row", "Archer inverted row"],
        // The elevated pike took tier 3 and the wall handstand
        // moved up to 4; the chest-to-wall variation left the library. Stored
        // levels keep their numbers (owner's decision 19.08.2026), so anyone
        // above tier 2 meets an easier movement at the same level — never a
        // harder one.
        .pushV: ["Wall push-up", "Pike push-up", "Feet-elevated pike push-up",
                 "Wall handstand push-up"],
        .lunge: ["Static lunge", "Reverse lunge", "Jump lunge", "Paused jump lunge"],
        .coreAntiExt: ["Knee plank", "Plank", "Hollow hold", "Long-lever plank"],
        .coreRot: ["Bird dog (hold)", "Side plank", "Side plank with leg raise",
                   "Star side plank"],
        .calf: ["Calf raises", "Single-leg calf raise",
                "Single-leg calf raise with pause", "Single-leg calf raise on a step"],
        .pullBar: ["Bar hang", "Negative pull-up", "Partial pull-up", "Pull-up"]
    ]

    /// Every position, by value and in order. A swap of two variations
    /// inside a tier — invisible to golden — fails here by name. The
    /// expected side resolves the pinned keys through the library's own
    /// bundle, so the test holds in every test-runner locale, not only
    /// English.
    func testEveryVariationIdentityIsPinned() {
        for pattern in Pattern.allCases {
            let expected = Self.catalog[pattern]!
            let entry = ExerciseLibrary.entry(for: pattern)
            XCTAssertEqual(entry.variations.count, expected.count,
                           "\(pattern.rawValue): four tiers, always")
            for (index, key) in expected.enumerated() {
                let localized = String(localized: String.LocalizationValue(key),
                                       bundle: ExerciseLibrary.localizationBundle)
                XCTAssertEqual(entry.variations[index].name, localized,
                               "\(pattern.rawValue) tier \(index + 1) must be “\(key)”")
            }
        }
    }

    /// The pin covers the whole library — a new pattern cannot slip past it.
    func testTheCatalogCoversEveryPattern() {
        XCTAssertEqual(Set(Self.catalog.keys), Set(Pattern.allCases))
        XCTAssertEqual(Self.catalog.values.reduce(0) { $0 + $1.count }, 40)
    }
}
