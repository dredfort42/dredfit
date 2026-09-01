//
//  What a finished workout leaves behind, and what an unfinished one holds
//  on to. Both are read back out of one JSON file, so both are inputs.
//

import Foundation
import DredfitCore

/// Where a pattern stood, in the terms v3 states a position in. Three numbers
/// and no measure: the measure is derived from them when it is needed, and
/// deriving it the other way round is impossible on purpose.
struct RecordedPosition: Codable, Equatable {
    let variation: Int
    let sets: Int
    let dose: Int
    /// The two sparse coordinates, recorded since the UI-truth audit
    /// (27.08.2026): without them the per-pattern chart replotted a snapshot
    /// up to two steps off the number beside it. Optional with a nil default,
    /// like every field added to a persisted type — a record written by an
    /// older build carries neither key, and a nil encodes to nothing, so a
    /// position that never saw a sub-step stays byte-identical on disk.
    let sub: Int?
    let cut: Int?

    init(variation: Int, sets: Int, dose: Int, sub: Int? = nil, cut: Int? = nil) {
        self.variation = variation
        self.sets = sets
        self.dose = dose
        self.sub = sub
        self.cut = cut
    }

    /// Clamped on the way in, for the reason `WorkoutRecord` states below and
    /// was the one field here that did not honour: these five go straight into
    /// `Engine.progress`, and `Dose.rung` SUBTRACTS the grid floor from the
    /// dose before anything clamps it. A hand-edited `Int.min` trapped there
    /// (SIGTRAP, confirmed) — the app died opening Progress rather than
    /// drawing a silly number.
    ///
    /// `dose` keeps its sign: a descent legitimately reads BELOW a grid's
    /// floor and `Dose.rung` documents the negative term. Every real value
    /// sits far inside these bounds, so no record on disk reads differently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
        variation = clamp(try c.decode(Int.self, forKey: .variation), 1, EngineConfig.countMax)
        sets = clamp(try c.decode(Int.self, forKey: .sets), 0, EngineConfig.countMax)
        dose = clamp(try c.decode(Int.self, forKey: .dose),
                     -EngineConfig.countMax, EngineConfig.countMax)
        sub = try c.decodeIfPresent(Int.self, forKey: .sub)
            .map { clamp($0, 0, EngineConfig.countMax) }
        cut = try c.decodeIfPresent(Int.self, forKey: .cut)
            .map { clamp($0, 0, EngineConfig.countMax) }
    }
}

