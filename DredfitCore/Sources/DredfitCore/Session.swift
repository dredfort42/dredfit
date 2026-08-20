//
//  Session.swift
//  DredfitCore
//
//  What a workout looks like on the day: the session value types, the
//  rotation anchor, the duration estimate, and the v2.17 budget that trims a
//  plan to the length the trainee asked for. Split out of Engine.swift when
//  that file outgrew the lint's ceiling; the code is unchanged.
//

import Foundation

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

// MARK: - Building the session

extension Engine {

    /// The first movement of the rotation window for a counter — the anchor
    /// of the short workout. The window shifts by 3 over 8 rotating patterns,
    /// so over any 8 consecutive sessions the anchor visits all 8; the short
    /// workout depends on that property.
    public static func rotationAnchor(counter: Int) -> Pattern {
        let n = rotating.count
        let start = (((EngineState.clamped(counter, 0, EngineConfig.countMax)
                       * EngineConfig.rotationStep) % n) + n) % n
        return rotating[start]
    }

    public static func estimatedMin(exercises: [SessionExercise],
                                    ends: Int = EngineConfig.warmupMin + EngineConfig.cooldownMin) -> Double {
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
        let totalSec = workSec + Double(ends * 60)
        return roundedToTenths(totalSec / 60)
    }

    /// Rounded to 0.1 min the way the reference does it — `toFixed(1)`: the
    /// nearest tenth to the EXACT value of the double, with a tie taken to the
    /// larger number.
    ///
    /// `(x * 10).rounded() / 10` is not that, and the two answers differ by a
    /// whole tenth in both directions. 2079 s / 60 is 34.649999999999999 as a
    /// double — under 34.65, so the reference prints 34.6 — but `x * 10` rounds
    /// that product up to exactly 346.5 and `.rounded()` then says 34.7. Going
    /// the other way, 2115 s / 60 is exactly 35.25, a real tie: the reference
    /// takes 35.3 while any round-half-to-even conversion takes 35.2.
    ///
    /// The divergence is older than this wave and was simply unreachable: with
    /// static doses at multiples of five seconds no session ever landed on
    /// either case. v2.21 put odd second counts into the statics and eighteen
    /// golden steps lit up at once.
    ///
    /// A tie is exactly a value that is an ODD number of quarters — 10x is a
    /// half-integer only for x = m/4 with m odd, because a dyadic fraction has
    /// no other way to sit halfway between two tenths. Scaling by four is exact
    /// for every finite double, so the test itself introduces no error; every
    /// other value is handed to correctly-rounded decimal conversion.
    static func roundedToTenths(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let quarters = value * 4
        if quarters == quarters.rounded(), quarters.truncatingRemainder(dividingBy: 2) != 0 {
            return (value * 10).rounded(.up) / 10
        }
        return Double(String(format: "%.1f", value)) ?? value
    }

