//
//  The engine's state (§40.2): six coordinates per pattern, the journal of
//  what was shown, and the global counters that survived v2 unchanged.
//
//  THERE IS NO MIGRATION FROM v2 — owner's decision, 25.08.2026 (§40.8). A
//  state written by an older build carries no `vars` and no `doses`, so the
//  decode below FAILS on it and the app hands the engine `initial`: every
//  pattern on its first rung at 3×4 (3×15 s). The workout journal — the
//  history the person has actually lived — is a different file and is not
//  touched. Code that reads the old shape is deliberately not written: people
//  walk back to their own level with the honest-numbers rule (§40.3, §40.8),
//  in about two appearances per variation, and a reader that guessed at old
//  levels would be predicting exactly what §40.0 forbids.
//

import Foundation

public struct EngineState: Codable, Equatable, Sendable {
    public var counter: Int
    public var hasBar: Bool

    // MARK: - The position, one coordinate per map

    /// Index along the pattern's ladder, 1…N. Dense: every pattern has one.
    public var vars: [Pattern: Int]
    /// Reps — or seconds — per set. Dense, in the unit of the CURRENT variation.
    public var doses: [Pattern: Int]
    /// Sets. Sparse, and the base of 3 is never stored — so a state that never
    /// entered a band is byte-identical to one that came back out of it. Bands
    /// 4 and 5 exist only on the top variation (§40.5).
    public var sets: [Pattern: Int]
    /// The sub-step (v2.22): the first `sub` sets carry one rung more. Sparse.
    public var sub: [Pattern: Int]
    /// Sets taken off (v2.25 §36). Sparse.
    public var cut: [Pattern: Int]
    /// THE JOURNAL OF WHAT WAS SHOWN: per variation touched, the last dose
    /// actually performed, in that variation's own unit. Written after every
    /// appearance — by the fact when numbers are entered, by the plan when the
    /// tap is used (§40.2).
    ///
    /// It is both the point of return (§40.6) and the ceiling on any
    /// assignment (И2). Doubly sparse: a pattern with no entries is not
    /// stored, a variation with no entry is not stored.
    public var shown: [Pattern: [Int: Int]]

    // MARK: - Global fields, unchanged in meaning since v2 (§40.7)

    /// Appearances left before the next set may come back. While it ticks, a
    /// growth event goes into the DOSE.
    public var setsHold: [Pattern: Int]
    /// The work shown in the last COMPLETED appearance, and the position it
    /// was shown AT — the two inputs to the postcondition repair.
    public var shownWork: [Pattern: Int]
    public var shownOrd: [Pattern: Int]
    public var failStreak: [Pattern: Int]
    /// Patterns whose last appearance the person called hard. A NEW field, and
    /// it cannot be derived from `failStreak`: a deload zeroes the streak,
    /// while the probe condition of §40.4 ("the last answer was not «hard»")
    /// has to outlive the deload.
    public var lastHard: Set<Pattern>
    /// How many "less" ratings in a row named no movement.
    public var lessRun: Int
    /// Branches of the pull slot the cross-credit is paused for.
    public var creditPaused: Set<Pattern>
    /// Comebacks applied in a row with no completed session between them.
    public var returnRun: Int
    /// The last appearances of each pattern as a bit mask — bit set = that
    /// appearance fell in a session rated an unnamed "less".
    public var lessHist: [Pattern: Int]
    /// Sessions left in the limited-growth window a comeback opens.
    public var rampWindow: Int
    /// Growth events spent inside the current weekly window, and how old that
    /// window is in days. Both stay idle until the app supplies the gap.
    public var weekGain: [Pattern: Int]
    /// FRACTIONAL. Rounding it lost the fraction of a day for good, and two
    /// workouts inside one day left the window standing still forever.
    public var weekAgeDays: Double

    // Spelled out (same names the compiler would synthesize) so decodeLenient
    // can reference the type — synthesized CodingKeys are only visible inside
    // init(from:)/encode(to:).
    private enum CodingKeys: String, CodingKey {
        case counter, hasBar, vars, doses, sets, sub, cut, shown,
             setsHold, shownWork, shownOrd, failStreak, lastHard,
             lessRun, creditPaused, returnRun, lessHist, rampWindow,
             weekGain, weekAgeDays
    }

