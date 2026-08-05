//
//  LifeBenefitTests.swift
//  DredfitTests
//
//  The life-benefit layer (issue #25) is pure data with one rule
//  (override → base), so the tests pin three things: every movement has a
//  line, the override list is exactly the closed list from the spec, and
//  the catalog carries all four languages for every life.* key. The last
//  check parses Localizable.xcstrings from the repo — the test plan pins
//  the run locale to en/US, so runtime lookups cannot see ru/es/pt-BR.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class LifeBenefitTests: XCTestCase {

    // MARK: - Base lines

    func testEveryMovementHasABaseLine() {
        for pattern in Pattern.allCases {
            let line = LifeBenefit.baseText(for: pattern)
            XCTAssertFalse(line.isEmpty, "no base line for \(pattern.rawValue)")
            XCTAssertFalse(line.hasPrefix("life."),
                           "\(pattern.rawValue) fell back to the raw key — missing defaultValue")
        }
    }

    func testBaseLinesAreDistinct() {
        let lines = Pattern.allCases.map { LifeBenefit.baseText(for: $0) }
        XCTAssertEqual(Set(lines).count, lines.count,
                       "two movements share a base line — copy-paste error")
    }

    // MARK: - Override rule (closed list)

    /// The closed list from the spec, pinned to library tiers. If a future
    /// library reshuffle moves these variations, this test is the tripwire.
    private struct OverridePin {
        let pattern: Pattern
        let tier: Int
        let variationName: String
    }

    private let closedList: [OverridePin] = [
        OverridePin(pattern: .squat, tier: 3, variationName: "Pistol squat"),
        OverridePin(pattern: .pushH, tier: 2, variationName: "Push-up"),
        OverridePin(pattern: .pushV, tier: 4, variationName: "Chest-to-wall handstand push-up"),
        OverridePin(pattern: .pullBar, tier: 4, variationName: "Pull-up"),
    ]

    func testOverridesExistExactlyForTheClosedList() {
        for pin in closedList {
            XCTAssertNotNil(LifeBenefit.overrideText(for: pin.pattern, tier: pin.tier),
                            "missing override for \(pin.pattern.rawValue) tier \(pin.tier)")
            XCTAssertNotEqual(LifeBenefit.text(for: pin.pattern, tier: pin.tier),
                              LifeBenefit.baseText(for: pin.pattern),
                              "override for \(pin.pattern.rawValue) tier \(pin.tier) equals the base line")
        }
        for pattern in Pattern.allCases {
            for tier in 1...4 where !closedList.contains(where: { $0.pattern == pattern && $0.tier == tier }) {
                XCTAssertNil(LifeBenefit.overrideText(for: pattern, tier: tier),
                             "unexpected override for \(pattern.rawValue) tier \(tier)")
                XCTAssertEqual(LifeBenefit.text(for: pattern, tier: tier),
                               LifeBenefit.baseText(for: pattern))
            }
        }
    }

    func testClosedListStillMatchesTheLibrary() {
        for pin in closedList {
            let name = ExerciseLibrary.entry(for: pin.pattern).variations[pin.tier - 1].name
            XCTAssertEqual(name, pin.variationName,
                           "\(pin.pattern.rawValue) tier \(pin.tier) is no longer \(pin.variationName) — revisit the override list")
        }
    }

    // MARK: - Catalog completeness (all shipping languages)

    func testCatalogCarriesAllShippingLanguagesForEveryLifeKey() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DredfitTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Dredfit/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        let lifeKeys = strings.keys.filter { $0.hasPrefix("life.") }
        // 1 kicker + 10 base + 4 overrides
        XCTAssertEqual(lifeKeys.count, 15, "unexpected number of life.* keys")

        for key in lifeKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any],
                                              "\(key) has no localizations")
            for lang in ["en", "ru", "es", "pt-BR", "de"] {
                let unit = (localizations[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) is missing \(lang)")
            }
        }
    }

    func testRussianLinesAvoidYo() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Dredfit/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        for (key, raw) in strings where key.hasPrefix("life.") {
            let entry = raw as? [String: Any]
            let ru = (((entry?["localizations"] as? [String: Any])?["ru"]
                       as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            XCTAssertFalse(ru?.contains("ё") ?? false, "\(key): RU line contains ё")
        }
    }
}
