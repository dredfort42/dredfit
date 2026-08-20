//
//  Engine.swift
//  DredfitCore
//
//  Port of the reference adaptive_engine.js. Behavior is verified by golden
//  tests (Fixtures/golden.json) generated from that reference — any
//  divergence is a port bug.
//

import Foundation

// MARK: - Movement patterns

// WARNING: Pattern must never adopt CodingKeyRepresentable. Swift encodes a
// [Pattern: Int] as an UNKEYED array [rawValue, count, rawValue, count, ...]
// precisely because Pattern is a plain String-raw enum; adopting the protocol
// would flip the wire format to a keyed object and break the saved state of
// every existing install (EngineState.decodeLenient parses the array form).
public enum Pattern: String, Codable, CaseIterable, Sendable {
    case squat, pushH = "push_h", hinge, pull, pushV = "push_v", lunge
    case coreAntiExt = "core_anti_ext", coreRot = "core_rot", calf
    case pullBar = "pull_bar"

    /// The two branches of the pull slot and the two push patterns — the sides
    /// the balance principle weighs against each other (spec §20).
    public static let pullSide: Set<Pattern> = [.pull, .pullBar]
    public static let pushSide: Set<Pattern> = [.pushH, .pushV]

    /// Fixed order — defines the rotation. Cannot be changed without a migration.
    public static let ordered: [Pattern] = [
        .squat, .pushH, .hinge, .pull, .pushV, .lunge, .coreAntiExt, .coreRot, .calf
    ]

    public var displayName: String {
        switch self {
        case .squat:       return String(localized: "Squat", bundle: .module)
        case .pushH:       return String(localized: "Horizontal push", bundle: .module)
        case .hinge:       return String(localized: "Hinge", bundle: .module)
        case .pull:        return String(localized: "Pull", bundle: .module)
        case .pushV:       return String(localized: "Vertical push", bundle: .module)
        case .lunge:       return String(localized: "Lunges", bundle: .module)
        case .coreAntiExt: return String(localized: "Core · plank", bundle: .module)
        case .coreRot:     return String(localized: "Core · rotation", bundle: .module)
        case .calf:        return String(localized: "Calves", bundle: .module)
        case .pullBar:     return String(localized: "Vertical pull", bundle: .module)
        }
    }
}

// MARK: - Configuration (all model constants)

public enum EngineConfig {
    public static let repMin = 8
    public static let stepsPerTier = 8
    public static let tiers = 4
    public static let holdMin = 20
    public static let setsBase = 3
    public static let setsMax = 5
    public static let restSetSec = 60
    public static let restExerciseSec = 60
    public static let tempoSecPerRep = 2.5
    public static let patternsPerSession = 6
    public static let rotationStep = 3
    /// v2.23 (spec §34.1): "less" is counted in SUB-STEPS. The same figure in
    /// a different unit: one position back along the growth path, not a level.
    public static let deltaLess = -1
    public static let deltaPlan = 1
    public static let deltaMore = 2
    /// Default cell of the growth ceiling below — the scalar this used to be.
    public static let maxUpPerSession = 2
    public static let failsToDeload = 3
    /// v2.9 (spec §19.2): how many "less" ratings in a row that named nothing
    /// before the delta goes back to the whole session. Measured, not chosen:
    /// at 1 the weak link suffers, at 3 the descent from an impossible plan
    /// costs another session.
    public static let lessRunToGlobal = 2
    public static let deloadDrop = 3
    public static let warmupMin = 5
    public static let cooldownMin = 3
    /// Rest between sets by set band (v2.8, spec §18.2): 60 s was a constant
    /// across the whole scale, including the 4–5-set bands of tier 4 where
    /// the literature gives trained users 2–3 minutes. `restSetSec` stays as
    /// the base and the fallback.
    public static let restSetByBand = [3: 60, 4: 90, 5: 120]
    public static let comebackMinGapDays = 14
    public static let comebackBase = 2
    public static let comebackStepDays = 21
    public static let comebackMax = 8
    public static let silentDecayGapDays = 7
    /// How many of a pattern's next APPEARANCES stay frozen after a discomfort
    /// report (v2.5). Counted in appearances, not sessions: a rotating pattern
    /// shows up in about five sessions out of eight, so "three sessions" would
    /// make the actual rest unpredictable. Three ≈ a calendar week.
    /// v2.22 (spec §33): the second way into the same freeze — the
    /// hold-this-level request — is cancelled, so the constant has one consumer
    /// again.
    public static let freezeAppearances = 3
    /// v2.11 (spec §21.2): the rest ladder's ceiling for repeated pain
    /// reports — the assignment doubles 3 → 6 → 12 and stops here
    /// (≈ a month at three sessions a week).
    public static let freezeCapAppearances = 12
    /// v2.12 (spec §22.4): how many sessions the "I was sick" lens holds —
    /// the plan is one tier easier, the levels stand. Six ≈ two weeks at
    /// three sessions a week: the clinical minimum-load window after an
    /// illness (Salman 2021, BMJ m4721).
    public static let illnessSessions = 6
    /// v2.13 (spec §24.1): the technical ceiling of every counter and of the
    /// gap in days. These have no semantic ceiling — a run grows freely (the
    /// golden fixture reaches a `lessRun` of 7 against a threshold of 2), so
    /// clamping them to their meaning would change behavior. But this port
    /// does its arithmetic on Int64: `counter * rotationStep` near `Int.max`
    /// traps the process (exit 133) on every plan, in a loop the store's
    /// quarantine never catches — the decode succeeded, so the file stays.
    /// A million is 2700 years of daily sessions: beyond any real history and
    /// far from any overflow, so the clamp is identity on the valid domain and
    /// identical on both sides — the dirty-state differential lines up exactly.
    public static let countMax = 1_000_000
    /// v2.17 (spec §28.2, #144): rest reads the TIER as well as the band.
    /// Tier-4 movements sitting in band 3 (levels 24-31 — pistols, archer
    /// rows, wall handstand work) were given 60 s, while Grgic 2018 and
    /// Schoenfeld 2016 put trained users on hard variations at >= 2 min. 90 s
    /// rather than 120: 120 inverts the ladder (L24-31 would rest longer than
    /// L32-39) and breaks the tier transition's unload.
    public static let restSetByTierBand: [Int: [Int: Int]] = [4: [3: 90]]
    /// v2.17 (spec §28.1, #142): the sets bands start at their own dose. The
    /// entry used to reset reps to the bottom of tier 4, which cut the actual
    /// work by 52-72% while the session got LONGER.
    public static let repStartBand = [4: 6, 5: 8]
    /// v2.21 (spec §32.3): the band starts drop 25/30 → 20/24. Tier 4 now tops
    /// out at 19 s (the ladder below), and the old starts tore the continuity
    /// at the band's door: L31 3×19 = 57 s of static work against L32 4×25 =
    /// 100 s, +75 % for ONE level. 20/24 give +40 % and −27 % — the same
    /// bounds every other boundary lives in (§28.1).
    public static let holdStartBand = [4: 20, 5: 24]
    public static let holdStepBand = [4: 3, 5: 3]
    /// v2.17 (spec §28.4, #129): sessions of limited growth after a comeback.
    public static let rampWindowSessions = 10
    /// v2.17 (spec §28.5, #129): the weekly ceiling on rises. The §15.3 caps
    /// are per session, so daily training walks around them by multiplication:
    /// 28 consecutive "plan" sessions took BOTH pull branches from 0 to 28 —
    /// full pull-ups in the plan after 28 days with no rest day at all.
    public static let weeklyRiseSlow = 3
    public static let weeklyRiseFast = 6
    public static let weeklyWindowDays = 7
    /// v2.19 (spec §30.8): the floor on how much a single session ages the
    /// window. A session cannot take less than an hour, so a zero gap is
    /// always a fault in the source, never a fact. Without the floor the
    /// engine silently freezes forever: two workouts inside one day used to
    /// round to zero, the §28.5 window never aged, and the weekly growth
    /// budget was spent once for a lifetime — 48 levels against 423 over 120
    /// sessions. The floor does not add to the real gap, it replaces it from
    /// below, so a correct app layer is never double-counted.
    public static let minSessionAgeDays = 1.0 / 24.0
    /// v2.17 (spec §28.3, #136): the time budget trims the PLAN, never levels.
    public static let budgetSetsFloor = 2
    public static let budgetPatternsFloor = 3
    public static let budgetShortEndsAt = 20
    public static let warmupShortMin = 3
    public static let cooldownShortMin = 2
    /// v2.15 (spec §26.1, #137): the chronic weak-link signal §19.4 deferred
    /// back in v2.9. The window counts a pattern's own APPEARANCES, not
    /// sessions: a rotating pattern shows up in five sessions out of eight, so
    /// a session-based threshold is structurally out of its reach — the same
    /// reason `lessRunToGlobal` never catches it. Three of the last four, and
    /// a double step: the owner's decision of 18.08.2026, measured — the weak
    /// link reaches its capacity in 13 appearances instead of 31, and the
    /// healthy movements stop being the lightning rod (19.4 of 20 vs 15.5).
    public static let chronicWindow = 4
    public static let chronicHits = 3
    /// v2.23 (spec §34.1): sub-steps as well. The 2:1 ratio to a plain "less"
    /// is kept — both constants changed unit, neither changed magnitude.
    public static let chronicStep = -2
    /// v2.15 (spec §26.2, #130): how many patterns calibrating from zero in
    /// ONE session make it a claim about the day rather than about the body.
    public static let calibrationGroup = 3
    public static let repStart = [1: 8, 2: 6, 3: 5, 4: 4]
    /// v2.21 (spec §32): the hold ladder — a relative step instead of a fixed
    /// five seconds.
    ///
    /// Five seconds on a base of 10 (tier 4) is +50 % for ONE rung, and under
    /// the §15.3 ceiling of two rungs up to +67 % in a single session:
    /// `coreAntiExt` L8→10 turned a 3×15 s plank into 3×25 s. No source writes
    /// progression as an absolute increment; ACSM 2009 (Med Sci Sports Exerc
    /// 41(3):687–708) says "a 2–10 % increase in load". The rung of "do no
    /// harm": ~10 % of the dose you are standing on.
    ///
    /// The tables are LITERAL, not a formula. The derivation —
    /// `next = prev + max(1, round(prev × 0.10))` — was run once and written
    /// down; keeping it as a formula would make the engine's behaviour depend
    /// on the platform's rounding mode (JS `Math.round` sends a half up,
    /// Swift's `.rounded()` sends it away from zero), and at 15 s and 25 s the
    /// increment is exactly 1.5 and 2.5 — right on that boundary. A literal
    /// is the same everywhere.
    public static let holdLadder: [Int: [Int]] = [
        1: [20, 22, 24, 26, 29, 32, 35, 39],
        2: [15, 17, 19, 21, 23, 25, 28, 31],
        3: [15, 17, 19, 21, 23, 25, 28, 31],
        4: [10, 11, 12, 13, 14, 15, 17, 19],
    ]
    /// The set bands do NOT follow the relative formula: their step stays a
    /// whole 3 s (§28.1), so the ladder is derived from the start and the step
    /// by exact integer arithmetic — platform-independent, and needing no
    /// literal of its own. One source of truth: `holdStartBand`/`holdStepBand`.
    public static let holdLadderBand: [Int: [Int]] = holdStartBand.reduce(into: [:]) { out, band in
        let step = holdStepBand[band.key] ?? 0
        out[band.key] = (0..<stepsPerTier).map { band.value + $0 * step }
    }
    public static var levelMax: Int { (tiers + setsMax - setsBase) * stepsPerTier - 1 } // 47

