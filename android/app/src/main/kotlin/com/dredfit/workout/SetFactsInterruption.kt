//
//  Time charged to an absence, and what an interrupted workout amounts to.
//  Port of ios/Dredfit/SetFacts+Interruption.swift. Swift nests `Absence`
//  and `Settlement` in `SetFacts`; a Kotlin extension cannot nest a type, so
//  they are top-level here (`Absence`, `InterruptionSettlement`).
//

package com.dredfit.workout

import com.dredfit.core.EngineConfig
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import java.time.Instant

// MARK: - Time the athlete was away

/**
 * Seconds to charge to an ABSENCE rather than to the workout, for one resume:
 * everything past the moment the session stopped owing time. A rest running
 * on schedule is training whether or not the process survived it, so the gap
 * is measured from its end.
 */
fun SetFacts.awayGained(savedAt: Instant, restEndDate: Instant?, now: Instant): Int {
    val owedUntil = if (restEndDate != null && restEndDate > savedAt) restEndDate else savedAt
    // Swift's `Int(_:)` truncates toward zero.
    return maxOf(0, Countdown.seconds(owedUntil, now).toInt())
}

/**
 * An absence the PROCESS LIVED THROUGH: the flow sent to the background and
 * brought back without dying, charged by the rule `restore` uses. The rest
 * end is taken as it stood when the flow left. Swift's struct: `copy()` is
 * `var b = a`.
 */
class Absence {
    private var leftAt: Instant? = null
    private var restEndDate: Instant? = null

    /** A leaving is stamped and not spent yet. */
    val isAway: Boolean get() = leftAt != null

    /** The first leaving wins. */
    fun leave(now: Instant, restEndDate: Instant?) {
        if (leftAt != null) return
        leftAt = now
        this.restEndDate = restEndDate
    }

    /** Seconds to add to the away time (0 if nothing was stamped); spends
     *  the stamp. */
    fun comeBack(now: Instant): Int {
        val left = leftAt ?: return 0
        val gained = SetFacts.awayGained(savedAt = left, restEndDate = restEndDate, now = now)
        leftAt = null
        restEndDate = null
        return gained
    }
}

// MARK: - An interrupted workout

/** What an interruption amounts to — ONE place for the flow's "Finish now"
 *  and the settlement of a workout trained and never rated. */
data class InterruptionSettlement(
    /** Never reached. A skip to the engine. */
    val skipped: Set<Pattern> = emptySet(),
    /** Sets taken off a movement that WAS trained — its numbers stay. */
    val setsSkipped: Map<Pattern, Int> = emptyMap(),
    /** Left half-done: a skip to the engine, "not finished" to the athlete. */
    val interrupted: Pattern? = null,
)

/**
 * @param exIndex the exercise in front of the athlete when it stopped.
 * @param setsBehind sets of THAT exercise already over, skips included.
 * @param currentIsDone every set of it is behind — the rest after a last set,
 *   the summary of a finished hold, or the rating screen.
 */
fun SetFacts.settlement(exercises: List<SessionExercise>, exIndex: Int, setsBehind: Int, currentIsDone: Boolean,
                        alreadySkipped: Map<Pattern, Int>): InterruptionSettlement {
    val setsSkipped = LinkedHashMap(alreadySkipped)
    var interrupted: Pattern? = null
    // Clamped from below — both numbers come off disk. Past the end is NOT
    // clamped: it means all behind.
    val index = maxOf(exIndex, 0)
    val behind = maxOf(setsBehind, 0)
    if (index >= exercises.size) return InterruptionSettlement(setsSkipped = setsSkipped)
    var firstUnfinished = index
    if (currentIsDone) {
        firstUnfinished = index + 1
    } else {
        val ex = exercises[index]
        val already = alreadySkipped[ex.pattern] ?: 0
        val left = maxOf(0, ex.sets - behind)
        val performed = behind - already
        if (performed >= EngineConfig.setsFloor && skipFits(left, of = ex.sets, alreadySkipped = already)) {
            if (left > 0) setsSkipped[ex.pattern] = (setsSkipped[ex.pattern] ?: 0) + left
            firstUnfinished = index + 1
        } else if (behind > 0) {
            interrupted = ex.pattern
        }
    }
    val skipped = LinkedHashSet<Pattern>()
    for (ex in exercises.drop(minOf(firstUnfinished, exercises.size))) {
        skipped += ex.pattern
        // A skip wins over a partial count: the movement was not trained.
        setsSkipped.remove(ex.pattern)
    }
    return InterruptionSettlement(skipped = skipped, setsSkipped = setsSkipped, interrupted = interrupted)
}
