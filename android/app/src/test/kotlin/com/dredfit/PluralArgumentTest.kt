//
//  `tr` declines a <plurals> key by its LAST integer argument (ui/L10n.kt),
//  because Android's getQuantityString takes one count and the generated
//  lookups do not say which argument it is. That is true of the catalogs
//  only as long as every key that varies by plural varies by its last
//  integer — this holds it against the iOS catalogs themselves: a
//  whole-string plural has one integer, and a substitution names the last
//  one. No Swift twin: on iOS the catalog itself carries `argNum`.
//

package com.dredfit

import com.dredfit.ui.pluralCount
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PluralArgumentTest {

    private val placeholder = Regex("""%(\d+\$)?(lld|ld|d|u|lu|llu|@)""")

    @Test
    fun everyPluralKeyIsDeclinedByItsLastInteger() {
        var checked = 0
        for (catalog in listOf("Dredfit/Localizable.xcstrings",
                               "DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings",
                               "DredfitWidgets/Localizable.xcstrings",
                               SetsNoticeTest.ANDROID_CATALOG)) {
            for ((key, entry) in IosCatalogs.strings(catalog)) {
                val localizations = (entry as JsonObject)["localizations"] as? JsonObject ?: continue
                val kinds = localizations.values.map { it as JsonObject }
                val wholeStringPlural = kinds.any { it.containsKey("variations") }
                val argNums = kinds.flatMap { loc ->
                    (loc["substitutions"] as? JsonObject)?.values?.mapNotNull {
                        (it as JsonObject)["argNum"]?.jsonPrimitive?.intOrNull
                    } ?: emptyList()
                }.toSet()
                if (!wholeStringPlural && argNums.isEmpty()) continue
                val args = placeholder.findAll(key).map { it.groupValues[2] }.toList()
                val lastInteger = args.indexOfLast { it != "@" } + 1
                if (argNums.isNotEmpty()) {
                    assertEquals(setOf(lastInteger), argNums, "$key: its substitution is not its last integer")
                } else {
                    assertEquals(1, args.count { it != "@" }, "$key: a whole-string plural with several integers")
                }
                checked += 1
            }
        }
        // 17 on 09.10.2026; the floor only proves the walk found them.
        assertTrue(checked >= 10, "the walk found almost no plural keys ($checked)")
    }

    @Test
    fun theCountIsTheLastIntegerArgument() {
        assertEquals(6, pluralCount(listOf(24, 32, 6)))
        assertEquals(3, pluralCount(listOf("Squat", 3)))
        assertEquals(null, pluralCount(listOf("Squat")))
    }
}
