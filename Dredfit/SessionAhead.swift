//
//  What is still ahead of the person in the session they are in — the live
//  half of the announced duration.
//
//  The plan announces how long the whole workout takes; once the decision
//  about its length is taken INSIDE the workout, that number has to follow
//  along. So the work screen carries what is left rather than what was
//  planned, and every skipped set comes off it the moment it is skipped.
//

import Foundation
import DredfitCore

/// Pure arithmetic over the session's own values, so it is not the main
/// actor's business — and it can be measured without a screen.
nonisolated enum SessionAhead {

    /// The exercises still to be performed: the one under way trimmed to the
    /// sets it has left, and everything after it whole.
    ///
    /// The sets that are left are the LAST ones of the plan, not the first —
    /// an uneven plan asks 9-8-8, and the person who has done the 9 has the
    /// two 8s ahead of them.
    static func remaining(_ exercises: [SessionExercise], exIndex: Int,
                          setsBehind: Int) -> [SessionExercise] {
        guard exercises.indices.contains(exIndex) else { return [] }
        let current = exercises[exIndex]
        let left = max(0, current.sets - max(0, setsBehind))
        var ahead: [SessionExercise] = []
        if left > 0 { ahead.append(trimmed(current, to: left)) }
        ahead.append(contentsOf: exercises[(exIndex + 1)...])
        return ahead
    }

    /// Minutes still ahead, through the ENGINE'S OWN arithmetic — the same
    /// `estimatedMin` the announced duration is made of, handed a shorter
    /// list. An app-side estimate would drift from the number on the plan by
    /// exactly the amount nobody could account for.
    ///
    /// `ends` is whatever fixed minutes are still to come: the cool-down while
    /// the work is under way, nothing once it is behind.
    static func minutes(_ exercises: [SessionExercise], exIndex: Int,
                        setsBehind: Int, ends: Int) -> Int {
        let ahead = remaining(exercises, exIndex: exIndex, setsBehind: setsBehind)
        return Int(Engine.estimatedMin(exercises: ahead, ends: max(0, ends)).rounded())
    }

    /// The same exercise with only its last `sets` sets left. Rebuilt rather
    /// than mutated — `SessionExercise` is a value with `let` fields, which is
    /// what keeps the plan the flow walks and the plan the engine reads the
    /// same object.
    private static func trimmed(_ ex: SessionExercise, to sets: Int) -> SessionExercise {
        SessionExercise(pattern: ex.pattern, name: ex.name, variation: ex.variation,
                        unit: ex.unit, load: ex.load, perSide: ex.perSide,
                        sets: sets,
                        restSetSec: ex.restSetSec, restExerciseSec: ex.restExerciseSec,
                        loads: ((ex.sets - sets)..<ex.sets).map { ex.plannedLoad(set: $0) },
                        // The probe is the LAST set of the exercise, so it is
                        // still ahead for as long as any of the exercise is.
                        probe: ex.probe)
    }
}
