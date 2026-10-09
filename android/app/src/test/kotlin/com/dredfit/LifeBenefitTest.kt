//
//  Port of ios/DredfitTests/LifeBenefitTests.swift: the life-benefit layer
//  (issue #25) is pure data with one rule (override → base), so the tests pin
//  three things: every movement has a line, the override list is exactly the
//  closed list from the spec, and the catalog carries all SEVEN shipping
//  languages for every life.* key.
//
//  The catalog checks read the iOS .xcstrings FILES in place — the one source
//  the generated Android resources come from — never a copy.
//

package com.dredfit

import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.workout.LifeBenefit
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class LifeBenefitTest {

    private fun strings(catalog: String): JsonObject = IosCatalogs.strings(catalog)

    private fun value(entry: JsonObject?, lang: String): String? = IosCatalogs.unit(entry, lang)

    // MARK: - Base lines

    @Test
    fun everyMovementHasABaseLine() {
        for (pattern in Pattern.allCases) {
            val line = LifeBenefit.baseText(pattern).english
            assertFalse(line.isEmpty(), "no base line for ${pattern.rawValue}")
            assertFalse(line.startsWith("life."),
                        "${pattern.rawValue} fell back to the raw key — missing defaultValue")
        }
    }

    @Test
    fun baseLinesAreDistinct() {
        val lines = Pattern.allCases.map { LifeBenefit.baseText(it).english }
        assertEquals(lines.size, lines.toSet().size, "two movements share a base line — copy-paste error")
    }

    // MARK: - Override rule (closed list)

    /** The closed list from the spec, pinned to library variations. If a
     *  future library reshuffle moves these variations, this test is the
     *  tripwire. */
    private data class OverridePin(val pattern: Pattern, val variation: Int, val variationName: String)

    /** Written by NAME and cross-checked against the library below: a
     *  reshuffle of the ladders moves the indices, not the movements. */
    private val closedList = listOf(
        OverridePin(Pattern.squat, 5, "Pistol squat"),
        OverridePin(Pattern.pushH, 3, "Push-up"),
        OverridePin(Pattern.pushV, 7, "Wall handstand push-up"),
        OverridePin(Pattern.pullBar, 7, "Pull-up"),
    )

    @Test
    fun overridesExistExactlyForTheClosedList() {
        for (pin in closedList) {
            assertNotNull(LifeBenefit.overrideText(pin.pattern, pin.variation),
                          "missing override for ${pin.pattern.rawValue} v${pin.variation}")
            assertNotEquals(LifeBenefit.baseText(pin.pattern).english,
                            LifeBenefit.text(pin.pattern, pin.variation).english,
                            "override for ${pin.pattern.rawValue} v${pin.variation} equals the base line")
            // The same guard the base lines have: an English value equal to
            // the KEY would show "life.override.pull-up" on an English device
            // where the line should be. A catalog entry for "en" wins over the
            // `defaultValue:` at the call site, so nothing in the Swift would
            // look wrong.
            assertFalse(LifeBenefit.text(pin.pattern, pin.variation).english.startsWith("life."),
                        "override for ${pin.pattern.rawValue} v${pin.variation} is rendering its own key")
        }
        for (pattern in Pattern.allCases) {
            for (v in 1..Library.count(pattern)) {
                if (closedList.any { it.pattern == pattern && it.variation == v }) continue
                assertNull(LifeBenefit.overrideText(pattern, v), "unexpected override for ${pattern.rawValue} v$v")
                assertEquals(LifeBenefit.baseText(pattern).english, LifeBenefit.text(pattern, v).english)
            }
        }
    }

    /** `Library.name` is the core's English base string here — what the iOS
     *  suite reads under its en/US test plan. */
    @Test
    fun closedListStillMatchesTheLibrary() {
        for (pin in closedList) {
            val name = Library.name(pin.pattern, pin.variation)
            assertEquals(pin.variationName, name,
                         "${pin.pattern.rawValue} v${pin.variation} is no longer " +
                             "${pin.variationName} — revisit the override list")
        }
    }

    // MARK: - Catalog completeness (all shipping languages)

    @Test
    fun catalogCarriesAllShippingLanguagesForEveryLifeKey() {
        val strings = strings("Dredfit/Localizable.xcstrings")

        val lifeKeys = strings.keys.filter { it.startsWith("life.") }
        // 1 kicker + 10 base + 4 overrides
        assertEquals(15, lifeKeys.size, "unexpected number of life.* keys")

        for (key in lifeKeys) {
            val entry = assertNotNull(strings[key] as? JsonObject)
            assertNotNull(entry["localizations"] as? JsonObject, "$key has no localizations")
            for (lang in listOf("en", "ru", "es", "pt-BR", "de", "fr", "it")) {
                assertFalse(value(entry, lang)?.isEmpty() ?: true, "$key is missing $lang")
            }
        }
    }

    @Test
    fun russianLinesAvoidYo() {
        val strings = strings("Dredfit/Localizable.xcstrings")

        for ((key, raw) in strings) {
            if (!key.startsWith("life.")) continue
            val ru = value(raw as? JsonObject, "ru")
            // A missing ru line passes here on purpose: its absence is
            // catalogCarriesAllShippingLanguagesForEveryLifeKey's failure,
            // and asserting it twice would turn one defect into two red tests.
            assertFalse(ru?.contains("ё") ?: false, "$key: RU line contains ё")
        }
    }

    /**
     * No dotted key may be its own translation, in any language.
     *
     * Lives beside the `life.*` scans because this is where the catalog is
     * already read; the check itself is catalog-wide on purpose. An explicit
     * "en" entry beats the `defaultValue:` at the call site, so the Swift
     * reads correctly while the screen shows the key itself.
     * `check_localization.py` cannot see it either — the value is present and
     * non-empty, it is simply the key.
     */
    @Test
    fun noCatalogEntryIsItsOwnKey() {
        for (catalog in listOf("Dredfit/Localizable.xcstrings",
                               "DredfitWidgets/Localizable.xcstrings",
                               "DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings",
                               SetsNoticeTest.ANDROID_CATALOG)) {
            val strings = strings(catalog)
            // Only dotted keys: a plain English sentence IS its own key here by
            // design — that is how the base language is written in this project.
            for ((key, raw) in strings) {
                if (!key.contains(".") || key.contains(" ")) continue
                val entry = raw as? JsonObject
                val localizations = entry?.get("localizations") as? JsonObject ?: continue
                for (lang in localizations.keys) {
                    assertNotEquals(key, value(entry, lang),
                                    "$catalog: $key renders as its own key in $lang")
                }
            }
        }
    }
}