struct WorkoutRecord: Codable, Identifiable, Equatable {
    // sessionNumber alone is NOT unique: resetProgress restarts the counter
    // while the journal survives, so identity needs the date too.
    var id: String { "\(sessionNumber)-\(date.timeIntervalSince1970)" }
    let sessionNumber: Int
    let date: Date
    let result: FeedbackResult
    /// How far along their ladders every pattern stood after this session,
    /// summed — what "total level" used to be, in the one scale v3 has
    /// (§40.2). OPTIONAL: a record written before v3 carries a number on a
    /// different scale entirely, and pretending otherwise would put a
    /// meaningless delta on the week card.
    var totalProgressAfter: Int?
    // Optional so older records still decode.
    var exercises: [SessionExercise]?
    /// The number the ENGINE was given for each adjusted pattern — the mean
    /// of its sets (`SetFacts.override`). Kept under its old name and shape
    /// so records written by any earlier build keep reading true.
    var actuals: [Pattern: Int]?
    /// The sets behind that mean, in order. The detail the history line
    /// shows when the sets did not all run the same.
    var setActuals: [Pattern: [Int]]?
    /// Sets skipped DURING the session, per movement — the count the engine
    /// turned into a cut. Written because it is part of what happened: a plan
    /// of 5×8 answered with three sets is not the same session as one answered
    /// in full, and a journal that keeps only the rating cannot tell
    /// them apart afterwards. Whether the mid-workout skip becomes the
    /// dominant price is still an open question, and this is the only place
    /// it can ever be answered from.
    var setsSkipped: [Pattern: Int]?
    var skipped: Set<Pattern>?
    /// Reported as painful mid-workout: to the engine a skip, to the journal a
    /// different fact — and the reason the pattern is resting afterwards.
    /// LEGACY, read-only. The pain report is gone, and nothing writes this any
    /// more — but a journal on disk still carries it, and a record that loses
    /// the fact is a record that lies about what happened. Kept so history
    /// stays readable; never populated again.
    var discomfort: Set<Pattern>?
    /// The position of every pattern after the session. A scalar can no longer
    /// stand in for it: the measure of §40.2 has NO INVERSE by construction,
    /// so "what was I doing then" has to be recorded as the movement and the
    /// dose it actually was.
    var positionsAfter: [Pattern: RecordedPosition]?
    var durationSec: Int?
    /// Seconds the two guided blocks ACTUALLY ran. Both end on one tap of a
    /// footer button, so their planned lengths are an intention, not a fact —
    /// and the calorie estimate was charging nine planned minutes to people
    /// who may have declined both. Optional with a nil default like every
    /// field added to a persisted type: a record written by an older build
    /// carries neither key, and nil reads as "never measured", which is not
    /// the same as the zero a declined block writes.
    var warmupSec: Int?
    var cooldownSec: Int?
    /// Only `true` is ever written; nil means "not exported yet".
    var healthExported: Bool?

    /// The journal is an input too. The engine heals the state it is handed,
    /// but its own snapshots come back out of this file and straight into
    /// arithmetic — the retrospective subtracts a stored level from the
    /// current one, the week summary subtracts two totals — and a hand-edited
    /// `Int.min` traps that subtraction instead of saturating. Every number
    /// here is clamped to the range it can mean; the valid domain never
    /// notices.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
        sessionNumber = clamp(try c.decode(Int.self, forKey: .sessionNumber),
                              0, EngineConfig.countMax)
        date = try c.decode(Date.self, forKey: .date)
        result = try c.decode(FeedbackResult.self, forKey: .result)
        totalProgressAfter = try c.decodeIfPresent(Int.self, forKey: .totalProgressAfter)
            .map { clamp($0, 0, EngineConfig.countMax) }
        exercises = try c.decodeIfPresent([SessionExercise].self, forKey: .exercises)
        actuals = try c.decodeIfPresent([Pattern: Int].self, forKey: .actuals)?
            .mapValues { clamp($0, 0, EngineConfig.countMax) }
        // No exercise has more sets than the scale has bands, so a longer
        // array is a hand-edited file, not a workout.
        setActuals = try c.decodeIfPresent([Pattern: [Int]].self, forKey: .setActuals)?
            .mapValues { $0.prefix(EngineConfig.setsMax).map { clamp($0, 0, EngineConfig.countMax) } }
        setsSkipped = try c.decodeIfPresent([Pattern: Int].self, forKey: .setsSkipped)?
            .mapValues { clamp($0, 0, EngineConfig.setsMax) }
        skipped = try c.decodeIfPresent(Set<Pattern>.self, forKey: .skipped)
        discomfort = try c.decodeIfPresent(Set<Pattern>.self, forKey: .discomfort)
        positionsAfter = try c.decodeIfPresent([Pattern: RecordedPosition].self,
                                              forKey: .positionsAfter)
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
            .map { clamp($0, 0, EngineConfig.countMax) }
        warmupSec = try c.decodeIfPresent(Int.self, forKey: .warmupSec)
            .map { clamp($0, 0, EngineConfig.countMax) }
        cooldownSec = try c.decodeIfPresent(Int.self, forKey: .cooldownSec)
            .map { clamp($0, 0, EngineConfig.countMax) }
        healthExported = try c.decodeIfPresent(Bool.self, forKey: .healthExported)
    }

    init(sessionNumber: Int, date: Date, result: FeedbackResult,
         totalProgressAfter: Int? = nil,
         exercises: [SessionExercise]? = nil, actuals: [Pattern: Int]? = nil,
         setActuals: [Pattern: [Int]]? = nil, setsSkipped: [Pattern: Int]? = nil,
         skipped: Set<Pattern>? = nil, discomfort: Set<Pattern>? = nil,
         positionsAfter: [Pattern: RecordedPosition]? = nil,
         durationSec: Int? = nil,
         warmupSec: Int? = nil, cooldownSec: Int? = nil,
         healthExported: Bool? = nil) {
        self.sessionNumber = sessionNumber
        self.date = date
        self.result = result
        self.totalProgressAfter = totalProgressAfter
        self.exercises = exercises
        self.actuals = actuals
        self.setActuals = setActuals
        self.setsSkipped = setsSkipped
        self.skipped = skipped
        self.discomfort = discomfort
        self.positionsAfter = positionsAfter
        self.durationSec = durationSec
        self.warmupSec = warmupSec
        self.cooldownSec = cooldownSec
        self.healthExported = healthExported
    }
}

