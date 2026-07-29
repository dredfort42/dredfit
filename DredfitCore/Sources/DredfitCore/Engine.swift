//
//  Engine.swift
//  DredfitCore
//
//  Adaptive general-fitness engine (a "thermostat"). Port of the reference
//  adaptive_engine.js. Behavior is verified by golden tests (Fixtures/golden.json)
//  generated from the JS reference — any divergence = a port bug.
//
//  API:
//    EngineState.initial            — starting state (all zeros)
//    Engine.generateSession(state)  — a workout from state (deterministic)
//    Engine.applyFeedback(...)      — the main state mutation
//    Engine.applyComeback(...)      — level drop after a long break
//    Engine.applySilentDecay(...)   — quiet −1 for the 7–13 day blind zone
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
    // Vertical pull (the "pull-up bar" module). Not part of the rotation —
    // with hasBar on it takes over the fixed pull slot on odd counters.
    case pullBar = "pull_bar"

    /// Fixed order — defines the rotation. Cannot be changed without a migration.
    public static let ordered: [Pattern] = [
        .squat, .pushH, .hinge, .pull, .pushV, .lunge, .coreAntiExt, .coreRot, .calf
    ]

    /// Localized pattern name.
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
    public static let repMin = 8            // fallback rep floor; the real floor is per-tier repStart
    public static let stepsPerTier = 8      // level steps within a tier
    public static let tiers = 4             // variations per pattern
    public static let holdMin = 20          // bottom of the hold range, sec
    public static let holdStepSec = 5       // hold step per level step
    public static let setsBase = 3          // sets in the 0...31 level band
    public static let setsMax = 5           // sets ceiling (bands 4 and 5 above tier 4)
    public static let restSetSec = 60       // pause between sets
    public static let restExerciseSec = 60  // pause between exercises
    public static let tempoSecPerRep = 2.5  // tempo for duration estimation
    public static let patternsPerSession = 6
    public static let rotationStep = 3      // rotation shift per session
    public static let deltaLess = -1
    public static let deltaPlan = 1
    public static let deltaMore = 2
    public static let maxUpPerSession = 2   // growth ceiling per session
    public static let failsToDeload = 3     // consecutive underperformances before a deload
    public static let deloadDrop = 3        // deload rollback
    public static let warmupMin = 5
    public static let cooldownMin = 3
    // Comeback after a break: 14–34 days → −2; each further 21 days → −1 more,
    // capped at −8. The engine is event-driven — the app layer applies it.
    public static let comebackMinGapDays = 14
    public static let comebackBase = 2
    public static let comebackStepDays = 21
    public static let comebackMax = 8
    // Silent decay (v2.4): the lower edge of the 7–13 day blind zone — the
    // comeback only starts at 14, yet ~10 days already cost the body a step
    // or two.
    public static let silentDecayGapDays = 7
    // Per-tier rep/hold floors: the harder the variation, the lower the
    // start, so the first step of a new tier lands softly instead of the
    // jump "tier1×15 → tier2×8".
    public static let repStart = [1: 8, 2: 6, 3: 5, 4: 4]
    public static let holdStart = [1: 20, 2: 15, 3: 15, 4: 10]
    // Two set bands above tier 4 — six bands of 8 steps.
    public static var levelMax: Int { (tiers + setsMax - setsBase) * stepsPerTier - 1 } // 47
}

// MARK: - State

public struct EngineState: Codable, Equatable, Sendable {
    public var counter: Int
    public var levels: [Pattern: Int]
    public var failStreak: [Pattern: Int]
    public var hasBar: Bool   // the "pull-up bar" toggle lives in engine state

    // Spelled out (same names the compiler would synthesize) so that
    // decodeLenient can reference the type — synthesized CodingKeys are only
    // visible inside init(from:)/encode(to:). The wire format is unchanged.
    private enum CodingKeys: String, CodingKey {
        case counter, levels, failStreak, hasBar
    }

    public init(counter: Int, levels: [Pattern: Int],
                failStreak: [Pattern: Int], hasBar: Bool = false) {
        self.counter = counter
        self.levels = levels
        self.failStreak = failStreak
        self.hasBar = hasBar
    }

    /// Lenient decode in both directions: files written before hasBar/pull_bar
    /// existed get the defaults (hasBar off, missing patterns at level 0), and
    /// entries for unknown patterns (a file written by a future version,
    /// opened after a downgrade) are dropped instead of failing the whole
    /// decode and losing the user's history.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A corrupt or hand-edited file must not feed a negative counter into
        // the rotation — clamp instead of failing; 0 is the safe restart.
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
    }

    /// Manual decode of the exact wire format Swift synthesizes for a
    /// [Pattern: Int]: an UNKEYED array alternating [rawValue, count, ...]
    /// (Pattern is String-raw and not CodingKeyRepresentable — see the
    /// warning on Pattern). Pairs whose raw value is not a known Pattern are
    /// dropped: a future version may add a pattern, and its file must still
    /// open after a downgrade. The encode side stays synthesized — the wire
    /// format is byte-compatible and pinned by testLegacyStateDecodesWithBarDefaults.
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
}

