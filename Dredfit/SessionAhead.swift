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

    /// The exercises still to be performed, ON THE PLAN ALONE — what the
    /// session announced before anybody deviated from it.
    ///
    /// The live header does not use this one: a hold runs on the time the
    /// athlete declared and on the shortfall a set cut short carries forward,
    /// and neither of those is in the plan. That is the form below.
    static func remaining(_ exercises: [SessionExercise], exIndex: Int,
                          setsBehind: Int) -> [SessionExercise] {
        remaining(exercises, exIndex: exIndex, setsBehind: setsBehind,
                  facts: [:], declared: nil)
    }

    /// The same list, built out of what the exercise UNDER WAY will actually
    /// run at rather than out of its plan.
    ///
    /// The sets that are left are the LAST ones of the plan, not the first —
    /// an uneven plan asks 9-8-8, and the person who has done the 9 has the
    /// two 8s ahead of them.
    ///
    /// `facts` and `declared` are the two things the work screen itself lives
    /// on: the clock counts down from `SetFacts.holdTarget`, and the header
    /// counted the plan — so declaring 45 s against a plan of 30 moved every
    /// remaining set of that movement and moved the number not at all, and a
    /// hold stopped at 22 of 40 went on promising 40 for the sets after it
    /// (UX review 05.09.2026). The two disagree exactly when the person has
    /// deviated, which is when "am I going to make it" is asked.
    ///
    /// ONLY the exercise under way takes them. The movements after it have
    /// had nothing said about them yet, so their plan is the honest answer,
    /// and a declaration belongs to the exercise it was made for — it is
    /// cleared on the way out of one (`resetHoldExercise`).
    ///
    /// The number can therefore go UP mid-exercise, which it never could
    /// before: declaring more than the plan makes the workout longer, and
    /// saying so is the whole point of a number that recalculates. What it
    /// must never do is move without the person having moved it.
    static func remaining(_ exercises: [SessionExercise], exIndex: Int,
                          setsBehind: Int,
                          facts: SetFacts.PerSet, declared: Int?) -> [SessionExercise] {
        guard exercises.indices.contains(exIndex) else { return [] }
        let current = exercises[exIndex]
        let left = max(0, current.sets - max(0, setsBehind))
        var ahead: [SessionExercise] = []
        if left > 0 {
            ahead.append(trimmed(current, to: left, facts: facts, declared: declared))
        } else if current.probe != nil {
            // The probe is a set of its own (§40.4) and it is the LAST one, so
            // it is still ahead when every working set is behind — which is
            // exactly the rest screen that announces it by name. Dropping the
            // exercise on `left == 0` took the probe and the rest after it off
            // the number, understating what is left by a minute or two at the
            // moment the person is deciding whether to try an unfamiliar
            // movement (UX review 05.09.2026).
            ahead.append(trimmed(current, to: 0, facts: facts, declared: declared))
        }
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
    ///
    /// Plan-only, like the `remaining` above it: this is what a session
    /// announces, and the live header calls the form that takes the facts.
    static func minutes(_ exercises: [SessionExercise], exIndex: Int,
                        setsBehind: Int, ends: Int) -> Int {
        minutes(exercises, exIndex: exIndex, setsBehind: setsBehind, ends: ends,
                facts: [:], declared: nil)
    }

    /// …and the same arithmetic over the list the person is actually walking.
    /// The engine still does the counting — only the numbers going into it
    /// change, so the header and the line on Today cannot drift apart.
    static func minutes(_ exercises: [SessionExercise], exIndex: Int,
                        setsBehind: Int, ends: Int,
                        facts: SetFacts.PerSet, declared: Int?) -> Int {
        let ahead = remaining(exercises, exIndex: exIndex, setsBehind: setsBehind,
                              facts: facts, declared: declared)
        return Int(Engine.estimatedMin(exercises: ahead, ends: max(0, ends)).rounded())
    }

    /// The same exercise with only its last `sets` sets left. Rebuilt rather
    /// than mutated — `SessionExercise` is a value with `let` fields, which is
    /// what keeps the plan the flow walks and the plan the engine reads the
    /// same object.
    ///
    /// Each remaining set is priced at what its clock will be set to, which
    /// with no facts and no declaration IS `plannedLoad` — `holdTarget` falls
    /// through to `inForce`, and `inForce` falls through to the plan — so the
    /// plan-only entry points above are unchanged to the bit.
    private static func trimmed(_ ex: SessionExercise, to sets: Int,
                                facts: SetFacts.PerSet, declared: Int?) -> SessionExercise {
        SessionExercise(pattern: ex.pattern, name: ex.name, variation: ex.variation,
                        unit: ex.unit, load: ex.load, perSide: ex.perSide,
                        sets: sets,
                        restSetSec: ex.restSetSec, restExerciseSec: ex.restExerciseSec,
                        // `index`, never `set`: the parser reads a binding
                        // named `set` as the accessor keyword and the file
                        // stops compiling (R23 paid for this once already).
                        loads: ((ex.sets - sets)..<ex.sets).map { index in
                            // A declaration governs a HOLD only; reps have no
                            // control that sets a target before the effort,
                            // and their shortfall carries forward through the
                            // very same `inForce` the work screen reads.
                            ex.unit == .hold
                                ? SetFacts.holdTarget(facts, ex, set: index, declared: declared)
                                : SetFacts.inForce(facts, ex, set: index)
                        },
                        // The probe is the LAST set of the exercise, so it is
                        // still ahead for as long as any of the exercise is.
                        // Its own number is untouched: a time declared for
                        // THIS movement says nothing about the one the probe
                        // offers (§40.4).
                        probe: ex.probe)
    }
}