/// How long one guided block ran, resolved once at its ending.
///
/// Pure, and here rather than inline in the flow, because the flow's own call
/// sites sit inside a SwiftUI view that nothing automated drives — this is the
/// part of the measurement that can be held to a test.
nonisolated enum BlockRun {
    /// No start means the block was DECLINED: zero, not unknown. The whole
    /// downstream model turns on that difference — unknown falls back to the
    /// planned length, declined bills nothing at all.
    static func seconds(began: Date?, ended: Date) -> Int {
        guard let began else { return 0 }
        return max(0, Int(ended.timeIntervalSince(began)))
    }
}

/// Written on every phase transition, so iOS evicting the process mid-session
/// does not lose it.
struct WorkoutSnapshot: Codable, Equatable {
    var sessionNumber: Int
    /// During rest this is still the set the rest FOLLOWS (the flow advances
    /// after rest) — restore replays that advance when the countdown expired.
    var exIndex: Int
    var setIndex: Int
    var restEndDate: Date?
    var restTotalSec: Int?
    /// What this transition PLANNED, which `restTotalSec` stops being as soon
    /// as the rest is extended — and the extension cap is twice the planned
    /// one. Optional like the fields below: a snapshot from an older build
    /// decodes and falls back to the total it does carry.
    var restPlannedSec: Int?
    /// Per-set facts, index = set: a number entered on the third set is the
    /// third set's. Optional so a snapshot written before a fact belonged to
    /// its own set still decodes.
    var setActuals: [Pattern: [Int]]?
    /// Sets skipped so far, per movement. Optional like everything
    /// below it: a snapshot written before the skip existed still decodes.
    var setsSkipped: [Pattern: Int]?
    /// What the PROBE set showed, per movement (§40.4). Its own field for the
    /// same reason it is its own argument to the engine: it is a number about
    /// a movement that is not in the plan yet, and folding it into the per-set
    /// facts would average two variations. Optional — a snapshot written
    /// before the probe existed decodes without it.
    var probes: [Pattern: Int]?
    /// The shape that came before — one number per exercise. Only ever
    /// DECODED (`facts` folds it into the current one), but it stays a stored
    /// property so an older snapshot round-trips rather than failing the file.
    var actuals: [Pattern: Int] = [:]
    var skipped: Set<Pattern> = []
    /// Optional, like the fields below: a snapshot written by an older build
    /// must still decode rather than take the whole file down with it. LEGACY,
    /// read-only. The pain report is gone, and nothing writes this any more —
    /// but a journal on disk still carries it, and a record that loses the
    /// fact is a record that lies about what happened. Kept so history stays
    /// readable; never populated again.
    var discomfort: Set<Pattern>?
    var workoutStart: Date
    var savedAt: Date
    /// The session number alone is not identity: the bar toggle and an
    /// accepted comeback both regenerate a *different* session under the
    /// *same* number, and a snapshot must never resume into exercises it was
    /// not taken from. Optional (with the fields below) so an older snapshot
    /// decodes and then fails this check, rather than failing the whole file.
    var fingerprint: String?
    /// Restore lands on the rating, not on the set the fields still describe.
    var atFeedback: Bool?
    /// Restore lands on the finished movement's SUMMARY. Without it a kill on
    /// that screen would come back on the last set and offer to run it again —
    /// an effort that is behind, with its seconds already recorded.
    var atExerciseSummary: Bool?
    /// How long the athlete DECLARED the hold in front of them would run,
    /// before doing it. Restored so that coming back after a process death
    /// does not quietly put the plan's number back on the clock.
    var holdDeclaredSec: Int?
    /// Sets of the exercise in front of us whose number is an ESTIMATE — the
    /// set ended under a thumb, so it carries a guessed reach allowance. An
    /// array
    /// because a `Set<Int>` is one on the wire anyway; read back as a set.
    var approxSets: [Int]?
    var interrupted: Pattern?
    /// The two blocks as measured so far, carried across a process death so a
    /// declined warm-up is not silently restored as a performed one. A kill
    /// DURING a block leaves its field nil — the block never reached its own
    /// ending — and the record then falls back to the planned length. That is
    /// the one case this does not rescue, and it is the old behaviour rather
    /// than a new claim.
    var warmupSec: Int?
    var cooldownSec: Int?

