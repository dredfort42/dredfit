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
    // swiftlint:disable:next function_parameter_count
    func previewPosition(after session: Session, pattern: Pattern,
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
    func raisedForNextPlan(_ pattern: Pattern) -> Int {
        guard let last = records.last,
              last.sessionNumber == engineState.counter,
              let steps = last.raisedSteps?[pattern], steps > 0,
              last.positionsAfter?[pattern] == currentPositions[pattern] else { return 0 }
        return min(steps, EngineConfig.raiseStepsMax)
    }
}