    /// How many levels a pattern may climb in one session, by (pattern, tier).
    /// Tendon and fascia remodel on a slower clock than muscle, and the
    /// ceiling is the one dial that acts *before* an overload rather than
    /// after it. A missing cell is `maxUpPerSession`.
    ///
    /// The rule in four lines: calves are held to a step at every tier
    /// (everything loads the Achilles), the vertical push from tier 3 (wall
    /// work bears the shoulder girdle), the pull from tier 2 — its fixed slot
    /// puts it in every session, eight appearances against the rotating
    /// five, so at equal feedback it out-climbs everything else unless held
    /// to a step (frequency, not tissue) — and tier 4 everywhere: the archer
    /// variants, the heaviest unilaterals, and the set bands 32...47, which
    /// are tier 4 by encoding. Spec §15.3 carries the table cell by cell with
    /// a rationale each, and the reference verifier compares the two.
    public static let maxUpByPatternTier: [Pattern: [Int: Int]] = [
        .squat: [4: 1],
        .pushH: [4: 1],
        .hinge: [4: 1],
        .pull: [2: 1, 3: 1, 4: 1],
        .pushV: [3: 1, 4: 1],
        .lunge: [4: 1],
        .coreAntiExt: [4: 1],
        .coreRot: [4: 1],
        .calf: [1: 1, 2: 1, 3: 1, 4: 1],
        // v2.10 (spec §20.1): the cross-credit restores the pull slot's full
        // speed, so #76's frequency argument now reaches the vertical branch
        // too — tiers 2-3 line up with the horizontal row.
        .pullBar: [2: 1, 3: 1, 4: 1]
    ]

    /// `tier` comes from the level BEFORE the update: the ceiling governs
    /// leaving a level, not arriving at one. Levels 32...47 are tier 4 by
    /// encoding, so the set bands need no special case.
    public static func maxUp(pattern: Pattern, tier: Int) -> Int {
        maxUpByPatternTier[pattern]?[tier] ?? maxUpPerSession
    }

    /// Landing ceilings past the comeback table's edge (v2.7, spec §17.2):
    /// the calendar cap of −8 knows nothing about the level, and a year away
    /// used to land a former ceiling user in tier 4. Rows are (minimum gap,
    /// level ceiling) in descending gap order; the first match wins.
    /// v2.12 (spec §22.2): a ladder of tier BOTTOMS — every next storey of
    /// the break lowers the ceiling by a tier, and a ceiling landing can
    /// never carry a high dose by construction. The old 15/7 rows (tier
    /// tops, the 11.08 decision) were themselves the sweep's worst case.
    public static let comebackLandingCeil: [(minGap: Int, ceil: Int)] =
        [(365, 0), (119, 8), (77, 16), (56, 24)]

