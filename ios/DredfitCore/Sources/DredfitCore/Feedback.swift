//
//  What one rating does to the state.
//
//  Kept apart from Engine.swift: together the two would exceed the lint's
//  file-length warning.
//

import Foundation

extension Engine {

    /// The result of deciding one exercise. `wantedDown` records the INTENT to
    /// descend rather than the movement of the plan: "hard" does not always
    /// change what the next plan shows, and the streak toward the deload and
    /// the probe's "not hard" condition count the answer, not its effect.
    private struct Step {
        var position: Position
        var wantedDown: Bool
        /// Fast adaptation: the dose is what the person did. The one rise the
        /// weekly ceiling leaves alone.
        var adapted = false
    }

    /// The weekly window, aged by the gap.
    private struct WeekWindow {
        let haveGap: Bool
        let gain: [Pattern: Int]
        let ageDays: Double
    }

    /*
     * result:    less | plan | more        — one rating per session
     * overrides: [pattern: actual]         — point facts about the WORKING sets
     *                                        (folded by the mean)
     * skipped:   {pattern, …}              — exercises not done at all
     * gapDays:   number or nil             — days since the last workout
     * probes:    [pattern: actual]         — the number from the PROBE SET
     *
     * `probes` is the SEVENTH parameter, and it is seventh deliberately:
     * `gapDays` stays sixth, so every caller written before v3 keeps passing
     * the gap where it always passed it. The "an argument moved one place"
     * trap fired twice in this engine, silently both times. And the probe is
     * its own channel rather than one more number in `overrides`: it is a
     * different exercise, and mixing it into the fold of the working sets
     * would average two different variations.
     */
    public static func applyFeedback(
        state dirty: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides dirtyOverrides: [Pattern: Double] = [:],
        skipped: Set<Pattern> = [],
        gapDays: Double? = nil,
        probes dirtyProbes: [Pattern: Int] = [:]) -> EngineState {
        let state = dirty.sanitized()
        let overrides = dirtyOverrides.mapValues(sanitizeActual)
        let probes = dirtyProbes.mapValues { Engine.sanitizeProbe($0) }
        // A no-op on a stale pair, exactly as the reference: feedback is valid
        // only for a session generated from THIS state.
        guard session.sessionNumber == state.counter + 1 else { return dirty }

        var entryPos: [Pattern: Position] = [:]
        for p in Pattern.allCases { entryPos[p] = state.position(p) }
        let window = rollWeeklyWindow(state, gapDays: gapDays)

        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0                          // a session breaks the series
        next.rampWindow = max(0, state.rampWindow - 1)
        next.weekGain = window.gain
        next.weekAgeDays = window.ageDays

        let named = namedMovements(session: session, overrides: overrides)
        let unnamedLess = result == .less && named.isEmpty
        let chronic = rollChronicWindow(&next, session: session, unnamedLess: unnamedLess,
                                        splitPullSlot: state.hasBar)
        let targeted = lessTargets(LessAim(
            entryPos: entryPos, session: session, result: result, named: named,
            overrides: overrides, skipped: skipped, chronic: chronic,
            prevLessRun: state.lessRun, hist: next.lessHist))
        // A named "less" does not feed the run: "it was hard, and it was this
        // one" is a statement about one movement, not about the plan.
        next.lessRun = unnamedLess ? state.lessRun + 1 : 0

        // Patterns that adapted fast by their numbers — the one rise the weekly
        // ceiling below leaves alone. Keyed on what the loop did, not on a
        // number being there: a number for a movement outside the session is
        // discarded, and must not lift the ceiling off the credit that
        // movement receives.
        var adapted: Set<Pattern> = []
        for ex in session.exercises where !skipped.contains(ex.pattern) {
            if advance(&next, ex: ex, old: entryPos[ex.pattern]!, state: state,
                       result: result, overrides: overrides, probes: probes,
                       targeted: targeted, chronic: chronic, rampLeft: state.rampWindow) {
                adapted.insert(ex.pattern)
            }
        }

        crossCredit(&next, session: session, result: result,
                    overrides: overrides, entryPos: entryPos)
        // Remember what the person SAW and at what position — the position is
        // the ENTRY one, because the plan was shown before the feedback.
        // An exercise with a probe writes its memory too, with the set the
        // probe OCCUPIED counted in — see `shownWorkOf` for why the base has to
        // be about slots, not reps.
        for ex in session.exercises {
            next.shownWork[ex.pattern] = shownWorkOf(ex)
            next.shownOrd[ex.pattern] = posOrd(ex.pattern, entryPos[ex.pattern]!)
        }
        if window.haveGap {
            applyWeeklyCap(&next, entryPos: entryPos, adapted: adapted)
        }
        return next
    }