// MARK: - Level encoding

public struct LevelDecoded: Equatable, Sendable {
    public let tier: Int   // 1...4
    public let sets: Int   // 3 | 4 | 5 (set bands above tier 4)
    public let reps: Int   // 4...15 (floor is repStart[tier])
    public let hold: Int   // 10...55 sec (floor is holdStart[tier])

    public init(tier: Int, sets: Int, reps: Int, hold: Int) {
        self.tier = tier
        self.sets = sets
        self.reps = reps
        self.hold = hold
    }
}

public enum Level {
    /// tier = min(4, 1 + L/8); sets = 3 (L≤31) | 4 (32...39) | 5 (40...47);
    /// reps = repStart[tier] + L%8; hold = holdStart[tier] + (L%8)*5.
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

    /// Level from an actual value (reps or seconds) given the planned tier and
    /// sets. Tier 4 spans three set bands, so the base depends on sets; the
    /// unit comes from the (pattern, tier) library record.
    public static func fromActual(pattern: Pattern, tier: Int, sets: Int, actual: Int) -> Int {
        let lib = ExerciseLibrary.entry(for: pattern)
        // The inversion counts from the plan tier's floor, not a global one.
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

    /// Session generation. A pure function: the only input is the state.
    /// Pull is a fixed slot in every session (push/pull balance); the other
    /// 8 patterns rotate over 5 places with a shift of 3 — over 8 sessions
    /// each appears exactly 5 times. With hasBar on, odd counters hand the
    /// pull slot to the vertical branch (pullBar), which inherits pull's
    /// position in the session order.
    /// The first movement of the rotation window for a counter — the "anchor"
    /// of the short workout (issue #27).
    ///
    /// Read-only and behaviour-free: it re-derives what `generateSession`
    /// already computes internally, so the app layer never has to keep its
    /// own copy of the rotation formula. Nothing in the engine calls it, and
    /// no fixture can move because of it.
    ///
    /// The rotation property that makes it useful: the window shifts by 3
    /// over 8 rotating patterns each session, so over any 8 consecutive
    /// sessions the anchor visits all 8 — every movement is trained at least
    /// once even if the user only ever does short workouts.
    public static func rotationAnchor(counter: Int) -> Pattern {
        let n = rotating.count
        let start = (((counter * EngineConfig.rotationStep) % n) + n) % n
        return rotating[start]
    }

    /// Estimated wall-clock minutes for a list of exercises, warm-up and
    /// cool-down included — the same arithmetic `generateSession` uses for a
    /// full session, exposed so the short workout can state its own length
    /// without the app layer re-deriving tempo and rest constants.
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
        // Round to 0.1 min — as in the reference (toFixed(1))
        return (totalSec / 60 * 10).rounded() / 10
    }

