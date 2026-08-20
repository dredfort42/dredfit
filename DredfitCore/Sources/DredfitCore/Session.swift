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
    public let load: Int          // the BASE dose: reps or seconds, per side if perSide
    public let perSide: Bool
    public let sets: Int
    public let restSetSec: Int
    public let restExerciseSec: Int
    /// v2.22 (spec §33): per-set doses, descending — `9-8-8`. OPTIONAL on
    /// purpose, and the optionality is compatibility, not style: a journal
    /// written by build 1.9 carries no such key, and one non-optional field
    /// added to this snapshot would zero that journal on decode. `nil` means a
    /// uniform plan, i.e. every set runs at `load`.
    public let loads: [Int]?

    /// Written out so `loads` can default to nil at every existing call site.
    public init(pattern: Pattern, name: String, tier: Int, unit: LoadUnit,
                load: Int, perSide: Bool, sets: Int, restSetSec: Int,
                restExerciseSec: Int, loads: [Int]? = nil) {
        self.pattern = pattern
        self.name = name
        self.tier = tier
        self.unit = unit
        self.load = load
        self.perSide = perSide
        self.sets = sets
        self.restSetSec = restSetSec
        self.restExerciseSec = restExerciseSec
        self.loads = loads
    }

    /// Every set's planned dose, uniform plan included.
    ///
    /// Bounded by the SCALE, not by the record. `sets` comes back out of the
    /// journal unclamped and this is called from a row body on the main
    /// thread, so a hand-edited `Int.max` would allocate until the app is
    /// killed — the same trap `SetFacts.allSets` was written to avoid, and one
    /// this property walked straight into when it was added. No exercise ever
    /// had more sets than the scale has bands, so the valid domain never
    /// notices the clamp.
    public var perSetLoads: [Int] {
        let count = min(max(sets, 0), EngineConfig.setsMax)
        guard let loads, !loads.isEmpty else {
            return Array(repeating: load, count: count)
        }
        return Array(loads.prefix(count))
    }

    /// What set `index` is planned to run at — the plan's own answer, before
    /// anything the trainee reports. Answers straight off `loads` so the
    /// common path allocates nothing at all.
    public func plannedLoad(set index: Int) -> Int {
        guard let loads, !loads.isEmpty else { return load }
        return loads[min(max(index, 0), loads.count - 1)]
    }

    /// The volume the plan asks for across all sets — the base of both the
    /// duration estimate and the work measure.
    public var plannedVolume: Int { perSetLoads.reduce(0, +) }

    /// "3×12", "3×10 per side", "3×40 sec" — localized via the core catalog.
    /// v2.22 (spec §33): "9-8-8" when the sets differ, "3×8" when they do not.
    public var display: String {
        let side = perSide ? " " + String(localized: "per side", bundle: .module) : ""
        let head = loads.map { $0.map(String.init).joined(separator: "-") } ?? "\(sets)×\(load)"
        switch unit {
        case .reps: return "\(head)\(side)"
        case .hold: return "\(head) " + String(localized: "sec", bundle: .module) + side
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
            // v2.22 (spec §33): the volume is read off the PER-SET doses — with
            // an uneven plan `load × sets` understates the work by exactly the
            // sub-steps' addition, and the estimate would stop being one.
            let volume = Double(ex.plannedVolume * sides)
            let work = ex.unit == .reps ? volume * EngineConfig.tempoSecPerRep : volume
            workSec += work
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

        // v2.22 (spec §33): under the "I was sick" lens the plan is UNIFORM.
        // The lens is the gentler regime, and a sub-step makes part of the sets
        // heavier — showing one here would hand back with one hand what the
        // lens took away with the other. The stored sub-step is untouched: the
        // lens builds the plan's VIEW (§22.4).
        func viewSub(_ p: Pattern) -> Int { eased ? 0 : (state.sub[p] ?? 0) }

        let exercises: [SessionExercise] = patterns.map { p in
            let lib = ExerciseLibrary.entry(for: p)
            let d = Level.decode(viewLevel(p))
            let variation = lib.variations[d.tier - 1]
            let unit = lib.unit(forTier: d.tier)
            let load = unit == .reps ? d.reps : d.hold
            // v2.24 (spec §35.1): the gate and the exercise's own band both go
            // through the one clamp.
            let sets = clampSets(Pattern.pushSide.contains(p) ? min(d.sets, pullSets) : d.sets)
            // The band is the FINAL one — the §20.2 gate may have trimmed it —
            // so a sub-step never asks for more sets than are on screen.
            let loads = Level.perSetLoads(pattern: p, level: viewLevel(p),
                                          sub: viewSub(p), sets: sets)

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
                restExerciseSec: EngineConfig.restExerciseSec,
                loads: loads
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
            ? trimToBudget(exercises, budget: budget, ends: warmup + cooldown)
            : exercises

        return Session(
            sessionNumber: state.counter + 1,
            warmupMin: warmup,
            cooldownMin: cooldown,
            exercises: trimmed,
            estimatedTotalMin: estimatedMin(exercises: trimmed, ends: warmup + cooldown)
        )
    }

    /// v2.24 (spec §35.1): the one and only clamp on a set count. Both
    /// mechanisms that CUT sets — the budget (§28.3) and the band gate (§20.2)
    /// — go through it, so the floor holds for their composition and not just
    /// for each cut on its own.
    static func clampSets(_ n: Int) -> Int { max(EngineConfig.setsFloor, n) }

    /// v2.17 (spec §28.3): fit the plan into the budget. Levels are never
    /// touched — the budget trims the PLAN, not the state.
    ///
    /// v2.24 (spec §35.2): ONE set per iteration, from the exercise whose
    /// removal saves the most seconds, repeated until the plan fits or every
    /// exercise stands on the floor. The old algorithm capped ALL six movements
    /// at once (4, then 3, then 2), and the gap between rungs was wider than
    /// the miss it was closing: a 45-minute budget went 45 → 29 → 45, a
    /// shortfall of up to 36%. One set of one movement is the smallest
    /// indivisible unit of a plan, so the shortfall falls to its size — 6.9%
    /// worst case over levels 24–47.
    ///
    /// Movements are no longer dropped at all (the old second stage and
    /// `keepForBudget` are gone). The reason is the arithmetic §28.3 already
    /// used to justify "sets first": a dropped set costs no progress, a dropped
    /// movement costs all of it. If the plan is still longer than the budget
    /// with everything on the floor, the session simply runs a little long —
    /// honest, and cheaper than dropping a pattern out of the rotation.
    ///
    /// Monotonicity in the budget comes for free: the removal sequence does not
    /// depend on the budget, so the plan for budget B is a prefix of one fixed
    /// sequence, and every removal strictly shortens the session.
    private static func trimToBudget(_ exercises: [SessionExercise], budget: Int,
                                     ends: Int) -> [SessionExercise] {
        var cur = exercises
        var total = estimatedMin(exercises: cur, ends: ends)
        while total > Double(budget) {
            var bestIdx: Int?
            var bestTotal = total
            var bestEx: SessionExercise?
            for i in cur.indices where cur[i].sets > EngineConfig.setsFloor {
                let trimmedEx = Self.withSets(cur[i], cur[i].sets - 1)
                var trial = cur
                trial[i] = trimmedEx
                let trialTotal = estimatedMin(exercises: trial, ends: ends)
                // A strict `<` leaves the win with the FIRST of equals, and the
                // session order is fixed — so the choice is deterministic.
                if trialTotal < bestTotal {
                    bestTotal = trialTotal
                    bestIdx = i
                    bestEx = trimmedEx
                }
            }
            // Everything on the floor (or a removal that saves nothing): this
            // is the shortest legal plan. Running a little long is the accepted
            // consequence of §35.2.
            guard let idx = bestIdx, let ex = bestEx else { break }
            cur[idx] = ex
            total = bestTotal
        }
        return cur
    }

    /// Rebuild an exercise on a different set count; the rest follows the
    /// RESULTING band (owner's decision 19.08.2026) — two minutes between two
    /// sets would swallow a short budget whole.
    /// v2.22 (spec §33): the sub-step is rebuilt for the new set count — it
    /// cannot ask for more sets than are left. Clamping to `sets-1` keeps the
    /// invariant "`load` is the plan's minimum": dropping a set gives the budget
    /// no right to raise that minimum.
    private static func withSets(_ ex: SessionExercise, _ requested: Int) -> SessionExercise {
        // v2.24 (spec §35.1): a rebuild is a cut too, so it goes through the
        // shared clamp — no path can hand back an exercise below the floor.
        let sets = clampSets(requested)
        let high = ex.loads?.first ?? ex.load
        let carried = ex.loads?.filter { $0 > ex.load }.count ?? 0
        let sub = min(carried, max(sets - 1, 0))
        let loads: [Int]? = sub > 0
            ? (0..<sets).map { $0 < sub ? high : ex.load }
            : nil
        return SessionExercise(
            pattern: ex.pattern, name: ex.name, tier: ex.tier, unit: ex.unit,
            load: ex.load, perSide: ex.perSide, sets: sets,
            restSetSec: EngineConfig.restSetByTierBand[ex.tier]?[sets]
                ?? EngineConfig.restSetByBand[sets] ?? EngineConfig.restSetSec,
            restExerciseSec: ex.restExerciseSec, loads: loads)
    }
}
