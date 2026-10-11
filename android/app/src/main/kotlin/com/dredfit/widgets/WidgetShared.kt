//
//  The snapshot contract between the store and the home-screen widget. Port
//  of ios/Shared/WidgetShared.swift. Plain Kotlin: the store writes it and a
//  JVM unit test reads it.
//
//  What differs from iOS, and why:
//  - No App Group. The widget is a receiver inside the app (android/README.md),
//    so the file is the app's own, in `noBackupFilesDir`: it is derived from
//    the state file at every write, and a backup carrying an old one would
//    show a restored phone a day that is not its own.
//  - The words are NOT resolved here. iOS bakes `nextLabel` and each plan
//    row's `detail` as strings in the app's language at write time; here the
//    snapshot keeps what they are made of — the next training DATE of each
//    day and the parts of a dose — and the widget says them in the language
//    it is drawn in (`TodayStatusView`). The store stays free of a locale,
//    and a language changed after the write is the language the widget
//    speaks. The rest days stay the store's: the widget never computes one.
//  - Dates are calendar days (`LocalDate`), not instants of midnight: the
//    widget picks its entry by the day on the wall at render time.
//  - No `planMinutes`/`planMinutesFloor`: their only readers on iOS are the
//    lock-screen accessories, which have no Android twin (TodayStatusWidget.kt).
//  - No optional-for-an-older-build fields: this is the first build that
//    writes one, and an update rewrites it at once (MY_PACKAGE_REPLACED,
//    ReminderReceiver.kt). A field added later must be optional, or the old
//    file reads as no snapshot until that write.
//

package com.dredfit.widgets

import com.dredfit.core.LoadUnit
import com.dredfit.workout.Words
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate
import java.time.format.DateTimeParseException

/** Starts on the Monday of the write week, not on today: an entry days out
 *  still has to find its own Monday–Sunday inside the snapshot. */
data class WidgetSnapshot(
    val days: List<Day>,
    val totalSteps: Int,
    val week: Week,
    /** The Monday the `week` tally belongs to — it travels only with it. */
    val weekStart: LocalDate,
    val planSessionNumber: Int,
    val plan: List<PlanRow>,
) {
    /** The raw names are the file's and do not move. */
    enum class DayStatus { workout, done, rest, unmarked }

    data class Day(
        val date: LocalDate,
        val status: DayStatus,
        /** Today's workout only. */
        val sessionNumber: Int?,
        /** The next training day seen FROM this day, for every day from the
         *  write day on that is not itself a workout — per day, because a
         *  relative word ("tomorrow") baked once reads wrong on every later
         *  entry. iOS's `nextLabel`, before it became words. */
        val nextDate: LocalDate?,
    )

    /** An exercise of the next plan: its name (a core catalog key) and the
     *  parts of its dose (`Words.display`). */
    data class PlanRow(val name: String, val head: String, val unit: LoadUnit, val perSide: Boolean) {
        val title: Words get() = Words.name(name)
        val detail: Words get() = Words.display(head, unit, perSide)
    }

    data class Week(val workouts: Int, val stepsDelta: Int)

    fun encode(): String = JsonObject(mapOf(
        "days" to JsonArray(days.map { d ->
            JsonObject(mapOf(
                "date" to JsonPrimitive(d.date.toString()),
                "status" to JsonPrimitive(d.status.name),
                "sessionNumber" to (d.sessionNumber?.let { JsonPrimitive(it) } ?: JsonNull),
                "nextDate" to (d.nextDate?.let { JsonPrimitive(it.toString()) } ?: JsonNull),
            ))
        }),
        "totalSteps" to JsonPrimitive(totalSteps),
        "week" to JsonObject(mapOf("workouts" to JsonPrimitive(week.workouts),
                                   "stepsDelta" to JsonPrimitive(week.stepsDelta))),
        "weekStart" to JsonPrimitive(weekStart.toString()),
        "planSessionNumber" to JsonPrimitive(planSessionNumber),
        "plan" to JsonArray(plan.map { r ->
            JsonObject(mapOf("name" to JsonPrimitive(r.name), "head" to JsonPrimitive(r.head),
                             "unit" to JsonPrimitive(r.unit.rawValue), "perSide" to JsonPrimitive(r.perSide)))
        }),
    )).toString()

    companion object {
        /** In `noBackupFilesDir` (see the header). */
        const val FILE_NAME = "widget-snapshot.json"

        /** Whole or nothing: a file this build cannot read is no snapshot,
         *  and the widget signs itself until the next write — it never draws
         *  half a week. */
        fun decode(text: String): WidgetSnapshot? = try {
            val o = Json.parseToJsonElement(text).jsonObject
            val week = o.getValue("week").jsonObject
            WidgetSnapshot(
                days = o.getValue("days").jsonArray.map { e ->
                    val d = e.jsonObject
                    Day(date = date(d.getValue("date")),
                        status = DayStatus.valueOf(string(d.getValue("status"))),
                        sessionNumber = d["sessionNumber"]?.takeUnless { it is JsonNull }?.let(::int),
                        nextDate = d["nextDate"]?.takeUnless { it is JsonNull }?.let(::date))
                },
                totalSteps = int(o.getValue("totalSteps")),
                week = Week(workouts = int(week.getValue("workouts")), stepsDelta = int(week.getValue("stepsDelta"))),
                weekStart = date(o.getValue("weekStart")),
                planSessionNumber = int(o.getValue("planSessionNumber")),
                plan = o.getValue("plan").jsonArray.map { e ->
                    val r = e.jsonObject
                    PlanRow(name = string(r.getValue("name")), head = string(r.getValue("head")),
                            unit = LoadUnit.fromRaw(string(r.getValue("unit"))) ?: throw IllegalArgumentException("unit"),
                            perSide = r.getValue("perSide").jsonPrimitive.booleanOrNull
                                ?: throw IllegalArgumentException("perSide"))
                },
            )
        } catch (_: IllegalArgumentException) {
            // kotlinx's parse and shape errors, a missing key, an unknown
            // status — all IllegalArgumentException or a subclass of it.
            null
        } catch (_: NoSuchElementException) {
            null
        } catch (_: DateTimeParseException) {
            null
        }

        private fun string(e: JsonElement): String {
            val p = e.jsonPrimitive
            require(p.isString) { "not a string" }
            return p.content
        }

        private fun int(e: JsonElement): Int {
            val p = e.jsonPrimitive
            require(!p.isString) { "a string where a number belongs" }
            return p.intOrNull ?: throw IllegalArgumentException("not an Int")
        }

        private fun date(e: JsonElement): LocalDate = LocalDate.parse(string(e))
    }
}