    /// A "slow tissue" pattern is one the §15.3 table holds to a step at
    /// EVERY tier — today only the calf. Derived from the table rather than
    /// kept as a second list: one source of truth (v2.7, spec §17.1).
    public static func isSlowTissue(_ pattern: Pattern) -> Bool {
        (1...tiers).allSatisfy { maxUp(pattern: pattern, tier: $0) == 1 }
    }
}

// MARK: - Level encoding

public struct LevelDecoded: Equatable, Sendable {
    public let tier: Int   // 1...4
    public let sets: Int   // 3 | 4 | 5
    public let reps: Int
    public let hold: Int

    public init(tier: Int, sets: Int, reps: Int, hold: Int) {
        self.tier = tier
        self.sets = sets
        self.reps = reps
        self.hold = hold
    }
}

// MARK: - Feedback

public enum FeedbackResult: String, Codable, Sendable {
    case less, plan, more

    var delta: Int {
        switch self {
        case .less: return EngineConfig.deltaLess
        case .plan: return EngineConfig.deltaPlan
        case .more: return EngineConfig.deltaMore
        }
    }
}

// MARK: - Engine

public enum Engine {

    /// Rotating patterns (all except pull — it appears in every session).
    /// Not private: the session builder in Session.swift reads it too.
    static let rotating: [Pattern] = Pattern.ordered.filter { $0 != .pull }

    /// v2.13 (spec §24.2): the gap in days is the engine's only numeric input
    /// besides the reported facts, and it sat outside the §17.4 contract. In
    /// the reference a NaN gap wrote NaN into every level; here the type rules
    /// that out, but `Int.min` would still trap the subtraction below. A
    /// negative gap already meant "no break", so clamping it to zero keeps the
    /// two sides answering identically on every input either can express.
    static func sanitizeGapDays(_ raw: Int) -> Int {
        EngineState.clamped(raw, 0, EngineConfig.countMax)
    }

    /// Where a single reported number puts the level (spec §12.1/§18.1/§25).
    /// Pulled out of `applyFeedback` so the three v2.14 rules read together —
    /// and so that function stays inside the lint's body-length ceiling.
    ///
    /// v2.22 (spec §33): answers a POSITION. Inside the "plan was met" window a
    /// growth event is worth one SUB-STEP; above the window the inversion still
    /// answers a level, but the rise is capped in sub-steps; below the base dose
    /// it is a descent, which stays in whole levels and zeroes the sub-step.
    private static func positionFromPointFact(pattern p: Pattern, exercise ex: SessionExercise,
                                              actual: Int, oldL: Int, oldSub: Int, cap: Int,
                                              calibratedUp: inout [Pattern]) -> Position {
        // v2.14 (spec §25.2): the inversion reads the pattern's TRUE set band,
        // not the shown one. The §20.2 gate clamps the PLAN, not the state —
        // but the fact was inverted against the trimmed sets, so an honest
        // overshoot of a gated plan dropped the level (32 → 30) and fed the
        // deload streak.
        let factL = Level.fromActual(pattern: p, tier: ex.tier,
                                     sets: Level.decode(oldL).sets, actual: actual)
        // v2.14 (spec §25.1): "the plan was met" is a WINDOW, not a point.
        // Seconds are encoded in ladder rungs, so an honest 21-22 s
        // against a plan of 20 rounded into the same rung and moved nothing,
        // while exactly 20 gave +1 — the level stopped being monotone in the
        // reported fact across the whole static class (v2.8 §18.1 granted the
        // step only at equality). For reps the step is one and the window is
        // that old equality.
        // v2.21 (spec §32.4): the window is one LOCAL rung of the ladder, not
        // five seconds, and it is read off the same band the inversion uses.
        // v2.22 (spec §33): the window is measured from the plan's BASE dose —
        // `ex.load` IS the minimum of an uneven plan.
        let window = Level.step(of: ex.unit, tier: ex.tier,
                                sets: Level.decode(oldL).sets, load: ex.load)
        let oldOrdinal = Level.ordinal(level: oldL, sub: oldSub)
        if actual >= ex.load && actual < ex.load + window {
            return Level.rise(level: oldL, sub: oldSub,
                              by: min(EngineConfig.deltaPlan, cap))
        }
        // Calibration: from a zero level the per-session cap does not apply —
        // but the reps→level inversion is only valid one tier out (v2.7, spec
        // §17.1): the result is bounded by the neighboring tier's ceiling,
        // slow tissues by tier 1's. That ceiling bounds where a fact may LAND,
        // so it is a level and stays one (§33.3); the landing carries a zero
        // sub-step.
        if oldL == 0 {
            let zeroCeil = EngineConfig.isSlowTissue(p)
                ? EngineConfig.stepsPerTier - 1
                : 2 * EngineConfig.stepsPerTier - 1
            let landed = min(max(factL, 0), zeroCeil)
            if landed > 0 { calibratedUp.append(p) }
            return Position(level: landed, sub: 0)
        }
        let factOrdinal = Level.ordinal(level: min(max(factL, 0), EngineConfig.levelMax), sub: 0)
        if factOrdinal > oldOrdinal {
            return Level.position(atOrdinal: min(factOrdinal, oldOrdinal + cap))
        }
        // v2.14 (spec §25.3): a descent may not make the plan heavier.
        return Position(level: Level.descendNoHarder(pattern: p, from: oldL,
                                                     factLevel: factL, fromSub: oldSub),
                        sub: 0)
    }

    /// v2.9 (spec §19.1): movements the user pointed at during the workout —
    /// an exact number below the plan, a discomfort report, a hold request.
    /// v2.22 (spec §33): the hold request is gone from this list — the input
    /// itself is cancelled. Two named signals are left: an exact number below
    /// the plan's BASE dose, and a discomfort report.
    private static func namedMovements(
        session: Session, overrides: [Pattern: Int], discomfort: Set<Pattern>
    ) -> Set<Pattern> {
        var named: Set<Pattern> = []
        for ex in session.exercises {
            let p = ex.pattern
            if discomfort.contains(p) {
                named.insert(p)
            } else if let actual = overrides[p], actual < ex.load {
                named.insert(p)
            }
        }
        return named
    }

