//
//  What the next plan will be for one movement, read before the rating
//  lands. Read-only: the summary of a finished hold asks, the store answers
//  by DRY-RUNNING the engine, and nothing is written.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The plan a movement will get after this session: the position it will
    /// stand on, computed the way `completeWorkout` will compute it — the same
    /// entry point and arguments, with the rating assumed to be "on plan" and
    /// the gap measured now — stated the way a plan states one.
    ///
    /// With the probe the next session would hand it, asked of the engine
    /// over the same state (`Engine.probe`): on a probing appearance the
    /// probe takes a working set, and a plan read without it would promise a
    /// set the engine will not ask for.
    ///
    /// The assumption is a promise only where it cannot break. With a fact
    /// entered for the movement the step is taken from the fact
    /// (`stepFromFact`) and the rating never reaches it; without one the
    /// step is the rating's, and the sentence on screen says so. The caller
    /// decides which sentence — this only answers where the numbers land.
    ///
    /// Nil when the session is not the one this state generated: a preview
    /// of a rating the engine would refuse is a preview of nothing.
    func previewPlan(after session: Session, pattern: Pattern, // swiftlint:disable:this function_parameter_count
                     overrides: [Pattern: Double], skipped: Set<Pattern>,
                     setsSkipped: SetFacts.Skips, probes: [Pattern: Int],
                     raised: [Pattern: Int]) -> SessionExercise? {
        guard session.sessionNumber == engineState.counter + 1 else { return nil }
        let next = Engine.applyFeedback(state: engineState, session: session,
                                        result: .plan, overrides: overrides,
                                        skipped: skipped, setsSkipped: setsSkipped,
                                        gapDays: gapFraction(),
                                        probes: probes, raised: raised)
        guard let position = Self.positions(of: next)[pattern] else { return nil }
        let probe = Engine.probe(pattern, at: next.position(pattern),
                                 lastHard: next.lastHard, shown: next.shown)
        return position.asPlanned(pattern, probe: probe)
    }

    /// Steps the LAST workout added to a movement "for next time", when the
    /// plan on screen is the one that addition shaped — `counter + 1` is the
    /// session the record's raise landed on, and any later record means the
    /// addition has already been shown and spent. Zero otherwise, and zero
    /// too once anything else has moved the movement since the rating (an
    /// easier variation by hand, a decay): the note names a rise that is
    /// still standing, not one that was.
    ///
    /// The landed share the record keeps (`raisedShare`, as `landed` counted
    /// it; a record written before that share was kept falls back to the
    /// taps): on the grid's ceiling the engine parks a raise, and the note is
    /// about the rise that stood.
    func raisedForNextPlan(_ pattern: Pattern) -> Int {
        guard let last = records.last,
              last.sessionNumber == engineState.counter,
              last.positionsAfter?[pattern] == currentPositions[pattern] else { return 0 }
        return min(max(last.raisedShare(pattern), 0), EngineConfig.raiseStepsMax)
    }

    /// The share of `raised` the journal records as having moved a
    /// position, per movement: the steps that changed the plan when the raise
    /// is replayed one step at a time over the state the rating alone would
    /// have left — the state the engine raises, since the raise lands last.
    /// A step parked on the grid's ceiling moves nothing and is not counted.
    ///
    /// Step by step, not by the total move on the measure: under a cut the
    /// step that completes a rung moves the measure by more than one, and a
    /// step burned on the ceiling after it would hide inside that jump.
    static func landed(_ raised: [Pattern: Int], from unraised: EngineState) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for (pattern, steps) in raised where steps > 0 {
            var before = Engine.progress(unraised, pattern)
            var moved = 0
            for k in 1...min(steps, EngineConfig.raiseStepsMax) {
                let after = Engine.progress(Engine.raiseDose(state: unraised, pattern: pattern, steps: k),
                                            pattern)
                if after > before { moved += 1 }
                before = after
            }
            if moved > 0 { out[pattern] = moved }
        }
        return out
    }
}
