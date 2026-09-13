//
//  What the next plan will be for one movement, read before the rating lands
//  (§41.13). Read-only: the summary of a finished hold asks, the store
//  answers by DRY-RUNNING the engine, and nothing is written.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The position a movement will stand on after this session, computed
    /// exactly the way `completeWorkout` will compute it — the same entry
    /// point, the same arguments — with the rating assumed to be "on plan".
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
    /// The LANDED share, not the taps: on the grid's ceiling the engine
    /// parks a raise, and the note is about the rise that stood.
    func raisedForNextPlan(_ pattern: Pattern) -> Int {
        guard let last = records.last,
              last.sessionNumber == engineState.counter,
              last.positionsAfter?[pattern] == currentPositions[pattern] else { return 0 }
        return min(max(last.raisedShare(pattern), 0), EngineConfig.raiseStepsMax)
    }

    /// The share of `raised` that moved a position: the growth events
    /// between the state the rating alone would have left and the one it
    /// left with the raise on top. One step of `raiseDose` is exactly one
    /// event along the ladder's measure — a sub-step, or the rung a full
    /// band of sub-steps turns into — so the difference of the two
    /// ordinals counts the steps that landed, and the engine's own
    /// parking on the ceiling (§41.13) shows up here as steps that did
    /// not. Bounded by the taps: nothing else moves between the two
    /// states, but a count the journal will print should not be able to
    /// exceed the decision it describes even if that changes.
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
