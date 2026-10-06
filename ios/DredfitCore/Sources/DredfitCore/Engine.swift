//
//  Port of the reference adaptive_engine.js ("the measured ladder").
//  Behavior is verified by the golden tests (Fixtures/golden.json) generated
//  from that reference — any divergence is a port bug.
//
//  THE PRINCIPLE. The engine does not predict — it measures.
//  Everything assigned was either already shown by the trainee (assignment =
//  what was shown + 1 rep in one set) or is being shown right now by a probe.
//  There are no rep-prediction formulas (Epley or any other). The difficulty
//  measure `w` lives in the library and has exactly two jobs: the order of the
//  rungs and the density invariant (a step of at most ×1.50). No dose is
//  computed from it.
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
    case pullBar = "pull_bar"

    /// The two branches of the pull slot and the two push patterns — the sides
    /// the balance principle weighs against each other.
    public static let pullSide: Set<Pattern> = [.pull, .pullBar]
    static let pushSide: Set<Pattern> = [.pushH, .pushV]

    /// Fixed order — defines the rotation. The vertical branch is NOT in it:
    /// it never rotates, it stands in for `pull` in the fixed slot. Snapshots
    /// and every ten-element array use `allCases`, which is the reference's
    /// `ALL_PATTERNS` in the same order.
    public static let ordered: [Pattern] = [
        .squat, .pushH, .hinge, .pull, .pushV, .lunge, .coreAntiExt, .coreRot, .calf
    ]

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
    /// Sets on any variation but the bands of the top one.
    public static let setsBase = 3
    /// The ceiling on sets (bands 4 and 5 exist only on the top variation).
    public static let setsMax = 5
    public static let restSetSec = 60
    public static let restExerciseSec = 60
    static let tempoSecPerRep = 2.5
    static let patternsPerSession = 6
    /// Over eight sessions each rotating pattern comes up exactly five times.
    static let rotationStep = 3
    /// "less" is counted in growth events — one position back along the very
    /// path growth took.
    static let deltaLess = -1
    static let deltaPlan = 1
    public static let deltaMore = 2
    /// Default cell of the growth ceiling below.
    static let maxUpPerSession = 2
    public static let failsToDeload = 3
    /// How many "less" ratings in a row that named nothing before the delta
    /// goes back to the whole session. Measured, not chosen: at 1 the weak
    /// link suffers, at 3 the descent from an impossible plan costs another
    /// session.
    static let lessRunToGlobal = 2
    /// The deload: the sub-step comes off and the base dose drops three whole
    /// rungs (3 reps, 15 s), which keeps v2's deload of three levels at one
    /// rung per level. On the dose floor `fallDoses` takes it from the sets or
    /// the variation below instead, while there is one.
    static let deloadDrop = 3
    /// The two blocks are budgeted in whole minutes: the app's worst warm-up
    /// plus cool-down is 520 s against the 600 this and `cooldownMin` give
    /// (`BlockReserveTests`). Nine minutes would hold it; ten stays because a
    /// minute given back is a change to the reference engine and the golden
    /// fixture, and shortens every announced session length. The warm-up's
    /// six carry the minute for the counted switch of its split moves
    /// (Warmup.swift), and the Health estimate caps each block at its own
    /// minutes (`EnergyEstimate`).
    public static let warmupMin = 6
    /// The two blocks share a reserve of `warmupMin + cooldownMin` — see
    /// GetReady.swift for the arithmetic it is spent by.
    public static let cooldownMin = 4
    /// Rest between sets by BAND (the sets in the state, not the sets on
    /// screen): a cut takes volume off, not recovery.
    static let restSetByBand = [1: 60, 2: 60, 3: 60, 4: 90, 5: 120]
    /// (#144) Grgic 2018 and Schoenfeld 2016 give trained users ≥2 min on hard
    /// variations. On bands 1–3 the TOP VARIATION of a ladder gets 90 s
    /// instead of 60.
    /// Bands 4 and 5 exist only there and take their pause from `restSetByBand`.
    static let restSetTopVarSec = 90
    public static let comebackMinGapDays = 14
    static let comebackBase = 2
    static let comebackStepDays = 21
    static let comebackMax = 8
    public static let silentDecayGapDays = 7
    /// The technical ceiling of every counter and of the gap in days. This
    /// port does its arithmetic on Int64 and `counter * rotationStep` near
    /// `Int.max` traps the process on every plan. A million is 2700 years of
    /// daily sessions, so the clamp is identity on the valid domain.
    public static let countMax = 1_000_000
    /// The window of limited growth a comeback opens.
    public static let rampWindowSessions = 10
    /// The weekly growth budget, in growth events. Slow tissues — the pull
    /// slot and the calves.
    static let weeklyRiseSlow = 3
    static let weeklyRiseFast = 6
    static let weeklyWindowDays = 7
    /// The floor on how much a session ages the weekly window. A zero gap is
    /// always a source error, not a fact; without the floor the engine simply
    /// freezes for good.
    static let minSessionAgeDays = 1.0 / 24.0
    /// The SHARED floor on sets. It goes through `clampSets`,
    /// so it holds for any composition of cuts.
    public static let setsFloor = 2
    static let setsBackPerSession = 1
    /// How many steps a person may add to ONE movement for next time, per
    /// session. Two is a ceiling, not a norm — kept here so it changes in one
    /// line. Public because the summary's
    /// stepper stops where the handle would stop clamping.
    public static let raiseStepsMax = 2
    /// How many APPEARANCES a returned set is held before the next one may
    /// come back. The set axis is an order of magnitude coarser than the dose.
    public static let setsBackHold = 2
    /// The chronic signal (#137): a window of recent appearances.
    public static let chronicWindow = 4
    public static let chronicHits = 3
    static let chronicStep = -2
    /// Ceilings on where a comeback may land. Rows are [minimum gap, ceiling
    /// "floor" 1…4 (see `ceilVar`)], by descending gap; the first match wins.
    static let comebackLandingCeil = [(365, 1), (119, 2), (77, 3), (56, 4)]
    static let comebackCeilFloors = 4

    /// (#64) The growth ceiling is a table, not a scalar. Tendon and fascia
    /// remodel more slowly than muscle, and the one handle that acts BEFORE an
    /// overload is the rate of growth.
    ///
    /// Each entry is "how many of a ladder's TOP variations carry a ceiling of
    /// 1": calves — all of them (everything loads the Achilles), pull and vertical
    /// pull — the top three (#76: the fixed slot puts the pull in every
    /// session), vertical push — the top two (wall handstand work loads the
    /// shoulder girdle), everything else — the top one.
    static let maxUpTopVars: [Pattern: Int] = [
        .squat: 1, .pushH: 1, .hinge: 1, .pull: 3, .pushV: 2, .lunge: 1,
        .coreAntiExt: 1, .coreRot: 1, .calf: 5, .pullBar: 3,
    ]

    /// The growth ceiling for a (pattern, variation) cell.
    static func maxUp(pattern: Pattern, variation: Int) -> Int {
        let v = Library.index(pattern: pattern, variation: variation)
        return Library.count(pattern) - v < (maxUpTopVars[pattern] ?? 0) ? 1 : maxUpPerSession
    }

    /// A "slow tissue" pattern — a ceiling of 1 on EVERY variation (today only
    /// the calves). Derived from the table rather than duplicated as a list.
    static func isSlowTissue(_ pattern: Pattern) -> Bool {
        (maxUpTopVars[pattern] ?? 0) >= Library.count(pattern)
    }
}

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

