//
//  What a workout looks like on the day: the session value types, the
//  rotation anchor and the duration estimate. Split out of Engine.swift when
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
    /// Per-set doses, descending — `9-8-8`. OPTIONAL on
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
    var perSetLoads: [Int] {
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
    /// "9-8-8" when the sets differ, "3×8" when they do not.
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
            // The volume is read off the PER-SET doses — with
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
    /// either case. put odd second counts into the statics and eighteen
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
        // Every public entry heals its input first, as the
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

        // The "I was sick" lens no
        // longer moves the LEVEL at all. Showing every level one tier easier
        // made the plan HEAVIER in 84 cells of 480: rep
        // continuity read a phantom `reps` field on the statics, and the
        // ladders of tier 3 sit above those of tier 4 (hinge L24 → 3×4 = 12
        // reps became 3×5 per leg = 30). The one tap a person has for "I need
        // something lighter right now" did the exact opposite of its promise.
        //
        // Taking sets off cannot make a plan heavier BY CONSTRUCTION: the
        // variation, the dose per set, the unit and the sides are the same and
        // the number of sets is strictly smaller. Zero cells of 480, with no
        // check needed — it follows from the definition of the measure.
        func viewLevel(_ p: Pattern) -> Int { state.levels[p] ?? 0 }

        // The pull slot's set band caps the push of the same
        // session. With the bar the pull enters the bands 13-16 sessions after
        // the push, and those windows are exactly where the balance fell to
        // 0.60. The PLAN is clamped, not the state: the push level keeps
        // growing and gets its sets back the moment the pull catches up.
        // The ceiling is the WEAKER of the slot's two
        // branches, not whichever one stands in this session. Reading the
        // in-slot branch made the push plan flip 5×4 ↔ 3×6 every session once
        // the branches diverged — visible churn with no cause on screen. The
        // gate exists so the push does not run ahead of the pull; the weaker
        // branch holds that line more strictly (owner's decision 19.08.2026).
        // The ceiling reads the pull slot's sets AFTER the cut. A
        // pull that hurts no longer moves its level, so a ceiling reading the
        // level's band stopped reacting at all: one "it hurt" tap on the pull
        // dropped the balance from 0.800 to 0.533, and on band 5 to 0.160.
        let pullSets = patterns.first { Pattern.pullSide.contains($0) }
            .map { _ in
                state.hasBar
                    ? min(Level.setsAfterCut(level: viewLevel(.pull), cut: viewCut(.pull)),
                          Level.setsAfterCut(level: viewLevel(.pullBar), cut: viewCut(.pullBar)))
                    : Level.setsAfterCut(level: viewLevel(.pull), cut: viewCut(.pull))
            } ?? EngineConfig.setsMax

        func viewSub(_ p: Pattern) -> Int { state.sub[p] ?? 0 }

        func viewCut(_ p: Pattern) -> Int { state.cutOf(p) }

        // ONE order of cuts. The level's band → the sets
        // handle (pain channel / descent / lens) → the gate → the
        // budget. Each next one may only lower, none may raise, and there is
        // one shared floor: two sets, except for a position the pain channel
        // has already taken to one — neither the gate nor the budget has the
        // right to lift that back.
        //
        // The per-exercise floor is SERVICE data and stays out of the
        // snapshot, exactly as it is a non-enumerable property in the
        // reference: `SessionExercise` gains no field, so a journal written by
        // build 1.9 still decodes whole. It travels alongside instead.
        var floors: [Int] = []
        let exercises: [SessionExercise] = patterns.map { p in
            let lib = ExerciseLibrary.entry(for: p)
            let d = Level.decode(viewLevel(p))
            let variation = lib.variations[d.tier - 1]
            let unit = lib.unit(forTier: d.tier)
            let load = unit == .reps ? d.reps : d.hold
            let ownSets = d.sets - Level.effCut(level: viewLevel(p), cut: viewCut(p),
                                                floor: EngineConfig.setsFloor)
            let floor = min(EngineConfig.setsFloor, ownSets)
            floors.append(floor)
            // The gate and the exercise's own band both go
            // through the one clamp.
            let sets = clampSets(Pattern.pushSide.contains(p) ? min(ownSets, pullSets) : ownSets,
                                 floor: floor)
            // The band is the FINAL one — the gate may have trimmed it —
            // so a sub-step never asks for more sets than are on screen.
            let loads = Level.perSetLoads(pattern: p, level: viewLevel(p),
                                          sub: viewSub(p), sets: sets)

            return SessionExercise(
                pattern: p, name: variation.name, tier: d.tier,
                unit: unit, load: load, perSide: variation.unilateral,
                sets: sets,
                // The rest between sets follows the set
                // band — the field is per-exercise, so the timer needs no
                // change.
                // The (tier, band) cell wins when set.
                // The band is the LEVEL'S, not the number of
                // sets shown. The handle takes volume off, not recovery: before
                // the fix a pain landing on band 5 was handed 90 s instead of
                // 120 — a REST SHORTER than before the complaint. The budget
                // still recomputes the pause on its result (`withSets`), and
                // there it is justified: two minutes between two sets would
                // swallow a short limit whole.
                restSetSec: EngineConfig.restSetByTierBand[d.tier]?[d.sets]
                    ?? EngineConfig.restSetByBand[d.sets] ?? EngineConfig.restSetSec,
                restExerciseSec: EngineConfig.restExerciseSec,
                loads: loads
            )
        }

        // There is no time budget. The engine does not fit
        // itself into the time a person allotted — it ANNOUNCES how long the
        // session takes, and the person shortens it with the sets handle. The
        // short warm-up and cool-down went with the budget: they existed only
        // to keep eight fixed minutes from eating half a fifteen-minute
        // session, and fifteen-minute sessions are no longer produced.
        let warmup = EngineConfig.warmupMin
        let cooldown = EngineConfig.cooldownMin
        let trimmedRaw = exercises
        // The postcondition "a descent never adds
        // load" is checked ON THE RESULT rather than derived from the way the
        // cut is built. It works with no budget at all: the band gate can
        // move sets about too.
        //
        var ordNow: [Pattern: Int] = [:]
        for ex in trimmedRaw { ordNow[ex.pattern] = Level.posOrd(state.position(ex.pattern)) }
        // `budgetChanged` is gone. It existed because the
        // budget moved the plan PAST the position measure, so a person moving
        // the handle had to be declared a legitimate cause of growth by hand.
        // The sets handle writes `cut`, a coordinate of the position, so
        // releasing it IS a rise and the general gate excludes it on its own.
        let trimmed = repairDescent(trimmedRaw, floors: floors, shownWork: state.shownWork,
                                    shownOrd: state.shownOrd, ordNow: ordNow)

        return Session(
            sessionNumber: state.counter + 1,
            warmupMin: warmup,
            cooldownMin: cooldown,
            exercises: trimmed,
            estimatedTotalMin: estimatedMin(exercises: trimmed, ends: warmup + cooldown)
        )
    }

    /// The one and only clamp on a set count. Every
    /// mechanism that CUTS sets — the band gate among them — goes
    /// through it, so the floor holds for their composition and not just for
    /// each cut on its own.
    /// The floor is a per-exercise number, and it carries
    /// NO default on purpose.: every caller now passes the same
    /// shared floor — the pain channel's single set is gone — but the explicit
    /// parameter stays. A default here is exactly what let `setsFloorPain`
    /// leak into all ten call sites of the previous wave.
    static func clampSets(_ n: Int, floor: Int) -> Int { max(floor, n) }

    /// THE POSTCONDITION REPAIR. The invariant the
    /// model promises is "if a pattern's position did not rise, its plan cannot
    /// get heavier". Deriving it from the shape of the budget did not work —
    /// three rounds of skeptics found a class of violations in every attempt.
    /// So it is checked ON THE RESULT: a movement whose position has not risen
    /// since it was last shown, and whose shown work has grown, loses sets
    /// until it stops.
    ///
    /// Why that is correct and why it terminates: taking a set off always
    /// strictly reduces the work (the dose per set and the sides do not
    /// change), so the loop is finite; the floor bounds it from below; and if
    /// even on the floor the work is above the old one, then the DOSE grew —
    /// that is, the position did rise after all and the condition does not
    /// hold. The cost is six checks a session.
    ///
    /// The comparison is NON-STRICT: "the position did not rise" covers both
    /// "fell" and "stood still". A strict one let through the very class the
    /// repair exists for — the budget can move a cut between movements with
    /// the position standing still (measured: 20 cells of 488). The ratchet
    /// this might have become is lifted at one point, the moved time handle
    /// below; and the lens expiring never reaches the repair at all, because
    /// the branch under the lens does NOT write the memory — the base stays
    /// the last ordinary showing, and after the lens the work returns exactly
    /// to it.
    private static func repairDescent(_ exercises: [SessionExercise], floors: [Int],
                                      shownWork: [Pattern: Int], shownOrd: [Pattern: Int],
                                      ordNow: [Pattern: Int],
                                      ) -> [SessionExercise] {
        // The person moved the time handle — the last showing says nothing any
        // more. Without this the cap held the plan at the old limit until the
        // first growth event: raising 30 to 60 gave 45.9 minutes instead of
        // 59.1.
        return exercises.enumerated().map { i, ex in
            let p = ex.pattern
            guard let work = shownWork[p], let ord = shownOrd[p] else { return ex }
            if (ordNow[p] ?? 0) > ord { return ex }
            var cur = ex
            let floor = floors[i]
            while cur.sets > floor, Engine.exerciseWork(cur) > work {
                cur = Self.withSets(cur, cur.sets - 1, floor: floor)
            }
            return cur
        }
    }

    /// Rebuild an exercise on a different set count; the rest follows the
    /// RESULTING band (owner's decision 19.08.2026) — two minutes between two
    /// sets would swallow a short budget whole.
    /// The sub-step is rebuilt for the new set count — it
    /// cannot ask for more sets than are left. Clamping to `sets-1` keeps the
    /// invariant "`load` is the plan's minimum": dropping a set gives the budget
    /// no right to raise that minimum.
    private static func withSets(_ ex: SessionExercise, _ requested: Int,
                                 floor: Int) -> SessionExercise {
        // A rebuild is a cut too, so it goes through the
        // shared clamp — no path can hand back an exercise below the floor.
        let sets = clampSets(requested, floor: floor)
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
