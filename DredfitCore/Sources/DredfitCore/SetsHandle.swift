//
//  SetsHandle.swift
//  DredfitCore
//
//  v2.25 (spec §36): the sets handle — the second axis of a position. Split
//  out of Level.swift the way Level itself was split out of Engine.swift: the
//  arithmetic is Level's, the file is separate only because the lint's ceiling
//  is a real one.
//
//  The engine had no way to say "the same movement, less of it". A level fixes
//  the VARIATION and the DOSE PER SET; on the floor of every mod-8 block the
//  dose is already the smallest that variation has (`repStart` is the bottom),
//  so a step down from there had to swap the exercise — and the top of the
//  tier below is heavier than the bottom of the current one. That is the whole
//  class of "the engine needs to lower the load and raises it": a 7-13 day
//  break made the plan heavier in 48 cells of 480, a pain report took nothing
//  off in 24, an honest "hard" locked movement on all 48 levels, and the "I
//  was ill" tap made the plan heavier in 40. With the handle each of the four
//  is zero.
//
//  NOT ONE FUNCTION HERE CARRIES A DEFAULT ARGUMENT, and that is deliberate.
//  Four rounds of skeptics in a row caught this model on the same class of
//  defect — an optional argument omitted, or omitted with the wrong floor:
//  `effCut` with the shared floor instead of the pain one silently handed a
//  set back to everyone sitting on a pain landing, in 480 cells out of 480. A
//  compile error is a stronger guard than a grep, so every caller spells every
//  floor out.
//

import Foundation

extension Level {

    /// How many sets may be taken off a level before it reaches `floor`.
    public static func cutMax(level: Int, floor: Int) -> Int {
        max(0, decode(level).sets - floor)
    }

    /// The cut actually in force: garbage and negatives read as none, anything
    /// past the path's own ceiling clamps to it.
    public static func effCut(level: Int, cut: Int, floor: Int) -> Int {
        min(max(cut, 0), cutMax(level: level, floor: floor))
    }

    /// The exercise's sets before the §20.2 band gate and before the §28.3
    /// budget. The floor here is the PAIN one: a state may legitimately carry
    /// the pain channel's landing of a single set, and nothing downstream is
    /// allowed to raise it back.
    public static func setsAfterCut(level: Int, cut: Int) -> Int {
        decode(level).sets - effCut(level: level, cut: cut,
                                    floor: EngineConfig.setsFloor)
    }

    /// v2.25 (spec §36.3): the position's MEASURE. One growth event is exactly
    /// +1 and one step of a descent exactly −1, so the §15.3 caps, the §28.5
    /// window and the §20.1 cross-credit keep counting it as integers and stay
    /// the code they were.
    ///
    /// A measure, not an encoding: it has no inverse and needs none — no path
    /// asks for one, because every clamp is expressed as a RETURN TO THE ENTRY
    /// TRIPLE rather than as a lookup by ordinal.
    ///
    /// ACCEPTED PROPERTY (round 4, S6-4): with a non-empty cut the scale is not
    /// surjective — the plan shows only the sub-steps that fit after the cut
    /// while the measure counts the whole band's, so ONE step of a descent
    /// sometimes moves it by 2–5 (118 triples of 392). Upward the step is
    /// exactly +1 (387 of 392, the rest being the scale's ceiling). The §15.3
    /// and §28.5 ceilings bound GROWTH, and there the measure is exact; on a
    /// descent they do not act at all, so the asymmetry is one-sided and in
    /// safety's favour.
    public static func posOrd(level: Int, sub: Int, cut: Int) -> Int {
        ordinal(level: level, sub: sub)
            - effCut(level: level, cut: cut, floor: EngineConfig.setsFloor)
    }

    public static func posOrd(_ position: Position) -> Int {
        posOrd(level: position.level, sub: position.sub, cut: position.cut)
    }

    /// Growth: SETS COME BACK FIRST, and only then the dose grows. That is
    /// what "until recovery" means — the trainee first wins back the volume
    /// that was taken away, and only then goes further along the dose. The
    /// order is not arbitrary: tolerance of volume returns before tolerance of
    /// intensity.
    ///
    /// At most `setsBackPerSession` come back in one session. Sets are taken
    /// off one report at a time and must return at the same step: two at once
    /// gave +200 % of work for one event (`squat` L8 cut 2: 1×6 per side →
    /// 3×6 per side) — right after a pain episode closed, when the tissue had
    /// only just stopped hurting. The leftover growth steps are NOT carried
    /// over into the dose: otherwise winning volume back would cost the
    /// trainee progress on the scale, and they would pay for it twice.
    ///
    /// A set only comes back once the hold has run out (`setsBackHold`). While
    /// it holds, a growth event goes into the DOSE — the trainee keeps growing,
    /// just by a smaller step, and the volume is added less often. That is the
    /// alternation the axis was missing: set, dose, dose, set — instead of
    /// set, set, set. The sets axis is an order of magnitude coarser than the
    /// dose axis (a dose step is ×1.033 median, ×1.08 worst; a set coming back
    /// is ×1.500 median and ×2.00 worst), and §32 rejected a +50 % dose step
    /// as a breach of "do no harm", citing ACSM 2009's "a 2–10 % increase in
    /// load".
    public static func riseBy(level: Int, sub: Int, cut: Int, by count: Int,
                              allowSetsBack: Bool) -> Position {
        var c = effCut(level: level, cut: cut, floor: EngineConfig.setsFloor)
        var k = max(0, count)
        let back = allowSetsBack ? min(min(c, k), EngineConfig.setsBackPerSession) : 0
        if back > 0 { c -= back; k = 0 }
        let pos = rise(level: level, sub: sub, by: k)
        let cc = min(c, cutMax(level: pos.level, floor: EngineConfig.setsFloor))
        return Position(level: pos.level,
                        sub: min(max(pos.sub, 0),
                                 max(0, decode(pos.level).sets - cc - 1)),
                        cut: cc)
    }

