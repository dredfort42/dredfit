//
//  SetFacts.swift
//  Dredfit
//
//  A fact belongs to the set it happened on.
//

import SwiftUI
import DredfitCore

/// What each set of an exercise actually ran at, and how that collapses into
/// the one number the engine takes.
///
/// "Went differently" and a hold stopped early both speak about the set under
/// way, never about the exercise — but the flow used to keep one number per
/// pattern, so 10 entered on the third set of 3×15 was recorded as 10 for all
/// three. Two sets done exactly on plan then reached `applyFeedback` as a full
/// shortfall: level 7 → 2 instead of 7 → 5, and a `failStreak` tick toward a
/// deload nobody earned.
///
/// The engine's contract is untouched — one honest number per pattern per
/// session (spec §5) — so the collapse lives here: the mean per set, which is
/// the volume actually performed divided by the sets that carried it.
/// Pure arithmetic over values, so it is not the main actor's business — and
/// the journal decodes off it.
nonisolated enum SetFacts {
    /// Per-set values for each adjusted exercise, in set order.
    ///
    /// Shorter than the exercise's own `sets` while it is still being
    /// performed, and shorter for good afterwards when nothing more was said:
    /// the last value stands for every set after it, because a number entered
    /// mid-exercise carries forward to the sets that follow — it is what the
    /// screen then shows and what the hold then counts down.
    typealias PerSet = [Pattern: [Int]]

    // MARK: - The corridors

    /// The grid a reportable number is snapped to: one second for holds, one
    /// rep for reps.
    ///
    /// v2.21 (spec §32.6): holds used to snap to 5 s, matching the engine's
    /// old fixed rung. The ladder is relative now — a rung costs from 1 s to
    /// 4 s depending on where you stand — so a five-second grid can express
    /// only 13 of the scale's 48 rungs. An honest 3 s short of the plan then
    /// snapped a full grid cell away and cost five rungs instead of one. The
    /// corridor itself (5...90 s) does not move.
    static func step(for unit: LoadUnit) -> Int {
        switch unit {
        case .hold, .reps: return 1
        }
    }

    /// The corridor a reportable number lives in.
    static func corridor(for unit: LoadUnit) -> ClosedRange<Int> {
        unit == .hold ? 5...90 : 0...30
    }

    /// `value` snapped to the unit's grid and held inside its corridor. One
    /// definition for all three roundings — the manual adjuster, a hold
    /// stopped early, and the mean below — so the number shown is always a
    /// number that can be stored.
    static func snap(_ value: Double, unit: LoadUnit) -> Int {
        let corridor = self.corridor(for: unit)
        guard value.isFinite else { return corridor.lowerBound }
        let step = Double(self.step(for: unit))
        // Clamped while still a Double: `Int(_:)` traps on anything past its
        // range, and a snapshot off disk can carry any number at all.
        let stepped = (value / step).rounded() * step
        return Int(min(max(stepped, Double(corridor.lowerBound)),
                       Double(corridor.upperBound)))
    }

    /// The per-set shape as the app is willing to read it back off disk. The
    /// journal earns this on decode (spec §24.1); a workout snapshot carries
    /// no decoder of its own, so it is sanitized where it is read: values
    /// inside the range they can mean, arrays no longer than an exercise can
    /// be, and nothing left standing that holds no sets at all.
    static func sanitized(_ facts: PerSet) -> PerSet {
        facts.compactMapValues { values in
            let clean = values.prefix(EngineConfig.setsMax)
                .map { min(max($0, 0), EngineConfig.countMax) }
            return clean.isEmpty ? nil : Array(clean)
        }
    }

    // MARK: - Reading

    /// The number set `index` runs at: the last thing said about this
    /// exercise, or the plan when nothing was.
    ///
    /// v2.22 (spec §33): "the plan" is per set now — an uneven plan asks 9-8-8,
    /// and set one is not set three. Reading `ex.load` here would show the
    /// minimum on every set and quietly lose the sub-step.
    static func inForce(_ facts: PerSet, _ ex: SessionExercise, set index: Int) -> Int {
        guard let values = facts[ex.pattern], !values.isEmpty else {
            return ex.plannedLoad(set: index)
        }
        return values[min(max(index, 0), values.count - 1)]
    }

    /// Every set of the exercise, the ones already behind at what they ran at
    /// and the ones ahead at what is in force for them.
    ///
    /// The count is bounded by the scale, not by the record: `sets` comes
    /// back out of the journal unclamped, and this walk is on the main thread
    /// inside a row body — a hand-edited `Int.max` would allocate until the
    /// app is killed. No exercise ever had more sets than the scale has
    /// bands, so the valid domain never notices.
    static func allSets(_ facts: PerSet, _ ex: SessionExercise) -> [Int] {
        let sets = min(max(ex.sets, 1), EngineConfig.setsMax)
        return (0..<sets).map { inForce(facts, ex, set: $0) }
    }

    // MARK: - Writing

    /// Records `value` for the set under way and nothing else. The sets
    /// before it keep what they ran at — that is the whole point — and are
    /// filled in first when they were performed silently, on plan.
    ///
    /// Everything landing back on the plan is nothing said at all: the entry
    /// is dropped and the session rating governs the pattern again, exactly
    /// as correcting a single number back to the plan always did.
    ///
    /// v2.22 (spec §33): "back on the plan" is compared PER SET against
    /// `loads ?? [load × sets]`. Against the flat `load` an uneven plan
    /// performed exactly as written — 9-8-8 — would read as a shortfall on its
    /// first set and hand the engine a number nobody meant to report.
    static func recording(_ value: Int, in facts: PerSet,
                          _ ex: SessionExercise, set index: Int) -> PerSet {
        var facts = facts
        var values = facts[ex.pattern] ?? []
        let index = max(index, 0)
        while values.count < index {
            values.append(values.last ?? ex.plannedLoad(set: values.count))
        }
        values = Array(values.prefix(index)) + [value]
        let onPlan = values.enumerated().allSatisfy { $0.element == ex.plannedLoad(set: $0.offset) }
        facts[ex.pattern] = onPlan ? nil : values
        return facts
    }

    // MARK: - The collapse

    /// The single number `applyFeedback` receives for this exercise, or nil
    /// when every set ran to plan and the rating should govern.
    ///
    /// The mean, snapped to the unit's grid: 15 / 15 / 10 against a plan of
    /// 3×15 reports 13, and 39 / 39 / 30 against 3×39 s reports 36.
    ///
    /// A shortfall is never reported as MEETING the plan, however close the
    /// mean lands. To the engine `actual == load` is two statements at once:
    /// the "on plan" step (§18.1) and the explicit fact that confirms a pain
    /// episode has recovered (§21.2). A near miss rounded up onto the plan
    /// would make both claims on the strength of a session that fell short —
    /// promoting out of a freeze the athlete who missed a rep, while the one
    /// who hit every rep says nothing and never escapes it. So when the grid
    /// cannot hold the mean below the plan without over-penalising a near
    /// miss, this says nothing at all and the session rating speaks instead.
    static func override(_ facts: PerSet, for ex: SessionExercise) -> Int? {
        guard facts[ex.pattern]?.isEmpty == false else { return nil }
        let values = allSets(facts, ex)
        guard !values.isEmpty else { return nil }
        // Summed as Doubles: the values are sanitized, but this is the one
        // place their total is taken and an Int overflow would trap.
        let raw = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
        let reported = snap(raw, unit: ex.unit)
        if raw < Double(ex.load) && reported >= ex.load { return nil }
        return reported
    }

    /// The whole session's `overrides`, keyed the way the engine wants them.
    static func overrides(_ facts: PerSet, in exercises: [SessionExercise]) -> [Pattern: Int] {
        var result: [Pattern: Int] = [:]
        for ex in exercises where facts[ex.pattern] != nil {
            result[ex.pattern] = override(facts, for: ex)
        }
        return result
    }
}

// MARK: - How they read

/// The one place an exercise's facts are printed: the rating screen and the
/// history line. Sets that all ran the same say the number once; sets that
/// differed say themselves, because "actual 13" alone would hide that two of
/// three were exactly on plan — the very thing this whole shape exists to
/// keep. The mean is deliberately not shown: what the athlete did is the
/// evidence, and the number the engine folds it into is its own business.
///
/// The dots are for the eye and commas for the ear — the same list either
/// way, so nothing is said to one reader and withheld from the other.
struct SetFactsLabel: View {
    let values: [Int]
    /// The one number to print when the sets have nothing to tell apart.
    let reported: Int
    var size: CGFloat = 14

    private var varying: Bool {
        values.count > 1 && values.contains { $0 != values[0] }
    }

    var body: some View {
        Group {
            if varying {
                Text(verbatim: values.map(String.init).joined(separator: " · "))
                    .accessibilityLabel(
                        Text(verbatim: values.map(String.init).joined(separator: ", ")))
            } else {
                Text("actual \(reported)")
            }
        }
        .dredfitFont(size, weight: .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.accentText)
    }
}