    public init(counter: Int, vars: [Pattern: Int], doses: [Pattern: Int],
                failStreak: [Pattern: Int], hasBar: Bool,
                sets: [Pattern: Int], sub: [Pattern: Int], cut: [Pattern: Int],
                shown: [Pattern: [Int: Int]], setsHold: [Pattern: Int],
                shownWork: [Pattern: Int], shownOrd: [Pattern: Int],
                lastHard: Set<Pattern>, lessRun: Int, creditPaused: Set<Pattern>,
                returnRun: Int, lessHist: [Pattern: Int], rampWindow: Int,
                weekGain: [Pattern: Int], weekAgeDays: Double) {
        self.counter = counter
        self.vars = vars
        self.doses = doses
        self.failStreak = failStreak
        self.hasBar = hasBar
        self.sets = sets
        self.sub = sub
        self.cut = cut
        self.shown = shown
        self.setsHold = setsHold
        self.shownWork = shownWork
        self.shownOrd = shownOrd
        self.lastHard = lastHard
        self.lessRun = lessRun
        self.creditPaused = creditPaused
        self.returnRun = returnRun
        self.lessHist = lessHist
        self.rampWindow = rampWindow
        self.weekGain = weekGain
        self.weekAgeDays = weekAgeDays
    }

    /// `vars` and `doses` are REQUIRED, and that is the whole of the
    /// no-migration decision in code: a v2 file has `levels` instead and
    /// throws here, which is what the app reads as "start clean". Every other
    /// field is additive and tolerant, exactly as before — a v3 file written
    /// by a build that predates a later field must keep working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counter = Self.clamped(try c.decode(Int.self, forKey: .counter),
                               0, EngineConfig.countMax)
        vars = try Self.decodeLenient(c, forKey: .vars)
        doses = try Self.decodeLenient(c, forKey: .doses)
        hasBar = try c.decodeIfPresent(Bool.self, forKey: .hasBar) ?? false
        sets = c.contains(.sets) ? try Self.decodeLenient(c, forKey: .sets) : [:]
        sub = c.contains(.sub) ? try Self.decodeLenient(c, forKey: .sub) : [:]
        cut = c.contains(.cut) ? try Self.decodeLenient(c, forKey: .cut) : [:]
        shown = c.contains(.shown) ? try Self.decodeShown(c, forKey: .shown) : [:]
        failStreak = c.contains(.failStreak)
            ? try Self.decodeLenient(c, forKey: .failStreak) : [:]
        setsHold = c.contains(.setsHold) ? try Self.decodeLenient(c, forKey: .setsHold) : [:]
        shownWork = c.contains(.shownWork) ? try Self.decodeLenient(c, forKey: .shownWork) : [:]
        shownOrd = c.contains(.shownOrd) ? try Self.decodeLenient(c, forKey: .shownOrd) : [:]
        lastHard = Set((try c.decodeIfPresent([String].self, forKey: .lastHard) ?? [])
            .compactMap(Pattern.init(rawValue:)))
        lessRun = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .lessRun) ?? 0,
                               0, EngineConfig.countMax)
        creditPaused = Set((try c.decodeIfPresent([String].self, forKey: .creditPaused) ?? [])
            .compactMap(Pattern.init(rawValue:))).intersection(Pattern.pullSide)
        returnRun = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .returnRun) ?? 0,
                                 0, EngineConfig.countMax)
        lessHist = c.contains(.lessHist) ? try Self.decodeLenient(c, forKey: .lessHist) : [:]
        rampWindow = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .rampWindow) ?? 0,
                                  0, EngineConfig.rampWindowSessions)
        weekGain = c.contains(.weekGain) ? try Self.decodeLenient(c, forKey: .weekGain) : [:]
        weekAgeDays = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .weekAgeDays) ?? 0,
                                   0, Double(EngineConfig.countMax))
    }

    /// Manual decode of the exact wire format Swift synthesizes for a
    /// `[Pattern: Int]`: an UNKEYED array alternating [rawValue, count, ...]
    /// (see the warning on Pattern). The encode side stays synthesized — the
    /// format is byte-compatible. Entries for unknown patterns (a file written
    /// by a future version, opened after a downgrade) are dropped rather than
    /// failing the whole decode.
    private static func decodeLenient(
        _ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [Pattern: Int] {
        var uc = try c.nestedUnkeyedContainer(forKey: key)
        var out: [Pattern: Int] = [:]
        while !uc.isAtEnd {
            let raw = try uc.decode(String.self)
            let value = try uc.decode(Int.self)   // a malformed pair is still a real error
            if let p = Pattern(rawValue: raw) { out[p] = value }
        }
        return out
    }

    /// The journal, one level deeper: the outer map is the same unkeyed
    /// alternating form, the inner `[Int: Int]` is a keyed object because
    /// Swift special-cases integer keys.
    private static func decodeShown(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys) throws -> [Pattern: [Int: Int]] {
        var uc = try c.nestedUnkeyedContainer(forKey: key)
        var out: [Pattern: [Int: Int]] = [:]
        while !uc.isAtEnd {
            let raw = try uc.decode(String.self)
            let row = try uc.decode([Int: Int].self)
            if let p = Pattern(rawValue: raw) { out[p] = row }
        }
        return out
    }

    /// §40.8: a clean start — every pattern on its first rung, 3×4 (3×15 s).
    public static var initial: EngineState {
        var vars: [Pattern: Int] = [:]
        var doses: [Pattern: Int] = [:]
        var streaks: [Pattern: Int] = [:]
        for p in Pattern.allCases {
            vars[p] = 1
            doses[p] = Dose.grid(Library.unit(p, 1)).min
            streaks[p] = 0
        }
        return EngineState(counter: 0, vars: vars, doses: doses, failStreak: streaks,
                           hasBar: false, sets: [:], sub: [:], cut: [:], shown: [:],
                           setsHold: [:], shownWork: [:], shownOrd: [:], lastHard: [],
                           lessRun: 0, creditPaused: [], returnRun: 0, lessHist: [:],
                           rampWindow: 0, weekGain: [:], weekAgeDays: 0)
    }

    /// The state as the engine is willing to read it — the port's mirror of
    /// "rebuild every field through a sanitizer on every call". Decoding alone
    /// was never enough: the memberwise initializer is a second door. On the
    /// valid domain this is the identity, which is what keeps the golden
    /// fixture bit-for-bit.
    ///
    /// The ORDER matters and mirrors `readState`: variations first (they fix
    /// the unit and the set ceiling), then sets, then doses, then the cut,
    /// then the sub-step, which needs all four.
    func sanitized() -> EngineState {
        var cleanVars: [Pattern: Int] = [:]
        var cleanStreaks: [Pattern: Int] = [:]
        for p in Pattern.allCases {
            cleanVars[p] = Self.clamped(vars[p] ?? 1, 1, Library.count(p))
            cleanStreaks[p] = Self.clamped(failStreak[p] ?? 0, 0, EngineConfig.countMax)
        }
        var cleanSets: [Pattern: Int] = [:]
        var cleanDoses: [Pattern: Int] = [:]
        for p in Pattern.allCases {
            let v = cleanVars[p]!
            if let raw = sets[p] {
                let value = Self.clamped(raw, EngineConfig.setsBase, Engine.setsCeil(p, v))
                if value != EngineConfig.setsBase { cleanSets[p] = value }
            }
            let unit = Library.unit(p, v)
            cleanDoses[p] = doses[p].map { Dose.clamped(unit, Dose.snap(unit, $0)) }
                ?? Dose.grid(unit).min
        }
        var cleanCut: [Pattern: Int] = [:]
        for (p, raw) in cut {
            let value = Engine.effCut(sets: cleanSets[p] ?? EngineConfig.setsBase, cut: raw)
            if value > 0 { cleanCut[p] = value }
        }
        var cleanSub: [Pattern: Int] = [:]
        for (p, raw) in sub {
            let pos = Position(variation: cleanVars[p] ?? 1,
                               sets: cleanSets[p] ?? EngineConfig.setsBase,
                               dose: cleanDoses[p] ?? 0, sub: raw,
                               cut: cleanCut[p] ?? 0)
            let value = Engine.effSub(p, pos, sets: nil)
            if value > 0 { cleanSub[p] = value }
        }
        return EngineState(
            counter: Self.clamped(counter, 0, EngineConfig.countMax),
            vars: cleanVars, doses: cleanDoses, failStreak: cleanStreaks, hasBar: hasBar,
            sets: cleanSets, sub: cleanSub, cut: cleanCut,
            shown: Self.healShown(shown),
            setsHold: setsHold.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.setsBackHold) },
            shownWork: shownWork.filter { $0.value > 0 },
            shownOrd: shownOrd,
            lastHard: lastHard,
            lessRun: Self.clamped(lessRun, 0, EngineConfig.countMax),
            creditPaused: creditPaused.intersection(Pattern.pullSide),
            returnRun: Self.clamped(returnRun, 0, EngineConfig.countMax),
            lessHist: lessHist.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineState.chronicMaskMax) },
            rampWindow: Self.clamped(rampWindow, 0, EngineConfig.rampWindowSessions),
            weekGain: weekGain.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) },
            weekAgeDays: Self.clamped(weekAgeDays, 0, Double(EngineConfig.countMax)))
    }

    /// The journal, healed. A value is snapped and capped by the SCALE of the
    /// variation it belongs to — the journal has no right to promise more than
    /// the ladder can show. It is NOT clamped from below: "I showed two reps"
    /// is a fact too, and it is exactly the one that sends a person a
    /// variation down (§40.3). The dose floor is applied at LANDING.
    static func healShown(_ src: [Pattern: [Int: Int]]) -> [Pattern: [Int: Int]] {
        var out: [Pattern: [Int: Int]] = [:]
        for p in Pattern.allCases {
            guard let row = src[p] else { continue }
            var dst: [Int: Int] = [:]
            for v in 1...Library.count(p) {
                guard let raw = row[v] else { continue }
                let unit = Library.unit(p, v)
                let d = min(Dose.snap(unit, raw), Dose.grid(unit).max)
                if d > 0 { dst[v] = d }
            }
            if !dst.isEmpty { out[p] = dst }
        }
        return out
    }

    /// The sets taken off a pattern, zero when none are.
    public func cutOf(_ pattern: Pattern) -> Int { cut[pattern] ?? 0 }

    /// The pattern's place on its ladder — all six coordinates.
    public func position(_ pattern: Pattern) -> Position {
        Position(variation: vars[pattern] ?? 1,
                 sets: sets[pattern] ?? EngineConfig.setsBase,
                 dose: doses[pattern] ?? 0,
                 sub: sub[pattern] ?? 0,
                 cut: cut[pattern] ?? 0)
    }

    /// The last dose recorded for a variation, if the trainee has ever been
    /// there. The app's progress screens read the ladder through this.
    public func shownDose(_ pattern: Pattern, variation: Int) -> Int? {
        shown[pattern]?[variation]
    }

    static func clamped(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

    /// The same clamp for the fractional window age. A NaN is neither `< lo`
    /// nor `> hi`, so it is turned into the floor here rather than smuggled
    /// into the arithmetic.
    static func clamped(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v.isFinite ? min(max(v, lo), hi) : lo
    }

    /// The widest a window mask can be.
    static var chronicMaskMax: Int { (1 << EngineConfig.chronicWindow) - 1 }

    /// How many of the last appearances fell in a failed session.
    func chronicHits(_ pattern: Pattern) -> Int {
        (lessHist[pattern] ?? 0).nonzeroBitCount
    }

    /// Does the chronic signal fire for this pattern?
    func chronicFires(_ pattern: Pattern) -> Bool {
        chronicHits(pattern) >= EngineConfig.chronicHits
    }
}
