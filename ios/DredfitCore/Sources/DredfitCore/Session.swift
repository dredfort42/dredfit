//
//  What a workout looks like on the day: the session value types, the
//  rotation, the probe, and the duration estimate.
//

import Foundation

// MARK: - Session

public enum LoadUnit: String, Codable, Sendable {
    case reps, hold
}

/// The last set of an exercise, swapped for one set of the NEXT variation
/// (§40.4). It is not a question and not a new screen: the number comes back
/// through the per-set channel that already exists (§37.8).
public struct SessionProbe: Codable, Equatable, Sendable {
    public let variation: Int
    public let name: String
    public let unit: LoadUnit
    public let load: Int
    public let perSide: Bool

    public init(variation: Int, name: String, unit: LoadUnit, load: Int, perSide: Bool) {
        self.variation = variation
        self.name = name
        self.unit = unit
        self.load = load
        self.perSide = perSide
    }

    /// "4" / "15 sec" / "4 per side" — one set, so no "N×".
    public var display: String {
        let side = perSide ? " " + String(localized: "per side", bundle: .module) : ""
        switch unit {
        case .reps: return "\(load)\(side)"
        case .hold: return "\(load) " + String(localized: "sec", bundle: .module) + side
        }
    }
}

public struct SessionExercise: Codable, Equatable, Identifiable, Sendable {
    public var id: Pattern { pattern }
    public let pattern: Pattern
    public let name: String
    /// 1-based index along the pattern's ladder (§40.1). Replaces `tier`: with
    /// `L` gone there are no tiers, only variations.
    public let variation: Int
    public let unit: LoadUnit
    public let load: Int          // the BASE dose: reps or seconds, per side if perSide
    public let perSide: Bool
    public let sets: Int
    public let restSetSec: Int
    public let restExerciseSec: Int
    /// Per-set doses, descending — `9-8-8`. OPTIONAL on purpose, and the
    /// optionality is compatibility, not style: a journal written by an older
    /// build carries no such key. `nil` means a uniform plan.
    public let loads: [Int]?
    /// Present only where the probe condition of §40.4 holds. The WORKING sets
    /// are already one fewer — the session's volume does not grow.
    public let probe: SessionProbe?

    /// The floor for THIS exercise. Service state: it never leaves the
    /// process, so it is out of `CodingKeys` (a journal must not carry it) and
    /// out of `==` (two plans that differ only here are the same plan). The
    /// reference keeps it non-enumerable for exactly these two reasons.
    public internal(set) var setsFloor: Int

    private enum CodingKeys: String, CodingKey {
        case pattern, name, variation, unit, load, perSide, sets,
             restSetSec, restExerciseSec, loads, probe
    }

    /// `setsFloor` carries a default for one reason: a caller OUTSIDE the
    /// engine rebuilding an exercise (the app's remaining-minutes estimate
    /// does) cannot know the floor this plan was built with and does not need
    /// to — nothing outside the engine reads it. Inside the engine every call
    /// site passes it explicitly.
    public init(pattern: Pattern, name: String, variation: Int, unit: LoadUnit,
                load: Int, perSide: Bool, sets: Int, restSetSec: Int,
                restExerciseSec: Int, loads: [Int]?, probe: SessionProbe?,
                setsFloor: Int = EngineConfig.setsFloor) {
        self.pattern = pattern
        self.name = name
        self.variation = variation
        self.unit = unit
        self.load = load
        self.perSide = perSide
        self.sets = sets
        self.restSetSec = restSetSec
        self.restExerciseSec = restExerciseSec
        self.loads = loads
        self.probe = probe
        self.setsFloor = setsFloor
    }

