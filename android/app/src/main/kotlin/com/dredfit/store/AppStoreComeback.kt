//
//  The read-only companion of the comeback card (issue #127): what the two
//  offers actually are in numbers. Port of ios/Dredfit/AppStore+Comeback.swift;
//  the mutation (`acceptComeback`) stays in AppStore.kt.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.applyComeback
import com.dredfit.core.generateSession
import com.dredfit.workout.Words
import java.time.Instant

/** Swift's `(was: String, easier: String)`. */
data class ComebackPreview(val was: Words, val easier: Words)

/** Both offers as the same movement, in numbers: the pull slot is in every
 *  session, so it is the honest exemplar of what "easier" means. */
fun AppStore.comebackPreview(now: Instant = clock.instant()): ComebackPreview? {
    val gap = gapDays(now) ?: return null
    val after = Engine.applyComeback(state = engineState, gapDays = gap,
                                     alreadyDecayed = silentDecayAppliedForCurrentBreak)
    val slot = { state: EngineState ->
        Engine.generateSession(state).exercises.firstOrNull { it.pattern in Pattern.pullSide }
    }
    val was = slot(engineState) ?: return null
    val easier = slot(after) ?: return null
    return ComebackPreview(line(was), line(easier))
}

/** The WHOLE plan of that appearance, probe included — `display` alone
 *  prints only the working sets. */
private fun line(ex: SessionExercise): Words {
    val plan = Words.join("%@ · %@", Words.name(ex.name), Words.display(ex))
    val probe = ex.probe ?: return plan
    return Words.of("%@ + probe: %@ · %@", plan, Words.name(probe.name), Words.display(probe))
}