    /// Who a session-wide "less" reaches, or nil when it reaches everyone as
    /// it did in v2.8. A named movement takes it alone and the other five have
    /// nothing to lose a level for; with nothing named it falls on a single
    /// movement, the highest-level one — the aim is a guess (hard ≠ highest),
    /// and what does the work is the asymmetry: on a hard session nobody grows
    /// and only one falls. A run of unnamed "less" hands the delta back to
    /// everyone (§19.2) — without that, someone for whom the whole plan is too
    /// hard stops descending altogether.
    private static func lessTargets(
        state: EngineState, session: Session, result: FeedbackResult,
        named: Set<Pattern>, overrides: [Pattern: Int],
        skipped: Set<Pattern>, discomfort: Set<Pattern>,
        chronic: Set<Pattern> = [], window: [Pattern: Int] = [:]
    ) -> Set<Pattern>? {
        guard result == .less, state.lessRun < EngineConfig.lessRunToGlobal else { return nil }
        guard named.isEmpty else { return named }
        // v2.15 (spec §26.1): the culprit is the pattern whose OWN appearances
        // fail most often — the weak link fails every time it shows up, a
        // healthy one only when it shared a session with the weak link. The
        // old aim ("the highest level") reached the weak link zero times out
        // of 62 failing appearances (audit A3-4): the weak link is by
        // definition the LOWER one. Ties go to the higher level.
        if !chronic.isEmpty {
            var best: Pattern?
            var bestHits = -1, bestLevel = -1
            // Walked in SESSION order, never over the set itself: a Swift Set
            // has no order, and the reference resolves ties by insertion —
            // iterating the set would make the two sides disagree on a tie.
            for ex in session.exercises {
                let p = ex.pattern
                guard chronic.contains(p), !skipped.contains(p), !discomfort.contains(p)
                else { continue }
                if overrides[p] != nil { continue }
                let hits = (window[p] ?? 0).nonzeroBitCount
                let level = state.levels[p] ?? 0
                if hits > bestHits || (hits == bestHits && level > bestLevel) {
                    bestHits = hits; bestLevel = level; best = p
                }
            }
            if let best { return [best] }
        }
        // Only movements that would take the delta at all can be the aim: a
        // skipped one was not trained, and one carrying an exact number goes
        // its own way.
        var best: Pattern?
        var bestL = -1
        for ex in session.exercises {
            let p = ex.pattern
            if skipped.contains(p) || discomfort.contains(p) || overrides[p] != nil { continue }
            let level = state.levels[p] ?? 0
            if level > bestL { bestL = level; best = p }
        }
        return best.map { [$0] } ?? []
    }

    /// Invariant: feedback is only valid for the session generated from this
    /// exact state (`session.sessionNumber == state.counter + 1`). Anything
    /// else returns the state untouched, so applying the same (state,
    /// session) twice is safe.
    ///
    /// Known limitation: `applyComeback` does not advance `counter`, so a
    /// session generated *before* a comeback still passes this check and its
    /// feedback lands on the post-comeback levels.
    ///
    /// A skipped pattern was not trained: its level, failStreak and freeze
    /// counter stay untouched (the streak is frozen, not reset), overrides for
    /// it are ignored. The counter still advances.
    ///
    /// `discomfort` is the joint-pain input (reworked in v2.11, spec §21, and
    /// again in v2.19, spec §30.6): the session is voided for the pattern and
    /// the load comes off in two steps — the first report lands on the floor
    /// of the current tier (`Level.tierFloor`), the second on the floor of the
    /// previous one (`Level.unload`), the streak resetting on both. The
    /// pattern is frozen with the episode marked in `sore`, and the freeze
    /// expires into WAITING, not into growth: taps keep clamping until the
    /// episode is confirmed. v2.20 (spec §31) gave that confirmation a SECOND
    /// route: an explicit fact at or above the plan still closes the episode
    /// on the spot and grows the level in the same move, and now a run of
    /// `soreLeft` CLEAN appearances closes it too — growth resuming from the
    /// NEXT appearance. Every repeat report doubles the rest up the
    /// 3 → 6 → 12 ladder and restarts the countdown at the new assignment;
    /// from the third report on, the level no longer moves.
    ///
    /// v2.22 (spec §33): growth moves by SUB-STEPS. What used to be "+1 level"
    /// is "+1 sub-step": one of the pattern's sets takes the next rung's dose,
    /// and the level rises only once every set carries it. Every ceiling that
    /// bounds a RISE counts sub-steps — the §15.3 cell, the §28.5 weekly
    /// window, the §28.4 ramp — which is what keeps §28.5 free for an honest
    /// three-a-week rhythm: three "plan" sessions are three sub-steps, exactly
    /// the slow budget, just as three sessions used to be three levels.
    /// Descents stay in WHOLE levels and zero the sub-step, so the §19.2
    /// guarantee does not stretch.
    ///
    /// The hold-this-level request (v2.6) is cancelled by the same wave, and
    /// `gapDays` moved into its place as the seventh parameter.
    public static func applyFeedback(
        state dirty: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides dirtyOverrides: [Pattern: Int] = [:],
        skipped: Set<Pattern> = [],
        discomfort: Set<Pattern> = [],
        /// v2.17 (spec §28.5): the one aggregate the engine needs to stop
        /// daily training from multiplying its way around the §15.3 caps.
        /// `nil` = the app supplies no signal, and the engine stays
        /// calendar-blind exactly as §7 promises.
        /// v2.19 (spec §30.8): FRACTIONAL days. Whole days threw away every
        /// gap shorter than one, so two workouts in a day froze growth for
        /// good; the app layer hands over `interval / 86_400`.
        gapDays: Double? = nil
    ) -> EngineState {
        // v2.13 (spec §24.1/§24.3): the state heals on entry, and a reported
        // fact is clamped to the same technical range — `actual - repStart`
        // near Int.min would trap, and past the range every fact already
        // saturates the 0...levelMax result, so this is identity on anything
        // a person could log.
        let state = dirty.sanitized()
        let overrides = dirtyOverrides.mapValues {
            EngineState.clamped($0, -EngineConfig.countMax, EngineConfig.countMax)
        }
        // A no-op on a stale pair, exactly as the reference: the guard reads
        // the sanitized counter, so a garbage one cannot smuggle a match.
        guard session.sessionNumber == state.counter + 1 else { return dirty }

        // v2.12 (spec §22.4): a session under the illness lens is restorative
        // — levels, streaks and the run of "less" stand.
        if state.illness > 0 {
            return Self.applyRestorativeSession(state: state, session: session,
                inputs: FeedbackInputs(result: result, overrides: overrides, skipped: skipped,
                                       discomfort: discomfort))
        }

        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0                          // v2.12: a session breaks the series

        // v2.9 (spec §19.1): who receives the SESSION-WIDE "less".
        let named = Self.namedMovements(session: session, overrides: overrides,
                                        discomfort: discomfort)
        // v2.15 (spec §26.1): the appearance window. Every exercise of the
        // session shifts its own mask — 1 when the session was rated an
        // unnamed "less". A named "less" writes nothing: it is already
        // addressed, and the chronic signal exists for the sessions where the
        // trainee says nothing and taps once.
        // v2.15 (spec §26.2, #130): who calibrates from zero in THIS session.
        var calibratedUp: [Pattern] = []
        // v2.17 (spec §28.5): no signal, no rule — the engine behaves exactly
        // as it did before v2.17, which is what makes the rollout safe.
        let haveGap = (gapDays?.isFinite ?? false)
        // v2.19 (spec §30.8): the floor replaces the gap from below — a
        // session that reports no elapsed time still ages the window.
        let agedDays = haveGap
            ? state.weekAgeDays + max(EngineConfig.minSessionAgeDays, gapDays ?? 0)
            : 0
        let windowExpired = agedDays >= Double(EngineConfig.weeklyWindowDays)
        var weekGain = (!haveGap || windowExpired) ? [:] : state.weekGain
        next.weekAgeDays = (!haveGap || windowExpired) ? 0 : agedDays
        // v2.17 (spec §28.4): the window a comeback opened is spent by sessions.
        let rampLeft = state.rampWindow
        next.rampWindow = max(0, rampLeft - 1)
        let chronic = Self.rollChronicWindow(&next, session: session,
                                            unnamedLess: result == .less && named.isEmpty)
        let lessTargets = Self.lessTargets(state: state, session: session, result: result,
                                           named: named, overrides: overrides,
                                           skipped: skipped, discomfort: discomfort,
                                           chronic: chronic, window: next.lessHist)
        // A named "less" does not feed the run: "it was hard, and it was this
        // one" is a statement about one movement, however often it repeats.
        next.lessRun = result == .less && named.isEmpty ? state.lessRun + 1 : 0

        for ex in session.exercises {
            let p = ex.pattern
            // Discomfort outranks a skip: the session is voided for the
            // pattern either way, but only one of them carries information.
            if discomfort.contains(p) {
                Self.applyDiscomfortReport(&next, state: state, pattern: p)
                continue
            }
            if skipped.contains(p) { continue }
            // "Frozen when this session started" — read from `state`, never
            // from `next`: a discomfort report writes `next.frozen` and leaves
            // the iteration at once, and leaning on that order would be an
            // accident. Both implementations read the entry state.
            let frozenLeft = state.freezeRemaining(p)
            let oldL = state.levels[p] ?? 0
            // v2.22 (spec §33): the whole position. Everything that moves a
            // pattern up works on the PAIR — a level alone cannot describe it.
            let oldSub = state.sub[p] ?? 0
            let oldOrdinal = Level.ordinal(level: oldL, sub: oldSub)
            // The tier is read from the level before the update, not from the
            // session — same thing today, and the rule stays true if a session
            // ever outlives the state it was generated from.
            // v2.22 (spec §33): the cell counts SUB-STEPS — a "2" means two
            // sub-steps, not two levels. That is what drops the worst relative
            // step of one growth event from 25 % to 8.3 % on reps.
            let cap = EngineConfig.maxUp(pattern: p, tier: Level.decode(oldL).tier)
            var position: Position
            // v2.23 (spec §34.1): an exact fact does NOT fall under the
            // sub-step rule — the athlete's honesty is never overridden
            // (§15.2 p.2). Its path stays v2.22's word for word: invert to a
            // level, pass the §25.3 gate, zero the sub-step. Someone who wrote
            // "2 out of 8" is talking about a dose, not about fatigue, and
            // there is nothing to make finer.
            let factPath = overrides[p] != nil
            // v2.23 (spec §34.2): the failure streak counts the INTENT to go
            // down, not the movement — see `positionFromRating`.
            var wantedDown = false

            if let actual = overrides[p] {
                position = Self.positionFromPointFact(
                    pattern: p, exercise: ex, actual: actual, oldL: oldL, oldSub: oldSub,
                    cap: cap, calibratedUp: &calibratedUp)
            } else {
                (position, wantedDown) = Self.positionFromRating(
                    pattern: p, result: result, from: Position(level: oldL, sub: oldSub),
                    cap: cap, rampLeft: rampLeft, lessTargets: lessTargets, chronic: chronic)
            }
            position = Position(level: min(max(position.level, 0), EngineConfig.levelMax),
                                sub: position.sub)
            var newL = position.level

            // A frozen pattern keeps its place in the plan at its current
            // level but cannot grow; a fact may still take it DOWN — the
            // athlete's honesty is never overridden. The streak neither grows
            // nor resets, so a deload cannot fire on top of a freeze.
            // v2.22 (spec §33): "cannot grow" clamps the POSITION, not the
            // level — a sub-step is growth too.
            if frozenLeft > 0 {
                let held = Level.position(atOrdinal: min(Level.ordinal(position), oldOrdinal))
                Self.applyFreezeTick(&next, pattern: p, position: held,
                                     frozenLeft: frozenLeft)
                continue
            }

            // v2.11 (spec §21.2 p.4-5), revised in v2.20 (spec §31.2): the
            // pain freeze ran out but the episode lives — the pattern waits.
            // Growth clamps, a fact may still go down, the streak stands.
            // There are TWO confirmations, and they are deliberately not
            // equally fast: an explicit fact at or above the session's plan
            // closes the episode and resumes growth in the SAME move, while a
            // run of clean appearances closes it but leaves the growth for the
            // next one. The second route exists because the first is
            // unreachable by construction for someone who logs no numbers —
            // one "it hurts" tap used to cost the movement for good (§31).
            if state.sore[p] != nil {
                guard let confirmed = Self.soreConfirmation(
                    &next, exercise: ex, actual: overrides[p],
                    oldL: oldL, oldSub: oldSub, cap: cap) else {
                    Self.spendCleanAppearance(&next, p, rating: result, fact: overrides[p], load: ex.load)
                    // The clamp is applied whether or not that tick was the
                    // last one: an appearance without growth is cheaper than a
                    // tendon, so the closing session still holds the position.
                    let held = Level.position(atOrdinal: min(Level.ordinal(position), oldOrdinal))
                    Self.setPosition(&next, p, held)
                    continue
                }
                position = confirmed
                newL = confirmed.level
            }

            position = Self.tickStreak(&next, pattern: p, entryStreak: state.failStreak[p] ?? 0,
                                       landed: position, entry: Position(level: oldL, sub: oldSub),
                                       wentDown: factPath ? newL < oldL : wantedDown,
                                       deloadFrom: factPath ? newL : oldL)
            Self.setPosition(&next, p, position)
        }

        Self.applyHumbleGroupLanding(&next, calibratedUp: calibratedUp)
        Self.applyCrossCredit(&next, state: state, session: session, result: result,
                              overrides: overrides, discomfort: discomfort)
        // v2.17 (spec §28.5): the weekly ceiling is applied ONCE, after every
        // rise this session — the cross-credit included, or it would walk
        // around the budget: with a bar the branch grows on credit every other
        // session, and the measurement gave 25 levels over 28 daily sessions.
        if haveGap { Self.applyWeeklyCeiling(&next, state: state, weekGain: &weekGain) }
        next.weekGain = weekGain
        return next
    }

