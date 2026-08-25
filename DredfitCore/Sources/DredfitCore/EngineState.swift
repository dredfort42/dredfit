//
//  The engine's state: the fields, the tolerant decode of files written by
//  older builds, and the sanitizer that heals garbage on the way in. Split out
//  of Engine.swift when that file outgrew the lint's ceiling.
//

import Foundation

public struct EngineState: Codable, Equatable, Sendable {
    public var counter: Int
    public var levels: [Pattern: Int]
    /// The sub-step — how many of a pattern's sets already carry the next
    /// rung's dose. Range after sanitizing is `0...sets(L)-1`: at `sets(L)`
    /// sub-steps the rung is complete and the level rises on its own. Sparse —
    /// zeros are never stored — so a state file written before this existed
    /// decodes to all zeros, and the plan it produces is bit-for-bit the plan
    /// the previous version produced. No migration.
    ///
    /// On the top rung of a tier or band (`L mod 8 == 7`) the sub-step is
    /// DISABLED and the sanitizer forces it to zero: rung `L+1` there belongs
    /// to another variation, and two variations may never share one exercise.
    public var sub: [Pattern: Int]
    /// Sets taken off the level's plan. Range after sanitizing is `0...band −
    /// setsFloor`: the ceiling is the SHARED floor, and it is the only one —
    /// the pain channel's landing of a single set no longer exists, so a state
    /// carrying one is normalized up to two sets rather than preserved. Sparse
    /// — zeros are never stored — so a file written before this existed
    /// decodes to all zeros and the plan it produces is bit-for-bit what the
    /// previous version produced. No migration.
    ///
    /// The second axis of a position: the level fixes the VARIATION and the
    /// DOSE PER SET, the cut fixes only the VOLUME.
    public var cut: [Pattern: Int]
    /// Appearances left before the next set may come back. While it ticks, a
    /// growth event goes into the DOSE — the trainee keeps growing, just by a
    /// smaller step. Sparse, like every other counter here.
    public var setsHold: [Pattern: Int]
    /// The work shown in the last COMPLETED session, and the position it was
    /// shown AT. Together they are the input to the postcondition repair — "if
    /// a pattern's position did not rise, its plan may not get heavier".
    ///
    /// The third input, `shownBudget`, is gone with the budget. It existed
    /// because the budget worked PAST the position measure — it trimmed the
    /// plan without touching level, sub-step or cut, so moving the handle had
    /// to be declared a legitimate cause of growth by hand. The sets handle
    /// writes `cut`, a coordinate of the position, so releasing it IS a rise
    /// and the general gate excludes it on its own.
    ///
    /// `shownWork` is sparse on "work > 0", so an absent entry unambiguously
    /// means "never shown"; `shownOrd` is only meaningful where `shownWork`
    /// has an entry — the pair is written by one loop and always together.
    public var shownWork: [Pattern: Int]
    public var shownOrd: [Pattern: Int]
    public var failStreak: [Pattern: Int]
    public var hasBar: Bool
    /// How many "less" ratings in a row named no movement. The third such
    /// rating hands the delta back to the whole session — a run of unnamed
    /// "less" is a statement about the plan, not about one exercise.
    public var lessRun: Int
    /// Branches of the pull slot the cross-credit is paused for, because the
    /// last session they appeared in was reported as hard. The credit lands on
    /// sessions the branch is not in — the ones you cannot answer — so without
    /// this the level runs away from what you can do.
    public var creditPaused: Set<Pattern>
    /// Comebacks applied in a row with no completed session between them. Each
    /// one past the first deepens the drop by one — the plan must slide faster
    /// than fitness decays, or every return in a "come back once, vanish a
    /// month" series is infeasible.
    public var returnRun: Int
    /// The last appearances of each pattern as a bit mask — bit set = that
    /// appearance fell in a session rated an unnamed "less". Sparse: an empty
    /// mask is not stored, so a state file written before this existed decodes
    /// to exactly that.
    public var lessHist: [Pattern: Int]
    /// Sessions left in the limited-growth window a comeback opens — "more" is
    /// credited as "plan" and every rise is one.
    public var rampWindow: Int
    /// Levels gained inside the current weekly window and how old that window
    /// is in days. Both stay idle until the app supplies the gap signal —
    /// without it the engine is calendar-blind, as the model says.
    public var weekGain: [Pattern: Int]
    /// FRACTIONAL. Rounding it lost the fraction of a day for good, and two
    /// workouts inside one day left the window standing still forever. States
    /// written by older builds carry whole days and stay valid without a
    /// migration.
    public var weekAgeDays: Double

