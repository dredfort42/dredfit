//
//  The words for the next training day — `nextTrainingDateLabel` of
//  ios/Dredfit/AppStore+Calendar.swift. The day itself is the store's
//  (`nextTrainingDate`); the words are `Words` with the locale a parameter,
//  so a unit test reaches them, and the screens resolve them.
//

package com.dredfit.ui.today

import androidx.compose.runtime.Composable
import com.dredfit.store.AppStore
import com.dredfit.store.localDay
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.swiftWeekday
import com.dredfit.ui.currentLocale
import com.dredfit.ui.tr
import com.dredfit.workout.Words
import java.time.Instant
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

object NextTrainingDateLabel {

    /** Spoken from `from`, not from today: the same date is "tomorrow" one
     *  day before it and a weekday two days before it. */
    fun words(store: AppStore, from: Instant, locale: Locale): Words =
        words(next = localDay(store.nextTrainingDate(from), store.zone), from = localDay(from, store.zone), locale = locale)

    /** The words alone, for a day the store has already found — the widget
     *  snapshot carries the date, and the widget says it in the language it
     *  is drawn in. */
    fun words(next: LocalDate, from: LocalDate, locale: Locale): Words {
        if (next == from) return Words.of("today")
        if (next == from.plusDays(1)) return Words.of("tomorrow")
        val day = next.dayOfWeek
        val weekday = day.getDisplayName(TextStyle.FULL_STANDALONE, locale)
        return when (locale.language) {
            // The formatter only gives the nominative; this needs the accusative.
            "ru" -> Words.join("%@", russianOnWeekday(swiftWeekday(day)))
            // Weekday gender: o sábado / o domingo, a segunda…sexta-feira.
            "pt" -> Words.join("%@", (if (swiftWeekday(day) == 1 || swiftWeekday(day) == 7) "no " else "na ") + weekday)
            else -> Words.of("on %@", weekday)
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
}

@Composable
fun nextTrainingDateLabel(store: AppStore, from: Instant = store.today): String =
    tr(NextTrainingDateLabel.words(store, from, currentLocale()))
