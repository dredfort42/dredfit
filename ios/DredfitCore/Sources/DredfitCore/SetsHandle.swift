//
//  The set axis: the cut, the bands on the top variation, and growth.
//
//  NO FUNCTION HERE CARRIES A DEFAULT ARGUMENT, deliberately. An omitted floor
//  argument was a repeated defect class — a compile error is a stronger guard
//  than a grep, and it stays that way now that the floor is shared by every
//  caller.
//

import Foundation

extension Engine {

    // MARK: - The cut

    /// Nobody cuts below the shared floor of sets.
    public static func cutMax(sets: Int) -> Int { max(0, sets - EngineConfig.setsFloor) }

    static func effCut(sets: Int, cut: Int) -> Int {
        min(max(cut, 0), cutMax(sets: sets))
    }

    static func setsAfterCut(sets: Int, cut: Int) -> Int {
        sets - effCut(sets: sets, cut: cut)
    }

    /// The one and only clamp on a set count. Every mechanism that cuts sets —
    /// the pull-caps-push gate among them — goes through it, so the floor holds for
    /// their COMPOSITION and not just for each cut on its own.
    static func clampSets(_ n: Int, floor: Int) -> Int { max(floor, n) }

    // MARK: - The bands on the top variation

    /// Once the dose tops out on the TOP variation, growth continues in sets:
    /// `sets → sets+1` at `⌊sets × ceiling / (sets+1)⌋`, snapped down to the
    /// grid. Total work does not rise at the moment of the transition
    /// (3×15 = 45 → 4×11 = 44; 3×45 s = 135 → 4×30 = 120) and the dose per set
    /// is strictly below the one already shown.
    static func bandEntryDose(_ unit: LoadUnit, setsFrom: Int) -> Int {
        Dose.snap(unit, (setsFrom * Dose.grid(unit).max) / (setsFrom + 1))
    }

    /// Where a band starts: the grid floor for the base, the band entry dose above.
    static func bandStartDose(_ unit: LoadUnit, sets: Int) -> Int {
        sets <= EngineConfig.setsBase ? Dose.grid(unit).min : bandEntryDose(unit, setsFrom: sets - 1)
    }

    /// Bands exist only on the top variation of a ladder.
    static func setsCeil(_ p: Pattern, _ v: Int) -> Int {
        Library.isTop(p, v) ? EngineConfig.setsMax : EngineConfig.setsBase
    }

    // MARK: - Growth

    /// Sets come back FIRST, and only then does the dose grow: the
    /// trainee wins back the volume that was taken off before going further on
    /// intensity. Tolerance of volume recovers before tolerance of intensity.
    ///
    /// At most ONE set per session, and only once the hold has run out:
    /// while it ticks, the growth event goes into the DOSE. That is
    /// what gives "set, dose, dose, set" instead of three sets in a row.
    ///
    /// The sub-step is counted against the BAND, so under a cut, while the
    /// hold ticks, it can land on a set the cut hides: `fit` clamps it back
    /// and the event is lost — the plan stands for at most the hold, then the
    /// set returns. Kept on purpose. Counting on the sets on screen moves the
    /// measure by two or more per visible rep, which the weekly window and the
    /// cross-credit then miscount; returning the set early breaks the very
    /// spacing the hold exists for.
    ///
    /// Growth NEVER crosses a variation: the only way into a new one is a
    /// probe. On the dose ceiling of a non-top variation growth honestly STANDS
    /// STILL — that is the declared parking.
    static func riseBy(_ p: Pattern, _ pos: Position, _ n: Int,
                       allowSetsBack: Bool) -> Position {
        var cur = fit(p, pos)
        var k = max(0, n)
        let back = allowSetsBack ? min(cur.cut, k, EngineConfig.setsBackPerSession) : 0
        if back > 0 {
            cur.cut -= back
            k = 0
        }
        while k > 0 {
            let unit = Library.unit(p, cur.variation)
            let g = Dose.grid(unit)
            if cur.dose < g.max {
                // A sub-step: +1 rep (or +5 s) in ONE set. Counted against the
                // BAND, not against the sets on screen — otherwise a set taken
                // off would make the rung cheaper.
                if cur.sub + 1 < cur.sets {
                    cur.sub += 1
                } else {
                    cur.dose += g.step
                    cur.sub = 0
                }
                k -= 1
                continue
            }
            if Library.isTop(p, cur.variation), cur.sets < EngineConfig.setsMax {
                let from = cur.sets
                cur.sets = from + 1
                cur.dose = bandEntryDose(unit, setsFrom: from)
                cur.sub = 0
                k -= 1
                continue
            }
            break   // parked on the ceiling: waiting for a probe, or at the top of the scale
        }
        return fit(p, cur)
    }

    /// Growth BOUNDED BY THE JOURNAL. Needed in exactly the one place a
    /// position rises WITHOUT the pattern appearing — the cross-credit:
    /// the pull slot's other branch was not in today's plan, and the
    /// trainee showed nothing in it. After an appearance `riseBy` needs no
    /// bound: it grows from the plan the person has just done.
    ///
    /// Unbounded, the credit would REPEAT someone else's gain and lift this
    /// branch past anything shown in it. The bound keeps what the credit is
    /// for — the branch does not fall a whole rung behind — and removes the
    /// prediction: the base dose may cross a rung only after the trainee has
    /// shown that rung IN THIS BRANCH.
    static func riseWithinJournal(_ p: Pattern, _ pos: Position, _ n: Int,
                                  allowSetsBack: Bool,
                                  shown: [Pattern: [Int: Int]]) -> Position {
        var cur = fit(p, pos)
        let row = shown[p] ?? [:]
        func allowed(_ q: Position) -> Bool {
            let g = Dose.grid(Library.unit(p, q.variation))
            let journal = max(g.min, min(row[q.variation] ?? g.min, g.max))
            return q.dose <= journal
        }
        var k = max(0, n)
        while k > 0 {
            let step = riseBy(p, cur, 1, allowSetsBack: allowSetsBack && cur.cut == pos.cut)
            if same(step, cur) || !allowed(step) { break }
            cur = step
            k -= 1
        }
        return cur
    }
}
