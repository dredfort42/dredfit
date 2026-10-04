//
//  A fact belongs to the set it happened on.
//

import SwiftUI
import DredfitCore

/// What each set of an exercise actually ran at, and how that collapses into
/// the one number the engine takes.
///
/// "Went differently" and a hold stopped early both speak about the set under
/// way, never about the exercise. One number per pattern would record 10
/// entered on the third set of 3×15 as 10 for all three, and two sets done
/// exactly on plan would reach `applyFeedback` as a full shortfall: the next
/// plan would start from 10 instead of 13 — the 13⅓ the three sets average,
/// snapped down to the grid.
///
/// The engine's contract is one honest number per pattern per session, so
/// the collapse lives here: the mean per set, which is the volume actually
/// performed divided by the sets that carried it. Pure arithmetic over
/// values, so it is not the main actor's business — and the journal decodes
/// off it.
nonisolated enum SetFacts {
    /// Per-set values for each adjusted exercise, in set order.
    ///
    /// Shorter than the exercise's own `sets` while it is still being
    /// performed, and shorter for good afterwards when nothing more was said:
    /// a set past the end reads `inForce` — the last value when it is below
    /// that set's plan, the plan otherwise — which is what the screen then
    /// shows and, unless a time was declared (`holdTarget`), what the hold
    /// then counts down.
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

    /// `value` snapped to the unit's grid and held inside its corridor. Every
    /// hold the clock records goes through it, so a recorded number is always
    /// one that can be stored — and so does the guard on the mean below.
    static func snap(_ value: Double, unit: LoadUnit) -> Int {
        let corridor = self.corridor(for: unit)
        guard value.isFinite else { return corridor.lowerBound }
        // One unit — one second, one rep: a five-second cell would snap an
        // honest 3 s short of the plan a whole cell away.
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
    /// drag the mean down into a descent for work of ordinary quality. The
    /// tap travels as an ordinary skipped exercise instead: the appearance is
    /// not spent and nothing moves.
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
    /// "the plan" is per set — an uneven plan asks 9-8-8, and set one is not
    /// set three. Reading `ex.load` here would show the minimum on every set
    /// and quietly lose the sub-step.
    ///
    /// THE CARRY-FORWARD IS ASYMMETRIC. A number BELOW the plan carries onto
    /// the sets ahead — someone who managed six of eight is telling you about
    /// the exercise, not about one set of it. A number ABOVE the plan applies
    /// to its own set and stops there.
    ///
    /// A symmetric carry would raise the remaining sets silently: entering 12
    /// on the first set of 3×8 would rewrite sets two and three to 12, up to
    /// +50 %, and the person would have to argue with the screen twice — once
    /// to say what they did, once to put back what they never asked to
    /// change. Nothing about doing one good set says the next two will match
    /// it.
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
    /// of an uneven plan would show an accented "actual" nobody entered — and
    /// an entered shortfall equal to the base would show nothing at all.
    static func offPlan(_ facts: PerSet, _ ex: SessionExercise, set index: Int) -> Int? {
        let value = inForce(facts, ex, set: index)
        return value == ex.plannedLoad(set: index) ? nil : value
    }

    /// Whether recorded sets differ from THIS plan, set for set. Compared
    /// against `plannedLoad`, never against the flat base: on an uneven plan
    /// 9-8-8 a recorded 8-8-8 is a shortfall the engine already acted on, and
    /// a guard on the base dose would read it as "ran to plan" and hide the
    /// fact.
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
    /// is dropped and the session rating governs the pattern again.
    ///
    /// "back on the plan" is compared PER SET against `loads ?? [load ×
    /// sets]`. Against the flat `load` an uneven plan performed exactly as
    /// written — 9-8-8 — would read as off the plan on its first set and hand
    /// the engine a number nobody meant to report.
    ///
    /// THE GAPS ARE FILLED AS THE SCREEN READ THEM — `inForce`, set for set —
    /// never with the last number carried forward. The two differ on an
    /// uneven plan: on 35-30-30 a hold recording its THIRD set with nothing
    /// said before it would fill set two with set ONE's 35, and a movement
    /// held exactly as asked would reach the summary and the journal as
    /// 35-35-30 — on every hold of every uneven plan, since the clock records
    /// every set. A plain carry would also fill a set after a surplus with
    /// the surplus, though the clock ran that set at the plan (`inForce`'s
    /// asymmetry).
    static func recording(_ value: Int, in facts: PerSet,
                          _ ex: SessionExercise, set index: Int) -> PerSet {
        var facts = facts
        var values = facts[ex.pattern] ?? []
        let index = max(index, 0)
        while values.count < index {
            let planned = ex.plannedLoad(set: values.count)
            values.append(min(values.last ?? planned, planned))
        }
        values = Array(values.prefix(index)) + [value]
        let onPlan = values.enumerated().allSatisfy { $0.element == ex.plannedLoad(set: $0.offset) }
        facts[ex.pattern] = onPlan ? nil : values
        return facts
    }

    /// Records ONE set and leaves every other set of the exercise standing.
    ///
    /// The writer of the exercise summary, where every set is already behind.
    /// `recording` above cannot do this and must not learn to: it writes THE
    /// SET UNDER WAY, and truncating what follows is exactly how a shortfall
    /// stops carrying a number nobody entered onto sets that have not
    /// happened. On the summary the sets after the one being corrected are
    /// facts, and the same truncation would delete them.
    ///
    /// Everything else is the rule `recording` follows. Every other set keeps
    /// what its card reads (`inForce`, set for set — never the flat base: an
    /// uneven plan asks 9-8-8), and a record that has landed back on the plan
    /// set for set is nothing said at all: the entry is dropped and the
    /// session rating governs the pattern again. That is what "put it back"
    /// does.
    ///
    /// Bounded by the exercise's own length, like `allSets` and for the same
    /// reason: `sets` comes back out of the journal unclamped, and the probe
    /// is not in here at all — it records to `probeActuals`, its own channel.
    static func recordingSet(_ value: Int, in facts: PerSet,
                             _ ex: SessionExercise, set index: Int) -> PerSet {
        var facts = facts
        let index = max(index, 0)
        let sets = min(max(ex.sets, 1), EngineConfig.setsMax)
        guard index < sets else { return facts }
        // The whole exercise is frozen AS THE SCREEN READS IT, and then one
        // value changes. `inForce` is what every card of the summary prints,
        // so filling with anything else would move a set nobody touched: a
        // record of [40] against a 3×45 s plan prints 40-40-40, and padding
        // with the plan would turn the two untouched cards into 45 the moment
        // set one was corrected. Where nothing has been said `inForce` IS the
        // plan, so the ordinary case reads exactly as it looks.
        var values = (0..<sets).map { inForce(facts, ex, set: $0) }
        values[index] = value
        let onPlan = values.enumerated().allSatisfy { $0.element == ex.plannedLoad(set: $0.offset) }
        facts[ex.pattern] = onPlan ? nil : values
        return facts
    }

    // MARK: - Correcting a hold on its summary

    /// The range a hold's recorded seconds may be corrected within on the
    /// movement's summary.
    ///
    /// ONLY THE LAST SET IS CORRECTED. It has nothing after it — no rest
    /// starts on its signal, and the person may have kept holding — so both
    /// directions stay open there, up to the corridor: the "Went differently"
    /// of the last hold, on its card. Every earlier set ended on its signal
    /// or under a thumb and stands as it ran: its range is the number itself,
    /// and its card opens no panel — one with both ends dead reads as a
    /// broken control.
    ///
    /// What is wanted next time is a different channel (`raisedSteps`): a
    /// number entered on a card is written down as HELD (`recordingSet`), so
    /// no card may invite the number the next plan should start from.
    ///
    /// `measured` is what the clock recorded for the set (`summaryMeasured`),
    /// or what the card shows when no clock ran for it. For a set ended by tap
    /// that is already the clock less the reach allowance, and the allowance
    /// is not handed back: it is a guess about a walk to the phone either way.
    static func correctionRange(measured: Int, isLastSet: Bool) -> ClosedRange<Int> {
        let corridor = corridor(for: .hold)
        guard !isLastSet else { return corridor }
        let fixed = min(max(measured, corridor.lowerBound), corridor.upperBound)
        return fixed...fixed
    }

    // MARK: - What a hold is worth when a thumb ends it

    /// Seconds taken off a hold that ended by TAP.
    ///
    /// The tap happens AFTER the effort has stopped: the person comes off the
    /// floor and reaches for the phone, and the timestamp of the thumb is not
    /// the timestamp of the last second held. A relative of
    /// `WorkoutSession.holdMistapSeconds`, which exists for the other half of
    /// the same fact — a tap is evidence about a hand, not about a plank.
    ///
    /// Three rather than a measurement: the honest direction is DOWN, because
    /// a number the athlete did not earn is the one the engine then plans
    /// from. Reading the lift of the phone off CoreMotion would be the real
    /// answer; nothing here reads it.
    static let holdReachSeconds = 3

    /// What a hold ended by tap records. Never below the corridor's own floor
    /// — five seconds is the least a hold can be STORED as — and never more
    /// than the thumb's own allowance below what the clock saw.
    static func holdEndedByTap(heldSeconds: Int) -> Int {
        max(corridor(for: .hold).lowerBound, heldSeconds - holdReachSeconds)
    }

    // MARK: - The set the run opens by itself

    /// Whether the hands-free run opens the set at `index` BY ITSELF.
    ///
    /// One question, two callers, because they have to agree: the rest's end
    /// starts that set, and the rest's screen offers a pause precisely because
    /// it will. A rest whose clock starts nothing needs no pause — nothing
    /// happens without the person — and a rest that does start something and
    /// offers no way to stop it is how a set goes by while somebody answers
    /// the door.
    ///
    /// `running` is the run's own flag: one tap bought THIS exercise, so the
    /// next movement is a decision of its own. The probe is excluded: it is
    /// one set of a movement nobody has done, possibly in another unit, and
    /// being dropped into a countdown for it is exactly the surprise a probe
    /// must never spring.
    static func runOpensSet(_ index: Int, of exercise: SessionExercise,
                            running: Bool) -> Bool {
        guard running, exercise.unit == .hold else { return false }
        let total = exercise.sets + (exercise.probe == nil ? 0 : 1)
        guard index >= 0, index < total else { return false }
        return !(exercise.probe != nil && index >= exercise.sets)
    }

    /// The last seconds of a rest are counted out loud, and this is how much
    /// of that the app is allowed to have missed before the go it played
    /// stops counting as heard. One second is the tick's own period; three is
    /// the 3-2-1 itself.
    static let restGoHeardWithinSec = 3.0

    /// Whether the set a rest hands over to still needs counting in.
    ///
    /// A rest that ran out under the person's eyes has already done it — its
    /// own 3-2-1 ends on the go that starts the hold, and a second window on
    /// top of that would announce the same start twice. Two cases still need
    /// the beat:
    ///
    /// - the rest was CUT SHORT BY A TAP. A tap is somebody saying "I am
    ///   ready", and the hold must not land under the thumb that said it.
    /// - the app was SUSPENDED across the end of the rest and comes back to
    ///   find it over. The go was played to a locked phone or to nobody at
    ///   all, and a signal nobody could hear cannot be what started a plank.
    static func restHandsOverWithCountIn(endedByTap: Bool, overshootSec: Double) -> Bool {
        endedByTap || overshootSec > restGoHeardWithinSec
    }

    // MARK: - The time a hold is set to run

    /// The seconds set `index` of a hold counts down from.
    ///
    /// Without a declaration this is `inForce`. With one, THE DECLARATION
    /// STANDS IN FOR THE PLAN: the athlete said before the effort how long
    /// they mean to hold, and that is what the clock is set to for every set
    /// of the exercise.
    ///
    /// It is not simply the declared number on every set, because a set that
    /// was cut short has already said something: the sets after it follow what
    /// was actually shown, capped by what was declared. That is the same
    /// asymmetry `inForce` applies against the plan — a shortfall carries
    /// forward, a surplus does not — with the declaration as the ceiling
    /// instead of the plan, and the same rule `holdSideSeconds` applies
    /// between the two sides of one set.
    ///
    /// A declaration BELOW the plan is allowed and means what it says. Doing
    /// less than planned is a decision the person is entitled to take, and it
    /// reaches the engine as the honest number it is.
    static func holdTarget(_ facts: PerSet, _ ex: SessionExercise,
                           set index: Int, declared: Int?) -> Int {
        guard let declared else { return inForce(facts, ex, set: index) }
        // Clamped where it is READ, like everything else that can come back
        // off disk: the declaration is carried in the workout snapshot.
        let ceiling = min(max(declared, corridor(for: .hold).lowerBound),
                          corridor(for: .hold).upperBound)
        let values = facts[ex.pattern] ?? []
        let index = max(index, 0)
        guard index > 0, !values.isEmpty else { return ceiling }
        return min(values[min(index, values.count) - 1], ceiling)
    }

    // MARK: - The collapse

    /// How long ONE side of a per-side hold runs.
    ///
    /// Both sides of a set carry the same load, so the second runs for what
    /// the first actually ran rather than for what the plan asked. Handed the
    /// full 30 after a first side stopped at 20 s of a planned 30, the second
    /// would carry ten seconds that load one side harder and cannot reach the
    /// number at all — the fact recorded for the set is the SMALLER of the
    /// two sides.
    ///
    /// Never longer than the plan: the only way a first side could report
    /// more would be a plan raised between the sides, and equal load means the
    /// second side follows the first, not the new plan.
    ///
    /// Floored at the hold corridor's own minimum, and that floor is not
    /// decoration: a second side of three seconds could neither be STORED
    /// (`snap` lifts anything under the corridor back to five) nor STOPPED
    /// (every tap inside three seconds reads as a mis-tap, so Stop would be a
    /// dead control for the whole run).
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
    /// reach, and such a rule can quietly stop being true.
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
    /// engine's, not this one's — see the last paragraph below.
    ///
    /// A shortfall is never reported as MEETING the plan, however close the
    /// mean lands: a session that fell short is no proof the plan was met.
    /// So when the grid cannot hold the mean below the plan without
    /// over-penalising a near miss, this says nothing at all and the session
    /// rating speaks instead.
    ///
    /// The RAW mean goes to the engine — snapping to the grid happens there,
    /// where a dose is actually assigned. The fraction is the whole point:
    /// the mean of an uneven plan sits strictly between its base and its top,
    /// and it is that fraction which says whether the top set was taken.
    /// Doing [8,7,7] gives 7.33 and counts as the plan met; doing [7,7,7]
    /// gives 7.00 and does not. Rounded here, both would be a seven, and the
    /// engine could no longer tell the two apart.
    static func override(_ facts: PerSet, for ex: SessionExercise) -> Double? {
        guard facts[ex.pattern]?.isEmpty == false else { return nil }
        let values = allSets(facts, ex)
        guard !values.isEmpty else { return nil }
        // Summed as Doubles: the values are sanitized, but this is the one
        // place their total is taken and an Int overflow would trap.
        let raw = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
        // The guard: a mean below the plan's base that would round onto it
        // reports nothing, and the pattern falls back to the session's
        // rating. The engine snaps a fact DOWN to its grid, so a near miss
        // would otherwise cost a whole rung (44⅔ s of 3×45 s lands on 40).
        if raw < Double(ex.load) && snap(raw, unit: ex.unit) >= ex.load { return nil }
        return raw
    }

    /// The knowable half of the probe's condition "the last answer was not
    /// «hard»", read at the moment the probe runs: the working sets are all
    /// behind by then, so a fold below the plan's mean is already the step
    /// down the engine will take — and a caption promising the new variation
    /// would be broken by numbers the person has themselves entered. The
    /// unnamed "tough" a rating may add later stays unknowable here, and no
    /// caption should guess at it.
    static func foldFallsShort(_ facts: PerSet, of ex: SessionExercise) -> Bool {
        guard let fold = override(facts, for: ex) else { return false }
        return fold < Double(ex.plannedVolume) / Double(max(ex.sets, 1))
    }

    /// What the PROBE set records when it ends: its own target, unless a
    /// number was entered by hand — that one is more precise than "as asked"
    /// and wins.
    ///
    /// It lives here rather than inline in `completeSet` so a test can reach
    /// it. Not new trust: an ordinary set records no number either, and
    /// "tapped Done" means "did the plan" everywhere else in the app, with
    /// the session's rating carrying the rest. A hold's probe is recorded by
    /// its timer; without this, a probe in reps could be resolved only
    /// through the adjust panel, and its ladder would stay frozen for anyone
    /// who only taps.
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
    /// inside a SwiftUI view is a rule no test can reach, and such a rule can
    /// quietly stop being true.
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

    // MARK: - Time the athlete was away

    /// Seconds to charge to an ABSENCE rather than to the workout, for one
    /// resume: everything past the moment the session stopped owing time.
    ///
    /// A rest running on schedule is training whether or not the process
    /// survived it. Measured from `savedAt` alone — the last phase transition,
    /// which for a rest is its START — a phone locked at the top of a 90 s
    /// rest and opened at its end would report a workout a minute and a half
    /// SHORTER than it was, the exact mirror of the inflation the away time
    /// exists to remove.
    ///
    /// The work screen carries no end date, so a kill inside a hold still
    /// charges the set to the absence. That is a known floor, not a claim:
    /// closing it needs the moment of leaving stamped on the snapshot, which
    /// nothing writes yet.
    ///
    /// Here rather than in the flow because it is arithmetic over three dates,
    /// and a rule stated inside a SwiftUI view is a rule no test can reach.
    static func awayGained(savedAt: Date, restEndDate: Date?, now: Date) -> Int {
        let owedUntil = max(savedAt, restEndDate ?? .distantPast)
        return max(0, Int(now.timeIntervalSince(owedUntil)))
    }

    /// An absence the PROCESS LIVED THROUGH: the flow sent to the background
    /// and brought back without dying. Charged by the same rule `restore`
    /// uses, from the moment of leaving — otherwise a phone locked overnight
    /// would send an eleven-hour workout to Health.
    /// The rest end is taken AS IT STOOD WHEN THE SCENE LEFT: on the way back
    /// the timer may tick first, and the tick that ends a rest clears its date.
    struct Absence {
        private var leftAt: Date?
        private var restEndDate: Date?

        /// A leaving is stamped and not spent yet.
        var isAway: Bool { leftAt != nil }

        /// The first leaving wins.
        mutating func leave(now: Date, restEndDate: Date?) {
            guard leftAt == nil else { return }
            leftAt = now
            self.restEndDate = restEndDate
        }

        /// Seconds to add to the away time (0 if nothing was stamped); spends
        /// the stamp.
        mutating func comeBack(now: Date) -> Int {
            guard let leftAt else { return 0 }
            let gained = SetFacts.awayGained(savedAt: leftAt, restEndDate: restEndDate, now: now)
            self = Absence()
            return gained
        }
    }

    // MARK: - An interrupted workout

    /// What an interruption amounts to: which movements were never trained,
    /// how many sets of the one in progress are missing, and which movement —
    /// if any — was left half-done.
    ///
    /// ONE place, because two callers describe the same interruption: the
    /// flow's "finish now" and the settlement of a workout that was trained
    /// and never rated. Two copies would let the same abandoned session reach
    /// the journal two different ways depending on whether the app happened
    /// to stay alive.
    struct Settlement: Equatable {
        /// Never reached. A skip to the engine: the ladder freezes.
        var skipped: Set<Pattern> = []
        /// Sets taken off a movement that WAS trained — its numbers stay.
        var setsSkipped: Skips = [:]
        /// Left half-done. Also a skip to the engine; "not finished" is the
        /// only difference, and it is a difference the athlete sees.
        var interrupted: Pattern?
    }

    /// - Parameters:
    ///   - exIndex: the exercise in front of the athlete when it stopped.
    ///   - setsBehind: sets of THAT exercise already over, skips included.
    ///   - currentIsDone: every set of it is behind — the rest that follows a
    ///     last set, the summary of a finished hold, or the rating screen.
    static func settlement(in exercises: [SessionExercise],
                           exIndex: Int,
                           setsBehind: Int,
                           currentIsDone: Bool,
                           alreadySkipped: Skips) -> Settlement {
        var out = Settlement(setsSkipped: alreadySkipped)
        // Clamped from below the way `restore(from:)` clamps a resume: both
        // numbers come off disk, and a negative index would trap here inside
        // `activate()` before the snapshot is cleared — so every launch after
        // it would trap too. Past the end is NOT clamped: it means all
        // behind. A negative count settles exactly like zero.
        let exIndex = max(exIndex, 0)
        let setsBehind = max(setsBehind, 0)
        guard exIndex < exercises.count else { return out }
        var firstUnfinished = exIndex
        if currentIsDone {
            firstUnfinished = exIndex + 1
        } else {
            let ex = exercises[exIndex]
            let already = alreadySkipped[ex.pattern] ?? 0
            let left = max(0, ex.sets - setsBehind)
            let performed = setsBehind - already
            // Enough of the movement is behind to leave a trained one: keep
            // its numbers and let the remainder travel as skipped SETS, the
            // same statement an in-workout skip makes. Otherwise there is no
            // movement to keep, and it is named as unfinished instead.
            if performed >= EngineConfig.setsFloor,
               skipFits(left, of: ex.sets, alreadySkipped: already) {
                if left > 0 { out.setsSkipped[ex.pattern, default: 0] += left }
                firstUnfinished = exIndex + 1
            } else if setsBehind > 0 {
                out.interrupted = ex.pattern
            }
        }
        for ex in exercises[min(firstUnfinished, exercises.count)...] {
            out.skipped.insert(ex.pattern)
            // A skip wins over a partial count: the movement was not trained.
            out.setsSkipped.removeValue(forKey: ex.pattern)
        }
        return out
    }
}

// MARK: - How they read

/// An exercise's facts as the rating screen prints them (the history line
/// has its own spelling, `HistorySheet.factLine`). Sets that all ran the same
/// say the number once; sets that differed say themselves, because "actual
/// 13" alone would hide that two of three were exactly on plan — the very
/// thing this whole shape exists to keep. The mean is deliberately not shown:
/// what the athlete did is the evidence, and the number the engine folds it
/// into is its own business.
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

    /// The list as set, and as spoken — the comma is what VoiceOver pauses on.
    private var printed: String { values.map(String.init).joined(separator: " · ") }
    private var spoken: String { values.map(String.init).joined(separator: ", ") }

    var body: some View {
        Group {
            // Both branches carry the word: a bare list of numbers does not
            // say that it is the fact rather than a plan.
            if varying {
                Text("actual \(printed)")
                    .accessibilityLabel(Text("actual \(spoken)"))
            } else {
                Text("actual \(reported)")
            }
        }
        .dredfitFont(size, weight: .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.accentText)
    }
}