    // MARK: - One exercise

    // One exercise of the session. Answers whether it adapted fast by its
    // number — the one rise the weekly ceiling leaves alone.
    // swiftlint:disable:next function_parameter_count
    private static func advance(_ next: inout EngineState, ex: SessionExercise,
                                old: Position, state: EngineState, result: FeedbackResult,
                                overrides: [Pattern: Double], probes: [Pattern: Int],
                                targeted: Set<Pattern>?, chronic: [Pattern],
                                rampLeft: Int) -> Bool {
        let p = ex.pattern
        let unit = Library.unit(p, old.variation)
        let g = Dose.grid(unit)
        // While the hold ticks, growth goes into the DOSE — and under a cut
        // it can land on a set the cut hides and be lost (see `riseBy`).
        let setsBackOk = (next.setsHold[p] ?? 0) == 0
        let cap = EngineConfig.maxUp(pattern: p, variation: old.variation)
        // The MAXIMUM dose per set in the plan that was shown — what a tap
        // journals: on 9-8-8 the person showed a nine. Journalling the BASE
        // would let the plan outrun the journal at every rung boundary: two
        // growth events off 8-7-7 give 3×8 while the journal would hold 7.
        let planTop = ex.load
            + ((ex.loads?.contains { $0 > ex.load } ?? false) ? g.step : 0)
        // The plan's MEAN — what a trainee shows by doing it set for set.
        // With it, "the plan was met" becomes a threshold reachable on any shape
        // of plan: on a uniform one the mean equals the dose, on an uneven one it
        // lands exactly where an honest fold of the fact lands. A threshold at the
        // top would be unreachable; a threshold at the base credits people who
        // never took the top set.
        let planMean: Double = {
            guard let loads = ex.loads, !loads.isEmpty else { return Double(ex.load) }
            return Double(loads.reduce(0, +)) / Double(loads.count)
        }()

        var step: Step
        // The fraction judges; the grid-snapped integer assigns. There is
        // deliberately NO clamp here: a dose outside [min,max] is legal as an
        // INPUT and its rung has to be allowed to go negative — clipping it at
        // the edge is exactly what broke monotonicity of the fact-based rating
        // (#139), and the "fact below the variation floor" branch
        // stands on it.
        let actualRaw = overrides[p]
        let actual = actualRaw.map { Dose.snapToInt(unit, $0) }
        // "the plan was met" is a WINDOW one rung wide — one rep, five seconds
        // (#139) — from the plan's MEAN (`planMean`), not its base or its top.
        // The raw mean of the facts is fractional, so on reps it is a window
        // too: [8,7,7] on 7-7-7 is 7.33 and meets the plan.
        let metPlan = actualRaw.map { $0 >= planMean && $0 < planMean + Double(g.step) } ?? false
        if let actual {
            step = stepFromFact(p, ex: ex, actual: actual, metPlan: metPlan, old: old,
                                cap: cap, setsBackOk: setsBackOk, shown: state.shown)
        } else {
            step = stepFromRating(p, old: old, result: result, targeted: targeted,
                                  chronic: chronic, cap: cap, rampLeft: rampLeft,
                                  setsBackOk: setsBackOk, shown: state.shown)
        }

        // The journal is written for a COMPLETED appearance. An exercise with a
        // probe writes no journal for the OLD variation — see below.
        if ex.probe == nil {
            setShown(&next, p, old.variation,
                     journalEntry(actualRaw, metPlan: metPlan, planTop: planTop, unit: unit))
        } else {
            resolveProbe(&next, ex: ex, step: &step, probes: probes)
        }

        if step.wantedDown {
            next.failStreak[p] = (next.failStreak[p] ?? 0) + 1
            if next.failStreak[p]! >= EngineConfig.failsToDeload {
                step.position = fallDoses(p, step.position, EngineConfig.deloadDrop,
                                          shown: state.shown)
                next.failStreak[p] = 0
            }
        } else {
            next.failStreak[p] = 0
        }
        // The input to the probe condition. It outlives a deload on
        // purpose — the deload zeroes the streak, but does not unsay "hard".
        if step.wantedDown { next.lastHard.insert(p) } else { next.lastHard.remove(p) }

        let fitted = fit(p, step.position)
        if setsCameBack(from: old, to: fitted) {
            next.setsHold[p] = EngineConfig.setsBackHold
        } else {
            let held = (next.setsHold[p] ?? 0) - 1
            next.setsHold[p] = held > 0 ? held : nil
        }
        setPosition(&next, p, fitted)
        return step.adapted
    }