    // Spelled out (same names the compiler would synthesize) so that
    // decodeLenient can reference the type — synthesized CodingKeys are only
    // visible inside init(from:)/encode(to:). The wire format is unchanged.
    // Seven keys are gone — `frozen`, `sore`, `soreLeft`, `painSeen`,
    // `illness`, `timeBudgetMin`, `shownBudget`. A file written by an older
    // build still carries them; `decodeIfPresent`/`contains` never ask for
    // them, so they are simply ignored. That IS the migration.
    private enum CodingKeys: String, CodingKey {
        case counter, levels, failStreak, hasBar, lessRun, creditPaused,
             returnRun, lessHist, rampWindow, weekGain,
             weekAgeDays, sub,
             // Four sparse maps, all additive.
             cut, setsHold, shownWork, shownOrd
    }

    public init(counter: Int, levels: [Pattern: Int],
                failStreak: [Pattern: Int], hasBar: Bool = false,
                lessRun: Int = 0,
                creditPaused: Set<Pattern> = [],
                returnRun: Int = 0, lessHist: [Pattern: Int] = [:],
                rampWindow: Int = 0,
                weekGain: [Pattern: Int] = [:], weekAgeDays: Double = 0,
                sub: [Pattern: Int] = [:],
                cut: [Pattern: Int] = [:],
                setsHold: [Pattern: Int] = [:], shownWork: [Pattern: Int] = [:],
                shownOrd: [Pattern: Int] = [:]) {
        self.counter = counter
        self.levels = levels
        self.sub = sub
        self.cut = cut
        self.setsHold = setsHold
        self.shownWork = shownWork
        self.shownOrd = shownOrd
        self.failStreak = failStreak
        self.hasBar = hasBar
        self.lessRun = lessRun
        self.creditPaused = creditPaused
        self.returnRun = returnRun
        self.lessHist = lessHist
        self.rampWindow = rampWindow
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
        // the rotation — it would index out of bounds in generateSession. And
        // not a huge one either — `counter * rotationStep` near Int.max traps
        // the process on every plan.
        counter = Self.clamped(try c.decode(Int.self, forKey: .counter), 0, EngineConfig.countMax)
        var lv = try Self.decodeLenient(c, forKey: .levels)
        var fs = try Self.decodeLenient(c, forKey: .failStreak)
        for p in Pattern.allCases {
            // A level outside the scale used to survive decode and produce an
            // unearned deload on a successful session (`999` read as an old
            // level made every new one a shortfall).
            lv[p] = Self.clamped(lv[p] ?? 0, 0, EngineConfig.levelMax)
            fs[p] = Self.clamped(fs[p] ?? 0, 0, EngineConfig.countMax)
        }
        levels = lv
        failStreak = fs
        hasBar = try c.decodeIfPresent(Bool.self, forKey: .hasBar) ?? false
        // Additive: absent in every file an older build wrote, and a
        // hand-edited negative can only mean garbage.
        lessRun = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .lessRun) ?? 0,
                               0, EngineConfig.countMax)
        // Additive: absent from older files, and unknown patterns are dropped
        // the same way the level maps drop them. The pause is a map over the
        // pull slot's two branches — any other pattern is garbage the
        // reference filters out on every build, and used to live here forever.
        creditPaused = Set((try c.decodeIfPresent([String].self, forKey: .creditPaused) ?? [])
            .compactMap(Pattern.init(rawValue:))).intersection(Pattern.pullSide)
        // Additive, garbage sanitized as the reference does.
        returnRun = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .returnRun) ?? 0,
                                 0, EngineConfig.countMax)
        // Additive, sanitized as the reference does: only live masks survive,
        // each clamped to the window's width.
        lessHist = c.contains(.lessHist)
            ? try Self.decodeLenient(c, forKey: .lessHist)
                .filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineState.chronicMaskMax) }
            : [:]
        // Additive: absent in every file written before this.
        rampWindow = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .rampWindow) ?? 0,
                                  0, EngineConfig.rampWindowSessions)
        weekGain = c.contains(.weekGain)
            ? try Self.decodeLenient(c, forKey: .weekGain)
                .filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) }
            : [:]
        // Fractional now. A whole number written by an older build decodes
        // into a Double unchanged, so old files need no migration.
        weekAgeDays = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .weekAgeDays) ?? 0,
                                   0, Double(EngineConfig.countMax))
        // Additive; healed against the levels, so it is read last.
        sub = Self.healSub(c.contains(.sub) ? try Self.decodeLenient(c, forKey: .sub) : [:], levels: lv)
        // Additive. The cut is healed against the levels too — its ceiling is
        // a property of the level's band, not a constant.
        cut = Self.healCut(c.contains(.cut) ? try Self.decodeLenient(c, forKey: .cut) : [:],
                           levels: lv)
        setsHold = c.contains(.setsHold)
            ? try Self.decodeLenient(c, forKey: .setsHold)
                .filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.setsBackHold) }
            : [:]
        // Sparse on "work > 0": an absent entry means the plan was never
        // shown, which is what the repair reads it as.
        shownWork = c.contains(.shownWork)
            ? try Self.decodeLenient(c, forKey: .shownWork).filter { $0.value > 0 }
            : [:]
        // NOT sparse on zero: a shown position of exactly zero is a real
        // value, and only the presence of the key carries "was it shown".
        shownOrd = c.contains(.shownOrd) ? try Self.decodeLenient(c, forKey: .shownOrd) : [:]
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

    /// The state as the engine is willing to read it — the port's mirror of
    /// the reference's "rebuild every field through a sanitizer on every
    /// build". Decoding alone was not enough: the memberwise initializer is a
    /// second door (the app's migrations, a test, a future caller), and the
    /// reference heals the same garbage on every call. On the valid domain
    /// this is the identity, which is what keeps the golden fixture
    /// bit-for-bit.
    func sanitized() -> EngineState {
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
            lessRun: Self.clamped(lessRun, 0, EngineConfig.countMax),
            // The credit pause is a map over the pull slot's two branches; any
            // other pattern in there is garbage the reference filters out.
            creditPaused: creditPaused.intersection(Pattern.pullSide),
            returnRun: Self.clamped(returnRun, 0, EngineConfig.countMax),
            lessHist: lessHist.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineState.chronicMaskMax) },
            rampWindow: Self.clamped(rampWindow, 0, EngineConfig.rampWindowSessions),
            weekGain: weekGain.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.countMax) },
            weekAgeDays: Self.clamped(weekAgeDays, 0, Double(EngineConfig.countMax)),
            sub: Self.healSub(sub, levels: lv),
            cut: Self.healCut(cut, levels: lv),
            setsHold: setsHold.filter { $0.value >= 1 }
                .mapValues { Self.clamped($0, 1, EngineConfig.setsBackHold) },
            shownWork: shownWork.filter { $0.value > 0 },
            shownOrd: shownOrd)
    }

    /// The cut map, healed the way the reference heals it. The ceiling is the
    /// SHARED floor, and it is now the only one. A state written by an older
    /// build that sat on the pain channel's single set normalizes UP to two —
    /// 480 positions out of 480, worst `squat L0: 1×8 → 2×8`. That cost is
    /// named in the spec and accepted: one set of anything is lighter than two
    /// of the easiest thing, so no landing of the level could avoid it. Zeros
    /// are never stored, so a state that gave every set back is byte-identical
    /// to one that never lost any.
    static func healCut(_ src: [Pattern: Int], levels: [Pattern: Int]) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for (p, raw) in src {
            let level = clamped(levels[p] ?? 0, 0, EngineConfig.levelMax)
            let value = Level.effCut(level: level, cut: raw,
                                     floor: EngineConfig.setsFloor)
            if value > 0 { out[p] = value }
        }
        return out
    }

    /// The sub-step map, healed the way the reference heals it. Non-numbers
    /// and negatives read as zero; anything at or above the level's set band
    /// clamps to `sets-1`; the top rung of a tier or band is forced to zero,
    /// which is what makes "the plan on a top rung is always uniform" hold
    /// structurally rather than by a check inside the plan. Zeros are never
    /// stored, so a state that descended is byte-identical to one that never
    /// saw a sub-step at all.
    static func healSub(_ src: [Pattern: Int], levels: [Pattern: Int]) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for (p, raw) in src {
            let level = clamped(levels[p] ?? 0, 0, EngineConfig.levelMax)
            let value = Level.effectiveSub(level: level, sub: raw)
            if value > 0 { out[p] = value }
        }
        return out
    }

    /// The sets taken off a pattern, zero when none are.
    public func cutOf(_ pattern: Pattern) -> Int { cut[pattern] ?? 0 }

    /// The pattern's place on the progression — a TRIPLE: the sets taken off
    /// are a coordinate of the position, and every ceiling that reads a rise
    /// reads the measure over all three.
    public func position(_ pattern: Pattern) -> Position {
        Position(level: levels[pattern] ?? 0, sub: sub[pattern] ?? 0, cut: cut[pattern] ?? 0)
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
