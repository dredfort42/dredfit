//
//  The life-benefit layer (issue #25) is pure data with one rule
//  (override → base), so the tests pin three things: every movement has a
//  line, the override list is exactly the closed list from the spec, and
//  the catalog carries all SEVEN shipping languages for every life.* key.
//  It said "all four" for three languages longer than that was true — the
//  list the check actually walks is en + the six translations named in
//  CLAUDE.md (de, es, fr, it, pt-BR, ru), and it is written out in full in
//  the test rather than summarised here again.
//
//  The catalog checks read the .xcstrings FILE, never the bundle:
//  Dredfit.xctestplan pins the run to en/US, so a runtime lookup cannot see
//  ru, de or pt-BR at all and would pass over a missing translation.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class LifeBenefitTests: XCTestCase {

    /// The checkout root, from this file's own compile-time path. Derived in
    /// ONE place: the same two `deletingLastPathComponent()` steps were
    /// written out three times below, so moving this file one directory
    /// would have had to be noticed three times — and each copy fails with
    /// "no such file", which reads like a missing catalog rather than a
    /// mis-derived path.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DredfitTests/
            .deletingLastPathComponent()   // repo root
    }

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
        let variation: Int
        let variationName: String
    }

    /// The indices moved with §40.1 — every one of them. The movements did
    /// not, which is why the pins are written by NAME and cross-checked
    /// against the library below.
    private let closedList: [OverridePin] = [
        OverridePin(pattern: .squat, variation: 5, variationName: "Pistol squat"),
        OverridePin(pattern: .pushH, variation: 3, variationName: "Push-up"),
        OverridePin(pattern: .pushV, variation: 7, variationName: "Wall handstand push-up"),
        OverridePin(pattern: .pullBar, variation: 7, variationName: "Pull-up"),
    ]

    func testOverridesExistExactlyForTheClosedList() {
        for pin in closedList {
            XCTAssertNotNil(LifeBenefit.overrideText(for: pin.pattern, variation: pin.variation),
                            "missing override for \(pin.pattern.rawValue) v\(pin.variation)")
            XCTAssertNotEqual(LifeBenefit.text(for: pin.pattern, variation: pin.variation),
                              LifeBenefit.baseText(for: pin.pattern),
                              "override for \(pin.pattern.rawValue) v\(pin.variation) equals the base line")
            // The same guard the base lines have had since wave 4, and it is
            // here because the overrides went without it: v3 renamed these four
            // keys and filled their English value with the KEY, so an English
            // device read "life.override.pull-up" where the line should be.
            // A catalog entry for "en" wins over the `defaultValue:` at the call
            // site, so nothing in the Swift looked wrong.
            XCTAssertFalse(
                LifeBenefit.text(for: pin.pattern, variation: pin.variation).hasPrefix("life."),
                "override for \(pin.pattern.rawValue) v\(pin.variation) is rendering its own key")
        }
        for pattern in Pattern.allCases {
            for v in 1...Library.count(pattern)
            where !closedList.contains(where: { $0.pattern == pattern && $0.variation == v }) {
                XCTAssertNil(LifeBenefit.overrideText(for: pattern, variation: v),
                             "unexpected override for \(pattern.rawValue) v\(v)")
                XCTAssertEqual(LifeBenefit.text(for: pattern, variation: v),
                               LifeBenefit.baseText(for: pattern))
            }
        }
    }

    /// `Library.name` is localized, so these pins are English only because
    /// Dredfit.xctestplan fixes the run at en/US. Run this suite by hand under
    /// -AppleLanguages (ru) and it goes red on the LOCALE, not on a library
    /// reshuffle — the pins would have to move to a non-localized handle
    /// (there is none today) to say what they mean in every language.
    func testClosedListStillMatchesTheLibrary() {
        for pin in closedList {
            let name = Library.name(pin.pattern, pin.variation)
            XCTAssertEqual(name, pin.variationName,
                           "\(pin.pattern.rawValue) v\(pin.variation) is no longer "
                           + "\(pin.variationName) — revisit the override list")
        }
    }

    // MARK: - Catalog completeness (all shipping languages)

    func testCatalogCarriesAllShippingLanguagesForEveryLifeKey() throws {
        let data = try Data(contentsOf: repoRoot
            .appendingPathComponent("Dredfit/Localizable.xcstrings"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        let lifeKeys = strings.keys.filter { $0.hasPrefix("life.") }
        // 1 kicker + 10 base + 4 overrides
        XCTAssertEqual(lifeKeys.count, 15, "unexpected number of life.* keys")

        for key in lifeKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any],
                                              "\(key) has no localizations")
            for lang in ["en", "ru", "es", "pt-BR", "de", "fr", "it"] {
                let unit = (localizations[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) is missing \(lang)")
            }
        }
    }

    func testRussianLinesAvoidYo() throws {
        let data = try Data(contentsOf: repoRoot
            .appendingPathComponent("Dredfit/Localizable.xcstrings"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        for (key, raw) in strings where key.hasPrefix("life.") {
            let entry = raw as? [String: Any]
            let ru = (((entry?["localizations"] as? [String: Any])?["ru"]
                       as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            // A missing ru line passes here on purpose: its absence is
            // testCatalogCarriesAllShippingLanguagesForEveryLifeKey's failure,
            // and asserting it twice would turn one defect into two red tests.
            XCTAssertFalse(ru?.contains("ё") ?? false, "\(key): RU line contains ё")
        }
    }

    /// No dotted key may be its own translation, in any language.
    ///
    /// Lives beside the `life.*` scans because this is where the catalog is
    /// already read; the check itself is catalog-wide on purpose. v3 shipped
    /// FIVE entries whose English value was the key text —
    /// `progress.stepsLabel` under the big number on Progress and the four
    /// renamed `life.override.*` lines — and nothing caught it: an explicit
    /// "en" entry beats the `defaultValue:` at the call site, so the Swift
    /// reads correctly while the screen shows "progress.stepsLabel".
    /// `check_localization.py` cannot see it either — the value is present and
    /// non-empty, it is simply the key.
    func testNoCatalogEntryIsItsOwnKey() throws {
        let root = repoRoot
        for catalog in ["Dredfit/Localizable.xcstrings",
                        "DredfitWidgets/Localizable.xcstrings",
                        "DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings"] {
            let data = try Data(contentsOf: root.appendingPathComponent(catalog))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try XCTUnwrap(json["strings"] as? [String: Any])
            // Only dotted keys: a plain English sentence IS its own key here by
            // design — that is how the base language is written in this project.
            for (key, raw) in strings where key.contains(".") && !key.contains(" ") {
                let localizations = (raw as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
                for (lang, unit) in localizations {
                    let value = ((unit as? [String: Any])?["stringUnit"]
                                 as? [String: Any])?["value"] as? String
                    XCTAssertNotEqual(value, key,
                                      "\(catalog): \(key) renders as its own key in \(lang)")
                }
            }
        }
    }
}
