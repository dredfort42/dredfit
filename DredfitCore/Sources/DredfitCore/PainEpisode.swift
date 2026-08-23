//
//  PainEpisode.swift
//  DredfitCore
//
//  The pain channel: the report, the rest ladder, the freeze, the confirmation
//  countdown, and the restorative session under the "I was sick" lens. Split
//  out of Engine.swift the way Descent.swift was in v2.23 — when the rules
//  stopped being a clamp and became a mechanism of their own.
//
//  v2.25 (spec §36.5) REPLACED the ladder whole. It used to walk LEVELS: the
//  first report landed on the floor of the current tier, the second on the
//  floor of the previous one. Both steps were defective, and both in the same
//  direction. The first took 0 % of the work off in 40 cells of 480 — every
//  block floor, where the dose is already the smallest its variation has, so
//  the tap a person makes to be given something lighter did nothing at all.
//  The second left the plan HEAVIER than it was before the pain in 53 cells of
//  480 — the top of the tier below is heavier than the bottom of the current
//  one — and cost up to 23 levels and 49 weeks of climbing back.
//
//  Now the LEVEL DOES NOT MOVE and the sets come off: the first report of a
//  new episode down to the shared floor, the second and every one after it
//  down to the pain floor. That takes 67 % of the work off on band 3, 75 % on
//  band 4, 80 % on band 5 — and it takes it off PROVABLY: inside one variation
//  the measure is valid, which is more than can be said for a change of
//  variation (§30.4).
//

import Foundation

extension Engine {

    /// v2.25 (spec §36.5): the rest ladder reads the MEMORY of pain, not
    /// whether an episode is open. With §36.5 an episode closes on a
    /// countdown, so a repeat report tied to `sore` would have stopped
    /// deepening the rest at all. The same counter fixes the "time to see a
    /// specialist" threshold: it used to hang on a STREAK that the 3/6/12
    /// freeze was guaranteed to break, so nobody it was written for ever
    /// reached it.
    static func painStair(seen: Int) -> Int {
        min(EngineConfig.freezeAppearances * (1 << max(0, seen - 1)),
            EngineConfig.freezeCapAppearances)
    }

    /// v2.11 (spec §21.1-21.2), reworked in v2.19 (§30.6) and again in v2.25
    /// (§36.5): taking the load off is a CUT OF SETS at a level that does not
    /// move.
    ///
    /// THE DEPTH OF THE CUT DOES NOT READ THE HISTORY. The first report of a
    /// new episode always lands on two sets, however many reports there have
    /// been before. Otherwise the second tap in a lifetime, two years and two
    /// hundred clean sessions later, turned `5×15 per side` into `1×15` —
    /// minus 80 % for one press, and an honest signal became too expensive to
    /// give. What the history does read is the REST LADDER (3 → 6 → 12) and
    /// the specialist threshold: the depth of the rest grows, the depth of the
    /// cut does not.
    ///
    /// This runs under the illness lens too (§22.4) — safety outranks the
    /// gentler regime, and one tap must not land differently depending on
    /// whether the trainee happened to be ill. Both branches call this one
    /// function, so the two copies cannot drift apart.
    static func applyDiscomfortReport(_ next: inout EngineState, pattern p: Pattern) {
        // The memory of pain grows on EVERY report — the first, the repeat,
        // and one after a closed episode alike.
        let seen = min((next.painSeen[p] ?? 0) + 1, EngineConfig.painSeenMax)
        next.painSeen[p] = seen
        let stair = Self.painStair(seen: seen)
        let level = next.levels[p] ?? 0
        let stored = next.cut[p] ?? 0
        if next.sore[p] != nil {
            if seen == 2 {
                // The second report: one set. The level STANDS — the
                // variation, the dose per set and the sides are the same, only
                // the volume comes off. FIXED: the cut only ever DEEPENS; an
                // absolute landing handed a set back to whoever already had
                // more taken off (1×8 → 2×8 once the memory had faded).
                Self.setPosition(&next, p, Position(
                    level: level, sub: 0,
                    cut: max(stored, Level.cutMax(level: level,
                                                  floor: EngineConfig.setsFloorPain))))
                next.failStreak[p] = 0
            } else {
                // The third report and beyond: the sets are already on the
                // pain floor, so only the dose is levelled out.
                next.sub.removeValue(forKey: p)
            }
            next.frozen[p] = stair
            next.sore[p] = stair
            // v2.20 (spec §31.2 p.4): the countdown restarts at the NEW
            // assignment — the way back lengthens along with the rest.
            next.soreLeft[p] = stair
        } else {
            // The first report of a new episode: two sets on the same level.
            Self.setPosition(&next, p, Position(
                level: level, sub: 0,
                cut: max(stored, Level.cutMax(level: level,
                                              floor: EngineConfig.setsFloor))))
            next.failStreak[p] = 0
            next.frozen[p] = stair
            next.sore[p] = stair
            next.soreLeft[p] = stair
        }
    }