    /// v2.17 (spec §28.5): the weekly ceiling, applied ONCE per session over
    /// every rise it produced — the cross-credit included, or it would walk
    /// around the budget: with a bar the branch grows on credit every other
    /// session, and the measurement gave 25 levels over 28 daily sessions
    /// instead of twelve. Slow tissue (both pull branches, calves) may rise
    /// three levels a week, everything else six.
    /// v2.22 (spec §33): the budget is counted in SUB-STEPS. §28.5's property
    /// — "the rule costs an honest three-a-week rhythm nothing" — survives
    /// verbatim: three "plan" sessions are three sub-steps, exactly the slow
    /// budget, where three sessions used to be three levels. A daily rhythm is
    /// held harder than before, which is the direction the rule exists for.
    private static func applyWeeklyCeiling(_ next: inout EngineState, state: EngineState,
                                           weekGain: inout [Pattern: Int]) {
        for p in Pattern.allCases {
            let entry = state.position(p)
            let rise = Level.subRise(from: entry, to: next.position(p))
            guard rise > 0 else { continue }
            let budget = EngineConfig.isSlowTissue(p) || Pattern.pullSide.contains(p)
                ? EngineConfig.weeklyRiseSlow : EngineConfig.weeklyRiseFast
            let spent = weekGain[p] ?? 0
            let granted = min(rise, max(0, budget - spent))
            Self.setPosition(&next, p,
                             Level.rise(level: entry.level, sub: entry.sub, by: granted))
            if granted > 0 { weekGain[p] = spent + granted }
        }
    }

