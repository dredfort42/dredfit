//
//  The dose grids (§40.2) — the whole of what used to be the arithmetic of a
//  level `L ∈ [0,47]`.
//
//  TWO grids for the entire library: reps 4…15 by 1, holds 15…45 by 5. There
//  are no per-tier starting doses any more (`repStart`, `repStartBand`,
//  `holdLadder`, `holdStartBand`): the start of any variation is its grid's
//  floor, and the "smoothing of the steps" v2.3 spent a table on is done by
//  the LADDER itself now — the rungs stand at most ×1.50 apart (§40.1), so one
//  step of 5 s on 15…45 is between +11 % and +33 % wherever you stand.
//
//  Nothing here reads `w`. A dose is measured, never predicted (§40.0).
//

import Foundation

public struct DoseGrid: Equatable, Sendable {
    public let min: Int
    public let max: Int
    public let step: Int
}

public enum Dose {

    public static let reps = DoseGrid(min: 4, max: 15, step: 1)
    public static let hold = DoseGrid(min: 15, max: 45, step: 5)

    public static func grid(_ unit: LoadUnit) -> DoseGrid {
        switch unit {
        case .reps: return reps
        case .hold: return hold
        }
    }

    /// How many rungs a grid has, floor included.
    static func rungCount(_ unit: LoadUnit) -> Int {
        let g = grid(unit)
        return (g.max - g.min) / g.step + 1
    }

    /// The rung a dose sits on. Doses OUTSIDE `[min, max]` are legal as an
    /// INPUT — a raw reported fact is one — and the rung then goes negative or
    /// past the top. Clipping it at the edge is exactly what broke the
    /// monotonicity of the reading-from-a-fact in #139, so it is not clipped.
    static func rung(_ unit: LoadUnit, dose: Int) -> Int {
        floorDiv(dose - grid(unit).min, grid(unit).step)
    }

    static func dose(_ unit: LoadUnit, atRung rung: Int) -> Int {
        grid(unit).min + rung * grid(unit).step
    }

    /// A fact is snapped DOWN to the grid ("do no harm"): 37 s at a step of 5
    /// is 35 s, not 40. There is deliberately no round-to-nearest here — the
    /// platform's rounding mode (JS `Math.round` takes halves up, Swift's
    /// `.rounded()` takes them away from zero) is not part of the model.
    static func snap(_ unit: LoadUnit, _ x: Int) -> Int {
        dose(unit, atRung: rung(unit, dose: x))
    }

    static func clamped(_ unit: LoadUnit, _ d: Int) -> Int {
        Swift.min(Swift.max(d, grid(unit).min), grid(unit).max)
    }

    /// Floor division. Swift's `/` truncates toward zero, so `(2 - 4) / 1` is
    /// −2 either way but `(11 - 15) / 5` is 0 where `Math.floor` gives −1 —
    /// and a hold reported as 11 s IS below the floor. Getting this wrong
    /// makes a fact under the grid read as "on the floor" and the descent
    /// through the variation boundary never fires.
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        let r = a % b
        return r != 0 && ((r < 0) != (b < 0)) ? q - 1 : q
    }
}
