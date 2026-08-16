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
    public static let holdStepSec = 5
    public static let setsBase = 3
    public static let setsMax = 5
    public static let restSetSec = 60
    public static let restExerciseSec = 60
    public static let tempoSecPerRep = 2.5
    public static let patternsPerSession = 6
    public static let rotationStep = 3
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
    /// How many of a pattern's next APPEARANCES stay frozen after either of
    /// the inputs that arm the rest: a discomfort report (v2.5) or a
    /// hold-this-level request, `pinned` (v2.6). Counted in appearances, not
    /// sessions: a rotating pattern shows up in about five sessions out of
    /// eight, so "three sessions" would make the actual rest unpredictable.
    /// Three ≈ a calendar week.
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
    public static let repStart = [1: 8, 2: 6, 3: 5, 4: 4]
    public static let holdStart = [1: 20, 2: 15, 3: 15, 4: 10]
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

// MARK: - State

public struct EngineState: Codable, Equatable, Sendable {
    public var counter: Int
    public var levels: [Pattern: Int]
    public var failStreak: [Pattern: Int]
    public var hasBar: Bool
    /// Appearances a pattern still has to sit out after discomfort was
    /// reported on it. Only positive counters are kept, so an empty map is
    /// "nothing is frozen" — and a state file written before this existed
    /// decodes to exactly that.
    public var frozen: [Pattern: Int]
    /// How many "less" ratings in a row named no movement (spec §19.1). The
    /// third such rating hands the delta back to the whole session — a run of
    /// unnamed "less" is a statement about the plan, not about one exercise.
    public var lessRun: Int
    /// Branches of the pull slot the cross-credit is paused for, because the
    /// last session they appeared in was reported as hard (spec §20.1). The
    /// credit lands on sessions the branch is not in — the ones you cannot
    /// answer — so without this the level runs away from what you can do.
    public var creditPaused: Set<Pattern>
    /// v2.11 (spec §21.2): live pain episodes. The value is the last freeze
    /// assignment made by this episode (the 3 → 6 → 12 ladder). An episode
    /// outlives its freeze counter: once the counter runs out the pattern
    /// waits — growth stays clamped until an explicit fact at or above the
    /// plan confirms the pain settled. Empty map = no episodes, so a state
    /// file written before this existed decodes to exactly that.
    public var sore: [Pattern: Int]
    /// v2.12 (spec §22.3): comebacks applied in a row with no completed
    /// session between them. Each one past the first deepens the drop by one
    /// — the plan must slide faster than fitness decays, or every return in
    /// a "come back once, vanish a month" series is infeasible.
    public var returnRun: Int
    /// v2.12 (spec §22.4): sessions left under the "I was sick" lens — the
    /// plan is one tier easier, the stored levels stand.
    public var illness: Int

    // Spelled out (same names the compiler would synthesize) so that
    // decodeLenient can reference the type — synthesized CodingKeys are only
    // visible inside init(from:)/encode(to:). The wire format is unchanged.
    private enum CodingKeys: String, CodingKey {
        case counter, levels, failStreak, hasBar, frozen, lessRun, creditPaused, sore,
             returnRun, illness
    }

    public init(counter: Int, levels: [Pattern: Int],
                failStreak: [Pattern: Int], hasBar: Bool = false,
                frozen: [Pattern: Int] = [:], lessRun: Int = 0,
                creditPaused: Set<Pattern> = [], sore: [Pattern: Int] = [:],
                returnRun: Int = 0, illness: Int = 0) {
        self.counter = counter
        self.levels = levels
        self.failStreak = failStreak
        self.hasBar = hasBar
        self.frozen = frozen
        self.lessRun = lessRun
        self.creditPaused = creditPaused
        self.sore = sore
        self.returnRun = returnRun
        self.illness = illness
    }