    /// v2.22 (spec §33): writing a position. Sparseness is part of the
    /// contract: a zero is never stored, so a state that descended is
    /// byte-identical to one that never carried a sub-step at all.
    static func setPosition(_ next: inout EngineState, _ p: Pattern, _ position: Position) {
        next.levels[p] = position.level
        let sub = Level.effectiveSub(level: position.level, sub: position.sub)
        if sub > 0 { next.sub[p] = sub } else { next.sub.removeValue(forKey: p) }
    }

    /// v2.11 (spec §21.2 p.4-5): the pain freeze ran out but the episode
    /// lives — the pattern waits, indefinitely. Only an explicit fact at or
    /// above the session's plan confirms recovery, and that same fact resumes
    /// growth, through the ordinary cap and without the zero-level
    /// calibration exception: a sore pattern at zero is unloaded history, not
    /// a blank slate. Returns the level the fact earns, or `nil` when the
    /// pattern only waits — then the caller holds it where it was.
    /// v2.22 (spec §33): the fast route resumes growth in SUB-STEPS, like the
    /// main branch. Under a live episode the sub-step is always zero — the
    /// report zeroed it and growth stayed clamped — so the plan's base equals
    /// the plan here.
    private static func soreConfirmation(_ next: inout EngineState, exercise ex: SessionExercise,
                                         actual: Int?, oldL: Int, oldSub: Int,
                                         cap: Int) -> Position? {
        guard let actual, actual >= ex.load else { return nil }
        Self.closeEpisode(&next, pattern: ex.pattern)
        let oldOrdinal = Level.ordinal(level: oldL, sub: oldSub)
        if actual == ex.load {
            return Level.rise(level: oldL, sub: oldSub,
                              by: min(EngineConfig.deltaPlan, cap))
        }
        // v2.17 (spec §28.0): the inversion reads the TRUE set band, as the
        // main fact branch has since v2.14 (§25.2). This one stayed on the
        // shown sets, so the §20.2 gate turned an honest overshoot into a
        // collapse: push_v at 44, trimmed to 3×8, answered with 9 reps, fell
        // to 29.
        let factL = min(max(Level.fromActual(pattern: ex.pattern, tier: ex.tier,
                                             sets: Level.decode(oldL).sets, actual: actual),
                            0), EngineConfig.levelMax)
        return Level.position(atOrdinal: min(Level.ordinal(level: factL, sub: 0),
                                             oldOrdinal + cap))
    }

    /// v2.20 (spec §31.2 p.1-2): one appearance of a waiting pattern.
    ///
    /// A CLEAN appearance — the pattern was trained and the session carried no
    /// "it was hard" signal about it — spends one tick of the countdown, and
    /// at zero the episode closes. A "less" rating or a fact below the plan
    /// takes the cleanliness away and the countdown stands; a fact at or above
    /// the plan is clean (on the fast route it has already closed the episode
    /// and never reaches here). Skips, discomfort reports and holds leave the
    /// loop earlier and never reach here either.
    ///
    /// One implementation for both branches — the ordinary one and the
    /// restorative one under the illness lens (§22.4): the same appearance
    /// cannot mean different things depending on whether the trainee tapped
    /// "I was sick". Growth is the caller's business, and the session that
    /// closes an episode still keeps its clamp (§31.2 p.2).
    private static func spendCleanAppearance(_ next: inout EngineState, _ p: Pattern,
                                             rating: FeedbackResult, fact: Int?, load: Int) {
        guard next.sore[p] != nil, rating != .less,
              fact.map({ $0 >= load }) ?? true else { return }
        let left = (next.soreLeft[p] ?? next.sore[p] ?? 0) - 1
        if left > 0 { next.soreLeft[p] = left } else { Self.closeEpisode(&next, pattern: p) }
    }

    /// The episode is over: assignment and countdown go together — a leftover
    /// tick with no episode behind it would just be garbage in a saved file.
    private static func closeEpisode(_ next: inout EngineState, pattern p: Pattern) {
        next.sore.removeValue(forKey: p)
        next.soreLeft.removeValue(forKey: p)
    }

    /// A frozen pattern keeps its place in the plan at its current level but
    /// cannot grow; a fact may still take it DOWN — the athlete's honesty is
    /// never overridden. The streak neither grows nor resets, so a deload
    /// cannot fire on top of a freeze. A pin arms the rest AFTER the level
    /// update, so the reporting appearance is never spent; v2.11 (spec §21.2
    /// p.7) arms it through max(), which never shortens a pain freeze — before
    /// v2.11 `frozenLeft` never exceeded N, so max() reproduces the old
    /// "refresh to N" bit for bit.
    private static func applyFreezeTick(_ next: inout EngineState, pattern p: Pattern,
                                        position: Position, frozenLeft: Int) {
        Self.setPosition(&next, p, position)
        if frozenLeft > 1 {
            next.frozen[p] = frozenLeft - 1
        } else {
            next.frozen.removeValue(forKey: p)
        }
    }

    /// One session's inputs as a single value. The restorative branch needs
    /// all five of them, and an argument-count limit is not a reason to leave
    /// one out — v2.20 needed the rating and the facts there to tell a clean
    /// appearance from a hard one (§31.2 p.1).
    private struct FeedbackInputs {
        let result: FeedbackResult
        let overrides: [Pattern: Int]
        let skipped: Set<Pattern>
        let discomfort: Set<Pattern>
    }

    /// v2.12 (spec §22.4): the restorative session under the illness lens.
    /// The counter moves, the journal is written, the comeback series breaks,
    /// the lens ticks down, freezes spend appearances — but levels, streaks
    /// and the run of "less" stand: an illness is a time for neither growth
    /// nor conclusions. The rest inputs (§21/§16) are the exception — safety
    /// outranks the gentle mode.
    private static func applyRestorativeSession(
        state: EngineState, session: Session, inputs: FeedbackInputs
    ) -> EngineState {
        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0
        next.illness = state.illness - 1
        for ex in session.exercises {
            let p = ex.pattern
            if inputs.discomfort.contains(p) {
                Self.applyDiscomfortReport(&next, state: state, pattern: p)
                continue
            }
            if inputs.skipped.contains(p) { continue }   // a skip spends no appearance
            let frozenLeft = state.freezeRemaining(p)
            if frozenLeft > 1 { next.frozen[p] = frozenLeft - 1; continue }
            if frozenLeft == 1 { next.frozen.removeValue(forKey: p); continue }
            // v2.20 (spec §31.2 p.1): an appearance under the lens spends the
            // confirmation countdown just as an ordinary one does — the lens
            // already spends `frozen` (§22.4), and separate arithmetic here
            // would mean recovery counts differently depending on the "I was
            // sick" tap. Same predicate, and the fast route stays shut under
            // the lens: a fact at or above the plan does not confirm here, it
            // only leaves the appearance clean.
            Self.spendCleanAppearance(&next, p, rating: inputs.result, fact: inputs.overrides[p], load: ex.load)
        }
        return next
    }

