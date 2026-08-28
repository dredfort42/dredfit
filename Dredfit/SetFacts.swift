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
/// session — so the collapse lives here: the mean per set, which is the volume
/// actually performed divided by the sets that carried it. Pure arithmetic
/// over values, so it is not the main actor's business — and the journal
/// decodes off it.
nonisolated enum SetFacts {
    /// Per-set values for each adjusted exercise, in set order.
    ///
    /// Shorter than the exercise's own `sets` while it is still being
    /// performed, and shorter for good afterwards when nothing more was said:
    /// the last value stands for every set after it, because a number entered
    /// mid-exercise carries forward to the sets that follow — it is what the
    /// screen then shows and what the hold then counts down.
    typealias PerSet = [Pattern: [Int]]

    /// Sets SKIPPED during the session, per movement.
    ///
    /// A count, not a set of indices, and deliberately: what the engine is
    /// handed is how MANY sets went, because that is what `cut` measures.
    /// Which of the five it was is nobody's business once the workout is over
    /// — and a count is also what survives a snapshot without a shape of its
    /// own.
    ///
    /// It lives beside the per-set facts because it is the same kind of thing:
    /// what the set actually ran at, when the answer is "it did not".
    typealias Skips = [Pattern: Int]

    // MARK: - The corridors

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
        // One unit — one second, one rep. Holds used to snap to a 5 s grid,
        // matching the engine's old fixed rung. The ladder is relative now, so
        // a five-second cell could express 13 of the scale's 48 rungs, and an
        // honest 3 s short of the plan snapped a whole cell away and cost five
        // rungs instead of one. The corridor itself (5...90 s) does not move.
        let step = 1.0
        // Clamped while still a Double: `Int(_:)` traps on anything past its
        // range, and a snapshot off disk can carry any number at all.
        let stepped = (value / step).rounded() * step
        return Int(min(max(stepped, Double(corridor.lowerBound)),
                       Double(corridor.upperBound)))
    }

    /// The per-set shape as the app is willing to read it back off disk. The
    /// journal earns this on decode; a workout snapshot carries no decoder of
    /// its own, so it is sanitized where it is read: values inside the range
    /// they can mean, arrays no longer than an exercise can be, and nothing
    /// left standing that holds no sets at all.
    static func sanitized(_ facts: PerSet) -> PerSet {
        facts.compactMapValues { values in
            let clean = values.prefix(EngineConfig.setsMax)
                .map { min(max($0, 0), EngineConfig.countMax) }
            return clean.isEmpty ? nil : Array(clean)
        }
    }

    /// The same treatment for the skips, and for the same reason: they come
    /// back off disk. No movement can lose more sets than the scale has bands,
    /// and a count of none is not a fact about anything.
    static func sanitized(skips: Skips) -> Skips {
        skips.compactMapValues { count in
            let clean = min(max(count, 0), EngineConfig.setsMax)
            return clean > 0 ? clean : nil
        }
    }

    /// Whether `count` more skipped sets can be RECORDED as skipped sets at
    /// all — the one piece of arithmetic both escapes on the work screen read.
    ///
    /// A movement counts as trained only while the floor's worth of sets
    /// survives the skips. Below that there is nothing left to record: not a
    /// cut, because the axis has run out, and never a dose of 0 — that would
    /// cost a whole tier (eight levels at L24) for work of ordinary quality.
    /// The tap travels as an ordinary skipped exercise instead: the appearance
    /// is not spent and nothing moves.
    ///
    /// Counted on the PLAN IN FRONT OF THE PERSON, not on the state's own
    /// ceiling. The two agree wherever the band gate and the postcondition
    /// repair leave the plan alone; where they do not, what is on screen is
    /// what the tap is about.
    static func skipFits(_ count: Int, of sets: Int, alreadySkipped: Int) -> Bool {
        sets - alreadySkipped - count >= EngineConfig.setsFloor
    }

    // MARK: - Reading

    /// The number set `index` runs at: the last thing said about this
    /// exercise, or the plan when nothing was.
    ///
    /// "the plan" is per set now — an uneven plan asks 9-8-8, and set one is
    /// not set three. Reading `ex.load` here would show the minimum on every
    /// set and quietly lose the sub-step.
    ///
    /// THE CARRY-FORWARD IS ASYMMETRIC. A number BELOW the plan carries onto
    /// the sets ahead, as it always did — someone who managed six of eight is
    /// telling you about the exercise, not about one set of it. A number ABOVE
    /// the plan applies to its own set and stops there.
    ///
    /// The symmetric version raised the remaining sets silently: entering 12
    /// on the first set of 3×8 rewrote sets two and three to 12, up to +50 %,
    /// and the person had to argue with the screen twice — once to say what
    /// they did, once to put back what they never asked to change. Nothing
    /// about doing one good set says the next two will match it.
    static func inForce(_ facts: PerSet, _ ex: SessionExercise, set index: Int) -> Int {
        let index = max(index, 0)
        guard let values = facts[ex.pattern], !values.isEmpty else {
            return ex.plannedLoad(set: index)
        }
        if index < values.count { return values[index] }
        // Ahead of everything recorded: carry the last number DOWN only.
        let last = values[values.count - 1]
        let planned = ex.plannedLoad(set: index)
        return min(last, planned)
    }

    /// The number worth accenting on the work screen: what is in force for
    /// set `index` when that differs from the SET'S OWN plan, nil when the
    /// set is simply running to plan. Against the flat base dose the top set
    /// of an uneven plan showed an accented "actual" nobody entered — and an
    /// entered shortfall equal to the base showed nothing at all (UI-truth
    /// audit, 27.08.2026).
    static func offPlan(_ facts: PerSet, _ ex: SessionExercise, set index: Int) -> Int? {
        let value = inForce(facts, ex, set: index)
        return value == ex.plannedLoad(set: index) ? nil : value
    }

    /// Whether recorded sets differ from THIS plan, set for set. Compared
    /// against `plannedLoad`, never against the flat base: on an uneven plan
    /// 9-8-8 a recorded 8-8-8 is a shortfall the engine already acted on, and
    /// a guard on the base dose read it as "ran to plan" and hid the fact
    /// (UI-truth audit, 27.08.2026).
    static func differs(_ values: [Int], from ex: SessionExercise) -> Bool {
        values.enumerated().contains { $0.element != ex.plannedLoad(set: $0.offset) }
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
    /// "back on the plan" is compared PER SET against `loads ?? [load ×
    /// sets]`. Against the flat `load` an uneven plan performed exactly as
    /// written — 9-8-8 — would read as a shortfall on its first set and hand
    /// the engine a number nobody meant to report.
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

    /// How long ONE side of a per-side hold runs.
    ///
    /// Both sides of a set carry the same load, so the second runs for what
    /// the first actually ran rather than for what the plan asked (owner,
    /// 27.08.2026). Before this, a first side stopped at 20 s of a planned 30
    /// handed the second the full 30 — and the fact recorded for the set is
    /// the SMALLER of the two sides, so those ten seconds loaded one side
    /// harder and could not reach the number at all.
    ///
    /// Never longer than the plan: the only way a first side could report
    /// more would be a plan raised between the sides, and equal load means the
    /// second side follows the first, not the new plan.
    ///
    /// Floored at the hold corridor's own minimum, and that floor is not
    /// decoration: the mis-tap grace lets a first side end as short as three
    /// seconds, and a second side of three could neither be STORED (`snap`
    /// lifts anything under the corridor back to five) nor STOPPED (every tap
    /// inside three seconds reads as a mis-tap, so Stop would be a dead
    /// control for the whole run).
    ///
    /// It lives here and not in the view for the reason `didFullPlan` and
    /// `maximumOutOfOrder` do: a rule stated inside a SwiftUI view is a rule
    /// no gating test can reach — CI runs with `-skip-testing:DredfitUITests`.
    static func holdSideSeconds(planned: Int, firstSideHeld: Int?) -> Int {
        guard let firstSideHeld else { return planned }
        let floor = corridor(for: .hold).lowerBound
        return max(min(firstSideHeld, planned), min(floor, planned))
    }

    /// A maximum taken out of order: a number above the plan of THIS set, on
    /// a set that is not the last one.
    ///
    /// It lives here and not in the view's body for the reason `didFullPlan`
    /// does — a rule stated inside a SwiftUI view is a rule no test can
    /// reach, and that is how the audit of 27.08.2026 found rules that had
    /// quietly stopped being true.
    ///
    /// What the note built on this must NOT say is that the engine measures
    /// the last set more closely. It does not measure order at all: the fold
    /// is the MEAN, so 12-6-6 and 6-6-12 reach it as the same 8.00 and land
    /// the same next plan. What the advice is actually about is the total —
    /// a maximum early tends to cost the sets after it, and the whole
    /// exercise is what the fold is taken over.
    static func maximumOutOfOrder(_ value: Int, _ ex: SessionExercise, set index: Int) -> Bool {
        index < ex.sets - 1 && value > ex.plannedLoad(set: index)
    }

    /// The single number `applyFeedback` receives for this exercise, or nil
    /// when every set ran to plan and the rating should govern.
    ///
    /// The mean per set: 15 / 15 / 10 against a plan of 3×15 reports 13⅓, and
    /// 45 / 45 / 30 against 3×45 s reports 40. The snap to the grid is the
    /// engine's, not this one's — see the §41.3 paragraph below.
    ///
    /// A shortfall is never reported as MEETING the plan, however close the
    /// mean lands. To the engine `actual == load` is two statements at once:
    /// the "on plan" step and the explicit fact that confirms a pain episode
    /// has recovered. A near miss rounded up onto the plan would make both
    /// claims on the strength of a session that fell short — promoting out of
    /// a freeze the athlete who missed a rep, while the one who hit every rep
    /// says nothing and never escapes it. So when the grid cannot hold the
    /// mean below the plan without over-penalising a near miss, this says
    /// nothing at all and the session rating speaks instead.
    /// §41.3: the RAW mean goes to the engine — snapping to the grid happens
    /// there, where a dose is actually assigned. The fraction is the whole
    /// point: the mean of an uneven plan sits strictly between its base and
    /// its top, and it is that fraction which says whether the top set was
    /// taken. Doing [8,7,7] gives 7.33 and counts as the plan met; doing
    /// [7,7,7] gives 7.00 and does not. Rounded here, both became a seven and
    /// the engine had to substitute the plan's top into the journal instead —
    /// a dose that was in none of the sets, 2903 inflated cells out of 28880.
    static func override(_ facts: PerSet, for ex: SessionExercise) -> Double? {
        guard facts[ex.pattern]?.isEmpty == false else { return nil }
        let values = allSets(facts, ex)
        guard !values.isEmpty else { return nil }
        // Summed as Doubles: the values are sanitized, but this is the one
        // place their total is taken and an Int overflow would trap.
        let raw = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
        // The guard stays as it was: a mean genuinely below the plan's base
        // must not be lifted onto it by rounding, and reporting nothing is how
        // that is said — the pattern falls back to the session's rating.
        if raw < Double(ex.load) && snap(raw, unit: ex.unit) >= ex.load { return nil }
        return raw
    }

    /// The knowable half of §40.4's "the last answer was not «hard»", read
    /// at the moment the probe runs: the working sets are all behind by then,
    /// so a fold below the plan's mean is already the step down the engine
    /// will take — and a caption promising the new variation would be broken
    /// by numbers the person has themselves entered (UI-truth audit,
    /// 27.08.2026). The unnamed "tough" a rating may add later stays
    /// unknowable here, and no caption should guess at it.
    static func foldFallsShort(_ facts: PerSet, of ex: SessionExercise) -> Bool {
        guard let fold = override(facts, for: ex) else { return false }
        return fold < Double(ex.plannedVolume) / Double(max(ex.sets, 1))
    }

    /// What the PROBE set records when it ends: its own target, unless a
    /// number was entered by hand — that one is more precise than "as asked"
    /// and wins.
    ///
    /// §41.2, and it lives here rather than inline in the flow because it was
    /// the one policy in `completeSet` that no test could reach. Not new
    /// trust: an ordinary set records no number either, and "tapped Done"
    /// means "did the plan" everywhere else in the app, with the session's
    /// rating carrying the rest. The probe was the only place that opted out
    /// of that convention — a hold's probe was already recorded by its timer,
    /// while a probe in reps could only be resolved through the adjust panel.
    /// The audit of 26.08.2026 measured what the exception cost: EIGHT LADDERS
    /// OUT OF TEN frozen for anyone who only taps — 400 sessions, seven
    /// patterns still on variation 1.
    ///
    /// `isProbe` is a parameter and not the caller's `if`, deliberately: the
    /// half of this rule that says "and nothing else records itself" is the
    /// half a refactor is most likely to lose.
    static func recordingProbe(_ probes: [Pattern: Int], _ pattern: Pattern,
                               isProbe: Bool, target: Int) -> [Pattern: Int] {
        guard isProbe, probes[pattern] == nil else { return probes }
        var probes = probes
        probes[pattern] = target
        return probes
    }

    /// The whole session's `overrides`, keyed the way the engine wants them.
    static func overrides(_ facts: PerSet, in exercises: [SessionExercise]) -> [Pattern: Double] {
        var result: [Pattern: Double] = [:]
        for ex in exercises where facts[ex.pattern] != nil {
            result[ex.pattern] = override(facts, for: ex)
        }
        return result
    }

    /// "The whole plan, or more": nothing set aside, no set dropped, and every
    /// exercise reaching the volume it was asked for. What the rating screen
    /// asks before it offers "easy" — the one rating that claims MORE than the
    /// plan, and so the one the plan has to have been finished for.
    ///
    /// Measured as VOLUME per exercise rather than as the mean the engine
    /// folds to, because `plannedVolume` already carries the shape of an
    /// uneven plan: 9-8-8 performed as written passes, and 8-8-8 does not —
    /// the top set is part of the plan, and a mean would let it be traded
    /// against the two below it.
    ///
    /// It lives here and not in the view's body deliberately. A rule stated
    /// inside a SwiftUI view is a rule no test can reach, which is how the
    /// last audit found rules that had quietly stopped being true.
    ///
    /// A probe is outside this on purpose: it is one set of the NEXT
    /// variation, offered rather than asked for, and someone who declines it
    /// has still done every rep of the plan in front of them.
    static func didFullPlan(_ facts: PerSet, skips: Skips, skipped: Set<Pattern>,
                            in exercises: [SessionExercise]) -> Bool {
        guard skipped.isEmpty, skips.values.allSatisfy({ $0 <= 0 }) else { return false }
        return exercises.allSatisfy { ex in
            allSets(facts, ex).reduce(0, +) >= ex.plannedVolume
        }
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