    /// Records written before v3 carry `tier` where this now reads
    /// `variation`, and no `probe` at all. The ENGINE state has no migration
    /// (§40.8) — the JOURNAL does, because history is what actually happened
    /// and a record that will not decode is history lost.
    ///
    /// Such a record decodes with `variation == 0`, which is no rung of any
    /// ladder and is meant to read as exactly one thing: this line predates
    /// §40.1, and its own `name` is the only truth about what was done. The
    /// old tier numbers point at DIFFERENT movements in the v3 ladders, so
    /// re-resolving a name through them would quietly rewrite the person's
    /// history — the very failure the library pin exists to prevent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try c.decode(Pattern.self, forKey: .pattern)
        name = try c.decode(String.self, forKey: .name)
        variation = try c.decodeIfPresent(Int.self, forKey: .variation) ?? 0
        unit = try c.decode(LoadUnit.self, forKey: .unit)
        load = try c.decode(Int.self, forKey: .load)
        perSide = try c.decode(Bool.self, forKey: .perSide)
        sets = try c.decode(Int.self, forKey: .sets)
        restSetSec = try c.decode(Int.self, forKey: .restSetSec)
        restExerciseSec = try c.decode(Int.self, forKey: .restExerciseSec)
        loads = try c.decodeIfPresent([Int].self, forKey: .loads)
        probe = try c.decodeIfPresent(SessionProbe.self, forKey: .probe)
        setsFloor = EngineConfig.setsFloor
    }

    public static func == (lhs: SessionExercise, rhs: SessionExercise) -> Bool {
        lhs.pattern == rhs.pattern && lhs.name == rhs.name
            && lhs.variation == rhs.variation && lhs.unit == rhs.unit
            && lhs.load == rhs.load && lhs.perSide == rhs.perSide
            && lhs.sets == rhs.sets && lhs.restSetSec == rhs.restSetSec
            && lhs.restExerciseSec == rhs.restExerciseSec
            && lhs.loads == rhs.loads && lhs.probe == rhs.probe
    }

    /// Every set's planned dose, uniform plan included.
    ///
    /// Bounded by the SCALE, not by the record: `sets` comes back out of the
    /// journal unclamped and this is called from a row body on the main
    /// thread, so a hand-edited `Int.max` would allocate until the app is
    /// killed. No exercise ever had more sets than the scale has bands, so the
    /// valid domain never notices the clamp.
    var perSetLoads: [Int] {
        let count = min(max(sets, 0), EngineConfig.setsMax)
        guard let loads, !loads.isEmpty else {
            return Array(repeating: load, count: count)
        }
        return Array(loads.prefix(count))
    }

    /// What set `index` is planned to run at — the plan's own answer, before
    /// anything the trainee reports.
    public func plannedLoad(set index: Int) -> Int {
        guard let loads, !loads.isEmpty else { return load }
        return loads[min(max(index, 0), loads.count - 1)]
    }

    /// The volume the plan asks for across all WORKING sets. The probe is not
    /// in it: it belongs to another variation, and adding up reps of two
    /// different movements is exactly the incommensurability §40 forbids.
    public var plannedVolume: Int { perSetLoads.reduce(0, +) }

    /// "3×12", "3×10 per side", "3×40 sec" — "9-8-8" when the sets differ.
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

    public static func estimatedMin(
        exercises: [SessionExercise],
        ends: Int = EngineConfig.warmupMin + EngineConfig.cooldownMin) -> Double {
        var workSec = 0.0
        for ex in exercises {
            let sides = ex.perSide ? 2 : 1
            workSec += ex.unit == .reps
                ? Double(ex.plannedVolume * sides) * EngineConfig.tempoSecPerRep
                : Double(ex.plannedVolume * sides)
            // The probe counts as its own set: the session's volume does not
            // grow, and it does not shrink either.
            var sets = ex.sets
            if let probe = ex.probe {
                let pSides = probe.perSide ? 2 : 1
                workSec += probe.unit == .reps
                    ? Double(probe.load * pSides) * EngineConfig.tempoSecPerRep
                    : Double(probe.load * pSides)
                sets += 1
            }
            workSec += Double((sets - 1) * ex.restSetSec) + Double(ex.restExerciseSec)
        }
        return roundedToTenths((workSec + Double(ends * 60)) / 60)
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
    /// A tie is exactly a value that is an ODD number of quarters — 10x is a
    /// half-integer only for x = m/4 with m odd, because a dyadic fraction has
    /// no other way to sit halfway between two tenths. Scaling by four is exact
    /// for every finite double, so the test itself introduces no error.
    static func roundedToTenths(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let quarters = value * 4
        if quarters == quarters.rounded(), quarters.truncatingRemainder(dividingBy: 2) != 0 {
            return (value * 10).rounded(.up) / 10
        }
        return Double(String(format: "%.1f", value)) ?? value
    }

    /// §40.4: the probe condition. The dose is on its variation's ceiling, the
    /// variation is not the top one, and the last answer for the pattern was
    /// not "hard". That last clause does NOT follow from `failStreak`: a
    /// deload zeroes the streak, and "hard" does not stop having been said.
    /// §41.4 (v3.1): the gate reads the JOURNAL OF WHAT WAS SHOWN, not only the
    /// dose the plan climbed to. A trainee whose real maximum is 14 against a
    /// ceiling of 15 was handed the probe eleven times in 75 appearances, did
    /// it, and had the result thrown away — because in that same session they
    /// honestly entered 14 for the old movement. Not maxed, no probe, and the
    /// last set stays a working one. The rule only became possible alongside
    /// §41.3: before it the journal held the plan's top, and a gate on the
    /// journal would have been no different from a gate on the dose.
    static func probeAllowed(_ p: Pattern, _ pos: Position, lastHard: Set<Pattern>,
                             shown: [Pattern: [Int: Int]]) -> Bool {
        let ceiling = Dose.grid(Library.unit(p, pos.variation)).max
        return !Library.isTop(p, pos.variation)
            && pos.dose >= ceiling
            && (shown[p]?[pos.variation] ?? 0) >= ceiling
            && !lastHard.contains(p)
    }

    /// A pure function: the only input is the state.
    public static func generateSession(_ dirty: EngineState) -> Session {
        // Every public entry heals its input first, as the reference does on
        // every build. Identity on the valid domain.
        let state = dirty.sanitized()
        let n = rotating.count
        // Nonnegative modulo: Swift's % is a remainder and goes negative with
        // a negative counter, which would index out of bounds below.
        let start = (((state.counter * EngineConfig.rotationStep) % n) + n) % n
        let five = (0..<(EngineConfig.patternsPerSession - 1)).map { rotating[(start + $0) % n] }
        let chosen = Set([Pattern.pull] + five)
        let useBar = state.hasBar && state.counter % 2 == 1
        let patterns = Pattern.ordered.filter { chosen.contains($0) }
            .map { $0 == .pull && useBar ? Pattern.pullBar : $0 }

        func setsShown(_ p: Pattern) -> Int {
            let q = state.position(p)
            return setsAfterCut(sets: q.sets, cut: q.cut)
        }
        // The pull slot's set count caps the push of the same session, and it
        // reads the WEAKER of the slot's two branches rather than whichever
        // one stands today: on diverged branches the push plan would otherwise
        // flip every session with no cause on screen.
        let pullSets = patterns.contains(where: { Pattern.pullSide.contains($0) })
            ? (state.hasBar ? min(setsShown(.pull), setsShown(.pullBar)) : setsShown(patterns.first { Pattern.pullSide.contains($0) }!))
            : EngineConfig.setsMax

        let exercises: [SessionExercise] = patterns.map { p in
            let pos = state.position(p)
            let unit = Library.unit(p, pos.variation)
            let sides = Library.sides(p, pos.variation)
            // ONE order of cuts (v2.25 §36.6): band → sets handle → the §20.2
            // gate → floor. Each next one may only lower.
            let ownSets = setsAfterCut(sets: pos.sets, cut: pos.cut)
            let floor = min(EngineConfig.setsFloor, ownSets)
            let slotSets = clampSets(
                Pattern.pushSide.contains(p) ? min(ownSets, pullSets) : ownSets, floor: floor)
            // The pause is a property of the BAND (the sets in the state), not
            // of the number shown: a cut takes volume off, not recovery.
            let restSet = Library.isTop(p, pos.variation) && pos.sets <= EngineConfig.setsBase
                ? EngineConfig.restSetTopVarSec
                : (EngineConfig.restSetByBand[pos.sets] ?? EngineConfig.restSetSec)

            // §40.4: the probe replaces the LAST of the remaining sets.
            let probing = probeAllowed(p, pos, lastHard: state.lastHard, shown: state.shown)
            let sets = probing ? slotSets - 1 : slotSets
            var probe: SessionProbe?
            if probing {
                let nv = pos.variation + 1
                let nUnit = Library.unit(p, nv)
                probe = SessionProbe(variation: nv, name: Library.name(p, nv), unit: nUnit,
                                     load: Dose.grid(nUnit).min,
                                     perSide: Library.sides(p, nv) == 2)
            }
            return SessionExercise(
                pattern: p, name: Library.name(p, pos.variation), variation: pos.variation,
                unit: unit, load: pos.dose, perSide: sides == 2, sets: sets,
                restSetSec: restSet, restExerciseSec: EngineConfig.restExerciseSec,
                loads: planLoads(p, pos, sets: sets), probe: probe,
                // With a probe the floor drops to one working set: the slot's
                // second set is taken by the probe, and the shared floor of two
                // is held by the slot as a whole, not by one half of it.
                setsFloor: probing ? max(1, floor - 1) : floor)
        }

        // The postcondition "a descent never adds load" is checked ON THE
        // RESULT rather than derived from the way the cut is built. With no
        // time budget left, only the band gate can still move sets about — but
        // it can, so the repair stays.
        var ordNow: [Pattern: Int] = [:]
        for ex in exercises { ordNow[ex.pattern] = posOrd(ex.pattern, state.position(ex.pattern)) }
        let trimmed = repairDescent(exercises, shownWork: state.shownWork,
                                    shownOrd: state.shownOrd, ordNow: ordNow)

        return Session(
            sessionNumber: state.counter + 1,
            warmupMin: EngineConfig.warmupMin,
            cooldownMin: EngineConfig.cooldownMin,
            exercises: trimmed,
            estimatedTotalMin: estimatedMin(
                exercises: trimmed, ends: EngineConfig.warmupMin + EngineConfig.cooldownMin))
    }

    /// The work of an exercise in the units of the measure: sets × dose ×
    /// sides, sub-steps included. The probe is NOT in it (see `plannedVolume`).
    static func exerciseWork(_ ex: SessionExercise) -> Int {
        ex.plannedVolume * (ex.perSide ? 2 : 1)
    }

    /// §41.11 (v3.3): the work a SHOWING remembers. It differs from
    /// `exerciseWork` on exactly one shape — a probing appearance, where the
    /// probe does not remove a set but OCCUPIES one: the position still holds
    /// the same `sets`, and the session is no shorter for it, which is why
    /// `estimatedMin` counts the probe as its own set. The memory is written
    /// as if the borrowed set were still there.
    ///
    /// Counting the probe at its own dose does not save it: the repair below
    /// can only TAKE SETS OFF, so its base has to be about slots rather than
    /// about reps. With the working-sets base the depth of a comeback stopped
    /// being monotone in the length of the break — 84 days met a person higher
    /// than 56 did — and a descent took away the set the probe had borrowed.
    static func shownWorkOf(_ ex: SessionExercise) -> Int {
        guard ex.probe != nil else { return exerciseWork(ex) }
        return exerciseWork(ex) + ex.load * (ex.perSide ? 2 : 1)
    }

    /// THE POSTCONDITION REPAIR (v2.25 §36.6, round 4). The invariant the
    /// model promises is "if a pattern's position did not rise, its plan
    /// cannot get heavier". Deriving it from the shape of the cut did not
    /// survive three rounds of skeptics, so it is checked on the result: a
    /// movement whose position has not risen since it was last shown, and
    /// whose shown work has grown, loses sets until it stops. The loop is
    /// finite (taking a set off strictly reduces the work) and bounded below
    /// by the floor.
    ///
    /// An exercise WITH A PROBE is left alone: it has one working set fewer by
    /// construction, so there is nothing to trim inside a probing appearance.
    ///
    /// §41.10 (v3.2): its memory IS written now. It used to be skipped —
    /// "2×15 plus a probe" and "3×15" were called incommensurable — and the
    /// base stayed a showing two appearances old. What is actually compared is
    /// the work of one and the same movement: same variation, same unit, same
    /// sides.
    ///
    /// §41.11 (v3.3): and it is written by `shownWorkOf`, which counts the set
    /// the probe occupied. By the working sets alone the base sat one set
    /// below the position, so this loop took away a set the probe had only
    /// borrowed — a 20-day comeback read `2×13` while the position held three
    /// — and the depth of a comeback stopped being monotone in the break.
    ///
    /// The comparison is NON-STRICT: "the position did not rise" covers both
    /// "fell" and "stood still".
    private static func repairDescent(_ exercises: [SessionExercise],
                                      shownWork: [Pattern: Int], shownOrd: [Pattern: Int],
                                      ordNow: [Pattern: Int]) -> [SessionExercise] {
        exercises.map { ex in
            let p = ex.pattern
            if ex.probe != nil { return ex }
            guard let work = shownWork[p], let ord = shownOrd[p] else { return ex }
            if (ordNow[p] ?? 0) > ord { return ex }
            var cur = ex
            while cur.sets > cur.setsFloor, exerciseWork(cur) > work {
                cur = withSets(cur, cur.sets - 1, floor: cur.setsFloor)
            }
            return cur
        }
    }

    /// Rebuild an exercise on a different set count. The pause is NOT
    /// recomputed: the sets handle and the band gate take volume off, not
    /// recovery, and the time budget the pause once travelled with is gone.
    /// The sub-step is rebuilt for the new count — it cannot ask for more sets
    /// than are left, and clamping to `sets-1` keeps "`load` is the plan's
    /// minimum" true.
    private static func withSets(_ ex: SessionExercise, _ requested: Int,
                                 floor: Int) -> SessionExercise {
        let sets = clampSets(requested, floor: floor)
        let high = ex.loads?.first ?? ex.load
        let carried = ex.loads?.filter { $0 > ex.load }.count ?? 0
        let sub = min(carried, max(sets - 1, 0))
        let loads: [Int]? = sub > 0 ? (0..<sets).map { $0 < sub ? high : ex.load } : nil
        return SessionExercise(
            pattern: ex.pattern, name: ex.name, variation: ex.variation, unit: ex.unit,
            load: ex.load, perSide: ex.perSide, sets: sets,
            restSetSec: ex.restSetSec, restExerciseSec: ex.restExerciseSec,
            loads: loads, probe: ex.probe, setsFloor: ex.setsFloor)
    }
}