    public static func generateSession(_ state: EngineState) -> Session {
        let n = rotating.count
        // Nonnegative modulo: Swift's % is a remainder and goes negative with
        // a negative counter, which would index out of bounds below. Decode
        // already clamps counter to >= 0 — this is defense in depth, and it
        // is bit-identical to plain % for every nonnegative counter.
        let start = (((state.counter * EngineConfig.rotationStep) % n) + n) % n
        let five = (0..<(EngineConfig.patternsPerSession - 1)).map {
            rotating[(start + $0) % n]
        }
        let chosen = Set([Pattern.pull] + five)
        let useBar = state.hasBar && state.counter % 2 == 1
        let patterns = Pattern.ordered.filter { chosen.contains($0) } // ordering follows Pattern.ordered
            .map { $0 == .pull && useBar ? Pattern.pullBar : $0 }

        let exercises: [SessionExercise] = patterns.map { p in
            let lib = ExerciseLibrary.entry(for: p)
            let d = Level.decode(state.levels[p] ?? 0)
            let variation = lib.variations[d.tier - 1]
            let unit = lib.unit(forTier: d.tier)
            let load = unit == .reps ? d.reps : d.hold

            return SessionExercise(
                pattern: p, name: variation.name, tier: d.tier,
                unit: unit, load: load, perSide: variation.unilateral,
                sets: d.sets,
                restSetSec: EngineConfig.restSetSec,
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

    /// Applying feedback — the main state mutation.
    ///
    /// Invariant: feedback is only valid for the session generated from this
    /// exact state, i.e. `session.sessionNumber == state.counter + 1`.
    /// Anything else — the same feedback replayed after a crash, or a stale
    /// session kept around across state changes — returns the state
    /// untouched, so applying the same (state, session) twice is safe.
    /// Known limitation: `applyComeback` does not advance `counter`, so a
    /// session generated *before* a comeback still passes this check and its
    /// feedback lands on the post-comeback levels.
    ///
    /// - overrides: per-pattern actual values (reps or seconds) that
    ///   override the overall rating for their pattern.
    /// - skipped: patterns the user skipped in this session. A skipped
    ///   pattern was not trained: its level and failStreak stay untouched
    ///   (the streak is frozen, not reset), overrides for it are ignored.
    ///   Patterns not in the session are ignored. The counter still
    ///   advances — the session took place.
    public static func applyFeedback(
        state: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides: [Pattern: Int] = [:],
        skipped: Set<Pattern> = []
    ) -> EngineState {
        // Replay guard: a session that does not belong to this state must not
        // mutate it (see the invariant in the doc comment above).
        guard session.sessionNumber == state.counter + 1 else { return state }
        var next = state
        next.counter = state.counter + 1

        for ex in session.exercises {
            let p = ex.pattern
            if skipped.contains(p) { continue } // not trained — no change
            let oldL = state.levels[p] ?? 0
            var newL: Int

            if let actual = overrides[p] {
                let factL = Level.fromActual(pattern: p, tier: ex.tier,
                                             sets: ex.sets, actual: actual)
                // Calibration: from a zero level the +2 cap does not apply —
                // there is nothing to trust but the actual, and the cap would
                // stretch a trained beginner's ramp-up over ~10 sessions.
                newL = oldL == 0
                    ? min(max(factL, 0), EngineConfig.levelMax)
                    : min(max(factL, 0), oldL + EngineConfig.maxUpPerSession)
            } else {
                newL = oldL + result.delta
            }
            newL = min(max(newL, 0), EngineConfig.levelMax)

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
        return next
    }

    /// Comeback after a break. The second state-mutating function — called
    /// not from the workout flow but by the app layer when the app opens
    /// after a pause.
    ///
    /// All patterns drop, including `pullBar` when `hasBar == false`: a break
    /// detrains the whole body, not just what was in the plan. `failStreak`
    /// must reset — otherwise the first underperformance after the return
    /// would ride the old streak into a deload and drop the level twice.
    /// `counter` does not move: no workouts happened, but there is no "debt"
    /// for the gap either.
    ///
    /// The drop preserves the step within the tier (`L % 8`), so −8 is
    /// exactly one tier down at the same step: an easier movement, with the
    /// rep count shifting into the easier tier's range.
    ///
    /// NOT idempotent: every call subtracts the drop again. The caller must
    /// apply it at most once per break — the app keys this decision on
    /// `comebackDecidedFor`, so the same gap is never applied twice.
    ///
    /// `alreadyDecayed` (v2.4): the silent −1 was already applied to this
    /// same break (the user opened the app inside the 7–13 day blind zone).
    /// The two drops must not stack — whoever peeked mid-break must not end
    /// up punished harder than whoever stayed away — so the comeback weakens
    /// by one and the break's total is exactly the table value. Per level
    /// this is exact even at the clamp:
    /// `max(max(L−1,0) − (drop−1), 0) == max(L − drop, 0)` for drop ≥ 2.
    public static func applyComeback(state: EngineState, gapDays: Int,
                                     alreadyDecayed: Bool = false) -> EngineState {
        guard gapDays >= EngineConfig.comebackMinGapDays else { return state }
        let raw = EngineConfig.comebackBase
            + (gapDays - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays
        let drop = min(max(raw, 2), EngineConfig.comebackMax) - (alreadyDecayed ? 1 : 0)

        var next = state
        for p in Pattern.allCases {
            next.levels[p] = max(0, (state.levels[p] ?? 0) - drop)
            next.failStreak[p] = 0
        }
        return next
    }

    /// Silent decay for the 7–13 day blind zone (v2.4, issue #37): the
    /// comeback starts at 14 days, yet the most common real-life gap length
    /// (vacation, work trip, a cold) already costs the body a step or two.
    /// A quiet −1 to every pattern — including `pullBar` when
    /// `hasBar == false`, a break detrains the whole body — clamped at 0.
    ///
    /// `failStreak` is deliberately untouched, unlike the comeback: −1 is a
    /// soft plan correction, not a level capitulation, and a one-week pause
    /// is no reason to erase an accumulated streak. `counter` does not move.
    ///
    /// NOT idempotent, same as the comeback: the app layer applies it at
    /// most once per break, keyed to the last workout's date.
    public static func applySilentDecay(state: EngineState, gapDays: Int) -> EngineState {
        guard gapDays >= EngineConfig.silentDecayGapDays,
              gapDays < EngineConfig.comebackMinGapDays else { return state }
        var next = state
        for p in Pattern.allCases {
            next.levels[p] = max(0, (state.levels[p] ?? 0) - 1)
        }
        return next
    }
}