    /// Descent: THE DOSE GOES BEFORE THE SETS. While there is somewhere to
    /// step inside the block along the growth path we step there — exactly the
    /// reverse of a growth event (§34.1). On a block floor that path has run
    /// out, and the step down becomes a set taken off. The bottom is `floor`
    /// sets; below that a descent has to change the variation, and that is the
    /// one place where a measure across the boundary stops being valid (§30.4).
    public static func fallBy(level: Int, sub: Int, cut: Int, by count: Int,
                              floor: Int) -> Position {
        // v2.25 (Ф5): the same invariant on entry and at every step — a
        // sub-step can never ask for more sets than the cut leaves.
        func fit(_ lv: Int, _ sb: Int, _ ct: Int) -> Int {
            min(max(sb, 0),
                max(0, decode(lv).sets
                    - effCut(level: lv, cut: ct, floor: EngineConfig.setsFloor) - 1))
        }
        var curLevel = level
        var c = effCut(level: level, cut: cut, floor: EngineConfig.setsFloor)
        var curSub = fit(level, sub, c)
        var k = max(0, count)
        while k > 0 {
            let cand = descend(level: curLevel, sub: curSub, by: 1)
            if cand.level != curLevel || cand.sub != curSub {
                curLevel = cand.level
                curSub = cand.sub
                k -= 1
                continue
            }
            if decode(curLevel).sets - c > floor {
                c += 1
                curSub = fit(curLevel, curSub, c)
                k -= 1
                continue
            }
            break                       // the bottom of the variation
        }
        return Position(level: curLevel, sub: fit(curLevel, curSub, c), cut: c)
    }

    /// v2.25 (spec §36.4, round 6 fix 5): TIME UNDER LOAD — the only quantity
    /// that is comparable across a change of unit. Reps and seconds are
    /// incommensurable (§30.4), but "how many seconds the muscle works" is
    /// defined for both: a rep costs `tempoSecPerRep` seconds, a second of a
    /// hold costs a second.
    public static func timeUnderLoad(pattern: Pattern, level: Int, sub: Int, cut: Int) -> Double {
        let w = work(pattern: pattern, level: level, sub: sub, cut: cut)
        return w.unit == .reps
            ? Double(w.total) * EngineConfig.tempoSecPerRep
            : Double(w.total)
    }

    /// Where a descent lands when the UNIT changes: the highest rung of the
    /// target tier whose time under load is no greater than the current plan's.
    ///
    /// Before this the gate let ANY level through on a branch of
    /// incommensurable units, and `pullBar` answering an honest "5 of 6
    /// negatives" landed on the top of the hang — 2×39 s against 2×6 reps,
    /// ×1.44 on time under load, with the grip becoming the limiter instead of
    /// the pull. Landing on the tier's very floor (this fix's first draft)
    /// cured the overload but wiped the branch out. A search by time gives
    /// both: no harder, and not the bottom either.
    ///
    /// ACCEPTED (§36.10 p. 7): if even the bottom rung of the target tier
    /// costs more at the same set count, we sit down on the floor and the
    /// branch loses what it had. For `pullBar` that is L8 → L0: three sets of
    /// a 20 s hang (60 s) already cost more than three sets of six negatives
    /// (45 s), and the library has no rung in between. §30.4 says it plainly —
    /// a break in the UNIT is a defect of the LADDER and is fixed in the
    /// library, the way v2.18 (§29) fixed the pike → handstand gap. Until then
    /// safety outranks a kept level.
    public static func landOnUnitChange(pattern: Pattern, fromLevel: Int, fromSub: Int,
                                        fromCut: Int, toTier: Int) -> Int {
        let budget = timeUnderLoad(pattern: pattern, level: fromLevel,
                                   sub: fromSub, cut: fromCut)
        let floor = (toTier - 1) * EngineConfig.stepsPerTier
        var best = floor
        for i in 0..<EngineConfig.stepsPerTier {
            let cand = floor + i
            if cand > EngineConfig.levelMax { break }
            if timeUnderLoad(pattern: pattern, level: cand, sub: 0, cut: 0) <= budget {
                best = cand
            } else {
                break
            }
        }
        return best
    }

    /// How many growth steps an honest fact buys: how far it overtakes the
    /// current position, and no further than the (pattern, tier) ceiling.
    ///
    /// ONE expression for BOTH fact paths — the main one and the fast one that
    /// closes a pain episode. Two copies of one rule drifting apart is the
    /// defect class the local sweep exists to catch, and this rule in
    /// particular had exactly that history.
    ///
    /// Both sides of the difference are floored at zero: at level 0 with a
    /// non-empty cut the measure is negative, and without the floor the step
    /// would be counted from a position that does not exist — that is, sets
    /// would be handed back for free.
    public static func riseSteps(toFact factLevel: Int, from ordinal: Int, cap: Int) -> Int {
        let base = max(0, ordinal)
        return max(0, min(Level.ordinal(level: factLevel, sub: 0), base + cap) - base)
    }
}
