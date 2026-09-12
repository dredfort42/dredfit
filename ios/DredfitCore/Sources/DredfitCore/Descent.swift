//
//  Descent (§40.3, §40.6) and the "no harder" gate (the rewritten §22.1/§30.4).
//
//  There are no TIER FLOORS in v3. Every descent through a variation boundary
//  lands in the JOURNAL OF WHAT WAS SHOWN — "exactly what you have already
//  done in this variation" — which is what closes both findings of
//  FINDING-tier-entry.md at once: the blind entry (now a probe) and the
//  rollback through a target (now the journal).
//

import Foundation

extension Engine {

    /// A variation's point of return. The grid floor when the trainee has
    /// never been there — that is the declared beginning, 3×4 (3×15 s).
    ///
    /// The journal is clamped by the dose FLOOR: "I showed two reps" sends you
    /// a variation down (§40.3) rather than landing you on a two.
    static func landingDose(_ p: Pattern, _ v: Int, shown: [Pattern: [Int: Int]]) -> Int {
        let unit = Library.unit(p, v)
        guard let recorded = shown[p]?[v] else { return Dose.grid(unit).min }
        return Dose.clamped(unit, Dose.snap(unit, recorded))
    }

    /// §41.1: THE LANDING DOES NOT ADD WORK.
    ///
    /// The journal gives a CEILING, not the dose itself. By construction of
    /// §40.4 a variation cannot be entered without showing its grid maximum,
    /// so `shown[v]` equals that maximum for everyone who passed through — and
    /// landing on it handed the trainee the LARGEST volume they had ever done
    /// in that movement, right after they said it was too hard. The audit of
    /// 26.08.2026 measured it: work rose on 49 boundaries out of 49, worst
    /// ×11.25 in time under load.
    ///
    /// Two axes, in this order: dose first at the full band, then the cut.
    /// Dose outranks volume — someone who left on two sets would rather have
    /// three light ones than three heavy ones, and a dropped set comes back in
    /// a single appearance (§37.6) while dose is walked back a rung at a time.
    ///
    /// When no pair fits, the grid floor at the sets they were doing: there is
    /// nothing lighter to land on, and that is accepted gap §41.6 item 1 —
    /// two hinge boundaries and one pull_bar unit boundary, ×2.00 at worst.
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
    /// growth event, §34.1). On the dose floor the step down becomes a set
    /// taken off. On the floor of the variation — dose floor AND set floor —
    /// the step down is the variation below, landing in the journal (§40.6).
    ///
    /// A descent deliberately does NOT cross a band downward: (4,11) → (3,15)
    /// would raise the dose per set from 11 to 15, i.e. the descent would make
    /// the plan HEAVIER — precisely the defect class (A3-1, §36.8) the gate was
    /// written for. Volume inside a band is taken off by the `cut` axis.
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
                break                       // the bottom of the whole ladder (§37.1)
            }
            k -= 1
        }
        return fit(p, cur)
    }

    /// Descent by WHOLE rungs of dose. §40.3: every descent that used to be
    /// expressed "in levels" (deload −3, comeback −2…−8, silent decay) is
    /// carried over by the rule "1 old level = 1 rep per set". The sub-step is
    /// zeroed — a descent takes it — and on the dose floor a set taken off
    /// becomes the rung, exactly as for a rated descent: without that a
    /// three-week break could not move anyone off an impossible variation at
    /// all.
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

    /// The gate, which in v3 is a CHECK rather than a filter (invariant И4):
    /// no path of descent may break it by construction.
    ///
    /// In v2 the measure across a variation boundary was declared invalid and
    /// the gate rested on the exception "a tier floor is always no harder". In
    /// v3 the measure across the boundary IS A SHOWN FACT — landing in
    /// `shown[var−1]` means "exactly what you have already done here" — so
    /// comparing reps of two different variations is no longer required.
    ///
    ///   • inside a variation — dose per set and total work with sides both
    ///     stay put or fall (the quantities are commensurable: same variation,
    ///     same unit, same sides);
    ///   • across a boundary downward — the assigned dose is no higher than
    ///     the target variation's journal (or its floor, if there is none),
    ///     and the set count is no higher than the base.
    static func noHarder(_ p: Pattern, from: Position, to: Position,
                         shown: [Pattern: [Int: Int]]) -> Bool {
        let a = planLoad(p, fit(p, from))
        let b = planLoad(p, fit(p, to))
        if to.variation > from.variation { return false }        // up is not a descent
        if to.variation == from.variation { return b.load <= a.load && b.total <= a.total }
        // §41.1: across a boundary this compares the SAME quantity as inside
        // one. The old branch checked only `b.load <= journal && b.sets <=
        // setsBase`, and `to` only ever arrives from `landInVar`, which sets
        // exactly those two equalities — the predicate could not return false
        // on any of 13 734 cells and guarded §40.6's promise with a tautology.
        // Writing the spec's literal text into it turned verify2 from 0 to 365
        // failures, which is how the defect was finally established.
        let journal = landingDose(p, to.variation, shown: shown)
        return b.load <= journal && b.sets <= EngineConfig.setsBase && b.total <= a.total
    }
}
