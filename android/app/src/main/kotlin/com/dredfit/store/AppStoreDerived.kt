//
//  The store's read-only derivations: the next plan, the progress curve and
//  what the journal says about a given day. Nothing here writes.
//  Port of ios/Dredfit/AppStore+Derived.swift.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.journal.RecordedPosition
import com.dredfit.journal.WorkoutRecord
import java.time.Instant

/** IMPORTANT: right after a workout the counter has advanced, so this is the
 *  NEXT workout — never present it under today's date. */
val AppStore.nextSession: Session get() = session(engineState)

/** A pattern with no snapshotted history is never badged: better a missed
 *  badge than "new variation" on an exercise done for weeks. */
val AppStore.debutPatterns: Set<Pattern>
    get() {
        val maxPerformed = mutableMapOf<Pattern, Int>()
        for (record in records) {
            val exercises = record.exercises ?: continue
            // A painful exercise was not performed either (legacy field).
            val skipped = (record.skipped ?: emptySet()) + (record.discomfort ?: emptySet())
            for (ex in exercises) {
                if (ex.pattern in skipped) continue
                maxPerformed[ex.pattern] = maxOf(maxPerformed[ex.pattern] ?: 0, ex.variation)
            }
        }
        return nextSession.exercises.filter { ex ->
            val seen = maxPerformed[ex.pattern]
            seen != null && ex.variation > seen
        }.map { it.pattern }.toSet()
    }

/** How far along their ladders every movement stands, summed. */
val AppStore.totalProgress: Int get() = Engine.totalProgress(engineState)

/** The position of every movement right now, as the journal records it. */
val AppStore.currentPositions: Map<Pattern, RecordedPosition> get() = positions(engineState)

fun positions(state: EngineState): Map<Pattern, RecordedPosition> =
    Pattern.allCases.associateWith { p ->
        val pos = state.position(p)
        RecordedPosition(variation = pos.variation, sets = pos.sets, dose = pos.dose,
                         sub = pos.sub.takeIf { it > 0 }, cut = pos.cut.takeIf { it > 0 })
    }

/** Oldest first; `through` cuts it at a date. Records from before v3 carry no
 *  point on this scale and are left out. */
fun AppStore.progressCurve(through: Instant? = null): List<Int> {
    val run = recordsSinceReset
    val history = if (through == null) run else run.filter { it.date <= through }
    return history.mapNotNull { it.totalProgressAfter }
}

/**
 * Where the journal starts describing the CURRENT plan: the first record whose
 * number does not exceed its predecessor's opens the new run — and between a
 * reset and the first workout after it, the counter (already moved) cuts it.
 */
val AppStore.recordsSinceReset: List<WorkoutRecord>
    get() {
        val resumed = records.indices.drop(1).lastOrNull { records[it].sessionNumber <= records[it - 1].sessionNumber }
        return records.drop(resumed ?: 0).filter { it.sessionNumber <= engineState.counter }
    }

val AppStore.lastRecord: WorkoutRecord? get() = records.lastOrNull()

val AppStore.doneToday: Boolean get() = isDone(today)

fun AppStore.isDone(date: Instant): Boolean {
    val last = records.lastOrNull() ?: return false
    return sameDay(last.date, date)
}

/** Rest weekdays are stored in iOS numbering (1 = Sunday) — see `swiftWeekday`. */
fun AppStore.isRestDay(date: Instant): Boolean =
    swiftWeekday(date.atZone(zone).dayOfWeek) in settings.restWeekdays

/** The workout completed on the given day, if any. */
fun AppStore.record(on: Instant): WorkoutRecord? = records.lastOrNull { sameDay(it.date, on) }