public enum Engine {

    /// Rotating patterns (all except pull — it appears in every session).
    static let rotating: [Pattern] = Pattern.ordered.filter { $0 != .pull }

    /// A probe's number is one set of one movement — an integer by nature —
    /// clamped to the technical range.
    static func sanitizeProbe(_ raw: Int) -> Int {
        EngineState.clamped(raw, -EngineConfig.countMax, EngineConfig.countMax)
    }

    /// A reported number, clamped to the technical range. Past it every fact
    /// already saturates, so this is identity on anything a person could log.
    /// A fact is NOT rounded on the way in. The mean of an uneven plan sits
    /// strictly between its base and its top (8-7-7 → 7.33), and it is the
    /// fraction that answers "did they take the top set": [7,7,7] gives 7.00,
    /// [8,7,7] gives 7.33. Snapping to the integer grid would make those two
    /// indistinguishable. The fraction lives only in comparisons; every
    /// ASSIGNED dose is still an integer on the grid.
    static func sanitizeActual(_ raw: Double) -> Double {
        guard raw.isFinite else { return 0 }
        return min(max(raw, -Double(EngineConfig.countMax)), Double(EngineConfig.countMax))
    }

    // MARK: - Writing a position back

    /// Sparseness is part of the contract: the base set count, a zero sub-step
    /// and an empty cut are not stored, so the state after a descent is
    /// bit-for-bit the state that never saw either.
    static func setPosition(_ next: inout EngineState, _ p: Pattern, _ raw: Position) {
        let pos = fit(p, raw)
        next.vars[p] = pos.variation
        next.doses[p] = pos.dose
        if pos.sets != EngineConfig.setsBase { next.sets[p] = pos.sets } else { next.sets[p] = nil }
        if pos.sub > 0 { next.sub[p] = pos.sub } else { next.sub[p] = nil }
        if pos.cut > 0 { next.cut[p] = pos.cut } else { next.cut[p] = nil }
    }