    /// What a completed appearance writes into the journal of its variation.
    ///
    /// A tap journals the plan's top: it asserts the whole plan was done, top
    /// set included. A number journals its FOLD — except INSIDE the "plan met"
    /// window, where it journals the best set the numbers prove. The fold
    /// there is the plan's base: at a rung boundary the judge says "the top
    /// was taken" while such a journal says it was not — 10-8-8 on 9-9-8 plans
    /// 3×9 over a journal of 8, the probe comes an appearance after a tap's and
    /// the cross-credit stalls. Sets are whole reps or seconds, so the best
    /// one is at least the mean rounded up; that, snapped down to the grid and
    /// never above the plan's top. On reps a met number always proves the top,
    /// so a logger and a tapper leave one journal. On holds the 5 s grid does
    /// not always let it, and the fold stays: the top taken on trust would
    /// offer a 44 s holder a probe their own working sets then throw out as
    /// "hard". Storage snaps to the grid, so the journal stays integer; the
    /// fraction only ever judges.
    private static func journalEntry(_ actualRaw: Double?, metPlan: Bool, planTop: Int,
                                     unit: LoadUnit) -> Int {
        guard let raw = actualRaw else { return planTop }
        guard metPlan else { return Dose.snapToInt(unit, raw) }
        return min(planTop, Dose.snapToInt(unit, raw.rounded(.up)))
    }

    // swiftlint:disable:next function_parameter_count
    private static func stepFromFact(_ p: Pattern, ex: SessionExercise, actual: Int,
                                     metPlan: Bool, old: Position, cap: Int,
                                     setsBackOk: Bool,
                                     shown: [Pattern: [Int: Int]]) -> Step {
        let g = Dose.grid(Library.unit(p, old.variation))
        if metPlan {
            return Step(position: riseBy(p, old, min(EngineConfig.deltaPlan, cap),
                                         allowSetsBack: setsBackOk), wantedDown: false)
        }
        if actual >= ex.load + g.step {
            // FAST ADAPTATION. The mean of the sets is a rung or more above
            // the plan's base and past the "met" window, so the dose becomes
            // that mean on the grid (no higher than the variation's ceiling),
            // sub-step cleared — unless a probe in the same appearance moves
            // the position instead.
            // `maxUp` does not apply: the cap bounds growth the engine ASSIGNS,
            // and here the dose is what the person just did on their own. It is
            // the way back to a person's own level after a clean start with no
            // per-session cap: a rating climbs at most `maxUp` growth events,
            // the raise handle at most `raiseStepsMax` steps of its own. A
            // variation can never be jumped by facts — only by a probe.
            var pos = old
            pos.dose = min(g.max, actual)
            pos.sub = 0
            return Step(position: fit(p, pos), wantedDown: false, adapted: true)
        }
        if actual < g.min {
            // A fact below the floor of the variation: a variation down,
            // landing under its journal.
            let pos = old.variation > 1
                ? landInVar(p, old.variation - 1, shown: shown, from: old)
                : fit(p, Position(variation: old.variation, sets: old.sets,
                                  dose: g.min, sub: 0, cut: old.cut))
            return Step(position: pos, wantedDown: true)
        }
        // Below the plan but inside the variation: the next showing equals the
        // fact. The cut and the band are kept — the person spoke about the
        // dose, not about the volume.
        var pos = old
        pos.dose = actual
        pos.sub = 0
        return Step(position: fit(p, pos), wantedDown: true)
    }