    /// v2.11 (spec §21.1-21.2), reworked in v2.19 (spec §30.6): taking the
    /// load off is TWO-STEP.
    ///
    /// The first report of an episode puts the pattern on the floor of its
    /// CURRENT tier — the same variation, the smallest dose it has. The work
    /// always falls (0 violations over 480 cells, 10 patterns × 48 levels),
    /// and one tap does not
    /// hand the trainee a movement they have never seen. The second report,
    /// while the episode still lives, does what v2.11 did first: the floor of
    /// the PREVIOUS tier, i.e. the change of variation §15.2 calls for. After
    /// that the level stands — "the load comes off once per episode" (§21.3)
    /// survives in substance, the descent being bounded at two steps and
    /// never reaching zero on honest reports alone. The 3 → 6 → 12 rest
    /// ladder already encodes which report this is, so no extra counter is
    /// needed. The streak resets on both steps: it belonged to the old dose.
    ///
    /// This runs under the illness lens too (§22.4) — safety outranks the
    /// gentler regime, and one tap must not land differently depending on
    /// whether the trainee happened to be ill.
    private static func applyDiscomfortReport(_ next: inout EngineState,
                                              state: EngineState, pattern p: Pattern) {
        if let episode = state.sore[p] {
            let assigned = min(episode * 2, EngineConfig.freezeCapAppearances)
            if episode == EngineConfig.freezeAppearances {   // the second report
                // v2.22 (spec §33): taking the load off is a descent, so the
                // sub-step goes with it.
                Self.setPosition(&next, p,
                                 Position(level: Level.unload(state.levels[p] ?? 0), sub: 0))
                next.failStreak[p] = 0
            } else {
                // The third report and beyond: the level stands, but keeping
                // heavier sets after "it hurts" makes no sense either.
                next.sub.removeValue(forKey: p)
            }
            next.frozen[p] = assigned
            next.sore[p] = assigned
            // v2.20 (spec §31.2 p.4): the countdown restarts, and at the NEW
            // assignment — the way back lengthens along with the rest. From
            // here assignment and countdown agree again, which is what keeps
            // the ladder readable after any number of clean appearances: one
            // field could never carry both meanings (§31.3).
            next.soreLeft[p] = assigned
        } else {
            Self.setPosition(&next, p,
                             Position(level: Level.tierFloor(state.levels[p] ?? 0), sub: 0))
            next.failStreak[p] = 0
            next.frozen[p] = EngineConfig.freezeAppearances
            next.sore[p] = EngineConfig.freezeAppearances
            next.soreLeft[p] = EngineConfig.freezeAppearances
        }
    }

    /// v2.10 (spec §20.1): the cross-credit on the pull slot. The slot is in
    /// every session, but with the bar its bookkeeping is split in two, so
    /// each branch grew at half the slot's speed and the push entered the
    /// set bands 13-16 sessions earlier. The delta that landed is repeated
    /// to the other branch, capped by ITS OWN growth cell (§15.3). Upward
    /// only: a zero or negative delta credits nothing, so a skip, a
    /// discomfort report, a hold and a freeze on the trained branch all
    /// leave the other one alone without a special case. The other branch's
    /// streak is untouched — it was not trained.
    private static func applyCrossCredit(_ next: inout EngineState, state: EngineState,
                                         session: Session, result: FeedbackResult,
                                         overrides: [Pattern: Int],
                                         discomfort: Set<Pattern>) {
        guard next.hasBar,
              let trained = session.exercises.first(where: { Pattern.pullSide.contains($0.pattern) })?.pattern
        else { return }
        let other: Pattern = trained == .pull ? .pullBar : .pull
        // The pause (spec §20.1): a branch whose last appearance you called
        // hard earns no credit until an appearance goes by without such a
        // signal. Measured without it, the level climbed to 29 whether what
        // you could hold was 6, 12 or 20 — the credit lands on days the
        // branch is not in the plan, and a targeted "less" (§19.1) aims at
        // the highest-level movement of the session, usually not this one.
        let factBelowPlan = session.exercises.first { $0.pattern == trained }
            .map { ex in (overrides[trained].map { $0 < ex.load }) ?? false } ?? false
        if result == .less || discomfort.contains(trained) || factBelowPlan {
            next.creditPaused.insert(trained)
        } else {
            next.creditPaused.remove(trained)
        }

        // v2.11 (spec §21.3, #125): the credit never grows a frozen or sore
        // receiver — "a frozen pattern cannot grow" (§15.2 p.2) extends to
        // growth by someone else's credit. The receiving branch was not in
        // this session, so its freeze and episode in `next` are exactly the
        // state's.
        // v2.22 (spec §33): the gain is measured in SUB-STEPS and the receiver
        // is credited in sub-steps by the same helper. A difference of levels
        // would read zero in two cases out of three — growth by a sub-step does
        // not move `levels` — and the credit would quietly zero itself out,
        // handing the slot back the half speed §20.1 was written to fix.
        let gained = Level.subRise(from: state.position(trained), to: next.position(trained))
        if gained > 0, !next.creditPaused.contains(other),
           next.freezeRemaining(other) == 0, next.sore[other] == nil {
            let entry = next.position(other)
            let cap = EngineConfig.maxUp(pattern: other, tier: Level.decode(entry.level).tier)
            Self.setPosition(&next, other,
                             Level.rise(level: entry.level, sub: entry.sub,
                                        by: min(gained, cap)))
        }
    }

    // Time enters the engine here, and only here (issue #98, spec §7). The two
    // functions below are the whole of the model's date awareness, and both
    // read a single number — the gap since the last workout, from seven days
    // up. Below that the engine is blind by contract: `generateSession` and
    // `applyFeedback` never see a date, which is what makes them pure and the
    // golden fixture reproducible. Training frequency is therefore an
    // app-layer concern — seven workouts in seven days are legal here, and the
    // quiet rest offer that answers them lives in `AppStore+Signals`.