    /// What the flow restores into. A snapshot from before this shape kept
    /// one number per exercise, and that number was in force from the first
    /// set on — which is exactly what a one-element array says.
    /// Sanitized on the way out: unlike the journal's records this struct has
    /// no decoder of its own, and everything here comes back off disk.
    var facts: SetFacts.PerSet {
        SetFacts.sanitized(setActuals ?? actuals.mapValues { [$0] })
    }

    /// The probe numbers, sanitized where they are read for the same reason as
    /// `facts`. A probe target is a dose, so it lives in the same corridor any
    /// reported number does.
    var probeFacts: [Pattern: Int] {
        (probes ?? [:]).compactMapValues { value in
            min(max(value, 0), EngineConfig.countMax)
        }
    }

    /// Sanitized where it is read, for the same reason as `facts`: this struct
    /// has no decoder of its own and everything here comes back off disk.
    var skips: SetFacts.Skips {
        SetFacts.sanitized(skips: setsSkipped ?? [:])
    }

    /// The estimate marks, bounded by what an exercise can hold. Sanitized
    /// where it is read for the same reason as everything above it.
    var approximateSets: Set<Int> {
        Set((approxSets ?? []).filter { (0..<EngineConfig.setsMax).contains($0) })
    }

    static func fingerprint(of session: Session) -> String {
        session.exercises
            .map { ex in
                var head = "\(ex.pattern.rawValue):\(ex.variation):\(ex.load):\(ex.sets)"
                // The PROBE belongs in the identity too: "2×15 plus one set of
                // the split squat" and "2×15" are different plans with the
                // same base dose and set count, and resuming a snapshot into
                // the wrong one would put a probe on screen that nobody was
                // offered (§40.4).
                if let probe = ex.probe { head += ":p\(probe.variation)-\(probe.load)" }
                // The per-set doses belong in it as well. Without them 3×8
                // and 9-8-8 share a fingerprint — same variation, same base
                // dose, same set count — and a snapshot could resume into a
                // plan that asks different numbers of its sets. Appended only
                // for an UNEVEN plan, so a uniform one keeps a stable string.
                guard let loads = ex.loads else { return head }
                return head + ":" + loads.map(String.init).joined(separator: "-")
            }
            .joined(separator: "|")
    }
}
