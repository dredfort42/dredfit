//
//  Engine.swift
//  DredfitCore
//
//  Adaptive general-fitness engine v2 (a "thermostat"). Port of the reference
//  adaptive_engine.js. Behavior is verified by golden tests (Fixtures/golden.json)
//  generated from the JS reference — any divergence = a port bug.
//
//  Three pure functions:
//    EngineState.initial            — starting state (all zeros)
//    Engine.generateSession(state)  — a workout from state (deterministic)
//    Engine.applyFeedback(...)      — the only state mutation
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
    // v2.2: vertical pull (the "pull-up bar" module). Not part of the rotation —
    // with hasBar on it takes over the fixed pull slot on odd counters.
    case pullBar = "pull_bar"

    /// Fixed order — defines the rotation. Cannot be changed without a migration.
    public static let ordered: [Pattern] = [
        .squat, .pushH, .hinge, .pull, .pushV, .lunge, .coreAntiExt, .coreRot, .calf
    ]

    /// Localized pattern name (en is the base, ru the translation; see Resources).
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
    public static let repMin = 8            // tier-1 rep floor; only a fallback for repStart (v2.3: the real floor is per tier)
    public static let stepsPerTier = 8      // level steps within a tier
    public static let tiers = 4             // variations per pattern (v2.1: added tier 4)
    public static let holdMin = 20          // bottom of the hold range, sec
    public static let holdStepSec = 5       // hold step per level step
    public static let setsBase = 3          // sets in the 0...31 level band
    public static let setsMax = 5           // sets ceiling (v2.2: bands 4 and 5 above tier 4)
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
    // v2.3 (возврат после перерыва): 14–34 дня → −2; 35–55 → −3; 56–76 → −4;
    // …; 140+ → −8. Движок событийный, поэтому паузу должен внести app-слой.
    public static let comebackMinGapDays = 14
    public static let comebackBase = 2
    public static let comebackStepDays = 21
    public static let comebackMax = 8
    // v2.3 (сглаживание): низ диапазона повторов/удержания зависит от тира —
    // чем сложнее вариация, тем ниже старт, и первая ступень нового тира
    // ложится мягко вместо скачка «тир1×15 → тир2×8».
    public static let repStart = [1: 8, 2: 6, 3: 5, 4: 4]
    public static let holdStart = [1: 20, 2: 15, 3: 15, 4: 10]
    // v2.2: two set bands above tier 4 — six bands of 8 steps
    public static var levelMax: Int { (tiers + setsMax - setsBase) * stepsPerTier - 1 } // 47
}

// MARK: - State

public struct EngineState: Codable, Equatable, Sendable {
    public var counter: Int
    public var levels: [Pattern: Int]
    public var failStreak: [Pattern: Int]
    public var hasBar: Bool   // v2.2: the "pull-up bar" toggle lives in engine state

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

    /// v2.2 migration: files written before hasBar/pull_bar existed decode
    /// with the defaults (hasBar off, missing patterns at level 0). Lenient
    /// the other way too: entries for unknown patterns (a file written by a
    /// future version, opened after a downgrade) are dropped instead of
    /// failing the whole decode and losing the user's history.
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
    public let sets: Int   // 3 | 4 | 5 (v2.2: set bands above tier 4)
    public let reps: Int   // 4...15 (v2.3: the floor is repStart[tier], not a global 8)
    public let hold: Int   // 10...55 sec (v2.3: the floor is holdStart[tier])

    public init(tier: Int, sets: Int, reps: Int, hold: Int) {
        self.tier = tier
        self.sets = sets
        self.reps = reps
        self.hold = hold
    }
}

