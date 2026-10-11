//
//  The share headline's list (`NarrowList`, ui/NarrowList.kt) against what
//  iOS prints. No Swift twin: ShareCard.swift calls
//  `.formatted(.list(type: .and, width: .narrow))` and Foundation does the
//  rest. The expectations below are Foundation's own output, copied from a
//  probe run with `swift` on macOS (ListFormatStyle, the seven shipping
//  locales, 09.10.2026) — never from the Kotlin side.
//

package com.dredfit

import com.dredfit.ui.NarrowList
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

class NarrowListTest {

    private fun join(id: String, vararg items: String) = NarrowList.join(items.toList(), Locale.forLanguageTag(id))

    /** language → what Foundation printed for [A, B], [A, B, C], [A, B, C, D]. */
    private val foundation = mapOf(
        "en" to listOf("A, B", "A, B, C", "A, B, C, D"),
        "de" to listOf("A und B", "A, B und C", "A, B, C und D"),
        "es" to listOf("A y B", "A, B y C", "A, B, C y D"),
        "fr" to listOf("A, B", "A, B, C", "A, B, C, D"),
        "it" to listOf("A e B", "A, B e C", "A, B, C e D"),
        "pt-BR" to listOf("A, B", "A, B, C", "A, B, C, D"),
        "ru" to listOf("A, B", "A, B, C", "A, B, C, D"),
    )

    @Test
    fun everyShippingLanguageJoinsAsFoundationDoes() {
        for ((id, expected) in foundation) {
            assertEquals(expected[0], join(id, "A", "B"), id)
            assertEquals(expected[1], join(id, "A", "B", "C"), id)
            assertEquals(expected[2], join(id, "A", "B", "C", "D"), id)
        }
    }

    /** Spanish's "y" turns "e" before an i-sound — and only there. */
    @Test
    fun spanishTakesFoundationsContextualConjunction() {
        val probed = mapOf(
            "Inclinado" to "e", "Isla" to "e", "Ion" to "e", "ion" to "e", "Ia" to "e", "Hilo" to "e", "Hio" to "e",
            "Hiu" to "e", "Hierro" to "y", "Hielo" to "y", "Hiato" to "y", "Íntimo" to "y", "Hípica" to "y",
            "Hu" to "y", "Y" to "y", "8" to "y",
        )
        for ((word, and) in probed) assertEquals("A $and $word", join("es", "A", word), word)
        assertEquals("A, B e Iglesia", join("es", "A", "B", "Iglesia"))
        // Italian's "e" is not contextual.
        assertEquals("A e Hierro", join("it", "A", "Hierro"))
    }

    @Test
    fun oneItemIsItselfAndNoneIsNothing() {
        assertEquals("A", join("de", "A"))
        assertEquals("", NarrowList.join(emptyList(), Locale.GERMAN))
    }
}
