//
//  `String(localized:)` for Compose: the English base string IS the key, as
//  on iOS, and the generated lookups (l10n/, from the String Catalogs) turn
//  it into the resource the system resolves for the current language.
//

package com.dredfit.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.l10n.AppStrings
import com.dredfit.l10n.CoreStrings
import com.dredfit.l10n.WidgetStrings
import java.util.Locale

/**
 * The localized text of `key`, formatted with `args`. A key missing from
 * every catalog shows its English self rather than nothing — the
 * Localization gates are what keep that from shipping.
 */
@Composable
fun tr(key: String, vararg args: Any): String {
    val id = AppStrings.string(key) ?: CoreStrings.string(key) ?: WidgetStrings.string(key)
    if (id != null) return stringResource(id, *args)
    if (args.isEmpty()) return key
    return String.format(Locale.ROOT, key.replace("%@", "%s").replace("%lld", "%d"), *args)
}

/** "3×12", "3×10 per side", "3×40 sec" — `SessionExercise.display` with the
 *  two words in the reader's language, assembled the way Session.swift does. */
@Composable
fun displayOf(ex: SessionExercise): String {
    val side = if (ex.perSide) " " + tr("per side") else ""
    val head = ex.loads?.joinToString("-") ?: "${ex.sets}×${ex.load}"
    return when (ex.unit) {
        LoadUnit.reps -> "$head$side"
        LoadUnit.hold -> "$head " + tr("sec") + side
    }
}
