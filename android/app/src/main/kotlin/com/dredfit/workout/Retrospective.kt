//
//  The "then → now" block for anniversary milestones (issue #26), built from
//  the journal's position snapshots. Port of ios/Dredfit/Retrospective.swift.
//  Every number goes through core helpers; degradations are silent.
//

package com.dredfit.workout

import com.dredfit.core.Engine
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Position
import com.dredfit.journal.RecordedPosition
import com.dredfit.journal.WorkoutRecord
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

data class Retrospective(val thenLine: Words, val nowLine: Words, val sinceLine: Words) {

    /** For surfaces that want the comparison as one sentence (the share card). */
    val comparisonLine: Words get() = Words.join("%@ — %@", thenLine, nowLine)

    companion object {
        /**
         * null when there is nothing honest to say. Base is the first record
         * carrying a position snapshot; the movement is the largest gain
         * since, ties in rotation order. `zone` is the trainee's — iOS's
         * `Calendar.current`.
         */
        fun make(records: List<WorkoutRecord>, current: Map<Pattern, RecordedPosition>,
                 now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Retrospective? {
            val base = records.firstOrNull { it.positionsAfter != null } ?: return null
            val basePositions = base.positionsAfter ?: return null
            var best: Pair<Pattern, Int>? = null
            for (pattern in Pattern.allCases) {
                val then = basePositions[pattern] ?: continue
                val nowPosition = current[pattern] ?: continue
                val delta = progress(pattern, nowPosition) - progress(pattern, then)
                if (delta > (best?.second ?: 0)) best = pattern to delta
            }
            val pattern = best?.first ?: return null
            val then = basePositions[pattern] ?: return null
            val nowPosition = current[pattern] ?: return null
            return Retrospective(
                thenLine = Words.of("Then: %@", line(pattern, then)),
                nowLine = Words.of("Now: %@", line(pattern, nowPosition)),
                sinceLine = since(base.date, now, zone))
        }

        /** Every coordinate of the position — the DELTA is picked from here. */
        private fun progress(pattern: Pattern, position: RecordedPosition): Int =
            Engine.progress(pattern, Position(variation = position.variation, sets = position.sets,
                                              dose = position.dose, sub = position.sub ?: 0, cut = position.cut ?: 0))

        /** Movement, sets and dose exactly as the plan stated them. */
        private fun line(pattern: Pattern, position: RecordedPosition): Words {
            val name = Words.name(Library.name(pattern, position.variation))
            return when (Library.unit(pattern, position.variation)) {
                LoadUnit.reps -> Words.of("%@ · %lld×%lld", name, position.sets, position.dose)
                LoadUnit.hold -> Words.of("%@ · %lld×%lld s", name, position.sets, position.dose)
            }
        }

        /** Whole weeks up to 8, months from week 9 — against the BASE record. */
        private fun since(start: Instant, now: Instant, zone: ZoneId): Words {
            val from = start.atZone(zone)
            val to = now.atZone(zone)
            val days = maxOf(0L, ChronoUnit.DAYS.between(from, to))
            val weeks = days / 7
            if (weeks < 9) return Words.of("%lld weeks apart", maxOf(weeks, 1L))
            val months = maxOf(1L, ChronoUnit.MONTHS.between(from, to))
            return Words.of("%lld months apart", months)
        }
    }
}
