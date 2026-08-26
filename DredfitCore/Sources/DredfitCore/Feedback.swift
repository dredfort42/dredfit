//
//  What one rating does to the state (§40.3, §40.4).
//
//  Split out of Engine.swift: with `L` gone the arithmetic got smaller, but
//  the feedback path did not, and both files sit against the lint's ceilings.
//

import Foundation

extension Engine {

    /// The result of deciding one exercise. `wantedDown` records the INTENT to
    /// descend rather than the movement of the plan: on the floor of a
    /// variation "hard" moves nothing, and without this the tap would become
    /// inert — the streak would never build and the deload would be
    /// unreachable (v2.23 §34.2).
    private struct Step {
        var position: Position
        var wantedDown: Bool
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
     *                                        (folded by the mean, §37.8)
     * skipped:   {pattern, …}              — exercises not done at all (v2.1.1)
     * gapDays:   number or nil             — days since the last workout
     * probes:    [pattern: actual]         — the number from the PROBE SET (§40.4)
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
        // A no-op on a stale pair, exactly as the reference (И6): feedback is
        // valid only for a session generated from THIS state.
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
        // one" is a statement about one movement, not about the plan (§19.2).
        next.lessRun = unnamedLess ? state.lessRun + 1 : 0

        for ex in session.exercises where !skipped.contains(ex.pattern) {
            advance(&next, ex: ex, old: entryPos[ex.pattern]!, state: state,
                    result: result, overrides: overrides, probes: probes,
                    targeted: targeted, chronic: chronic, rampLeft: state.rampWindow)
        }

        crossCredit(&next, session: session, result: result,
                    overrides: overrides, entryPos: entryPos)
        // Remember what the person SAW and at what position — the position is
        // the ENTRY one, because the plan was shown before the feedback.
        for ex in session.exercises where ex.probe == nil {
            next.shownWork[ex.pattern] = exerciseWork(ex)
            next.shownOrd[ex.pattern] = posOrd(ex.pattern, entryPos[ex.pattern]!)
        }
        if window.haveGap {
            applyWeeklyCap(&next, entryPos: entryPos, overrides: overrides)
        }
        return next
    }

    // MARK: - One exercise

