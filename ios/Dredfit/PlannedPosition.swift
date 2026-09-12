//
//  A recorded position, stated the way a plan states one.
//
//  Moved out of HistorySheet when the summary of a finished hold started
//  saying what the next plan will be (§41.13): two screens describing one
//  position in two spellings is how "After: 30-30-25 s" and "The app will
//  set 3×30 s" come to disagree about the same numbers.
//

import Foundation
import DredfitCore

extension RecordedPosition {
    /// One recorded position stated the way a plan states one.
    ///
    /// Built as a `SessionExercise` rather than spelled out here so the line
    /// under a row is written in the same words as the line on it — the use of
    /// that initialiser from outside the engine that its own doc comment
    /// sanctions — and so the two can be compared at all.
    ///
    /// Two of the six coordinates have to be resolved first. `cut` takes sets
    /// off WITHOUT moving `sets`, so the raw coordinate would read HIGHER than
    /// the plan right after a descent took some away (§36.3); `sub` is what
    /// makes a plan read "9-8-8" instead of "3×8". Both resolve the way
    /// `Engine.fit` resolves them, the top-rung disable included — above it the
    /// next rung belongs to another band, and adding a step there would print a
    /// dose the grid does not have.
    func asPlanned(_ pattern: Pattern) -> SessionExercise {
        let unit = Library.unit(pattern, self.variation)
        let grid = Dose.grid(unit)
        // Bounded by the SCALE, not by the record: `sets` comes back out of the
        // journal clamped only to a million, and this runs in a row body on the
        // main thread — the allocation `SessionExercise.perSetLoads` documents.
        // No position ever had more sets than the scale has bands, so the valid
        // domain never notices.
        let standing = self.sets
            - min(max(self.cut ?? 0, 0), Engine.cutMax(sets: self.sets))
        let sets = min(max(standing, 0), EngineConfig.setsMax)
        let sub = self.dose >= grid.max
            ? 0
            : min(max(self.sub ?? 0, 0), max(sets - 1, 0))
        let loads: [Int]? = sub > 0
            ? (0..<sets).map { $0 < sub ? self.dose + grid.step : self.dose }
            : nil
        return SessionExercise(pattern: pattern,
                               name: Library.name(pattern, self.variation),
                               variation: self.variation, unit: unit,
                               load: self.dose,
                               perSide: Library.sides(pattern, self.variation) == 2,
                               sets: sets, restSetSec: 0, restExerciseSec: 0,
                               loads: loads, probe: nil)
    }
}
