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
    /// v2.26 (spec §37.7a): 3 → 4. The reserve for the two blocks was spent
    /// EXACTLY — 215 + 265 = 480 s = 8:00 at a five-second transition — and
    /// doubling the transition to ten seconds takes the worst composition to
    /// 540 s. So the reserve had to grow, and it grows here rather than in the
    /// app: `GetReady.swift` said so in as many words, and it was right.
    ///
    /// The price is named, not absorbed: every announced duration is one
    /// minute longer, and the reference's acceptance asserts "grew by exactly
    /// 1.0" rather than "unchanged". The PLAN is bit-for-bit v2.25's.
    public static let cooldownMin = 4
    /// Rest between sets by set band (v2.8, spec §18.2): 60 s was a constant
    /// across the whole scale, including the 4–5-set bands of tier 4 where
    /// the literature gives trained users 2–3 minutes. `restSetSec` stays as
    /// the base and the fallback.
    /// v2.25 (Ф6, spec §36.9): 1–2 sets inherit the pause of a triple instead
    /// of falling through to the shared default. Before the fix a cut handed
    /// back 60 s where band 5 asks for 120 — the pain channel made the REST
    /// SHORTER than it was before the complaint.
    public static let restSetByBand = [1: 60, 2: 60, 3: 60, 4: 90, 5: 120]
    public static let comebackMinGapDays = 14
    public static let comebackBase = 2
    public static let comebackStepDays = 21
    public static let comebackMax = 8
    public static let silentDecayGapDays = 7
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
    /// v2.25 (Ф6): and the same for the tier-4 cell — the table is spelled out
    /// whole so a future change is a change of number, not of structure.
    public static let restSetByTierBand: [Int: [Int: Int]] = [4: [1: 90, 2: 90, 3: 90]]
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
    /// v2.24 (spec §35.1): the SHARED floor on sets, not the budget's own. The
    /// old name (`budgetSetsFloor`) named an owner the floor does not have:
    /// two mechanisms cut sets — the budget §28.3 and the set-band gate §20.2 —
    /// and until v2.24 neither knew about the other. Everything that produces a
    /// set count goes through `clampSets`, so the floor survives ANY
    /// composition of them, not just one path.
    public static let setsFloor = 2
    /// v2.26 (spec §37.3): `setsFloorPain` is gone. It sat below the shared
    /// floor for the pain channel, and the audit found the default it was
    /// supposed to be an exception to was never once taken: all ten calls to
    /// `cutMax` and all seven to `effCut` passed the pain floor. The honest
    /// "hard" sweep put 3458 plans out of 18 000 below two sets — reachable
    /// without touching a handle. One floor now, and `setsFloor` is it.
    /// Sets that come back in one session (§36.3).
    public static let setsBackPerSession = 1
    /// HOW MANY APPEARANCES a returned set is held before the next one may
    /// come back. The sets axis is an order of magnitude coarser than the dose
    /// axis — a dose step is ×1.033 median and ×1.08 worst, a set coming back
    /// is ×1.500 median and ×2.00 worst, and 41 % of returns give +100 % or
    /// more. §32 rejected a +50 % dose step as a breach of "do no harm",
    /// citing ACSM 2009 ("a 2–10 % increase in load"), and rewrote the hold
    /// ladder into literals for it. The sets axis exceeded that same standard
    /// by 20–45× — and did so to the person who had only just stopped
    /// complaining of pain: weekly volume went from 60 to 162. The hold
    /// stretches the return so the dose has time to grow between additions.
    public static let setsBackHold = 2
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
                                              actual: Int, entry: Position, cap: Int,
                                              setsBackOk: Bool,
                                              calibratedUp: inout [Pattern]) -> Position {
        let oldL = entry.level, oldSub = entry.sub, oldCut = entry.cut
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
        // v2.25 (spec §36.3): the position is a TRIPLE, and the measure over
        // all three is what every ceiling counts.
        let oldOrdinal = Level.posOrd(entry)
        if actual >= ex.load && actual < ex.load + window {
            return Level.riseBy(level: oldL, sub: oldSub, cut: oldCut,
                                by: min(EngineConfig.deltaPlan, cap),
                                allowSetsBack: setsBackOk)
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
            // v2.25 (round 4b): a calibration KEEPS the cut. It ignores the
            // §15.3 ceiling on purpose — there is nothing to trust but the
            // fact — but that has no bearing on sets taken off: those were
            // taken by pain or by a descent, not by the engine not knowing.
            // Zeroing them here was the last route around "one set per
            // session" (6 cells of 552, up to ×4.13).
            return Position(level: landed, sub: 0,
                            cut: min(oldCut, Level.cutMax(level: landed,
                                                          floor: EngineConfig.setsFloor)))
        }
        // v2.25 (Ф2): "above or below" is settled by the DOSE, not by the
        // shared measure. The measure is lowered by the cut, so a shortfall
        // read as a rise: an honest "7 of 8" after a pain landing lifted the
        // plan from 2×8 to 3×8.
        let clampedFact = min(max(factL, 0), EngineConfig.levelMax)
        if Level.ordinal(level: clampedFact, sub: 0) > Level.ordinal(level: oldL, sub: oldSub) {
            // v2.25 (round 4b, P0-1): the rise goes THROUGH `riseBy`, not by
            // an absolute landing that zeroes the cut. The old form handed
            // back every taken set at once and walked around §36.3 ("no more
            // than one set per session"), because that rule lives in `riseBy`:
            // pull L8 with a cut of 2, answering an honest "did 7", showed
            // 3×15 instead of 1×6 — ×7.50 of work for one event.
            return Level.riseBy(level: oldL, sub: oldSub, cut: oldCut,
                                by: Level.riseSteps(toFact: clampedFact, from: oldOrdinal,
                                                    cap: cap),
                                allowSetsBack: setsBackOk)
        }
        // v2.14 (spec §25.3): a descent may not make the plan heavier.
        // v2.25 (round 4, S6-1): and it KEEPS the sets already taken off.
        // Zeroing them unconditionally turned "do not move at all" — which is
        // exactly what the gate returning `oldL` means — into a RISE: push_h
        // L8 after a "hard" tap went 2×6 → an honest "did 4 of 6" → 3×8, plus
        // a hundred per cent. 477 cells of 1080.
        let landed = Level.descendNoHarder(pattern: p, from: oldL, factLevel: factL,
                                           fromSub: oldSub, fromCut: oldCut)
        return Position(level: landed, sub: 0,
                        cut: min(oldCut, Level.cutMax(level: landed,
                                                      floor: EngineConfig.setsFloor)))
    }

    /// v2.9 (spec §19.1): movements the user pointed at during the workout.
    /// v2.22 (spec §33): the hold request left this list — the input was
    /// cancelled. v2.26 (spec §37.0): so did the discomfort report. ONE named
    /// signal is left, an exact number below the plan's BASE dose, and that is
    /// stated rather than implied: addressing is about who the delta reaches,
    /// not about how many ways there are to name a movement.
    private static func namedMovements(
        session: Session, overrides: [Pattern: Int]
    ) -> Set<Pattern> {
        var named: Set<Pattern> = []
        for ex in session.exercises {
            let p = ex.pattern
            if let actual = overrides[p], actual < ex.load {
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
        skipped: Set<Pattern>,
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
                guard chronic.contains(p), !skipped.contains(p) else { continue }
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
            if skipped.contains(p) || overrides[p] != nil { continue }
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
    /// v2.26 (spec §37.0): the joint-pain input is GONE, and with it the
    /// episode, the freeze and the 3 → 6 → 12 rest ladder. The audit of
    /// 23.08 found the channel broken in four independent places, and every
    /// honest way out of the state cost infinity. What replaces it is the
    /// channel that already worked better: honest numbers. A person with a
    /// capacity of one rep who logs it goes L24/tier 4 → L0/tier 1 in FOUR
    /// appearances; the tap used to strand them at L16/tier 3 indefinitely.
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
    /// The hold-this-level request (v2.6) was cancelled in v2.22 and
    /// `gapDays` moved into its place as the seventh parameter. v2.26 removes
    /// `discomfort` the same way, so `gapDays` is now the SIXTH. The arity is
    /// pinned by a test on purpose: a call written for the old signature does
    /// not fail to compile in a dynamically typed caller — it hands a set of
    /// patterns to `gapDays`, which sanitizes it to nil, and the gap signal
    /// silently disappears. That exact defect has now happened twice.
    public static func applyFeedback(
        state dirty: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides dirtyOverrides: [Pattern: Int] = [:],
        skipped: Set<Pattern> = [],
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

        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0                          // v2.12: a session breaks the series

        // v2.9 (spec §19.1): who receives the SESSION-WIDE "less".
        let named = Self.namedMovements(session: session, overrides: overrides)
        // v2.15 (spec §26.1): the appearance window. Every exercise of the
        // session shifts its own mask — 1 when the session was rated an
        // unnamed "less". A named "less" writes nothing: it is already
        // addressed, and the chronic signal exists for the sessions where the
        // trainee says nothing and taps once.
        // v2.15 (spec §26.2, #130): who calibrates from zero in THIS session.
        var calibratedUp: [Pattern] = []
        let window = Self.rollWeeklyWindow(state: state, gapDays: gapDays)
        let haveGap = window.haveGap
        var weekGain = window.gain
        next.weekAgeDays = window.ageDays
        // v2.17 (spec §28.4): the window a comeback opened is spent by sessions.
        let rampLeft = state.rampWindow
        next.rampWindow = max(0, rampLeft - 1)
        let chronic = Self.rollChronicWindow(&next, session: session,
                                            unnamedLess: result == .less && named.isEmpty)
        let lessTargets = Self.lessTargets(state: state, session: session, result: result,
                                           named: named, overrides: overrides,
                                           skipped: skipped,
                                           chronic: chronic, window: next.lessHist)
        // A named "less" does not feed the run: "it was hard, and it was this
        // one" is a statement about one movement, however often it repeats.
        next.lessRun = result == .less && named.isEmpty ? state.lessRun + 1 : 0

        for ex in session.exercises {
            let p = ex.pattern
            if skipped.contains(p) { continue }
            let oldL = state.levels[p] ?? 0
            // v2.22 (spec §33): the whole position. Everything that moves a
            // pattern up works on the PAIR — a level alone cannot describe it.
            // v2.25 (spec §36.3): on the TRIPLE. The measure `posOrd` folds
            // sub-steps and sets taken off into one integer scale — a growth
            // event is exactly +1, a step of a descent exactly −1 — so the
            // §15.3 caps, the §28.5 window and the §20.1 cross-credit stay the
            // code and the arithmetic they were.
            let oldSub = state.sub[p] ?? 0
            let oldCut = state.cutOf(p)
            let entry = Position(level: oldL, sub: oldSub, cut: oldCut)
            // The hold on a returning set: while it ticks, growth goes into
            // the dose (§36.3, round 6 fix 1).
            let setsBackOk = (state.setsHold[p] ?? 0) == 0
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
                    pattern: p, exercise: ex, actual: actual, entry: entry,
                    cap: cap, setsBackOk: setsBackOk, calibratedUp: &calibratedUp)
            } else {
                (position, wantedDown) = Self.positionFromRating(
                    pattern: p, result: result, from: entry,
                    limits: RatingLimits(
                        // v2.26 (spec §37.3): ONE floor. The episode-aware
                        // exception is gone with the episode, and with it the
                        // leak that let the pain floor reach every internal
                        // call — the honest-"hard" sweep put 3458 plans out of
                        // 18 000 below two sets, and now puts none.
                        cap: cap, rampLeft: rampLeft,
                        descentFloor: EngineConfig.setsFloor,
                        setsBackOk: setsBackOk),
                    aim: RatingAim(targets: lessTargets, chronic: chronic))
            }
            position = Position(level: min(max(position.level, 0), EngineConfig.levelMax),
                                sub: position.sub, cut: position.cut)
            let newL = position.level

            position = Self.tickStreak(&next, pattern: p, entryStreak: state.failStreak[p] ?? 0,
                                       landed: position, entry: entry,
                                       wentDown: factPath ? newL < oldL : wantedDown,
                                       deloadFrom: factPath ? newL : oldL)
            Self.tickSetsHold(&next, p, entryHold: state.setsHold[p] ?? 0,
                              gaveBack: position.cut < oldCut)
            Self.setPosition(&next, p, position)
        }

        Self.applyHumbleGroupLanding(&next, calibratedUp: calibratedUp)
        Self.applyCrossCredit(&next, state: state, session: session, result: result,
                              overrides: overrides)
        // v2.25 (spec §36.8): remember what the person SAW and at which
        // position. The position is the ENTRY one — the plan was shown before
        // any of this feedback existed.
        Self.rememberShownPlan(&next, entry: state, session: session)
        // v2.17 (spec §28.5): the weekly ceiling is applied ONCE, after every
        // rise this session — the cross-credit included, or it would walk
        // around the budget: with a bar the branch grows on credit every other
        // session, and the measurement gave 25 levels over 28 daily sessions.
        if haveGap { Self.applyWeeklyCeiling(&next, state: state, weekGain: &weekGain) }
        next.weekGain = weekGain
        return next
    }

    /// v2.17 (spec §28.5) · v2.19 (spec §30.8): how old the weekly window is
    /// at the start of this session, and what is left of its budget.
    ///
    /// No signal, no rule — with `nil` the engine behaves exactly as it did
    /// before v2.17, which is what made the rollout safe. The floor replaces
    /// the gap from below rather than adding to it: a session that reports no
    /// elapsed time still ages the window, and a correct app layer is never
    /// double-counted.
    ///
    /// Split out of `applyFeedback` in v2.25 for the lint's function-length
    /// ceiling; the arithmetic is unchanged.
    private static func rollWeeklyWindow(
        state: EngineState, gapDays: Double?
    ) -> (haveGap: Bool, gain: [Pattern: Int], ageDays: Double) {
        let haveGap = gapDays?.isFinite ?? false
        let agedDays = haveGap
            ? state.weekAgeDays + max(EngineConfig.minSessionAgeDays, gapDays ?? 0)
            : 0
        let expired = agedDays >= Double(EngineConfig.weeklyWindowDays)
        let fresh = !haveGap || expired
        return (haveGap, fresh ? [:] : state.weekGain, fresh ? 0 : agedDays)
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
            let landed = next.position(p)
            // v2.25 (spec §36.3): the rise is measured on the SHARED scale — a
            // growth event spent on giving a set back carries credit just like
            // one spent on the dose.
            let rise = max(0, Level.posOrd(landed) - Level.posOrd(entry))
            guard rise > 0 else { continue }
            let budget = EngineConfig.isSlowTissue(p) || Pattern.pullSide.contains(p)
                ? EngineConfig.weeklyRiseSlow : EngineConfig.weeklyRiseFast
            let spent = weekGain[p] ?? 0
            let granted = min(rise, max(0, budget - spent))
            // v2.25 (round 6, fix 1): rebuilding the position here used to walk
            // around the hold and hand back a set the hold was keeping — the
            // very "one branch of two" class the local sweep exists to catch.
            // The rebuild does not decide again whether a set comes back: it
            // only trims the growth steps, so it repeats what the main loop
            // decided — a set comes back exactly when it already came back.
            Self.setPosition(&next, p,
                             Level.riseBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                                          by: granted,
                                          allowSetsBack: landed.cut < entry.cut))
            if granted > 0 { weekGain[p] = spent + granted }
        }
    }

    /// v2.25 (round 6, fix 1): a set came back — arm the hold; otherwise this
    /// appearance spends it. It ticks by APPEARANCES of the pattern, not by
    /// the calendar, and only on the ordinary path: a freeze and a waiting
    /// episode leave the loop earlier, and neither is a chance to grow.
    static func tickSetsHold(_ next: inout EngineState, _ p: Pattern,
                             entryHold: Int, gaveBack: Bool) {
        guard !gaveBack else {
            next.setsHold[p] = EngineConfig.setsBackHold
            return
        }
        let held = entryHold - 1
        if held > 0 { next.setsHold[p] = held } else { next.setsHold.removeValue(forKey: p) }
    }

    /// v2.25 (spec §36.8): the work a session showed, in the units of the
    /// measure — sets × dose × sides, sub-steps included. The same number
    /// `Level.work` computes, but read off an already-assembled plan.
    static func exerciseWork(_ ex: SessionExercise) -> Int {
        ex.plannedVolume * (ex.perSide ? 2 : 1)
    }

    /// The shown-plan memory: what was on screen, and the position it was
    /// shown at. One writer for the automatic path and for `recordShown`, so
    /// the two can never disagree about what "shown" means.
    static func rememberShownPlan(_ next: inout EngineState, entry: EngineState,
                                  session: Session) {
        for ex in session.exercises {
            let p = ex.pattern
            next.shownWork[p] = Self.exerciseWork(ex)
            next.shownOrd[p] = Level.posOrd(entry.position(p))
        }
    }

    /// v2.25 (round 6, fix 7): recording a shown plan WITHOUT any feedback.
    /// The app layer owns the state and can call this right after showing the
    /// plan — and then the "a descent never adds load" invariant holds against
    /// a plan the person merely saw and did not train, not only between
    /// completed sessions.
    ///
    /// ACCEPTED until the app layer calls it (§36.8): memory is written by a
    /// COMPLETED session, so against a merely-seen plan a rise is possible.
    public static func recordShown(state dirty: EngineState, session: Session) -> EngineState {
        var next = dirty.sanitized()
        Self.rememberShownPlan(&next, entry: next, session: session)
        return next
    }

    /// v2.22 (spec §33): writing a position. Sparseness is part of the
    /// contract: a zero is never stored, so a state that descended is
    /// byte-identical to one that never carried a sub-step at all.
    static func setPosition(_ next: inout EngineState, _ p: Pattern, _ position: Position) {
        next.levels[p] = position.level
        // v2.25 (Ф5): a sub-step may not ask for more sets than the cut leaves.
        // Without this the measure saw the upper sub-steps and the plan did
        // not, and 1960 steps of a descent out of 5600 moved the plan not at
        // all: every third tap wasted, and on exactly the person who had
        // already had a set taken away.
        let cut = Level.effCut(level: position.level, cut: position.cut,
                               floor: EngineConfig.setsFloor)
        let room = max(0, Level.decode(position.level).sets - cut)
        let sub = Level.effectiveSub(level: position.level, sub: position.sub, sets: room)
        if sub > 0 { next.sub[p] = sub } else { next.sub.removeValue(forKey: p) }
        // v2.25 (§36.1): sparseness is part of the contract here too. What is
        // stored is the value the caller passed, exactly as the reference
        // stores it — every caller hands over an already-clamped cut, and the
        // sanitizer heals anything that ever is not on the next read.
        if position.cut > 0 { next.cut[p] = position.cut } else { next.cut.removeValue(forKey: p) }
    }

    /// v2.10 (spec §20.1): the cross-credit on the pull slot. The slot is in
    /// every session, but with the bar its bookkeeping is split in two, so
    /// each branch grew at half the slot's speed and the push entered the
    /// set bands 13-16 sessions earlier. The delta that landed is repeated
    /// to the other branch, capped by ITS OWN growth cell (§15.3). Upward
    /// only: a zero or negative delta credits nothing, so a skip, a
    /// an exact fact below the plan on the trained branch all
    /// leave the other one alone without a special case. The other branch's
    /// streak is untouched — it was not trained.
    private static func applyCrossCredit(_ next: inout EngineState, state: EngineState,
                                         session: Session, result: FeedbackResult,
                                         overrides: [Pattern: Int],
                                         ) {
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
        if result == .less || factBelowPlan {
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
        // v2.25 (spec §36.3): the gain is measured on the shared scale, or the
        // credit would zero itself out for anyone recovering from a cut.
        let gained = max(0, Level.posOrd(next.position(trained))
                         - Level.posOrd(state.position(trained)))
        if gained > 0, !next.creditPaused.contains(other) {
            let entry = next.position(other)
            let cap = EngineConfig.maxUp(pattern: other, tier: Level.decode(entry.level).tier)
            // v2.25 (round 6, fix 1): the cross-credit respects the hold too.
            Self.setPosition(&next, other,
                             Level.riseBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                                          by: min(gained, cap),
                                          allowSetsBack: (next.setsHold[other] ?? 0) == 0))
        }
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
            // v2.25 (local sweep, H2): the humble group landing KEEPS the cut
            // too. It was the last of the position-writing sites where it was
            // wiped unconditionally — and the one place the round-4b fix did
            // not reach: exactly the "one branch of two" class the skeptics
            // found three times.
            let capped = min(next.levels[p] ?? 0, EngineConfig.stepsPerTier - 1)
            Self.setPosition(&next, p, Position(
                level: capped, sub: 0,
                cut: min(next.cutOf(p), Level.cutMax(level: capped,
                                                     floor: EngineConfig.setsFloor))))
        }
    }
}
