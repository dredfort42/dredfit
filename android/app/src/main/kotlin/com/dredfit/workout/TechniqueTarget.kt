//
//  What a technique sheet is about. Lives in ios/Dredfit/Views/TechniqueSheet.swift;
//  a file of its own here because the flow decides which movement the sheet
//  of a rest describes (`WorkoutSession.restTechniqueTarget`), and the flow is
//  plain Kotlin.
//

package com.dredfit.workout

import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe

data class TechniqueTarget(val pattern: Pattern, val variation: Int, val unit: LoadUnit) {

    val id: String get() = "${pattern.rawValue}-$variation"

    constructor(exercise: SessionExercise) : this(exercise.pattern, exercise.variation, exercise.unit)

    /** The movement a probe offers — another variation, possibly in another
     *  unit (`pull_bar` 2→3). */
    constructor(probe: SessionProbe, of: Pattern) : this(of, probe.variation, probe.unit)
}