    /// v2.11 (spec §21.2 p.4-5): the pain freeze ran out but the episode
    /// lives — the pattern waits. Only an explicit fact at or above the
    /// session's plan confirms recovery, and that same fact resumes growth,
    /// through the ordinary cap and without the zero-level calibration
    /// exception: a sore pattern at zero is unloaded history, not a blank
    /// slate. Returns the position the fact earns, or `nil` when the pattern
    /// only waits — then the caller holds it where it was.
    ///
    /// v2.25 (spec §36.3): growth returns SETS first, so both branches go
    /// through `riseBy` and the "one set per session" rule holds here as it
    /// does everywhere else. Before that fix the first honest fact after pain
    /// handed every taken set back at once — up to +525 % in one session.
    static func soreConfirmation(_ next: inout EngineState, exercise ex: SessionExercise,
                                 actual: Int?, entry: Position, cap: Int,
                                 setsBackOk: Bool) -> Position? {
        guard let actual, actual >= ex.load else { return nil }
        Self.closeEpisode(&next, pattern: ex.pattern)
        let oldOrdinal = Level.posOrd(entry)
        if actual == ex.load {
            return Level.riseBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                                by: min(EngineConfig.deltaPlan, cap),
                                allowSetsBack: setsBackOk)
        }
        // v2.17 (spec §28.0): the inversion reads the TRUE set band, as the
        // main fact branch has since v2.14 (§25.2). This one stayed on the
        // shown sets, so the §20.2 gate turned an honest overshoot into a
        // collapse: push_v at 44, trimmed to 3×8, answered with 9 reps, fell
        // to 29.
        let factL = min(max(Level.fromActual(pattern: ex.pattern, tier: ex.tier,
                                             sets: Level.decode(entry.level).sets,
                                             actual: actual),
                            0), EngineConfig.levelMax)
        return Level.riseBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                            by: Level.riseSteps(toFact: factL, from: oldOrdinal, cap: cap),
                            allowSetsBack: setsBackOk)
    }

    /// v2.20 (spec §31.2 p.1-2): one appearance of a pattern with a live
    /// episode spends one tick of the confirmation countdown, and at zero the
    /// episode closes.
    ///
    /// v2.25 (spec §36.5) REPLACED THE PREDICATE. The countdown used to ask
    /// "was the plan manageable?" — a "less" rating or a fact below the plan
    /// took the cleanliness away. But it is asking "HAS THE PAIN PASSED?",
    /// and the two questions may not be tied together by a session rating:
    /// after two "less" in a row §19.1 makes the rating GLOBAL, and from that
    /// moment no appearance was ever clean — the episode never closed at all,
    /// in 480 cells of 480. The honest signal locked the trainee in and the
    /// dishonest one set them free.
    ///
    /// An appearance is clean now when it brought no NEW pain signal: a
    /// discomfort report and a skip leave the loop before this is reached, so
    /// getting here means the movement was done. Safety is held not by the
    /// countdown but by the DESCENT — closing an episode only lifts the growth
    /// clamp and never raises the plan, and the next "hard" lowers it again,
    /// this time for real, with the sets handle.
    static func spendCleanAppearance(_ next: inout EngineState, _ p: Pattern) {
        guard let assigned = next.sore[p] else { return }
        let left = (next.soreLeft[p] ?? assigned) - 1
        if left > 0 { next.soreLeft[p] = left } else { Self.closeEpisode(&next, pattern: p) }
    }

    /// The episode is over: assignment and countdown go together — a leftover
    /// tick with no episode behind it would just be garbage in a saved file.
    static func closeEpisode(_ next: inout EngineState, pattern p: Pattern) {
        next.sore.removeValue(forKey: p)
        next.soreLeft.removeValue(forKey: p)
    }

    /// A frozen pattern keeps its place in the plan but cannot grow; a fact may
    /// still take it DOWN — the athlete's honesty is never overridden. The
    /// streak neither grows nor resets, so a deload cannot fire on top of a
    /// freeze.
    ///
    /// v2.25 (round 6, fix 2): AN APPEARANCE UNDER THE FREEZE SPENDS THE
    /// CONFIRMATION COUNTDOWN TOO. Until this fix the two counters ran in
    /// SEQUENCE, so "rest for 12 appearances" actually meant 12 of freeze PLUS
    /// 12 of countdown plus the returns: three pain reports held a person on
    /// ONE set for 38 appearances — 12.7 weeks at three sessions a week, 19
    /// weeks at two. The counters answer different questions ("how long to
    /// rest" and "has the pain passed") and must tick at the same time, not in
    /// a queue. Parallel they give 20 appearances (6.7 and 10 weeks), and the
    /// full volume is back on the 31st appearance instead of the 48th.
    static func applyFreezeTick(_ next: inout EngineState, pattern p: Pattern,
                                position: Position, frozenLeft: Int) {
        if next.sore[p] != nil { Self.spendCleanAppearance(&next, p) }
        Self.setPosition(&next, p, position)
        if frozenLeft > 1 {
            next.frozen[p] = frozenLeft - 1
        } else {
            next.frozen.removeValue(forKey: p)
        }
    }

    /// One session's inputs as a single value. The restorative branch needs
    /// all of them, and an argument-count limit is not a reason to leave one
    /// out — v2.20 needed the rating and the facts there to tell a clean
    /// appearance from a hard one (§31.2 p.1).
    struct FeedbackInputs {
        let result: FeedbackResult
        let overrides: [Pattern: Int]
        let skipped: Set<Pattern>
        let discomfort: Set<Pattern>
    }

    /// v2.12 (spec §22.4): the restorative session under the illness lens.
    /// The counter moves, the journal is written, the comeback series breaks,
    /// the lens ticks down, freezes spend appearances — but levels, streaks
    /// and the run of "less" stand: an illness is a time for neither growth
    /// nor conclusions. The rest inputs (§21) are the exception — safety
    /// outranks the gentle mode.
    ///
    /// v2.25 (§36.6): the branch does NOT write the shown-plan memory, and
    /// that is deliberate — the base stays the last ordinary showing, so after
    /// the lens the work returns exactly to it instead of reading as a rise.
    static func applyRestorativeSession(
        state: EngineState, session: Session, inputs: FeedbackInputs
    ) -> EngineState {
        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0
        next.illness = state.illness - 1
        // v2.17 (spec §28.4): a restorative session spends the limited-growth
        // window like any other. The reference has always done this; the port
        // did not, so a comeback followed by "I was sick" left the window full
        // and handed the trainee extra sessions of damped growth. Golden could
        // not catch it: `rampWindow`, `weekGain` and `weekAgeDays` were the
        // three state fields `make_golden.js` never snapshotted (audit
        // 2026-08-20, findings S5-1/S5-2) — a hole closed in this same wave.
        next.rampWindow = max(0, state.rampWindow - 1)
        // v2.25 (§36.8): the budget the plan was shown under travels with the
        // state on every path, the lens included — a moved time handle lifts
        // the repair's cap for exactly one state transition, and a path that
        // forgot to write it would leave that loophole open until the next
        // piece of feedback.
        next.shownBudget = EngineState.sanitizeBudget(state.timeBudgetMin)
        for ex in session.exercises {
            let p = ex.pattern
            if inputs.discomfort.contains(p) {
                Self.applyDiscomfortReport(&next, pattern: p)
                continue
            }
            if inputs.skipped.contains(p) { continue }   // a skip spends no appearance
            let frozenLeft = state.freezeRemaining(p)
            if frozenLeft > 1 { next.frozen[p] = frozenLeft - 1; continue }
            if frozenLeft == 1 { next.frozen.removeValue(forKey: p); continue }
            // v2.20 (spec §31.2 p.1): an appearance under the lens spends the
            // confirmation countdown just as an ordinary one does — the lens
            // already spends `frozen` (§22.4), and separate arithmetic here
            // would mean recovery counted differently depending on the "I was
            // sick" tap. Same predicate, and the fast route stays shut under
            // the lens: a fact at or above the plan does not confirm here, it
            // only leaves the appearance clean.
            Self.spendCleanAppearance(&next, p)
        }
        return next
    }
}
