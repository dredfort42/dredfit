//
//  Descent and the "no harder" gate.
//
//  There are no TIER FLOORS. A descent through a variation boundary lands in
//  the variation below with the JOURNAL OF WHAT WAS SHOWN there as its
//  ceiling (the grid floor where the person has never been), walked down
//  until the plan weighs no more than the one being left — `landInVar`, which
//  also names the boundaries where nothing fits. The one crossing that skips
//  it is a comeback's landing ceiling, which writes the floor of its variation
//  directly (Breaks.swift).
//

import Foundation

extension Engine {

    /// A variation's point of return. The grid floor when the trainee has
    /// never been there — that is the declared beginning, 3×4 (3×15 s).
    ///
    /// The journal is clamped by the dose FLOOR: "I showed two reps" sends you
    /// a variation down rather than landing you on a two.
    static func landingDose(_ p: Pattern, _ v: Int, shown: [Pattern: [Int: Int]]) -> Int {
        let unit = Library.unit(p, v)
        guard let recorded = shown[p]?[v] else { return Dose.grid(unit).min }
        return Dose.clamped(unit, Dose.snap(unit, recorded))
    }

    /// THE LANDING DOES NOT ADD WORK.
    ///
    /// The journal gives a CEILING, not the dose itself. A variation cannot be
    /// entered without showing its grid maximum, so `shown[v]` equals that
    /// maximum for everyone who passed through — landing on it would hand the
    /// trainee the LARGEST volume they had ever done in that movement, right
    /// after they said it was too hard — more work than the floor they leave
    /// on every boundary, up to ×11.25 in time under load.
    ///
    /// Two axes, in this order: dose first at the full band, then the cut.
    /// Dose outranks volume — someone who left on two sets would rather have
    /// three light ones than two heavy ones, and a dropped set comes back in
    /// a single appearance while dose is walked back a rung at a time.
    ///
    /// When no pair fits, the grid floor at the sets they were doing: there is
    /// nothing lighter to land on. That is an accepted gap — two hinge
    /// boundaries and one pull_bar unit boundary, ×2.00 at worst.
    static func landInVar(_ p: Pattern, _ v: Int, shown: [Pattern: [Int: Int]],
                          from: Position? = nil) -> Position {
        let vi = Library.index(pattern: p, variation: v)
        let unit = Library.unit(p, vi)
        let grid = Dose.grid(unit)
        let ceiling = landingDose(p, vi, shown: shown)
        func make(_ dose: Int, _ cut: Int) -> Position {
            Position(variation: vi, sets: EngineConfig.setsBase, dose: dose, sub: 0, cut: cut)
        }
        guard let from else { return make(ceiling, 0) }
        let budget = planLoad(p, fit(p, from)).total
        let carried = Engine.effCut(sets: EngineConfig.setsBase, cut: from.cut)
        for cut in (carried == 0 ? [0] : [0, carried]) {
            var d = ceiling
            while d >= grid.min {
                if planLoad(p, make(d, cut)).total <= budget { return make(d, cut) }
                d -= grid.step
            }
        }
        return make(grid.min, carried)
    }

    /// Dose is spent before sets: while there is somewhere to step inside the
    /// variation along the growth path, step there (exactly the reverse of a
    /// growth event). On the dose floor the step down becomes a set
    /// taken off. On the floor of the variation — dose floor AND set floor —
    /// the step down is the variation below, landing under its journal.
    ///
    /// A descent deliberately does NOT cross a band downward: (4,11) → (3,15)
    /// would raise the dose per set from 11 to 15, i.e. the descent would make
    /// the plan HEAVIER — precisely the defect class the gate was written for.
    /// Volume inside a band is taken off by the `cut` axis.
    static func fallBy(_ p: Pattern, _ pos: Position, _ n: Int,
                       shown: [Pattern: [Int: Int]]) -> Position {
        var cur = fit(p, pos)
        var k = max(0, n)
        while k > 0 {
            let g = Dose.grid(Library.unit(p, cur.variation))
            if cur.sub > 0 {
                cur = fit(p, Position(variation: cur.variation, sets: cur.sets,
                                      dose: cur.dose, sub: cur.sub - 1, cut: cur.cut))
            } else if cur.dose > g.min {
                // The reverse of a growth event: (dose d, sub 0) → (d−1, band−1).
                cur = fit(p, Position(variation: cur.variation, sets: cur.sets,
                                      dose: cur.dose - g.step, sub: cur.sets - 1, cut: cur.cut))
            } else if setsAfterCut(sets: cur.sets, cut: cur.cut) > EngineConfig.setsFloor {
                cur = fit(p, Position(variation: cur.variation, sets: cur.sets,
                                      dose: cur.dose, sub: cur.sub, cut: cur.cut + 1))
            } else if cur.variation > 1 {
                cur = landInVar(p, cur.variation - 1, shown: shown, from: cur)
            } else {
                break                       // the bottom of the whole ladder
            }
            k -= 1
        }
        return fit(p, cur)
    }

