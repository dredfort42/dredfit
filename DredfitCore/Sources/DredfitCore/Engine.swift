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

public enum Pattern: String, Codable, CaseIterable, Sendable {
    case squat, pushH = "push_h", hinge, pull, pushV = "push_v", lunge
    case coreAntiExt = "core_anti_ext", coreRot = "core_rot", calf

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
        }
    }
}

// MARK: - Configuration (all model constants)

public enum EngineConfig {
    public static let repMin = 8            // bottom of the rep range
    public static let stepsPerTier = 8      // level steps within a tier
    public static let tiers = 4             // variations per pattern (v2.1: added tier 4)
    public static let holdMin = 20          // bottom of the hold range, sec
    public static let holdStepSec = 5       // hold step per level step
    public static let sets = 3              // sets per exercise
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
    public static var levelMax: Int { tiers * stepsPerTier - 1 } // 23
}

// MARK: - State

public struct EngineState: Codable, Equatable, Sendable {
    public var counter: Int
    public var levels: [Pattern: Int]
    public var failStreak: [Pattern: Int]

    public static var initial: EngineState {
        EngineState(
            counter: 0,
            levels: Dictionary(uniqueKeysWithValues: Pattern.ordered.map { ($0, 0) }),
            failStreak: Dictionary(uniqueKeysWithValues: Pattern.ordered.map { ($0, 0) })
        )
    }
}

// MARK: - Level encoding

public struct LevelDecoded: Equatable, Sendable {
    public let tier: Int   // 1...3
    public let reps: Int   // 8...15
    public let hold: Int   // 20...55 (sec)
}

public enum Level {
    /// tier = 1 + L/8; reps = 8 + L%8; hold = 20 + (L%8)*5
    public static func decode(_ level: Int) -> LevelDecoded {
        let l = min(max(level, 0), EngineConfig.levelMax)
        let step = l % EngineConfig.stepsPerTier
        return LevelDecoded(
            tier: 1 + l / EngineConfig.stepsPerTier,
            reps: EngineConfig.repMin + step,
            hold: EngineConfig.holdMin + step * EngineConfig.holdStepSec
        )
    }

    /// Level from an actual value (reps or seconds) given a known tier.
    public static func fromActual(pattern: Pattern, tier: Int, actual: Int) -> Int {
        let lib = ExerciseLibrary.entry(for: pattern)
        let step: Int
        switch lib.unit {
        case .reps:
            step = actual - EngineConfig.repMin
        case .hold:
            step = Int((Double(actual - EngineConfig.holdMin) / Double(EngineConfig.holdStepSec)).rounded())
        }
        let raw = (tier - 1) * EngineConfig.stepsPerTier + step
        return min(max(raw, 0), EngineConfig.levelMax)
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
    public static func generateSession(_ state: EngineState) -> Session {
        let n = rotating.count
        let start = (state.counter * EngineConfig.rotationStep) % n
        let five = (0..<(EngineConfig.patternsPerSession - 1)).map {
            rotating[(start + $0) % n]
        }
        let chosen = Set([Pattern.pull] + five)
        let patterns = Pattern.ordered.filter { chosen.contains($0) } // ordering follows Pattern.ordered

        var workSec = 0.0
        let exercises: [SessionExercise] = patterns.map { p in
            let lib = ExerciseLibrary.entry(for: p)
            let d = Level.decode(state.levels[p] ?? 0)
            let variation = lib.variations[d.tier - 1]
            let sides = variation.unilateral ? 2 : 1
            let load = lib.unit == .reps ? d.reps : d.hold

            let workPerSet: Double = lib.unit == .reps
                ? Double(d.reps * sides) * EngineConfig.tempoSecPerRep
                : Double(d.hold * sides)
            workSec += Double(EngineConfig.sets) * workPerSet
                + Double((EngineConfig.sets - 1) * EngineConfig.restSetSec)
                + Double(EngineConfig.restExerciseSec)

            return SessionExercise(
                pattern: p, name: variation.name, tier: d.tier,
                unit: lib.unit, load: load, perSide: variation.unilateral,
                sets: EngineConfig.sets,
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
    /// - overrides: per-pattern actual values (reps or seconds) that
    ///   override the overall rating for their pattern.
    public static func applyFeedback(
        state: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides: [Pattern: Int] = [:]
    ) -> EngineState {
        var next = state
        next.counter = state.counter + 1

        for ex in session.exercises {
            let p = ex.pattern
            let oldL = state.levels[p] ?? 0
            var newL: Int

            if let actual = overrides[p] {
                let factL = Level.fromActual(pattern: p, tier: ex.tier, actual: actual)
                newL = min(max(factL, 0), oldL + EngineConfig.maxUpPerSession)
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
}