    /// Lenient in both directions: files written before hasBar/pull_bar
    /// existed get the defaults, and entries for unknown patterns (a file
    /// written by a future version, opened after a downgrade) are dropped
    /// instead of failing the whole decode and losing the user's history.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A corrupt or hand-edited file must not feed a negative counter into
        // the rotation — it would index out of bounds in generateSession.
        counter = max(0, try c.decode(Int.self, forKey: .counter))
        var lv = try Self.decodeLenient(c, forKey: .levels)
        var fs = try Self.decodeLenient(c, forKey: .failStreak)
        for p in Pattern.allCases {
            if lv[p] == nil { lv[p] = 0 }
            if fs[p] == nil { fs[p] = 0 }
        }
        levels = lv
        failStreak = fs
        hasBar = try c.decodeIfPresent(Bool.self, forKey: .hasBar) ?? false
        // Additive: absent in every file written before the discomfort input,
        // and zero counters are never written, so this stays empty until a
        // pattern is actually frozen.
        frozen = c.contains(.frozen)
            ? try Self.decodeLenient(c, forKey: .frozen).filter { $0.value > 0 }
            : [:]
        // Additive, same shape as `frozen`: absent in every file written
        // before v2.9, and a hand-edited negative can only mean garbage.
        lessRun = max(0, try c.decodeIfPresent(Int.self, forKey: .lessRun) ?? 0)
        // Additive: absent before v2.10, and unknown patterns are dropped the
        // same way the level maps drop them.
        creditPaused = Set((try c.decodeIfPresent([String].self, forKey: .creditPaused) ?? [])
            .compactMap(Pattern.init(rawValue:)))
        // Additive, sanitized as the reference does (§21.4): only positive
        // entries survive, values are clamped to the ladder's ceiling.
        sore = c.contains(.sore)
            ? try Self.decodeLenient(c, forKey: .sore)
                .filter { $0.value >= 1 }
                .mapValues { min($0, EngineConfig.freezeCapAppearances) }
            : [:]
        // Additive (v2.12, §22.3-22.4), garbage sanitized as the reference does.
        returnRun = max(0, try c.decodeIfPresent(Int.self, forKey: .returnRun) ?? 0)
        illness = min(max(try c.decodeIfPresent(Int.self, forKey: .illness) ?? 0, 0),
                      EngineConfig.illnessSessions)
    }

    /// Manual decode of the exact wire format Swift synthesizes for a
    /// [Pattern: Int]: an UNKEYED array alternating [rawValue, count, ...]
    /// (see the warning on Pattern). The encode side stays synthesized — the
    /// format is byte-compatible and pinned by
    /// testLegacyStateDecodesWithBarDefaults.
    private static func decodeLenient(
        _ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws -> [Pattern: Int] {
        var uc = try c.nestedUnkeyedContainer(forKey: key)
        var out: [Pattern: Int] = [:]
        while !uc.isAtEnd {
            let raw = try uc.decode(String.self)
            let count = try uc.decode(Int.self)   // a malformed pair is still a real error
            if let p = Pattern(rawValue: raw) { out[p] = count }
        }
        return out
    }

    public static var initial: EngineState {
        EngineState(
            counter: 0,
            levels: Dictionary(uniqueKeysWithValues: Pattern.allCases.map { ($0, 0) }),
            failStreak: Dictionary(uniqueKeysWithValues: Pattern.allCases.map { ($0, 0) })
        )
    }

    /// Appearances left before this pattern may grow again; 0 = not frozen.
    public func freezeRemaining(_ pattern: Pattern) -> Int { frozen[pattern] ?? 0 }

    public var frozenPatterns: Set<Pattern> { Set(frozen.filter { $0.value > 0 }.keys) }
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

public enum Level {
    public static func decode(_ level: Int) -> LevelDecoded {
        let l = min(max(level, 0), EngineConfig.levelMax)
        let band = l / EngineConfig.stepsPerTier   // 0...5
        let step = l % EngineConfig.stepsPerTier
        let tier = min(EngineConfig.tiers, 1 + band)
        return LevelDecoded(
            tier: tier,
            sets: EngineConfig.setsBase + max(0, band - (EngineConfig.tiers - 1)),
            reps: (EngineConfig.repStart[tier] ?? EngineConfig.repMin) + step,
            hold: (EngineConfig.holdStart[tier] ?? EngineConfig.holdMin)
                + step * EngineConfig.holdStepSec
        )
    }

    /// v2.11 (spec §21.1): where a pain report lands — the bottom of the
    /// previous tier. A change of variation, not fewer reps of the same one:
    /// "take the load off, don't trim it" (§15.2). The set bands are tier 4
    /// by encoding, so they too land at the bottom of tier 3.
    public static func unload(_ level: Int) -> Int {
        let tier = decode(level).tier
        return max(0, (tier - 2) * EngineConfig.stepsPerTier)
    }

    /// v2.12 (spec §22.1/§22.4): the rung of a tier that carries a given rep
    /// dose — rep continuity. A descent into an easier variation keeps the
    /// NUMBER of reps, not the mod-8 rung: repStart grows down the tiers, so
    /// keeping the rung landed on the top of the lower tier with a higher
    /// dose (audit finding A3-1).
    static func rung(tier: Int, reps: Int) -> Int {
        min(max(reps - (EngineConfig.repStart[tier] ?? EngineConfig.repMin), 0),
            EngineConfig.stepsPerTier - 1)
    }

    /// v2.12 (spec §22.4): the "I was sick" lens — the same level seen one
    /// tier easier. Tier 1 stays itself; the set bands are tier 4 by encoding
    /// and ease into tier 3 on base sets. Stored levels never change — this
    /// builds the plan's VIEW.
    public static func eased(_ level: Int) -> Int {
        let s = min(max(level, 0), EngineConfig.levelMax)
        let d = decode(s)
        if d.tier <= 1 { return s }
        let t = d.tier - 1
        return (t - 1) * EngineConfig.stepsPerTier + rung(tier: t, reps: d.reps)
    }

    /// Level from an actual value (reps or seconds) given the planned tier and
    /// sets. Tier 4 spans three set bands, so the base depends on sets; the
    /// unit comes from the (pattern, tier) library record.
    public static func fromActual(pattern: Pattern, tier: Int, sets: Int, actual: Int) -> Int {
        let lib = ExerciseLibrary.entry(for: pattern)
        let step: Int
        switch lib.unit(forTier: tier) {
        case .reps:
            step = actual - (EngineConfig.repStart[tier] ?? EngineConfig.repMin)
        case .hold:
            let start = EngineConfig.holdStart[tier] ?? EngineConfig.holdMin
            step = Int((Double(actual - start) / Double(EngineConfig.holdStepSec)).rounded())
        }
        let base = sets <= EngineConfig.setsBase
            ? (tier - 1) * EngineConfig.stepsPerTier
            : (EngineConfig.tiers + sets - EngineConfig.setsBase - 1) * EngineConfig.stepsPerTier
        return min(max(base + step, 0), EngineConfig.levelMax)
    }
}

// MARK: - Session

public enum LoadUnit: String, Codable, Sendable {
    case reps, hold
}

public struct SessionExercise: Codable, Equatable, Identifiable, Sendable {
    public var id: Pattern { pattern }
    public let pattern: Pattern
    public let name: String
    public let tier: Int
    public let unit: LoadUnit
    public let load: Int          // reps or seconds; per side if perSide
    public let perSide: Bool
    public let sets: Int
    public let restSetSec: Int
    public let restExerciseSec: Int

    /// "3×12", "3×10 per side", "3×40 sec" — localized via the core catalog.
    public var display: String {
        let side = perSide ? " " + String(localized: "per side", bundle: .module) : ""
        switch unit {
        case .reps: return "\(sets)×\(load)\(side)"
        case .hold: return "\(sets)×\(load) " + String(localized: "sec", bundle: .module) + side
        }
    }
}

public struct Session: Codable, Equatable, Sendable {
    public let sessionNumber: Int          // counter + 1
    public let warmupMin: Int
    public let cooldownMin: Int
    public let exercises: [SessionExercise]
    public let estimatedTotalMin: Double
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
    private static let rotating: [Pattern] = Pattern.ordered.filter { $0 != .pull }

    /// The first movement of the rotation window for a counter — the anchor
    /// of the short workout. The window shifts by 3 over 8 rotating patterns,
    /// so over any 8 consecutive sessions the anchor visits all 8; the short
    /// workout depends on that property.
    public static func rotationAnchor(counter: Int) -> Pattern {
        let n = rotating.count
        let start = (((counter * EngineConfig.rotationStep) % n) + n) % n
        return rotating[start]
    }

    public static func estimatedMin(exercises: [SessionExercise]) -> Double {
        var workSec = 0.0
        for ex in exercises {
            let sides = ex.perSide ? 2 : 1
            let workPerSet: Double = ex.unit == .reps
                ? Double(ex.load * sides) * EngineConfig.tempoSecPerRep
                : Double(ex.load * sides)
            workSec += Double(ex.sets) * workPerSet
                + Double((ex.sets - 1) * ex.restSetSec)
                + Double(ex.restExerciseSec)
        }
        let totalSec = Double(EngineConfig.warmupMin * 60) + workSec
            + Double(EngineConfig.cooldownMin * 60)
        // Round to 0.1 min — as in the reference (toFixed(1)).
        return (totalSec / 60 * 10).rounded() / 10
    }

    /// A pure function: the only input is the state.
    public static func generateSession(_ state: EngineState) -> Session {
        let n = rotating.count
        // Nonnegative modulo: Swift's % is a remainder and goes negative with
        // a negative counter, which would index out of bounds below.
        let start = (((state.counter * EngineConfig.rotationStep) % n) + n) % n
        let five = (0..<(EngineConfig.patternsPerSession - 1)).map {
            rotating[(start + $0) % n]
        }
        let chosen = Set([Pattern.pull] + five)
        let useBar = state.hasBar && state.counter % 2 == 1
        let patterns = Pattern.ordered.filter { chosen.contains($0) } // ordering follows Pattern.ordered
            .map { $0 == .pull && useBar ? Pattern.pullBar : $0 }

        // v2.12 (spec §22.4): under the "I was sick" lens every level is seen
        // one tier easier; the stored levels never change.
        let eased = state.illness > 0
        func viewLevel(_ p: Pattern) -> Int {
            let level = state.levels[p] ?? 0
            return eased ? Level.eased(level) : level
        }

        // v2.10 (spec §20.2): the pull slot's set band caps the push of the same
        // session. With the bar the pull enters the bands 13-16 sessions after
        // the push, and those windows are exactly where the balance fell to
        // 0.60. The PLAN is clamped, not the state: the push level keeps
        // growing and gets its sets back the moment the pull catches up.
        let pullSets = patterns.first { Pattern.pullSide.contains($0) }
            .map { Level.decode(viewLevel($0)).sets } ?? EngineConfig.setsMax

        let exercises: [SessionExercise] = patterns.map { p in
            let lib = ExerciseLibrary.entry(for: p)
            let d = Level.decode(viewLevel(p))
            let variation = lib.variations[d.tier - 1]
            let unit = lib.unit(forTier: d.tier)
            let load = unit == .reps ? d.reps : d.hold
            let sets = Pattern.pushSide.contains(p) ? min(d.sets, pullSets) : d.sets

            return SessionExercise(
                pattern: p, name: variation.name, tier: d.tier,
                unit: unit, load: load, perSide: variation.unilateral,
                sets: sets,
                // v2.8 (spec §18.2): the rest between sets follows the set
                // band — the field is per-exercise, so the timer needs no
                // change.
                restSetSec: EngineConfig.restSetByBand[sets] ?? EngineConfig.restSetSec,
                restExerciseSec: EngineConfig.restExerciseSec
            )
        }

        let totalMin = estimatedMin(exercises: exercises)

        return Session(
            sessionNumber: state.counter + 1,
            warmupMin: EngineConfig.warmupMin,
            cooldownMin: EngineConfig.cooldownMin,
            exercises: exercises,
            estimatedTotalMin: totalMin
        )
    }

    /// v2.9 (spec §19.1): movements the user pointed at during the workout —
    /// an exact number below the plan, a discomfort report, a hold request.
    private static func namedMovements(
        session: Session, overrides: [Pattern: Int],
        discomfort: Set<Pattern>, pinned: Set<Pattern>
    ) -> Set<Pattern> {
        var named: Set<Pattern> = []
        for ex in session.exercises {
            let p = ex.pattern
            if discomfort.contains(p) || pinned.contains(p) { named.insert(p) }
            else if let actual = overrides[p], actual < ex.load { named.insert(p) }
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
        skipped: Set<Pattern>, discomfort: Set<Pattern>
    ) -> Set<Pattern>? {
        guard result == .less, state.lessRun < EngineConfig.lessRunToGlobal else { return nil }
        guard named.isEmpty else { return named }
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
    /// `discomfort` is the joint-pain input (reworked in v2.11, spec §21):
    /// the session is voided for the pattern, the first report of an episode
    /// takes the load off — the level lands at `Level.unload`, the streak
    /// resets — and the pattern is frozen with the episode marked in `sore`.
    /// The freeze expires into WAITING, not into growth: taps keep clamping
    /// until an explicit fact at or above the plan confirms recovery. A
    /// repeat report doubles the rest up the 3 → 6 → 12 ladder and never
    /// drops the level twice.
    ///
    /// `pinned` is the hold-this-level request (v2.6), the second and milder
    /// way into the same freeze. The session is processed, not voided: the
    /// rating applies, a fact applies and may still take the level DOWN — but
    /// growth clamps to the old level, the streak neither grows nor resets,
    /// and the pattern is then frozen. A pin expires into growth as before —
    /// a request is not an injury — and never shortens a pain freeze. The
    /// v2.6 identity discomfort ≡ pinned + skipped is superseded (§21.2):
    /// discomfort = pinned + skipped + unload + a confirmation gate.
    public static func applyFeedback(
        state: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides: [Pattern: Int] = [:],
        skipped: Set<Pattern> = [],
        discomfort: Set<Pattern> = [],
        pinned: Set<Pattern> = []
    ) -> EngineState {
        guard session.sessionNumber == state.counter + 1 else { return state }

        // v2.12 (spec §22.4): a session under the illness lens is restorative
        // — levels, streaks and the run of "less" stand.
        if state.illness > 0 {
            return Self.applyRestorativeSession(state: state, session: session,
                                                skipped: skipped,
                                                discomfort: discomfort, pinned: pinned)
        }

        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0                          // v2.12: a session breaks the series

        // v2.9 (spec §19.1): who receives the SESSION-WIDE "less".
        let named = Self.namedMovements(session: session, overrides: overrides,
                                        discomfort: discomfort, pinned: pinned)
        let lessTargets = Self.lessTargets(state: state, session: session, result: result,
                                           named: named, overrides: overrides,
                                           skipped: skipped, discomfort: discomfort)
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
            if skipped.contains(p) {
                // A pin still arms the rest through a skip — the two effects
                // are orthogonal, which is why pinned + skipped behaves
                // exactly as discomfort does.
                if pinned.contains(p) { next.frozen[p] = EngineConfig.freezeAppearances }
                continue
            }
            // "Frozen when this session started" — read from `state`, never
            // from `next`: a pin writes `next.frozen` for this very pattern
            // below, and reading the fresh value would consume the reporting
            // appearance. The reference reads from its `state` the same way.
            let frozenLeft = state.freezeRemaining(p)
            let oldL = state.levels[p] ?? 0
            // The tier is read from the level before the update, not from the
            // session — same thing today, and the rule stays true if a session
            // ever outlives the state it was generated from.
            let cap = EngineConfig.maxUp(pattern: p, tier: Level.decode(oldL).tier)
            var newL: Int

            if let actual = overrides[p] {
                let factL = Level.fromActual(pattern: p, tier: ex.tier,
                                             sets: ex.sets, actual: actual)
                // Calibration: from a zero level the per-session cap does not
                // apply — but the reps→level inversion is only valid one tier
                // out (v2.7, spec §17.1): the result is bounded by the
                // neighboring tier's ceiling, slow tissues by tier 1's.
                let zeroCeil = EngineConfig.isSlowTissue(p)
                    ? EngineConfig.stepsPerTier - 1
                    : 2 * EngineConfig.stepsPerTier - 1
                // v2.8 (spec §18.1): a fact EXACTLY equal to the plan steps
                // like "on plan" — the diligent logger must not stand still
                // where a tap moves. Compared against the plan's load, not
                // the inverted level: fromActual clamps at zero and would
                // read "below plan" as "equal to plan".
                if actual == ex.load {
                    newL = min(oldL + EngineConfig.deltaPlan, oldL + cap)
                } else {
                    newL = oldL == 0
                        ? min(max(factL, 0), zeroCeil)
                        : min(max(factL, 0), oldL + cap)
                }
            } else {
                // "More" runs through the same ceiling; downward moves never do.
                // v2.9 (§19.1): a targeted "less" reaches its aim only; every
                // other movement holds — holding is not underperforming.
                let sessionDelta: Int
                if let targets = lessTargets {
                    sessionDelta = targets.contains(p) ? EngineConfig.deltaLess : 0
                } else {
                    sessionDelta = result.delta
                }
                newL = min(oldL + sessionDelta, oldL + cap)
            }
            newL = min(max(newL, 0), EngineConfig.levelMax)

            // A frozen pattern keeps its place in the plan at its current
            // level but cannot grow; a fact may still take it DOWN — the
            // athlete's honesty is never overridden. The streak neither grows
            // nor resets, so a deload cannot fire on top of a freeze. A pin
            // runs through the same arithmetic, then arms the rest AFTER the
            // level update: the reporting appearance is never spent. v2.11
            // (spec §21.2 p.7): a pin arms the rest through max() and never
            // shortens a pain freeze — before v2.11 frozenLeft never exceeded
            // N, so max() reproduces the old "refresh to N" bit for bit.
            if frozenLeft > 0 || pinned.contains(p) {
                next.levels[p] = min(newL, oldL)
                if pinned.contains(p) {
                    next.frozen[p] = max(frozenLeft, EngineConfig.freezeAppearances)
                } else if frozenLeft > 1 {
                    next.frozen[p] = frozenLeft - 1
                } else {
                    next.frozen.removeValue(forKey: p)
                }
                continue
            }

            // v2.11 (spec §21.2 p.4-5): the pain freeze ran out but the
            // episode lives — the pattern waits, indefinitely: growth clamps,
            // a fact may still go down, the streak stands. Only an explicit
            // fact at or above the session's plan confirms recovery, and that
            // same fact resumes growth — through the ordinary cap, without
            // the zero-level calibration exception: a sore pattern at zero is
            // unloaded history, not a blank slate.
            if state.sore[p] != nil {
                if let actual = overrides[p], actual >= ex.load {
                    next.sore.removeValue(forKey: p)
                    if actual == ex.load {
                        newL = min(oldL + EngineConfig.deltaPlan, oldL + cap)
                    } else {
                        let factL = Level.fromActual(pattern: p, tier: ex.tier,
                                                     sets: ex.sets, actual: actual)
                        newL = min(max(factL, 0), oldL + cap)
                    }
                    newL = min(max(newL, 0), EngineConfig.levelMax)
                } else {
                    next.levels[p] = min(newL, oldL)
                    continue
                }
            }

            if newL < oldL {
                let streak = (state.failStreak[p] ?? 0) + 1
                if streak >= EngineConfig.failsToDeload {
                    newL = min(max(newL - EngineConfig.deloadDrop, 0), EngineConfig.levelMax)
                    next.failStreak[p] = 0
                } else {
                    next.failStreak[p] = streak
                }
            } else {
                next.failStreak[p] = 0
            }
            next.levels[p] = newL
        }

        Self.applyCrossCredit(&next, state: state, session: session, result: result,
                              overrides: overrides, discomfort: discomfort, pinned: pinned)
        return next
    }

    /// v2.12 (spec §22.4): the restorative session under the illness lens.
    /// The counter moves, the journal is written, the comeback series breaks,
    /// the lens ticks down, freezes spend appearances — but levels, streaks
    /// and the run of "less" stand: an illness is a time for neither growth
    /// nor conclusions. The rest inputs (§21/§16) are the exception — safety
    /// outranks the gentle mode.
    private static func applyRestorativeSession(
        state: EngineState, session: Session, skipped: Set<Pattern>,
        discomfort: Set<Pattern>, pinned: Set<Pattern>
    ) -> EngineState {
        var next = state
        next.counter = state.counter + 1
        next.returnRun = 0
        next.illness = state.illness - 1
        for ex in session.exercises {
            let p = ex.pattern
            if discomfort.contains(p) {
                Self.applyDiscomfortReport(&next, state: state, pattern: p)
                continue
            }
            if skipped.contains(p) {
                if pinned.contains(p) {
                    next.frozen[p] = max(state.freezeRemaining(p),
                                         EngineConfig.freezeAppearances)
                }
                continue                            // a skip spends no appearance
            }
            let frozenLeft = state.freezeRemaining(p)
            if pinned.contains(p) {
                next.frozen[p] = max(frozenLeft, EngineConfig.freezeAppearances)
            } else if frozenLeft > 1 {
                next.frozen[p] = frozenLeft - 1
            } else if frozenLeft == 1 {
                next.frozen.removeValue(forKey: p)
            }
        }
        return next
    }

    /// v2.11 (spec §21.1-21.2): the first report of an episode takes the load
    /// off — the level lands at the bottom of the previous tier
    /// (`Level.unload`), the streak resets, the episode is marked in `sore`.
    /// A repeat report while the episode lives leaves the level alone and
    /// doubles the rest assignment up the 3 → 6 → 12 ladder.
    private static func applyDiscomfortReport(_ next: inout EngineState,
                                              state: EngineState, pattern p: Pattern) {
        if let episode = state.sore[p] {
            let assigned = min(episode * 2, EngineConfig.freezeCapAppearances)
            next.frozen[p] = assigned
            next.sore[p] = assigned
        } else {
            next.levels[p] = Level.unload(state.levels[p] ?? 0)
            next.failStreak[p] = 0
            next.frozen[p] = EngineConfig.freezeAppearances
            next.sore[p] = EngineConfig.freezeAppearances
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
                                         discomfort: Set<Pattern>, pinned: Set<Pattern>) {
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
        if result == .less || discomfort.contains(trained) || pinned.contains(trained)
            || factBelowPlan {
            next.creditPaused.insert(trained)
        } else {
            next.creditPaused.remove(trained)
        }

        // v2.11 (spec §21.3, #125): the credit never grows a frozen or sore
        // receiver — "a frozen pattern cannot grow" (§15.2 p.2) extends to
        // growth by someone else's credit. The receiving branch was not in
        // this session, so its freeze and episode in `next` are exactly the
        // state's.
        let gained = (next.levels[trained] ?? 0) - (state.levels[trained] ?? 0)
        if gained > 0, !next.creditPaused.contains(other),
           next.freezeRemaining(other) == 0, next.sore[other] == nil {
            let oldOther = next.levels[other] ?? 0
            let cap = EngineConfig.maxUp(pattern: other, tier: Level.decode(oldOther).tier)
            next.levels[other] = min(max(oldOther + min(gained, cap), 0), EngineConfig.levelMax)
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
    public static func applyComeback(state: EngineState, gapDays: Int,
                                     alreadyDecayed: Bool = false) -> EngineState {
        guard gapDays >= EngineConfig.comebackMinGapDays else { return state }
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
    public static func applySilentDecay(state: EngineState, gapDays: Int) -> EngineState {
        guard gapDays >= EngineConfig.silentDecayGapDays,
              gapDays < EngineConfig.comebackMinGapDays else { return state }
        var next = state
        next.lessRun = 0            // v2.9: same as the comeback (spec §19.1)
        next.creditPaused = []      // v2.10: and so does the pause
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
    public static func applyIllness(state: EngineState) -> EngineState {
        var next = state
        next.illness = EngineConfig.illnessSessions
        return next
    }
}
