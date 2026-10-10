//
//  `String(localized:)` for Compose: the English base string IS the key, as
//  on iOS, and the generated lookups (l10n/, from the String Catalogs) turn
//  it into the resource the system resolves for the current language.
//

package com.dredfit.ui

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.l10n.AndroidStrings
import com.dredfit.l10n.AppStrings
import com.dredfit.l10n.CoreStrings
import com.dredfit.l10n.WidgetStrings
import com.dredfit.workout.Words
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The localized text of `key`, formatted with `args`. A key missing from
 * every catalog shows its English self rather than nothing — the
 * Localization gates are what keep that from shipping.
 *
 * A key some language declines by count is a <plurals> (the export script
 * says why); its count is the LAST integer argument — the one plural
 * variation or substitution every such key of the catalogs carries, which
 * `PluralArgumentTest` holds against the iOS catalogs.
 */
@Composable
fun tr(key: String, vararg args: Any): String {
    val plural = pluralId(key)
    if (plural != null) {
        val count = pluralCount(args.toList()) ?: 0
        return pluralStringResource(plural, count, *args)
    }
    val id = stringId(key)
    if (id != null) return stringResource(id, *args)
    if (args.isEmpty()) return key
    return Words(null, key, args.toList()).english
}

/** The four catalogs' resource for `key`, in the one order every lookup uses. */
private fun pluralId(key: String): Int? = AppStrings.plural(key) ?: CoreStrings.plural(key)
    ?: WidgetStrings.plural(key) ?: AndroidStrings.plural(key)

private fun stringId(key: String): Int? = AppStrings.string(key) ?: CoreStrings.string(key)
    ?: WidgetStrings.string(key) ?: AndroidStrings.string(key)

/** The argument a plural key is declined by: its last integer. */
fun pluralCount(args: List<Any>): Int? = args.lastOrNull { it is Int || it is Long }?.let { (it as Number).toInt() }

/** What the workout flow says (`Words`, plain Kotlin), in the reader's
 *  language: its arguments first — a `Words` among them resolved the same
 *  way — then its key; a composition has no key and joins its parts. */
@Composable
fun tr(words: Words): String {
    val args = words.args.map { if (it is Words) tr(it) else it }
    if (words.isNarrowList) return listFormatted(args.map { it.toString() }, narrow = true)
    val key = words.key ?: return Words(null, words.format, args).english
    if (pluralId(key) != null || stringId(key) != null) return tr(key, *args.toTypedArray())
    return Words(null, words.format, args).english
}

/**
 * `tr(words)` outside a composition — the ongoing notification's text, which
 * the system draws long after any screen. The same lookups, resolved
 * against `resources` (the app's, in its current language) instead of the
 * composition's configuration.
 *
 * `widget`: the home-screen widget's words, which iOS's extension reads from
 * ITS catalog first — a key both catalogs carry is not always translated
 * alike ("steps" in ru is «ступеней» on the widget, «ступени» in the app).
 */
fun Resources.tr(words: Words, widget: Boolean = false): String {
    val args = words.args.map { if (it is Words) tr(it, widget) else it }
    if (words.isNarrowList) return NarrowList.join(args.map { it.toString() }, configuration.locales[0])
    val key = words.key ?: return Words(null, words.format, args).english
    val plural = (if (widget) WidgetStrings.plural(key) else null) ?: pluralId(key)
    plural?.let { return getQuantityString(it, pluralCount(args) ?: 0, *args.toTypedArray()) }
    val string = (if (widget) WidgetStrings.string(key) else null) ?: stringId(key)
    string?.let { return getString(it, *args.toTypedArray()) }
    return Words(null, words.format, args).english
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

/** The reader's locale — what `Locale.current` is to a SwiftUI view. */
@Composable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

/** `Date.screenDateText`: weekday, day, month, in the locale's own order —
 *  one spelling for every date line above a day's card. */
@Composable
fun screenDateText(day: Instant, zone: ZoneId): String {
    val locale = currentLocale()
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "EEEEdMMMM")
    return DateTimeFormatter.ofPattern(pattern, locale).format(day.atZone(zone))
}

/** The locale's own list — "a, b and c" — as `.formatted(.list(type: .and))`;
 *  `narrow` is `width: .narrow`, which is iOS's table on every API level
 *  (NarrowList.kt), not ICU's. */
@Composable
fun listFormatted(items: List<String>, narrow: Boolean = false): String {
    if (items.size <= 1) return items.firstOrNull() ?: ""
    val locale = currentLocale()
    if (narrow) return NarrowList.join(items, locale)
    return android.icu.text.ListFormatter.getInstance(locale).format(items)
}
