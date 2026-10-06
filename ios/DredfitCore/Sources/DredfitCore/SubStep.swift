//
//  A position and its measure.
//
//  A position is FIVE coordinates — variation, sets, dose, sub-step, cut.
//  `sets` is one of them because a set band cannot be read off the dose:
//  `4×11` and `3×11` carry one dose and different volumes, and entering a band
//  LOWERS the dose. It is stored sparsely with a base of 3.
//
//  The MEASURE is how many growth events separate a position from the very
//  bottom of its ladder. It is a measure, not an encoding: it has no inverse
//  and needs none. A growth event is +1 on it, which keeps the growth cells,
//  the weekly window and the cross-credit in one integer unit — save one
//  accepted corner: under a cut, when no set may come back, `riseBy` can add
//  a sub-step the cut hides, and that event moves nothing. A descent has no
//  such unit: a whole dose rung (`fallDoses`) costs `sets`, and a crossing
//  lands wherever `landInVar` finds room.
//

import Foundation

public struct Position: Equatable, Sendable {
    /// 1-based index along the pattern's ladder.
    public var variation: Int
    /// Sets in the plan. Base 3; bands 4 and 5 exist only on the TOP variation.
    public var sets: Int
    /// Reps — or seconds — per set.
    public var dose: Int
    /// The sub-step: the first `sub` sets carry one rung more.
    public var sub: Int
    /// Sets taken off — the second axis of volume.
    public var cut: Int

    public init(variation: Int, sets: Int, dose: Int, sub: Int, cut: Int) {
        self.variation = variation
        self.sets = sets
        self.dose = dose
        self.sub = sub
        self.cut = cut
    }
}

extension Engine {

    /// The same invariant on the way in and after every step of every
    /// transition. Every transition below works on a COPY of the
    /// position rather than on the state: one shape for generation, feedback,
    /// comeback and decay — drifted copies of one rule are the defect class
    /// the exhaustive sweeps exist for.
    static func fit(_ p: Pattern, _ pos: Position) -> Position {
        let v = Library.index(pattern: p, variation: pos.variation)
        let unit = Library.unit(p, v)
        let sets = min(max(pos.sets, EngineConfig.setsBase), setsCeil(p, v))
        let cut = effCut(sets: sets, cut: pos.cut)
        let dose = Dose.clamped(unit, Dose.snap(unit, pos.dose))
        let raw = Position(variation: v, sets: sets, dose: dose, sub: pos.sub, cut: cut)
        return Position(variation: v, sets: sets, dose: dose,
                        sub: effSub(p, raw, sets: nil), cut: cut)
    }

    static func same(_ a: Position, _ b: Position) -> Bool { a == b }

    /// On the top rung of a grid the sub-step is DISABLED: the next rung
    /// belongs to another band or another variation, and one exercise may
    /// never mix two of either.
    static func subDisabled(_ p: Pattern, _ pos: Position) -> Bool {
        pos.dose >= Dose.grid(Library.unit(p, pos.variation)).max
    }

    /// The sub-step actually in force. A sub-step may not ask for more sets
    /// than the cut left standing: otherwise the measure would count upper
    /// sub-steps the plan cannot show, and a descent would spend taps on them
    /// without changing the plan.
    static func effSub(_ p: Pattern, _ pos: Position, sets: Int?) -> Int {
        guard !subDisabled(p, pos) else { return 0 }
        let top = max(0, (sets ?? (pos.sets - pos.cut)) - 1)
        return min(max(pos.sub, 0), top)
    }

    /// The ordinal INSIDE a variation. Bands 4 and 5 exist only on the top
    /// variation, so for every other one this collapses to
    /// `(dose rung × 3) + sub`.
    ///
    /// Doses BELOW a band's entry are legal — a descent lands there — and the
    /// term then goes negative; the sum stays non-negative and monotone across
    /// every reachable transition (swept in the reference's verify2).
    static func ordInVar(_ p: Pattern, _ pos: Position) -> Int {
        let unit = Library.unit(p, pos.variation)
        let g = Dose.grid(unit)
        let topRung = Dose.rung(unit, dose: g.max)
        var o = 0
        var band = EngineConfig.setsBase
        while band < pos.sets {
            o += (topRung - Dose.rung(unit, dose: bandStartDose(unit, sets: band))) * band + 1
            band += 1
        }
        o += (Dose.rung(unit, dose: pos.dose)
              - Dose.rung(unit, dose: bandStartDose(unit, sets: pos.sets))) * pos.sets
            + pos.sub
        return o
    }

    /// What a whole variation costs in growth events, the probe out of it
    /// included.
    static func varSpan(_ p: Pattern, _ v: Int) -> Int {
        (Dose.rungCount(Library.unit(p, v)) - 1) * EngineConfig.setsBase + 1
    }

    static func varBase(_ p: Pattern, _ v: Int) -> Int {
        var o = 0
        for u in 1..<Library.index(pattern: p, variation: v) { o += varSpan(p, u) }
        return o
    }

    /// The full measure: the walk along the ladder, less the sets taken off.
    static func posOrd(_ p: Pattern, _ pos: Position) -> Int {
        varBase(p, pos.variation) + ordInVar(p, pos) - pos.cut
    }

    /// Per-set doses, DESCENDING — the first `sub` sets carry the next rung.
    /// A uniform plan answers nil ("nothing to say"), and the wire form keeps
    /// the field optional for the same reason: a journal written by an older
    /// build carries no such key.
    static func planLoads(_ p: Pattern, _ pos: Position, sets: Int) -> [Int]? {
        let s = effSub(p, pos, sets: sets)
        guard s > 0 else { return nil }
        let step = Dose.grid(Library.unit(p, pos.variation)).step
        return (0..<sets).map { $0 < s ? pos.dose + step : pos.dose }
    }
}