public enum Level {
    /// tier = min(4, 1 + L/8); sets = 3 (L≤31) | 4 (32...39) | 5 (40...47);
    /// v2.3: reps = repStart[tier] + L%8; hold = holdStart[tier] + (L%8)*5.
    /// Арифметика L → (тир, ступень) не изменилась — изменился только рендер.
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
    /// sets. v2.2: tier 4 spans three set bands, so the base depends on sets;
    /// the unit comes from the (pattern, tier) library record.
    public static func fromActual(pattern: Pattern, tier: Int, sets: Int, actual: Int) -> Int {
        let lib = ExerciseLibrary.entry(for: pattern)
        // v2.3: инверсия считается от старта тира плана, а не от общего пола.
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
    /// v2.1: pull is a fixed slot in every session (push/pull balance);
    /// the other 8 patterns rotate over 5 places with a shift of 3 —
    /// over 8 sessions each appears exactly 5 times.
    /// v2.2: with hasBar on, odd counters hand the pull slot to the vertical
    /// branch (pullBar), which inherits pull's position in the session order.
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

        var workSec = 0.0
        let exercises: [SessionExercise] = patterns.map { p in
            let lib = ExerciseLibrary.entry(for: p)
            let d = Level.decode(state.levels[p] ?? 0)
            let variation = lib.variations[d.tier - 1]
            let unit = lib.unit(forTier: d.tier)
            let sides = variation.unilateral ? 2 : 1
            let load = unit == .reps ? d.reps : d.hold

            let workPerSet: Double = unit == .reps
                ? Double(d.reps * sides) * EngineConfig.tempoSecPerRep
                : Double(d.hold * sides)
            workSec += Double(d.sets) * workPerSet
                + Double((d.sets - 1) * EngineConfig.restSetSec)
                + Double(EngineConfig.restExerciseSec)

            return SessionExercise(
                pattern: p, name: variation.name, tier: d.tier,
                unit: unit, load: load, perSide: variation.unilateral,
                sets: d.sets,
                restSetSec: EngineConfig.restSetSec,
                restExerciseSec: EngineConfig.restExerciseSec
            )
        }

        let totalSec = Double(EngineConfig.warmupMin * 60) + workSec
            + Double(EngineConfig.cooldownMin * 60)
        // Round to 0.1 min — as in the reference (toFixed(1))
        let totalMin = (totalSec / 60 * 10).rounded() / 10

        return Session(
            sessionNumber: state.counter + 1,
            warmupMin: EngineConfig.warmupMin,
            cooldownMin: EngineConfig.cooldownMin,
            exercises: exercises,
            estimatedTotalMin: totalMin
        )
    }

    /// Applying feedback. The only state mutation.
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
    /// - skipped: patterns the user skipped in this session (v2.1.1).
    ///   A skipped pattern was not trained: its level and failStreak stay
    ///   untouched (the streak is frozen, not reset), overrides for it are
    ///   ignored. Patterns not in the session are ignored. The counter
    ///   still advances — the session took place.
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
            if skipped.contains(p) { continue } // v2.1.1: not trained — no change
            let oldL = state.levels[p] ?? 0
            var newL: Int

            if let actual = overrides[p] {
                let factL = Level.fromActual(pattern: p, tier: ex.tier,
                                             sets: ex.sets, actual: actual)
                // v2.3 (калибровка): с нулевой отметки кап не применяется —
                // доверять нечему, кроме факта, а кап +2 растягивал выход
                // тренированного новичка на реальную нагрузку на ~10 сессий.
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

    /// Возврат после перерыва (v2.3). Четвёртая функция API и вторая, что
    /// меняет состояние — но вызывается не из потока тренировки, а app-слоем
    /// при открытии приложения после паузы.
    ///
    /// Снижаются все паттерны, включая `pullBar` при `hasBar == false`:
    /// перерыв детренирует всё тело, а не только то, что было в плане.
    /// `failStreak` обнуляется обязательно — иначе первое недовыполнение
    /// после возврата доедет до разгрузки на старой серии и уронит уровень
    /// второй раз. `counter` не двигается: тренировок не было, но и «долга»
    /// за пропуск нет.
    ///
    /// При откате сохраняется ступень внутри тира (`L % 8`), поэтому −8 —
    /// это ровно тир ниже с тем же номером ступени: движение легче, а число
    /// повторов переходит в диапазон более лёгкого тира.
    ///
    /// NOT idempotent: every call subtracts the drop again. The caller must
    /// apply it at most once per break — the app keys this decision on
    /// `comebackDecidedFor`, so the same gap is never applied twice.
    public static func applyComeback(state: EngineState, gapDays: Int) -> EngineState {
        guard gapDays >= EngineConfig.comebackMinGapDays else { return state }
        let raw = EngineConfig.comebackBase
            + (gapDays - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays
        let drop = min(max(raw, 2), EngineConfig.comebackMax)

        var next = state
        for p in Pattern.allCases {
            next.levels[p] = max(0, (state.levels[p] ?? 0) - drop)
            next.failStreak[p] = 0
        }
        return next
    }
}