    // swiftlint:disable:next function_parameter_count
    private static func advance(_ next: inout EngineState, ex: SessionExercise,
                                old: Position, state: EngineState, result: FeedbackResult,
                                overrides: [Pattern: Double], probes: [Pattern: Int],
                                targeted: Set<Pattern>?, chronic: [Pattern],
                                rampLeft: Int) {
        let p = ex.pattern
        let unit = Library.unit(p, old.variation)
        let g = Dose.grid(unit)
        // While the hold ticks, growth goes into the DOSE (v2.25, round 6).
        let setsBackOk = (next.setsHold[p] ?? 0) == 0
        let cap = EngineConfig.maxUp(pattern: p, variation: old.variation)
        // The MAXIMUM dose per set in the plan that was shown. On an uneven
        // plan 9-8-8 the person showed a nine, and the next step — "shown + 1
        // rep in one set" — counts from that nine. Counting from the BASE
        // broke И2 on the boundary of every rung: three growth events off a
        // plan of 8-7-7 give 3×8 while the journal would hold 7.
        let planTop = ex.load
            + ((ex.loads?.contains { $0 > ex.load } ?? false) ? g.step : 0)
        // §41.3: the plan's MEAN — what a trainee shows by doing it set for set.
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
        // (#139), and the "fact below the variation floor" branch (§40.3)
        // stands on it.
        let actualRaw = overrides[p]
        let actual = actualRaw.map { Dose.snapToInt(unit, $0) }
        // "the plan was met" is a WINDOW one rung wide: for reps it collapses
        // to equality, for a hold it is five seconds (§25.1, #139). It is
        // measured from the plan's BASE dose — `ex.load` IS the minimum of an
        // uneven plan.
        let metPlan = actualRaw.map { $0 >= planMean && $0 < planMean + Double(g.step) } ?? false
        if let actual {
            step = stepFromFact(p, ex: ex, actual: actual, metPlan: metPlan, old: old,
                                cap: cap, setsBackOk: setsBackOk, shown: state.shown)
        } else {
            step = stepFromRating(p, old: old, result: result, targeted: targeted,
                                  chronic: chronic, cap: cap, rampLeft: rampLeft,
                                  setsBackOk: setsBackOk, shown: state.shown)
        }

        // §40.2: the journal is written for a COMPLETED appearance — by the
        // fact when numbers are entered, by the plan when the tap is used. A
        // fact that landed inside the "plan was met" window is SEMANTICALLY
        // the tap (§18.1, #96), so it writes the plan: the mean of 8-7-7 is
        // 7.33 → 7, and recording the fold would say "I showed less than I
        // did". An exercise with a probe writes no journal for the OLD
        // variation — see below.
        if ex.probe == nil {
            // §41.3: the journal records the FOLD when a number was entered and
            // the plan's top only on a tap — a tap asserts the whole plan was
            // done, top set included. Storage snaps to the grid, so the journal
            // itself stays integer; the fraction is only ever a judge.
            setShown(&next, p, old.variation, actual ?? planTop)
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
        // §40.4: the input to the probe condition. It outlives a deload on
        // purpose — the deload zeroes the streak, but does not unsay "hard".
        if step.wantedDown { next.lastHard.insert(p) } else { next.lastHard.remove(p) }

        let fitted = fit(p, step.position)
        if fitted.cut < old.cut {
            next.setsHold[p] = EngineConfig.setsBackHold
        } else {
            let held = (next.setsHold[p] ?? 0) - 1
            next.setsHold[p] = held > 0 ? held : nil
        }
        setPosition(&next, p, fitted)
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
            // §40.3, FAST ADAPTATION. The worst fact is above the plan, so the
            // journal writes the fact and the next showing equals WHAT WAS
            // SHOWN. `maxUp` does not apply: the cap bounds growth the engine
            // ASSIGNS, and here the dose is what the person just did on their
            // own. This is the one mechanism that walks a person back to their
            // own level after the clean start of 3.0 (§40.8). A variation can
            // never be jumped by facts — only by a probe.
            var pos = old
            pos.dose = min(g.max, actual)
            pos.sub = 0
            return Step(position: fit(p, pos), wantedDown: false)
        }
        if actual < g.min {
            // A fact below the floor of the variation: a variation down,
            // landing in the journal.
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

    /// §40.4, the outcomes of a probe. "Hard" on this movement is ordinary
    /// "hard" handling and the probe of this session does not count; a skipped
    /// set or a single tap leaves it unresolved and it comes back next time.
    /// И3: a failed or unresolved probe changes no field but the journal of
    /// facts.
    private static func resolveProbe(_ next: inout EngineState, ex: SessionExercise,
                                     step: inout Step, probes: [Pattern: Int]) {
        guard let probe = ex.probe, !step.wantedDown,
              let raw = probes[ex.pattern] else { return }
        let got = Dose.snap(probe.unit, raw)
        setShown(&next, ex.pattern, probe.variation, got)
        guard got >= Dose.grid(probe.unit).min else { return }
        // ENTRY IS ALWAYS 3×4 (3×15 s). The first working session of a new
        // variation is heavier than the probe — the named gap of §40.10 п. 2,
        // insured by the honest-numbers channel.
        step.position = Position(variation: probe.variation, sets: EngineConfig.setsBase,
                                 dose: Dose.grid(probe.unit).min, sub: 0, cut: 0)
    }

    // MARK: - The session-wide "less" (§19.1, #91)

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

    /// The window of appearances (§26.1, #137). Every exercise of the session
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

    /// v2.10 (§20.1, #90): the pull slot stands in every session, but with a
    /// bar its accounting splits into two branches, each growing half as fast
    /// as the slot. The applied gain is repeated to the other branch, bounded
    /// by ITS OWN growth cell — and, since v3, BY ITS OWN JOURNAL: repeating
    /// someone else's gain was assigning a dose the person never showed in
    /// that branch, which is exactly what §40.0 forbids.
    private static func crossCredit(_ next: inout EngineState, session: Session,
                                    result: FeedbackResult, overrides: [Pattern: Double],
                                    entryPos: [Pattern: Position]) {
        guard next.hasBar,
              let trainedEx = session.exercises.first(where: { Pattern.pullSide.contains($0.pattern) })
        else { return }
        let trained = trainedEx.pattern
        let other: Pattern = trained == .pull ? .pullBar : .pull
        // v2.16 (§27.1, #141): the mark is set by the rating of the WHOLE
        // session — owner's decision 19.08.2026. Telling "the branch really is
        // hard" from "that is how the rhythm fell" is impossible from the
        // inside, and the cost of the error is asymmetric.
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

    /// v2.17 (§28.5, #129): the weekly ceiling is applied ONCE, after every
    /// rise of this session — the cross-credit included, which would otherwise
    /// walk around the budget.
    ///
    /// Fast adaptation by facts is NOT subject to it: there the dose equals
    /// what was shown rather than what was assigned, and trimming it would be
    /// telling the person they did not do what they did. A RESOLVED PROBE is
    /// exempt for the same reason — and rebuilding through `riseBy` would
    /// additionally DESTROY the transition, since growth never crosses a
    /// variation and the position would snap back to the old ceiling.
    private static func applyWeeklyCap(_ next: inout EngineState,
                                       entryPos: [Pattern: Position],
                                       overrides: [Pattern: Double]) {
        for p in Pattern.allCases {
            if overrides[p] != nil { continue }
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
            setPosition(&next, p, riseBy(p, entry, granted,
                                         allowSetsBack: (next.cut[p] ?? 0) < entry.cut))
            if granted > 0 { next.weekGain[p] = spent + granted }
        }
    }
}