    /// Descent by WHOLE rungs of dose (deload, comeback, silent decay). The
    /// sub-step is zeroed — a descent takes it — and on the dose floor a set
    /// taken off becomes the rung, exactly as for a rated descent: without
    /// that a three-week break could not move anyone off an impossible
    /// variation at all.
    static func fallDoses(_ p: Pattern, _ pos: Position, _ n: Int,
                          shown: [Pattern: [Int: Int]]) -> Position {
        var cur = fit(p, Position(variation: pos.variation, sets: pos.sets,
                                  dose: pos.dose, sub: 0, cut: pos.cut))
        var k = max(0, n)
        while k > 0 {
            let g = Dose.grid(Library.unit(p, cur.variation))
            if cur.dose > g.min {
                cur = fit(p, Position(variation: cur.variation, sets: cur.sets,
                                      dose: cur.dose - g.step, sub: 0, cut: cur.cut))
            } else if setsAfterCut(sets: cur.sets, cut: cur.cut) > EngineConfig.setsFloor {
                cur = fit(p, Position(variation: cur.variation, sets: cur.sets,
                                      dose: cur.dose, sub: 0, cut: cur.cut + 1))
            } else if cur.variation > 1 {
                cur = landInVar(p, cur.variation - 1, shown: shown, from: cur)
            } else {
                break
            }
            k -= 1
        }
        return cur
    }

    /// What a plan weighs, in the units of the measure.
    struct PlanLoad: Equatable {
        let sets: Int
        let load: Int
        let total: Int
    }

    static func planLoad(_ p: Pattern, _ pos: Position) -> PlanLoad {
        let sets = setsAfterCut(sets: pos.sets, cut: pos.cut)
        let s = effSub(p, pos, sets: sets)
        let step = Dose.grid(Library.unit(p, pos.variation)).step
        let sides = Library.sides(p, pos.variation)
        return PlanLoad(sets: sets, load: pos.dose,
                        total: (sets * pos.dose + s * step) * sides)
    }

    /// The gate is a CHECK rather than a filter: the paths of descent are
    /// built to pass it, and the tests call it on what they produce — no
    /// production code does. The accepted gaps `landInVar` names are the only
    /// landings that fail it.
    ///
    ///   • inside a variation — dose per set and total work with sides both
    ///     stay put or fall (the quantities are commensurable: same variation,
    ///     same unit, same sides);
    ///   • across a boundary downward — the dose is no higher than the target
    ///     variation's journal (or its floor, if there is none), the set count
    ///     no higher than the base, and the total work with sides no higher
    ///     than the plan being left: the same quantity `landInVar` budgets,
    ///     compared across two movements.
    static func noHarder(_ p: Pattern, from: Position, to: Position,
                         shown: [Pattern: [Int: Int]]) -> Bool {
        let a = planLoad(p, fit(p, from))
        let b = planLoad(p, fit(p, to))
        if to.variation > from.variation { return false }        // up is not a descent
        if to.variation == from.variation { return b.load <= a.load && b.total <= a.total }
        // The first two clauses cannot fail on a `landInVar` landing — it
        // starts at the journal on the base sets and only walks down — so
        // without `b.total <= a.total` the gate would pass every landing.
        let journal = landingDose(p, to.variation, shown: shown)
        return b.load <= journal && b.sets <= EngineConfig.setsBase && b.total <= a.total
    }
}
