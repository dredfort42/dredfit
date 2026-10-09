//
//  The words for the next training day — `nextTrainingDateLabel` of
//  ios/Dredfit/AppStore+Calendar.swift. The day itself is the store's
//  (`nextTrainingDate`); the words live here, with the strings.
//

package com.dredfit.ui.today

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import com.dredfit.store.AppStore
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.sameDay
import com.dredfit.store.swiftWeekday
import com.dredfit.ui.tr
import java.time.Instant
import java.time.format.TextStyle

@Composable
fun nextTrainingDateLabel(store: AppStore, from: Instant = store.today): String {
    val d = store.nextTrainingDate(from)
    if (store.sameDay(d, from)) return tr("today")
    if (store.sameDay(d, from.atZone(store.zone).plusDays(1).toInstant())) return tr("tomorrow")
    val locale = LocalConfiguration.current.locales[0]
    val day = d.atZone(store.zone).dayOfWeek
    val weekday = day.getDisplayName(TextStyle.FULL_STANDALONE, locale)
    return when (locale.language) {
        // The formatter only gives the nominative; this needs the accusative.
        "ru" -> russianOnWeekday(swiftWeekday(day))
        // Weekday gender: o sábado / o domingo, a segunda…sexta-feira.
        "pt" -> (if (swiftWeekday(day) == 1 || swiftWeekday(day) == 7) "no " else "na ") + weekday
        else -> tr("on %@", weekday)
    }
}

private fun russianOnWeekday(index: Int): String = when (index) {
    1 -> "в воскресенье"
    2 -> "в понедельник"
    3 -> "во вторник"
    4 -> "в среду"
    5 -> "в четверг"
    6 -> "в пятницу"
    else -> "в субботу"
}
