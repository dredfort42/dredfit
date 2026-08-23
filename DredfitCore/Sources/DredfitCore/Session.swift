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

        // v2.12 (spec §22.4) · v2.25 (spec §36.6): the "I was sick" lens no
        // longer moves the LEVEL at all. Showing every level one tier easier
        // made the plan HEAVIER in 84 cells of 480 (audit 20.08, P0-6): rep
        // continuity read a phantom `reps` field on the statics, and the v2.21
        // ladders of tier 3 sit above those of tier 4 (hinge L24 → 3×4 = 12
        // reps became 3×5 per leg = 30). The one tap a person has for "I need
        // something lighter right now" did the exact opposite of its promise.
        //
        // Taking sets off cannot make a plan heavier BY CONSTRUCTION: the
        // variation, the dose per set, the unit and the sides are the same and
        // the number of sets is strictly smaller. Zero cells of 480, with no
        // check needed — it follows from the definition of the measure.
        let eased = state.illness > 0
        func viewLevel(_ p: Pattern) -> Int { state.levels[p] ?? 0 }

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
        // v2.25 (Ф4): the ceiling reads the pull slot's sets AFTER the cut. A
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

        // v2.22 (spec §33): under the "I was sick" lens the plan is UNIFORM.
        // The lens is the gentler regime, and a sub-step makes part of the sets
        // heavier — showing one here would hand back with one hand what the
        // lens took away with the other. The stored sub-step is untouched: the
        // lens builds the plan's VIEW (§22.4).
        func viewSub(_ p: Pattern) -> Int { eased ? 0 : (state.sub[p] ?? 0) }

        // v2.25 (round 6, fix 4): the lens is a SHARE and it adds to the pain
        // cut. A flat minus-one-set gave the less the more loaded a person
        // was: after flu, on a band of five, `4×12 shrimp squats per leg` was
        // left — minus 20 %, which is no gentle regime at all. And over a set
        // pain had already taken it gave NOTHING: someone with a bad knee and
        // the flu pressed the button and saw no difference — the same dead-tap
        // class §36.5 was fixing elsewhere. The lens now takes the plan to
        // half the band, rounding up, never past what pain already took and
        // never below the shared floor.
        //
        // ACCEPTED (§36.10 p. 6): if the plan is already on the shared floor
        // of two sets the lens gives nothing. Letting it reach a single set
        // would hand the pain floor to a channel that is not the pain channel.
        func viewCut(_ p: Pattern) -> Int {
            let stored = state.cutOf(p)
            guard eased else { return stored }
            let band = Level.decode(state.levels[p] ?? 0).sets
            return max(stored, band - max(EngineConfig.setsFloor, (band + 1) / 2))
        }

        // v2.25 (spec §36.6): ONE order of cuts. The level's band → the sets
        // handle (pain channel / descent / lens) → the §20.2 gate → the §28.3
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
                                                floor: EngineConfig.setsFloorPain)
            let floor = min(EngineConfig.setsFloor, ownSets)
            floors.append(floor)
            // v2.24 (spec §35.1): the gate and the exercise's own band both go
            // through the one clamp.
            let sets = clampSets(Pattern.pushSide.contains(p) ? min(ownSets, pullSets) : ownSets,
                                 floor: floor)
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
                // v2.25 (Ф6, §36.9): the band is the LEVEL'S, not the number of
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

        // v2.17 (spec §28.3): the budget trims the plan to fit. Warm-up and
        // cool-down shrink on the short rungs — eight fixed minutes would eat
        // half of a fifteen-minute session.
        let budget = state.timeBudgetMin
        let short = budget > 0 && budget <= EngineConfig.budgetShortEndsAt
        let warmup = short ? EngineConfig.warmupShortMin : EngineConfig.warmupMin
        let cooldown = short ? EngineConfig.cooldownShortMin : EngineConfig.cooldownMin
        let trimmedRaw = budget > 0
            ? trimToBudget(exercises, floors: floors, budget: budget, ends: warmup + cooldown)
            : exercises
        // v2.25 (spec §36.8, round 4): the postcondition "a descent never adds
        // load" is checked ON THE RESULT rather than derived from the way the
        // cut is built. It works with no budget at all: the §20.2 band gate can
        // move sets about too.
        //
        // The position here is the STORED one — the lens does not move it.
        var ordNow: [Pattern: Int] = [:]
        for ex in trimmedRaw { ordNow[ex.pattern] = Level.posOrd(state.position(ex.pattern)) }
        let trimmed = repairDescent(trimmedRaw, floors: floors, shownWork: state.shownWork,
                                    shownOrd: state.shownOrd, ordNow: ordNow,
                                    budgetChanged: state.shownBudget != budget)

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
    /// v2.25 (spec §36.6): the floor is a per-exercise number now, and it
    /// carries NO default — the pain channel's landing of a single set is the
    /// one place it drops below the shared two, and a caller that forgot to
    /// say so would silently hand that set back.
    static func clampSets(_ n: Int, floor: Int) -> Int { max(floor, n) }

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
    /// v2.25 (spec §36.8, round 4): THE SESSION-WIDE CUT IS BACK, and that is
    /// a deliberate rollback. The per-share scheme — every exercise fitting
    /// independently into its own slice of the budget — was introduced for the
    /// invariant "a descent never adds load BY CONSTRUCTION". The invariant
    /// turned out to be false: it is proven only INSIDE a set band, and a
    /// descent by a whole level — an honest fact below the plan, a deload, a
    /// chronic aim — crosses bands, and there the ground under the arithmetic
    /// falls away with the band. Measured: 1504 violations of 11,520 cells,
    /// 140 of them inside one variation, worst ×2.50. The price was steep too:
    /// 8.7–21.0 minutes of the budget thrown away, and the time handle
    /// distinguishing three positions on a scale from 15 to 95 minutes.
    ///
    /// The invariant is now held not by the shape of the cut but by CHECKING
    /// THE RESULT — see `repairDescent`. Checking it turned out to be both
    /// simpler and safer than deriving it.
    ///
    /// The cut itself is v2.24's in substance, but the victim is chosen
    /// WITHOUT READING THE DOSE: the set comes off the exercise with the most
    /// sets, ties by session order. The old greedy choice — "whoever saves the
    /// most seconds" — read doses, so a small change of dose moved the cut to
    /// another movement (audit 20.08, P0-2: 418 cells). The new order has no
    /// such class, and it also removes the churn in set counts (S1-07) and the
    /// unfairness to the start of the session order.
    private static func trimToBudget(_ exercises: [SessionExercise], floors: [Int],
                                     budget: Int, ends: Int) -> [SessionExercise] {
        var cur = exercises
        var total = estimatedMin(exercises: cur, ends: ends)
        while total > Double(budget) {
            var idx = -1
            var best = -1
            for i in cur.indices {
                let floor = floors[i]
                if cur[i].sets <= floor { continue }
                // A strict `>` leaves the win with the FIRST of equals, and the
                // session order is fixed — so the choice is deterministic.
                if cur[i].sets > best { best = cur[i].sets; idx = i }
            }
            // Everything on its floor: this is the shortest legal plan.
            // Running a little long is the accepted consequence of §35.2.
            guard idx >= 0 else { break }
            cur[idx] = Self.withSets(cur[idx], cur[idx].sets - 1, floor: floors[idx])
            total = estimatedMin(exercises: cur, ends: ends)
        }
        return cur
    }

    /// v2.25 (spec §36.8, round 4): THE POSTCONDITION REPAIR. The invariant the
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
                                      budgetChanged: Bool) -> [SessionExercise] {
        // The person moved the time handle — the last showing says nothing any
        // more. Without this the cap held the plan at the old limit until the
        // first growth event: raising 30 to 60 gave 45.9 minutes instead of
        // 59.1.
        guard !budgetChanged else { return exercises }
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
    /// v2.22 (spec §33): the sub-step is rebuilt for the new set count — it
    /// cannot ask for more sets than are left. Clamping to `sets-1` keeps the
    /// invariant "`load` is the plan's minimum": dropping a set gives the budget
    /// no right to raise that minimum.
    private static func withSets(_ ex: SessionExercise, _ requested: Int,
                                 floor: Int) -> SessionExercise {
        // v2.24 (spec §35.1): a rebuild is a cut too, so it goes through the
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
