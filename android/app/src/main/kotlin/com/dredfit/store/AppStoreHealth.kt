//
//  The store's half of Health Connect: the switch, the weight in force and
//  the export flags — the state, and the permission checks that flip the
//  switch. The export and its arithmetic are HealthExporter's. The rule this
//  half keeps: a record is flagged exported only after Health Connect
//  confirms the save, so a hole in the export is always still retriable.
//  Port of ios/Dredfit/AppStore+Health.swift; the Swift `async` functions are
//  `suspend` ones here, run on the store's thread (`healthScope`).
//
//  THE FLAG IS ANDROID'S OWN: `healthConnectExported`. `healthExported` and
//  `healthExportedThrough` are Apple Health's, written by an iPhone; an
//  iPhone's backup arrives with them, and they say nothing about Health
//  Connect — its workouts are offered here like any other not yet written
//  (owner decision, 11.10.2026). This file never reads or moves them, so a
//  backup that goes back to an iPhone still says what Apple Health holds.
//

package com.dredfit.store

import com.dredfit.core.SwiftJson
import com.dredfit.health.HealthExporter
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

val AppStore.healthExporter: HealthExporter get() = HealthExporter(health)

/** On denial the switch stays off — reality over wishful state. */
suspend fun AppStore.enableHealth(): Boolean {
    if (!health.isAvailable) return false
    val granted = health.requestAuthorization()
    if (granted) {
        update { it.copy(settings = it.settings.copy(healthEnabled = true)) }
        // Health Connect's reading is adopted from here on — if it is the
        // later statement about the weight (`refreshBodyMassFromHealth`).
        refreshBodyMassFromHealth()
    }
    return granted
}

/** The switch's ON as a job of the store's, as iOS's `Task` is: a Settings
 *  sheet closed while Health Connect's screen is up must not lose the
 *  grant, nor the question that follows it — past history is offered once
 *  (`healthBackfillOffered`). `then` hears the answer on the store's thread. */
fun AppStore.turnHealthOn(then: (granted: Boolean) -> Unit) {
    healthScope.launch {
        val granted = enableHealth()
        if (granted && healthBackfillCount > 0) offerHealthBackfill(true)
        then(granted)
    }
}

/** Keeps the flags: re-enabling later must not duplicate workouts already
 *  in Health Connect. */
fun AppStore.disableHealth() {
    update { it.copy(settings = it.settings.copy(healthEnabled = false)) }
}

/**
 * The switch follows the permission, which is the device's: a restored
 * backup (an import, or Android's own restore onto a new phone) brings the
 * flag without it, and the person can take the workout write back in Health
 * Connect at any time. Without this every save would fail under a switch
 * that reads "on". Nothing is lost — flags are kept, and turning it back on
 * asks again and offers what is pending. Never asks.
 */
suspend fun AppStore.reconcileHealthAuthorization() {
    if (!settings.healthEnabled) return
    // Only a definite "not granted" turns it off: on Android 10–13 the answer
    // is IPC to another app, and a Health Connect that cannot answer this
    // once (an update under way, a dead binder) has not taken anything back.
    if (health.isAvailable && health.workoutShareGranted() != false) return
    // Read again after the await: the switch may have gone down meanwhile.
    if (settings.healthEnabled) disableHealth()
}

/** Kilograms in, kilograms out — the pounds a US field shows are converted
 *  before they get here. Null clears it, and clearing is a real answer: no
 *  weight means no calories, not calories from a default. */
fun AppStore.setBodyMass(kg: Double?) {
    update { state ->
        val mass = kg?.let { HealthExporter.sanitizedBodyMass(it) }
        // Typed, so it is not Health Connect's; the DATE keeps the number
        // standing until a newer weigh-in. A cleared weight carries no date.
        state.copy(settings = state.settings.copy(
            bodyMassKg = mass,
            bodyMassFromHealth = false,
            bodyMassDate = if (mass == null) null else SwiftJson.swiftDate(clock.instant())))
    }
}