    /// A pure function: the only input is the state.
    public static func generateSession(_ dirty: EngineState) -> Session {
        // v2.13 (spec §24.1): every public entry heals its input first, as the
        // reference does on every build. Identity on the valid domain.
        let state = dirty.sanitized()
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
        // v2.16 (spec §27.2, #141): the ceiling is the WEAKER of the slot's two
        // branches, not whichever one stands in this session. Reading the
        // in-slot branch made the push plan flip 5×4 ↔ 3×6 every session once
        // the branches diverged — visible churn with no cause on screen. The
        // gate exists so the push does not run ahead of the pull; the weaker
        // branch holds that line more strictly (owner's decision 19.08.2026).
        let pullSets = patterns.first { Pattern.pullSide.contains($0) }
            .map { _ in
                state.hasBar
                    ? min(Level.decode(viewLevel(.pull)).sets,
                          Level.decode(viewLevel(.pullBar)).sets)
                    : Level.decode(viewLevel(.pull)).sets
            } ?? EngineConfig.setsMax

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
                // v2.17 (spec §28.2): the (tier, band) cell wins when set.
                restSetSec: EngineConfig.restSetByTierBand[d.tier]?[sets]
                    ?? EngineConfig.restSetByBand[sets] ?? EngineConfig.restSetSec,
                restExerciseSec: EngineConfig.restExerciseSec
            )
        }

        // v2.17 (spec §28.3): the budget trims the plan to fit. Warm-up and
        // cool-down shrink on the short rungs — eight fixed minutes would eat
        // half of a fifteen-minute session.
        let budget = state.timeBudgetMin
        let short = budget > 0 && budget <= EngineConfig.budgetShortEndsAt
        let warmup = short ? EngineConfig.warmupShortMin : EngineConfig.warmupMin
        let cooldown = short ? EngineConfig.cooldownShortMin : EngineConfig.cooldownMin
        let trimmed = budget > 0
            ? trimToBudget(exercises, budget: budget, ends: warmup + cooldown,
                           counter: state.counter, levels: state.levels)
            : exercises

        return Session(
            sessionNumber: state.counter + 1,
            warmupMin: warmup,
            cooldownMin: cooldown,
            exercises: trimmed,
            estimatedTotalMin: estimatedMin(exercises: trimmed, ends: warmup + cooldown)
        )
    }

    /// v2.17 (spec §28.3): fit the plan into the budget. The order is measured:
    /// sets first, movements only after. Growth in the model is +1 per pattern
    /// per session and does not depend on the set count, so a dropped set costs
    /// no progress while a dropped movement costs all of it (measured on the
    /// busy-parent persona: 66.6 levels against 30.4 at a 20-minute budget).
    /// Levels are never touched — the budget trims the PLAN.
    private static func trimToBudget(_ exercises: [SessionExercise], budget: Int,
                                     ends: Int, counter: Int,
                                     levels: [Pattern: Int]) -> [SessionExercise] {
        var cur = exercises
        if estimatedMin(exercises: cur, ends: ends) <= Double(budget) { return cur }
        for sets in stride(from: EngineConfig.setsMax - 1,
                           through: EngineConfig.budgetSetsFloor, by: -1) {
            cur = cur.map { $0.sets <= sets ? $0 : Self.withSets($0, sets) }
            if estimatedMin(exercises: cur, ends: ends) <= Double(budget) { return cur }
        }
        for n in stride(from: cur.count - 1,
                        through: EngineConfig.budgetPatternsFloor, by: -1) {
            cur = keepForBudget(cur, n, counter: counter, levels: levels)
            if estimatedMin(exercises: cur, ends: ends) <= Double(budget) { return cur }
        }
        return cur   // the budget is below the floor — the shortest legal plan
    }

    /// WHO stays when movements have to go. Cutting the tail is wrong: the
    /// session order is fixed, so the last patterns (calves, rotation) would
    /// never appear at all — measured zero appearances of calves over 24
    /// sessions. The rule is the app's own short-workout rule (#27, verified by
    /// simulation): the pull slot, the rotation anchor, then the laggards.
    private static func keepForBudget(_ exercises: [SessionExercise], _ n: Int,
                                      counter: Int,
                                      levels: [Pattern: Int]) -> [SessionExercise] {
        var keep: [Pattern] = []
        if let pull = exercises.first(where: { Pattern.pullSide.contains($0.pattern) }) {
            keep.append(pull.pattern)
        }
        let anchor = rotationAnchor(counter: counter)
        if exercises.contains(where: { $0.pattern == anchor }), !keep.contains(anchor) {
            keep.append(anchor)
        }
        for ex in exercises.filter({ !keep.contains($0.pattern) })
            .sorted(by: { (levels[$0.pattern] ?? 0) < (levels[$1.pattern] ?? 0) }) {
            if keep.count >= n { break }
            keep.append(ex.pattern)
        }
        return exercises.filter { keep.contains($0.pattern) }
    }

    /// Rebuild an exercise on a different set count; the rest follows the
    /// RESULTING band (owner's decision 19.08.2026) — two minutes between two
    /// sets would swallow a short budget whole.
    private static func withSets(_ ex: SessionExercise, _ sets: Int) -> SessionExercise {
        SessionExercise(
            pattern: ex.pattern, name: ex.name, tier: ex.tier, unit: ex.unit,
            load: ex.load, perSide: ex.perSide, sets: sets,
            restSetSec: EngineConfig.restSetByTierBand[ex.tier]?[sets]
                ?? EngineConfig.restSetByBand[sets] ?? EngineConfig.restSetSec,
            restExerciseSec: ex.restExerciseSec)
    }
}