    // swiftlint:disable:next function_parameter_count
    private static func stepFromRating(_ p: Pattern, old: Position, result: FeedbackResult,
                                       targeted: Set<Pattern>?, chronic: [Pattern],
                                       cap: Int, rampLeft: Int, setsBackOk: Bool,
                                       shown: [Pattern: [Int: Int]]) -> Step {
        // While the window a comeback opened is open, "more" is credited as
        // "plan" — tissue does not recover along with the number. It does not
        // block the way down: honesty is never overridden.
        let capped = rampLeft > 0 && result == .more ? FeedbackResult.plan : result
        let delta: Int
        if let targeted {
            delta = targeted.contains(p)
                ? (chronic.contains(p) ? EngineConfig.chronicStep : EngineConfig.deltaLess)
                : 0
        } else {
            delta = capped.delta
        }
        let rampCap = rampLeft > 0 ? min(cap, EngineConfig.deltaPlan) : cap
        if delta > 0 {
            return Step(position: riseBy(p, old, min(delta, rampCap), allowSetsBack: setsBackOk),
                        wantedDown: false)
        }
        if delta < 0 {
            return Step(position: fallBy(p, old, -delta, shown: shown), wantedDown: true)
        }
        return Step(position: old, wantedDown: false)
    }

    /// The outcomes of a probe. "Hard" on this movement is ordinary
    /// "hard" handling and the probe of this session does not count; a skipped
    /// set or a single tap leaves it unresolved and it comes back next time.
    /// A failed or unresolved probe changes no field but the journal of
    /// facts.
    private static func resolveProbe(_ next: inout EngineState, ex: SessionExercise,
                                     step: inout Step, probes: [Pattern: Int]) {
        guard let probe = ex.probe, !step.wantedDown,
              let raw = probes[ex.pattern] else { return }
        let got = Dose.snap(probe.unit, raw)
        setShown(&next, ex.pattern, probe.variation, got)
        guard got >= Dose.grid(probe.unit).min else { return }
        // ENTRY IS ALWAYS 3×4 (3×15 s). The first working session of a new
        // variation is heavier than the probe — a known gap, insured by the
        // honest-numbers channel.
        step.position = Position(variation: probe.variation, sets: EngineConfig.setsBase,
                                 dose: Dose.grid(probe.unit).min, sub: 0, cut: 0)
    }

    // MARK: - The session-wide "less" (#91)

    /// Who a point fact NAMED: a number below the plan is the trainee already
    /// pointing at the movement, and the other five have nothing to lose.
    private static func namedMovements(session: Session,
                                       overrides: [Pattern: Double]) -> Set<Pattern> {
        var named: Set<Pattern> = []
        for ex in session.exercises {
            guard let raw = overrides[ex.pattern] else { continue }
            if Dose.snapToInt(ex.unit, raw) < ex.load { named.insert(ex.pattern) }
        }
        return named
    }

    /// The window of appearances (#137). Every exercise of the session
    /// shifts its own mask: 1 when the session was rated an unnamed "less".
    /// Returns the patterns the chronic signal fires for, IN SESSION ORDER —
    /// a Swift `Set` has none, and the reference's object literal does.
    private static func rollChronicWindow(_ next: inout EngineState, session: Session,
                                          unnamedLess: Bool,
                                          splitPullSlot: Bool) -> [Pattern] {
        for ex in session.exercises {
            let shifted = (((next.lessHist[ex.pattern] ?? 0) << 1) | (unnamedLess ? 1 : 0))
                & EngineState.chronicMaskMax
            next.lessHist[ex.pattern] = shifted > 0 ? shifted : nil
        }
        return session.exercises.map(\.pattern)
            .filter { !(splitPullSlot && Pattern.pullSide.contains($0)) }
            .filter { next.chronicFires($0) }
    }

