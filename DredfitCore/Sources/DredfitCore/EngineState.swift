//
//  EngineState.swift
//  DredfitCore
//
//  The engine's state: the fields, the tolerant decode of files written by
//  older builds, and the sanitizer that heals garbage on the way in (spec
//  §17.4/§24.1). Split out of Engine.swift when that file outgrew the lint's
//  ceiling; the code moved unchanged.
//

import Foundation

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
    /// v2.20 (spec §31.2): how many CLEAN appearances the episode still needs
    /// before it closes — the second way out, for the trainee who logs no
    /// numbers. A clean appearance is one where the pattern was trained and
    /// the session carried no "it was hard" signal about it; each one spends
    /// one tick, and at zero both this and `sore` are dropped.
    ///
    /// It is a SEPARATE field from `sore` on purpose (spec §31.3): `sore`
    /// holds the episode's freeze ASSIGNMENT, and two rules read it — the
    /// 3 → 6 → 12 rest ladder and which report this is in the two-step unload
    /// (§30.6). A counting-down `sore` would misread both, and an assignment
    /// of 6 worn down to 3 would land the variation drop a SECOND time.
    ///
    /// Sparse and only ever alongside a live `sore`. A missing entry for a
    /// live episode reads as the FULL assignment, so an episode opened before
    /// v2.20 gets a whole confirmation window instead of closing on the first
    /// appearance — old files need no migration.
    public var soreLeft: [Pattern: Int]
    /// v2.12 (spec §22.3): comebacks applied in a row with no completed
    /// session between them. Each one past the first deepens the drop by one
    /// — the plan must slide faster than fitness decays, or every return in
    /// a "come back once, vanish a month" series is infeasible.
    public var returnRun: Int
    /// v2.12 (spec §22.4): sessions left under the "I was sick" lens — the
    /// plan is one tier easier, the stored levels stand.
    public var illness: Int
    /// v2.15 (spec §26.1): the last appearances of each pattern as a bit mask
    /// — bit set = that appearance fell in a session rated an unnamed "less".
    /// Sparse: an empty mask is not stored, so a state file written before this
    /// existed decodes to exactly that.
    public var lessHist: [Pattern: Int]
    /// v2.17 (spec §28.4): sessions left in the limited-growth window a
    /// comeback opens — "more" is credited as "plan" and every rise is one.
    public var rampWindow: Int
    /// v2.17 (spec §28.3): the session-time budget in minutes; 0 = no limit.
    /// It trims the PLAN and never the levels.
    public var timeBudgetMin: Int
    /// v2.17 (spec §28.5): levels gained inside the current weekly window and
    /// how old that window is in days. Both stay idle until the app supplies
    /// the gap signal — without it the engine is calendar-blind, as §7 says.
    public var weekGain: [Pattern: Int]
    /// v2.19 (spec §30.8): FRACTIONAL. Rounding it lost the fraction of a day
    /// for good, and two workouts inside one day left the window standing
    /// still forever. States written before v2.19 carry whole days and stay
    /// valid without a migration.
    public var weekAgeDays: Double

    // Spelled out (same names the compiler would synthesize) so that
    // decodeLenient can reference the type — synthesized CodingKeys are only
    // visible inside init(from:)/encode(to:). The wire format is unchanged.
    private enum CodingKeys: String, CodingKey {
        case counter, levels, failStreak, hasBar, frozen, lessRun, creditPaused, sore,
             soreLeft, returnRun, illness, lessHist, rampWindow, timeBudgetMin, weekGain,
             weekAgeDays
    }

    public init(counter: Int, levels: [Pattern: Int],
                failStreak: [Pattern: Int], hasBar: Bool = false,
                frozen: [Pattern: Int] = [:], lessRun: Int = 0,
                creditPaused: Set<Pattern> = [], sore: [Pattern: Int] = [:],
                soreLeft: [Pattern: Int] = [:],
                returnRun: Int = 0, illness: Int = 0, lessHist: [Pattern: Int] = [:],
                rampWindow: Int = 0, timeBudgetMin: Int = 0,
                weekGain: [Pattern: Int] = [:], weekAgeDays: Double = 0) {
        self.counter = counter
        self.levels = levels
        self.failStreak = failStreak
        self.hasBar = hasBar
        self.frozen = frozen
        self.lessRun = lessRun
        self.creditPaused = creditPaused
        self.sore = sore
        self.soreLeft = soreLeft
        self.returnRun = returnRun
        self.illness = illness
        self.lessHist = lessHist
        self.rampWindow = rampWindow
        self.timeBudgetMin = timeBudgetMin
        self.weekGain = weekGain
        self.weekAgeDays = weekAgeDays
    }

    /// Lenient in both directions: files written before hasBar/pull_bar
    /// existed get the defaults, and entries for unknown patterns (a file
    /// written by a future version, opened after a downgrade) are dropped
    /// instead of failing the whole decode and losing the user's history.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A corrupt or hand-edited file must not feed a negative counter into
        // the rotation — it would index out of bounds in generateSession.
        // v2.13 (§24.1): and not a huge one either — `counter * rotationStep`
        // near Int.max traps the process on every plan.
        counter = Self.clamped(try c.decode(Int.self, forKey: .counter), 0, EngineConfig.countMax)
        var lv = try Self.decodeLenient(c, forKey: .levels)
        var fs = try Self.decodeLenient(c, forKey: .failStreak)
        for p in Pattern.allCases {
            // v2.13 (§24.1): a level outside the scale used to survive decode
            // and produce an unearned deload on a successful session (`999`
            // read as an old level made every new one a shortfall).
            lv[p] = Self.clamped(lv[p] ?? 0, 0, EngineConfig.levelMax)
            fs[p] = Self.clamped(fs[p] ?? 0, 0, EngineConfig.countMax)
        }
        levels = lv
        failStreak = fs
        hasBar = try c.decodeIfPresent(Bool.self, forKey: .hasBar) ?? false
        // Additive: absent in every file written before the discomfort input,
        // and zero counters are never written, so this stays empty until a
        // pattern is actually frozen.
        frozen = c.contains(.frozen)
            ? try Self.decodeLenient(c, forKey: .frozen)
                .filter { $0.value > 0 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) }
            : [:]
        // Additive, same shape as `frozen`: absent in every file written
        // before v2.9, and a hand-edited negative can only mean garbage.
        lessRun = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .lessRun) ?? 0,
                               0, EngineConfig.countMax)
        // Additive: absent before v2.10, and unknown patterns are dropped the
        // same way the level maps drop them. v2.13 (§24.1): the pause is a map
        // over the pull slot's two branches — any other pattern is garbage the
        // reference filters out on every build, and used to live here forever.
        creditPaused = Set((try c.decodeIfPresent([String].self, forKey: .creditPaused) ?? [])
            .compactMap(Pattern.init(rawValue:))).intersection(Pattern.pullSide)
        // Additive, sanitized as the reference does (§21.4): only positive
        // entries survive, values are clamped to the ladder's ceiling.
        let episodes: [Pattern: Int] = c.contains(.sore)
            ? try Self.decodeLenient(c, forKey: .sore)
                .filter { $0.value >= 1 }
                .mapValues { min($0, EngineConfig.freezeCapAppearances) }
            : [:]
        sore = episodes
        // Additive (v2.20, §31.3): the confirmation countdown. Absent for a
        // live episode means the FULL assignment — that is how a file written
        // before v2.20 gets a whole confirmation window rather than closing on
        // the first appearance. An entry without a live episode is garbage.
        let left: [Pattern: Int] = c.contains(.soreLeft)
            ? try Self.decodeLenient(c, forKey: .soreLeft)
            : [:]
        soreLeft = Self.healSoreLeft(left, episodes: episodes)
        // Additive (v2.12, §22.3-22.4), garbage sanitized as the reference does.
        returnRun = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .returnRun) ?? 0,
                                 0, EngineConfig.countMax)
        illness = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .illness) ?? 0,
                               0, EngineConfig.illnessSessions)
        // Additive (v2.15, §26.1), sanitized as the reference does: only live
        // masks survive, each clamped to the window's width.
        lessHist = c.contains(.lessHist)
            ? try Self.decodeLenient(c, forKey: .lessHist)
                .filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineState.chronicMaskMax) }
            : [:]
        // Additive (v2.17, §28): absent in every file written before this.
        rampWindow = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .rampWindow) ?? 0,
                                  0, EngineConfig.rampWindowSessions)
        let budget = try c.decodeIfPresent(Int.self, forKey: .timeBudgetMin) ?? 0
        timeBudgetMin = budget > 0 ? Self.clamped(budget, 5, EngineConfig.countMax) : 0
        weekGain = c.contains(.weekGain)
            ? try Self.decodeLenient(c, forKey: .weekGain)
                .filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) }
            : [:]
        // v2.19 (§30.8): fractional now. A whole number written by v2.17-v2.18
        // decodes into a Double unchanged, so old files need no migration.
        weekAgeDays = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .weekAgeDays) ?? 0,
                                   0, Double(EngineConfig.countMax))
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

    /// v2.13 (spec §24.1, issue #132): the state as the engine is willing to
    /// read it — the port's mirror of the reference's "rebuild every field
    /// through a sanitizer on every build". Decoding alone was not enough:
    /// the memberwise initializer is a second door (the app's migrations, a
    /// test, a future caller), and the reference heals the same garbage on
    /// every call. On the valid domain this is the identity, which is what
    /// keeps the golden fixture bit-for-bit.
    func sanitized() -> EngineState {
        let healedEpisodes = sore.filter { $0.value >= 1 }
            .mapValues { Self.clamped($0, 1, EngineConfig.freezeCapAppearances) }
        var lv: [Pattern: Int] = [:]
        var fs: [Pattern: Int] = [:]
        for p in Pattern.allCases {
            lv[p] = Self.clamped(levels[p] ?? 0, 0, EngineConfig.levelMax)
            fs[p] = Self.clamped(failStreak[p] ?? 0, 0, EngineConfig.countMax)
        }
        return EngineState(
            counter: Self.clamped(counter, 0, EngineConfig.countMax),
            levels: lv,
            failStreak: fs,
            hasBar: hasBar,
            // Sparse maps keep only live entries, exactly as the reference does.
            frozen: frozen.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) },
            lessRun: Self.clamped(lessRun, 0, EngineConfig.countMax),
            // The credit pause is a map over the pull slot's two branches; any
            // other pattern in there is garbage the reference filters out.
            creditPaused: creditPaused.intersection(Pattern.pullSide),
            sore: healedEpisodes,
            soreLeft: Self.healSoreLeft(soreLeft, episodes: healedEpisodes),
            returnRun: Self.clamped(returnRun, 0, EngineConfig.countMax),
            illness: Self.clamped(illness, 0, EngineConfig.illnessSessions),
            lessHist: lessHist.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineState.chronicMaskMax) },
            rampWindow: Self.clamped(rampWindow, 0, EngineConfig.rampWindowSessions),
            timeBudgetMin: timeBudgetMin > 0
                ? Self.clamped(timeBudgetMin, 5, EngineConfig.countMax) : 0,
            weekGain: weekGain.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) },
            weekAgeDays: Self.clamped(weekAgeDays, 0, Double(EngineConfig.countMax)))
    }

    /// v2.20 (spec §31.3): the confirmation countdown, healed the way the
    /// reference heals it. A tick without a live episode is dropped; a tick
    /// above its own assignment is impossible by construction (the countdown
    /// starts AT the assignment and only falls), so it clamps down to it; and
    /// a missing tick for a live episode reads as the full assignment.
    static func healSoreLeft(_ src: [Pattern: Int],
                             episodes: [Pattern: Int]) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for (p, assigned) in episodes {
            let raw = src[p] ?? 0
            out[p] = raw >= 1
                ? min(clamped(raw, 1, EngineConfig.freezeCapAppearances), assigned)
                : assigned
        }
        return out
    }

    static func clamped(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

    /// v2.19 (spec §30.8): the same clamp for the fractional window age. A
    /// NaN is neither `< lo` nor `> hi`, so it is turned into the floor here
    /// rather than smuggled into the arithmetic.
    static func clamped(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v.isFinite ? min(max(v, lo), hi) : lo
    }

    /// The widest a window mask can be (v2.15, §26.1).
    static var chronicMaskMax: Int { (1 << EngineConfig.chronicWindow) - 1 }

    /// How many of the last appearances fell in a failed session.
    func chronicHits(_ pattern: Pattern) -> Int {
        (lessHist[pattern] ?? 0).nonzeroBitCount
    }

    /// v2.15 (spec §26.1): does the chronic signal fire for this pattern?
    func chronicFires(_ pattern: Pattern) -> Bool {
        chronicHits(pattern) >= EngineConfig.chronicHits
    }
}