/**
 * The number the app shows — and multiplies every calorie by — follows the
 * LATEST statement about the weight: Health Connect's newest reading when it
 * is newer than the number in force, the number in force otherwise. Called
 * on every activation and at the head of every export run.
 *
 * A null reading NEVER clears anything (empty and refused are the same
 * null), nor touches the origin flag. Writes only on a real change: this
 * runs on every return to the app.
 */
suspend fun AppStore.refreshBodyMassFromHealth() {
    if (!settings.healthEnabled || !health.isAvailable) return
    val reading = healthExporter.latestBodyMass()
    // Both re-checks are about that await: the switch can go down while the
    // read hangs, and a newer activation may have cancelled this run — its
    // reading is the older of the two and must not land on top.
    if (!settings.healthEnabled || !currentCoroutineContext().isActive) return
    if (reading == null || !HealthExporter.adopts(reading, settings.bodyMassKg, settings.bodyMassDate)) return
    if (settings.bodyMassKg == reading.kg && settings.bodyMassFromHealth && settings.bodyMassDate == reading.date) return
    // The weight reaches nothing the widget shows.
    update(refreshWidget = false) {
        it.copy(settings = it.settings.copy(bodyMassKg = reading.kg, bodyMassFromHealth = true,
                                            bodyMassDate = reading.date))
    }
}

fun AppStore.setWatchRecordsWorkouts(on: Boolean) {
    update { it.copy(settings = it.settings.copy(watchRecordsWorkouts = on)) }
}

/** Workouts not yet written to Health Connect from this journal (nor
 *  declined) — an iPhone's Apple Health flags count for nothing here. */
val AppStore.healthBackfillCount: Int get() = records.count { it.healthConnectExported != true }

/**
 * Journal order, one flag at a time, only on a confirmed save. Stops at the
 * first failure so the tail stays retriable — a failed save is never
 * declared exported, and a later success cannot leapfrog it. The in-flight
 * guard forbids a second concurrent run; the loop re-reads the journal (a
 * workout finished mid-run is picked up) and re-checks the switch.
 */
suspend fun AppStore.backfillHealth() {
    if (backfillInFlight) return
    backfillInFlight = true
    try {
        // Before the context: the weight the calories are multiplied by has
        // to be today's.
        refreshBodyMassFromHealth()
        val exporter = healthExporter
        val context = exporter.energyContext(settings.bodyMassKg, settings.watchRecordsWorkouts, now = clock.instant()) {
            records.filter { it.healthConnectExported != true }
        }
        while (settings.healthEnabled) {
            val record = records.firstOrNull { it.healthConnectExported != true } ?: break
            if (!exporter.export(record, context)) break   // the tail stays pending
            // The await may have replaced the whole journal (importBackup):
            // flag by identity AMONG THE UNEXPORTED, never by a pre-await
            // index — and never by id alone, or two records sharing an id
            // would send every flag to the first and loop forever.
            val i = records.indexOfFirst { it.id == record.id && it.healthConnectExported != true }
            if (i < 0) continue
            // The flags reach nothing the widget shows. Apple Health's
            // high-water mark is not moved: it is an iPhone's.
            update(refreshWidget = false) { state ->
                state.copy(records = state.records.mapIndexed { j, r ->
                    if (j == i) r.copy(healthConnectExported = true) else r
                })
            }
        }
    } finally {
        backfillInFlight = false
    }
}

/** The alert's "Export N workouts": the backfill as a job of the store's,
 *  which a closed Settings sheet does not cancel. */
fun AppStore.startHealthBackfill() {
    healthScope.launch { backfillHealth() }
}

/** Past workouts are declared handled so they never export later, even
 *  after toggling off and on. */
fun AppStore.skipHealthBackfill() {
    update { state ->
        state.copy(
            records = state.records.map { it.copy(healthConnectExported = true) })
    }
}