    /// All patterns drop, `pullBar` included even with `hasBar == false`: a
    /// break detrains the whole body. A freeze survives it untouched — the
    /// error is asymmetric, and a couple of sessions without growth cost less
    /// than a tendon — and so does a pain episode (v2.11, spec §21.2 p.8):
    /// levels drop as usual, the confirmation stays owed. `failStreak` must
    /// reset — otherwise the first underperformance after the return would
    /// ride the old streak into a deload and drop the level twice. `counter`
    /// does not move.
    ///
    /// NOT idempotent: every call subtracts the drop again. The caller must
    /// apply it at most once per break (the app keys this on
    /// `comebackDecidedFor`).
    ///
    /// `alreadyDecayed`: the silent −1 already hit this same break, so the
    /// comeback weakens by one and the two drops do not stack. Exact even at
    /// the clamp: `max(max(L−1,0) − (drop−1), 0) == max(L − drop, 0)` for
    /// drop ≥ 2.
    ///
    /// v2.7 (spec §17.2): past the table's edge an absolute landing ceiling
    /// (`comebackLandingCeil`) — `min` composes with the alreadyDecayed
    /// weakening untouched, so the no-stacking identity holds by
    /// construction. And crossing a SET BAND snaps the rung to the band
    /// floor: preserving `L mod 8` across 40/32 made the first dose
    /// non-monotonic in the gap (90 days → 5×6, 140 days → 4×11).
    public static func applyComeback(state dirty: EngineState, gapDays rawGap: Int,
                                     alreadyDecayed: Bool = false) -> EngineState {
        // v2.13 (spec §24.1-24.2): heal the state, clamp the gap. A negative
        // gap already fell through this guard; the clamp also keeps
        // `gapDays - comebackMinGapDays` off Int.min.
        let state = dirty.sanitized()
        let gapDays = Engine.sanitizeGapDays(rawGap)
        guard gapDays >= EngineConfig.comebackMinGapDays else { return dirty }
        // v2.12 (spec §22.3): consecutive comebacks with no session between
        // deepen the drop by one each — the plan must slide faster than
        // fitness decays (A8b-9). The cap is the same table cap.
        let raw = EngineConfig.comebackBase
            + (gapDays - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays
            + state.returnRun
        let drop = min(max(raw, 2), EngineConfig.comebackMax) - (alreadyDecayed ? 1 : 0)
        let landingCeil = EngineConfig.comebackLandingCeil
            .first { gapDays >= $0.minGap }?.ceil ?? Int.max

        var next = state
        next.lessRun = 0            // v2.9: a break is not a continued run of "less"
        next.creditPaused = []      // v2.10: a break clears the strain evidence too
        // v2.22 (spec §33): a comeback is a DESCENT, and it takes the sub-steps
        // off every pattern — a break detrains the whole body, and the heavier
        // sets belonged to a dose that is gone.
        next.sub = [:]
        // v2.15 (spec §26.1): a comeback rebuilds the levels, which makes the
        // appearance window a record about DIFFERENT levels — it goes with
        // them. The silent decay (−1) barely moves the levels and keeps it.
        next.lessHist = [:]
        // v2.17 (spec §28.4): a comeback opens the limited-growth window.
        next.rampWindow = EngineConfig.rampWindowSessions
        // The weekly window is about a week that is now over.
        next.weekGain = [:]
        next.weekAgeDays = 0
        next.returnRun = state.returnRun + 1   // v2.12 (§22.3)
        for p in Pattern.allCases {
            let stored = state.levels[p] ?? 0
            // The level BEFORE the break: with alreadyDecayed the input
            // already carries the silent −1, and reading the band or the tier
            // from it would break the identity exactly at the boundaries.
            let preL = alreadyDecayed ? min(stored + 1, EngineConfig.levelMax) : stored
            let pre = Level.decode(preL)
            var landed = max(0, stored - drop)
            let post = Level.decode(landed)
            // The snap applies to the DROP's result only; the band keeps its
            // v2.7 priority, then v2.12 rep continuity on a tier crossing:
            // the same dose of reps in an easier variation, never the top of
            // the lower tier (audit finding A3-1). The ceiling below is a
            // deliberate absolute — a tier bottom by construction.
            if pre.sets != post.sets {
                landed = (landed / EngineConfig.stepsPerTier) * EngineConfig.stepsPerTier
            } else if pre.tier != post.tier {
                landed = (post.tier - 1) * EngineConfig.stepsPerTier
                    + Level.rung(tier: post.tier, reps: pre.reps)
            }
            next.levels[p] = min(landed, landingCeil)
            next.failStreak[p] = 0
        }
        return next
    }

    /// v2.7 (spec §17.3): `failStreak` resets, same as the comeback. The old
    /// "deliberately untouched" reading inverted the 13/14-day boundary at a
    /// streak of 2: a 13-day pause plus the first honest "less" rode into a
    /// deload (−5 total) while a 14-day break cost −3. `counter` does not
    /// move.
    ///
    /// NOT idempotent, same as the comeback: the app layer applies it at most
    /// once per break, keyed to the last workout's date.
    public static func applySilentDecay(state dirty: EngineState, gapDays rawGap: Int) -> EngineState {
        let state = dirty.sanitized()
        let gapDays = Engine.sanitizeGapDays(rawGap)
        guard gapDays >= EngineConfig.silentDecayGapDays,
              gapDays < EngineConfig.comebackMinGapDays else { return dirty }
        var next = state
        next.lessRun = 0            // v2.9: same as the comeback (spec §19.1)
        next.creditPaused = []      // v2.10: and so does the pause
        next.sub = [:]              // v2.22 (§33): a decay is a descent too
        // v2.12 (§22.3-22.4): the decay belongs to the same break — it is not
        // a return, so `returnRun` stands; the illness lens survives too.
        for p in Pattern.allCases {
            next.levels[p] = max(0, (state.levels[p] ?? 0) - 1)
            next.failStreak[p] = 0
        }
        return next
    }

    /// v2.12 (spec §22.4): the "I was sick" one-tap — the sixth API function.
    /// An illness shorter than seven days is invisible to the time contract
    /// (§7) by construction, so the channel is explicit. The lens makes the
    /// plan one tier easier for `illnessSessions` restorative sessions
    /// without touching the stored levels; a repeat tap tops the lens back
    /// up (a prolongation, not an escalation), and on a fresh lens the call
    /// is a no-op.
    public static func applyIllness(state dirty: EngineState) -> EngineState {
        // v2.13 (spec §24.1): the sixth entry heals its input too — the
        // reference rebuilds every field here just as it does elsewhere.
        var next = dirty.sanitized()
        next.illness = EngineConfig.illnessSessions
        return next
    }

    /// v2.15 (spec §26.1): rolls the appearance window and returns the
    /// patterns whose chronic signal fires. Every exercise of the session
    /// shifts its own mask — 1 when the session was rated an unnamed "less".
    /// A named "less" writes nothing: it is already addressed, and the signal
    /// exists for the sessions where the trainee says nothing and taps once.
    ///
    /// The branches of a split pull slot are excluded: with a bar each stands
    /// every other session, so its appearances can line up with "less" through
    /// no fault of its own — which is exactly why §20.1 gave the slot a
    /// cross-credit instead of its own feedback. The period-2 lock opened in
    /// v2.10 must not latch again.
    private static func rollChronicWindow(_ next: inout EngineState, session: Session,
                                          unnamedLess: Bool) -> Set<Pattern> {
        for ex in session.exercises {
            let shifted = (((next.lessHist[ex.pattern] ?? 0) << 1) | (unnamedLess ? 1 : 0))
                & EngineState.chronicMaskMax
            next.lessHist[ex.pattern] = shifted > 0 ? shifted : nil
        }
        let splitPullSlot = next.hasBar
        return Set(session.exercises.map(\.pattern)
            .filter { !(splitPullSlot && Pattern.pullSide.contains($0)) }
            .filter { next.chronicFires($0) })
    }

    /// v2.15 (spec §26.2, #130): the humble group landing. §17.1 caps a
    /// from-zero calibration at the NEIGHBOUR tier's top — per pattern, and
    /// half the body can go there in one session while §19.1 untangles it one
    /// −1 at a time: an overconfident novice spent about a month above his
    /// abilities (17 sessions of 24 past capacity+1, six deloads). A session
    /// that calibrated `calibrationGroup` patterns at once is a claim about
    /// the DAY, not about the body — they land at their own tier's top, the
    /// ceiling the slow tissues always had.
    private static func applyHumbleGroupLanding(_ next: inout EngineState,
                                                calibratedUp: [Pattern]) {
        guard calibratedUp.count >= EngineConfig.calibrationGroup else { return }
        for p in calibratedUp {
            // A calibration landing always carries a zero sub-step, so there is
            // nothing to descend here — but the invariant is stated explicitly.
            Self.setPosition(&next, p,
                             Position(level: min(next.levels[p] ?? 0,
                                                 EngineConfig.stepsPerTier - 1), sub: 0))
        }
    }
}