    /// Everything the aim of a session-wide "less" is decided from. A struct
    /// rather than nine parameters: nine is past what the lint allows and past
    /// what a reader can hold, and every field here is read by the same one
    /// decision.
    private struct LessAim {
        let entryPos: [Pattern: Position]
        let session: Session
        let result: FeedbackResult
        let named: Set<Pattern>
        let overrides: [Pattern: Double]
        let skipped: Set<Pattern>
        let chronic: [Pattern]
        let prevLessRun: Int
        let hist: [Pattern: Int]

        func eligible(_ p: Pattern) -> Bool { !skipped.contains(p) && overrides[p] == nil }
    }

    /// Who receives the session-wide "less". `nil` means "everyone", which is
    /// what a run of unnamed ratings earns: it is a statement about the plan.
    private static func lessTargets(_ aim: LessAim) -> Set<Pattern>? {
        guard aim.result == .less,
              aim.prevLessRun < EngineConfig.lessRunToGlobal else { return nil }
        if !aim.named.isEmpty { return aim.named }
        func advance(_ p: Pattern) -> Int { posOrd(p, aim.entryPos[p]!) }
        // The culprit is whoever fails their OWN appearances more often: a weak
        // link fails every appearance of its own, a healthy pattern only the
        // ones it shared with the link. On an equal share — the one further
        // along its ladder.
        var best: Pattern?
        var bestHits = -1
        var bestAdvance = -1
        for p in aim.chronic where aim.eligible(p) {
            let hits = (aim.hist[p] ?? 0).nonzeroBitCount
            let adv = advance(p)
            if hits > bestHits || (hits == bestHits && adv > bestAdvance) {
                bestHits = hits
                bestAdvance = adv
                best = p
            }
        }
        if let best { return [best] }
        // An unnamed "less" hits ONE movement — the session's most advanced.
        var target: Pattern?
        var targetAdvance = -1
        for ex in aim.session.exercises where aim.eligible(ex.pattern) {
            let adv = advance(ex.pattern)
            if adv > targetAdvance {
                targetAdvance = adv
                target = ex.pattern
            }
        }
        return target.map { [$0] } ?? []
    }

    // MARK: - Cross-credit and the weekly cap

    /// (#90) The pull slot stands in every session, but with a bar its
    /// accounting splits into two branches, each growing half as fast as the
    /// slot. The applied gain is repeated to the other branch, bounded by ITS
    /// OWN growth cell and BY ITS OWN JOURNAL: repeated unbounded, someone
    /// else's gain would lift that branch's base dose past anything the person
    /// has shown in it. The gain is the trained branch's BEFORE its weekly
    /// ceiling: the ceiling runs once, after the credit, and trims each branch
    /// by its own budget.
    private static func crossCredit(_ next: inout EngineState, session: Session,
                                    result: FeedbackResult, overrides: [Pattern: Double],
                                    entryPos: [Pattern: Position]) {
        guard next.hasBar,
              let trainedEx = session.exercises.first(where: { Pattern.pullSide.contains($0.pattern) })
        else { return }
        let trained = trainedEx.pattern
        let other: Pattern = trained == .pull ? .pullBar : .pull
        // (#141) The mark is set by a "less" for the WHOLE session, named or
        // not, and by an override for this branch below its base dose. Telling "the branch really is hard" from "that is how the
        // rhythm fell" is impossible from the inside, and the cost of the
        // error is asymmetric.
        let strained = result == .less
            || overrides[trained].map { Dose.snapToInt(trainedEx.unit, $0) < trainedEx.load } ?? false
        if strained { next.creditPaused.insert(trained) } else { next.creditPaused.remove(trained) }

        let gained = max(0, posOrd(trained, next.position(trained))
                         - posOrd(trained, entryPos[trained]!))
        guard gained > 0, !next.creditPaused.contains(other) else { return }
        let q = next.position(other)
        let pos = riseWithinJournal(
            other, q, min(gained, EngineConfig.maxUp(pattern: other, variation: q.variation)),
            allowSetsBack: (next.setsHold[other] ?? 0) == 0, shown: next.shown)
        setPosition(&next, other, pos)
        // A set the credit returns arms the branch's hold, as its own return
        // does: without it the branch's next appearance returned a second set at
        // once — two volume jumps in a row against the hold's spacing.
        if setsCameBack(from: q, to: pos) { next.setsHold[other] = EngineConfig.setsBackHold }
    }

