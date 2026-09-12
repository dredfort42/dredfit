//
//  How an addition "for next time" is printed (§41.13), in one place for
//  the four screens that print one: the summary's stepper, the rating, the
//  history line and tomorrow's plan. One step of the ladder is +5 s to one
//  set of a hold or +1 rep to one set of a reps movement (§33), so the
//  figure is the steps times the grid's step, in the movement's own unit.
//

import Foundation
import DredfitCore

nonisolated enum RaiseLabel {
    static func added(steps: Int, unit: LoadUnit) -> Int {
        max(0, steps) * Dose.grid(unit).step
    }

    /// "+5 s" / "+1" — verbatim, no words to translate.
    static func text(steps: Int, unit: LoadUnit) -> String {
        let n = added(steps: steps, unit: unit)
        return unit == .hold ? "+\(n) s" : "+\(n)"
    }

    static func spoken(steps: Int, unit: LoadUnit) -> String {
        let n = added(steps: steps, unit: unit)
        return unit == .hold
            ? String(localized: "plus \(n) seconds for next time")
            : String(localized: "plus \(n) reps for next time")
    }
}
