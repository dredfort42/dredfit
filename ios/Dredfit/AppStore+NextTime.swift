//
//  What the next plan will be for one movement, read before the rating
//  lands. Read-only: the summary of a finished hold asks, the store answers
//  by DRY-RUNNING the engine, and nothing is written.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The position a movement will stand on after this session, computed
    /// the way `completeWorkout` will compute it — the same entry point and
    /// arguments, with the rating assumed to be "on plan" and the gap
    /// measured now.
    ///
    /// The assumption is a promise only where it cannot break. With a fact
    /// entered for the movement the step is taken from the fact
    /// (`stepFromFact`) and the rating never reaches it; without one the
    /// step is the rating's, and the sentence on screen says so. The caller
    /// decides which sentence — this only answers where the numbers land.
    ///
    /// Nil when the session is not the one this state generated: a preview
    /// of a rating the engine would refuse is a preview of nothing.
    func previewPosition(after session: Session, pattern: Pattern, // swiftlint:disable:this function_parameter_count
                         overrides: [Pattern: Double], skipped: Set<Pattern>,
                         setsSkipped: SetFacts.Skips, probes: [Pattern: Int],
                         raised: [Pattern: Int]) -> RecordedPosition? {
        guard session.sessionNumber == engineState.counter + 1 else { return nil }
        let next = Engine.applyFeedback(state: engineState, session: session,
                                        result: .plan, overrides: overrides,
                                        skipped: skipped, setsSkipped: setsSkipped,
                                        gapDays: gapFraction(),
                                        probes: probes, raised: raised)
        return Self.positions(of: next)[pattern]
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
    /// it), not the taps: on the grid's ceiling the engine parks a raise, and
    /// the note is about the rise that stood.
    func raisedForNextPlan(_ pattern: Pattern) -> Int {
        guard let last = records.last,
              last.sessionNumber == engineState.counter,
              last.positionsAfter?[pattern] == currentPositions[pattern] else { return 0 }
        return min(max(last.raisedShare(pattern), 0), EngineConfig.raiseStepsMax)
    }

    /// The share of `raised` the journal records as having moved a
    /// position, per movement: the growth events between the state the rating
    /// alone would have left and the one it left with the raise on top,
    /// capped at the taps. Only the raise differs between the two states, so
    /// a raise parked on the grid's ceiling shows up here as steps that did
    /// not land.
    ///
    /// It counts events, not steps. Without a cut the two agree step for
    /// step; under a cut the step that rolls the sub-step into the next rung
    /// is worth more than one event: squat 3×10 with cut 1 moves +1 after one
    /// step of `raiseDose` and +3 after two, which the cap brings back to 2.
    /// A step burned on the ceiling after such a step is still counted: at
    /// 3×14, sub 1, cut 1, two steps land where one does, the ordinals move
    /// +2, and this returns 2.
    static func landed(_ raised: [Pattern: Int],
                       from unraised: EngineState, to next: EngineState) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for (pattern, steps) in raised where steps > 0 {
            let moved = Engine.progress(next, pattern) - Engine.progress(unraised, pattern)
            if moved > 0 { out[pattern] = min(steps, moved) }
        }
        return out
    }
}