    /// The pull cap a push was shown under — the slot's sets then (with the bar,
    /// the weaker branch's) and its own sets then — with the trace of a cut
    /// taken off it closed: this showing is the new reference. One write for
    /// both places a showing is remembered, the feedback and `recordShown`.
    static func rememberCap(_ next: inout EngineState, _ p: Pattern, _ pos: Position, cap: Int) {
        guard Pattern.pushSide.contains(p) else { return }
        next.shownCap[p] = cap
        next.shownOwn[p] = setsAfterCut(sets: pos.sets, cut: pos.cut)
        next.shownSkip.remove(p)
    }

    /// The journal of what was shown: ONE point of writing in the whole engine.
    static func setShown(_ next: inout EngineState, _ p: Pattern, _ v: Int, _ dose: Int) {
        let unit = Library.unit(p, v)
        let d = min(Dose.snap(unit, dose), Dose.grid(unit).max)
        guard d > 0 else { return }
        next.shown[p, default: [:]][Library.index(pattern: p, variation: v)] = d
    }

    /// The whole ladder of a pattern as a measure — what the progress scale
    /// reads. Position zero is the clean start; the top is 5×15 (5×45 s) on
    /// the last variation.
    public static func ladderSpan(_ p: Pattern) -> Int {
        let unit = Library.unit(p, Library.count(p))
        return posOrd(p, Position(variation: Library.count(p), sets: EngineConfig.setsMax,
                                  dose: Dose.grid(unit).max, sub: 0, cut: 0))
    }

    /// How far along its ladder a pattern stands — the ordinal every
    /// screen that shows progress reads.
    public static func progress(_ state: EngineState, _ p: Pattern) -> Int {
        posOrd(p, state.sanitized().position(p))
    }

    /// The same measure for a position the app recorded earlier. The journal
    /// stores the position rather than the measure because the measure has no
    /// inverse — this is the one direction that exists.
    ///
    /// All five coordinates: a snapshot replotted without `sub` and `cut` would
    /// sit off the number beside it by its sub-steps less its cut. A record
    /// that carries neither passes zeros, which is all the shorter form below
    /// does. The coordinates arrive as one `Position` so the call stays within
    /// the parameter-count limit.
    public static func progress(_ p: Pattern, _ position: Position) -> Int {
        posOrd(p, fit(p, position))
    }

    public static func progress(_ p: Pattern, variation: Int, sets: Int, dose: Int) -> Int {
        progress(p, Position(variation: variation, sets: sets, dose: dose, sub: 0, cut: 0))
    }

    /// The sum of those ordinals — the total progress across all patterns.
    public static func totalProgress(_ state: EngineState) -> Int {
        let clean = state.sanitized()
        return Pattern.allCases.reduce(0) { $0 + posOrd($1, clean.position($1)) }
    }

    /// Where each variation begins on that ordinal — the ticks of the progress
    /// bar. The first is always 0 and is left out: a scale marks its divisions,
    /// not its start.
    public static func variationBoundaries(_ p: Pattern) -> [Int] {
        (2...Library.count(p)).map { varBase(p, $0) }
    }

    /// How many growth events still separate a pattern from the dose ceiling
    /// of its CURRENT variation; sets taken off are not counted. Zero does not
    /// promise a probe: `probeAllowed` also wants a variation that is not the
    /// top one, the journal on that ceiling, and a last answer that was not
    /// "hard".
    public static func stepsToVariationCeiling(_ state: EngineState, _ p: Pattern) -> Int {
        let pos = state.sanitized().position(p)
        var ceiling = pos
        ceiling.dose = Dose.grid(Library.unit(p, pos.variation)).max
        ceiling.sub = 0
        return max(0, posOrd(p, fit(p, ceiling)) - posOrd(p, pos))
    }

    /// Record the plan the person SAW, with no feedback. The app owns the
    /// state and can call this right after showing the plan — then "a descent
    /// never adds load" holds against a plan that was seen and not done.
    ///
    /// An exercise WITH A PROBE writes its memory too, by `shownWorkOf`: the
    /// working sets plus the slot the probe occupies (see there for why).
    /// Otherwise the base would stay a showing two appearances old:
    /// a descent would knock the dose off the ceiling, the probe would go with
    /// it, the third working set would come back, and the "easier" plan would
    /// ask +40 % of the work the person had actually seen.
    ///
    /// A push keeps the cap it was shown under as well: a showing on screen is
    /// the one the next plan's "the cap has risen since" is measured from.
    public static func recordShown(state dirty: EngineState, session: Session) -> EngineState {
        let state = dirty.sanitized()
        var next = state
        let cap = pullSlotSets(state)
        for ex in session.exercises {
            next.shownWork[ex.pattern] = shownWorkOf(ex)
            next.shownOrd[ex.pattern] = posOrd(ex.pattern, state.position(ex.pattern))
            rememberCap(&next, ex.pattern, state.position(ex.pattern), cap: cap)
        }
        return next
    }
}