    private static func rollWeeklyWindow(_ state: EngineState, gapDays: Double?) -> WeekWindow {
        guard let gap = gapDays, gap.isFinite else {
            return WeekWindow(haveGap: false, gain: [:], ageDays: 0)
        }
        let aged = state.weekAgeDays + max(EngineConfig.minSessionAgeDays, gap)
        guard aged < Double(EngineConfig.weeklyWindowDays) else {
            return WeekWindow(haveGap: true, gain: [:], ageDays: 0)
        }
        return WeekWindow(haveGap: true, gain: state.weekGain, ageDays: aged)
    }

    /// (#129) The weekly ceiling is applied ONCE, after every
    /// rise of this session — the cross-credit included, which would otherwise
    /// walk around the budget.
    ///
    /// Fast adaptation by facts is the one rise NOT subject to it: there the
    /// dose equals what was shown rather than what was assigned, and trimming
    /// it would be telling the person they did not do what they did. A number
    /// that merely met the plan is subject to it: its +1 is the engine's, as a
    /// tap's is, and exempting it let a daily logger outgrow the window on the
    /// slow tissues by half again.
    ///
    /// A RESOLVED PROBE is left alone too — the person showed the new
    /// variation themselves — and rebuilding through `riseBy` would
    /// additionally DESTROY the transition, since growth never crosses a
    /// variation and the position would snap back to the old ceiling.
    ///
    /// A set return the ceiling undoes arms no hold. The main loop has armed
    /// it in full; left so, with the set still off, the next two appearances
    /// would run under a hold with a cut — the corner where a growth event can
    /// be lost — though no set came back at all. Without the return the
    /// appearance would have left the hold empty: a return needs an expired
    /// one. A set the cross-credit returned arms a hold too, and goes the same
    /// way.
    ///
    /// The window charges what the rebuild REALISED, not what it granted: a
    /// granted event can land on a set the cut hides and be lost, and it was
    /// charged all the same.
    private static func applyWeeklyCap(_ next: inout EngineState,
                                       entryPos: [Pattern: Position],
                                       adapted: Set<Pattern>) {
        for p in Pattern.allCases {
            if adapted.contains(p) { continue }
            let entry = entryPos[p]!
            if next.vars[p] != entry.variation { continue }
            let rise = max(0, posOrd(p, next.position(p)) - posOrd(p, entry))
            if rise <= 0 { continue }
            let budget = EngineConfig.isSlowTissue(p) || Pattern.pullSide.contains(p)
                ? EngineConfig.weeklyRiseSlow : EngineConfig.weeklyRiseFast
            let spent = next.weekGain[p] ?? 0
            let granted = min(rise, max(0, budget - spent))
            // The rebuild does not decide again whether to give a set back —
            // it only trims the steps, repeating the main loop's decision.
            let returned = (next.cut[p] ?? 0) < entry.cut
            let rebuilt = riseBy(p, entry, granted, allowSetsBack: returned)
            setPosition(&next, p, rebuilt)
            if returned, rebuilt.cut >= entry.cut { next.setsHold[p] = nil }
            let realised = max(0, posOrd(p, rebuilt) - posOrd(p, entry))
            if realised > 0 { next.weekGain[p] = spent + realised }
        }
    }
}
