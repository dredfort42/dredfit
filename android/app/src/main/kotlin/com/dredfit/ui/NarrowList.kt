//
//  `.formatted(.list(type: .and, width: .narrow))` — the share card's list of
//  unlocked variations (ShareCardFactory.headline, ShareCard.swift). Plain
//  Kotlin rather than ICU: Android offers ICU's narrow width only from API 33,
//  and below it the standard width printed "A, B, and C" where iOS prints
//  "A, B, C". The table is what Foundation prints in each shipping language
//  (probed with `swift` on macOS, 09.10.2026; NarrowListTest holds it):
//  English, French, Portuguese and Russian join with commas alone; German,
//  Spanish and Italian put their "and" before the last item — Spanish's "y"
//  becoming "e" before an i-sound, as Foundation's CLDR rule has it.
//

package com.dredfit.ui

import java.util.Locale

object NarrowList {

    fun join(items: List<String>, locale: Locale): String {
        if (items.size <= 1) return items.firstOrNull() ?: ""
        val head = items.dropLast(1).joinToString(", ")
        val last = items.last()
        val and = when (locale.language) {
            "de" -> "und"
            "it" -> "e"
            "es" -> if (spanishE(last)) "e" else "y"
            else -> return "$head, $last"
        }
        return "$head $and $last"
    }

    /** CLDR's `(i.*|hi|hi[^ae].*)`, case-insensitive: "e Isla", "e Hilo",
     *  but "y Hielo", "y Hiato" and "y Íntimo" (the accented í is not i). */
    private fun spanishE(word: String): Boolean {
        val w = word.lowercase(Locale.ROOT)
        return w.startsWith("i") || w == "hi" || (w.startsWith("hi") && w[2] != 'a' && w[2] != 'e')
    }
}
