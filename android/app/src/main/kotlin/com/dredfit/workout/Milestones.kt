//
//  Derived, never stored: computed from the state before and after
//  applyFeedback, so they cannot go stale or be double-counted.
//  Port of ios/Dredfit/Milestones.swift.
//

package com.dredfit.workout

import com.dredfit.core.EngineState
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Session

sealed interface Milestone {
    /** An identity for a list, not a description: the "tier-" prefix is
     *  Swift's and needs no rename. */
    val id: String

    /** A new movement on the ladder — always something the person just did. */
    data class VariationUp(val pattern: Pattern, val variation: Int, val exercise: String) : Milestone {
        override val id: String get() = "tier-${pattern.rawValue}-$variation"
    }

    /** Past the top variation the sets grow instead (3 → 4 → 5). */
    data class SetBand(val pattern: Pattern, val sets: Int, val exercise: String) : Milestone {
        override val id: String get() = "sets-${pattern.rawValue}-$sets"
    }

    data class Jubilee(val workouts: Int) : Milestone {
        override val id: String get() = "jubilee-$workouts"
    }
}

object MilestoneDetector {

    /** Jubilees: 10, 25, then every 50 (50, 100, 150, …). */
    fun isJubilee(counter: Int): Boolean = counter == 10 || counter == 25 || (counter > 0 && counter % 50 == 0)

    /** Skipped patterns are excluded explicitly. Order is deterministic:
     *  new variations, set bands, jubilee. */
    fun detect(before: EngineState, after: EngineState, session: Session,
               skipped: Set<Pattern> = emptySet()): List<Milestone> {
        val variationUps = mutableListOf<Milestone>()
        val setBands = mutableListOf<Milestone>()
        for (ex in session.exercises) {
            if (ex.pattern in skipped) continue
            val old = before.position(ex.pattern)
            val new = after.position(ex.pattern)
            // The *new* variation: the movement just unlocked.
            val name = Library.name(ex.pattern, new.variation)
            if (new.variation > old.variation) {
                variationUps += Milestone.VariationUp(ex.pattern, new.variation, name)
            }
            // Not an `else`: both render if the banding ever changes.
            if (new.sets > old.sets) setBands += Milestone.SetBand(ex.pattern, new.sets, name)
        }
        val result = variationUps + setBands
        // Not gated on the rating: a jubilee fires on one exact counter value
        // and never again.
        return if (isJubilee(after.counter)) result + Milestone.Jubilee(after.counter) else result
    }
}
