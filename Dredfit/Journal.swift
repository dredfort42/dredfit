//
//  What a finished workout leaves behind, and what an unfinished one holds
//  on to. Both are read back out of one JSON file, so both are inputs.
//

import Foundation
import DredfitCore

struct WorkoutRecord: Codable, Identifiable, Equatable {
    // sessionNumber alone is NOT unique: resetProgress restarts the counter
    // while the journal survives, so identity needs the date too.
    var id: String { "\(sessionNumber)-\(date.timeIntervalSince1970)" }
    let sessionNumber: Int
    let date: Date
    let result: FeedbackResult
    let totalLevelAfter: Int
    // Optional so older records still decode.
    var exercises: [SessionExercise]?
    /// The number the ENGINE was given for each adjusted pattern — the mean
    /// of its sets (`SetFacts.override`). Kept under its old name and shape
    /// so records written by any earlier build keep reading true.
    var actuals: [Pattern: Int]?
    /// The sets behind that mean, in order. The detail the history line
    /// shows when the sets did not all run the same.
    var setActuals: [Pattern: [Int]]?
    /// Sets skipped DURING the session, per movement (§38.2) — the count the
    /// engine turned into a cut. Written because it is part of what happened:
    /// a plan of 5×8 answered with three sets is not the same session as one
    /// answered in full, and a journal that keeps only the rating cannot tell
    /// them apart afterwards. §38.6 asks whether the mid-workout skip becomes
    /// the dominant price, and this is the only place that question can ever
    /// be answered from.
    var setsSkipped: [Pattern: Int]?
    var skipped: Set<Pattern>?
    /// Reported as painful mid-workout: to the engine a skip, to the journal a
    /// different fact — and the reason the pattern is resting afterwards.
    /// LEGACY, read-only. The pain report is gone, and nothing writes this any
    /// more — but a journal on disk still carries it, and a record that loses
    /// the fact is a record that lies about what happened. Kept so history
    /// stays readable; never populated again.
    var discomfort: Set<Pattern>?
    var levelsAfter: [Pattern: Int]?
    var durationSec: Int?
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
        totalLevelAfter = clamp(try c.decode(Int.self, forKey: .totalLevelAfter),
                                0, EngineConfig.countMax)
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
        levelsAfter = try c.decodeIfPresent([Pattern: Int].self, forKey: .levelsAfter)?
            .mapValues { clamp($0, 0, EngineConfig.levelMax) }
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
            .map { clamp($0, 0, EngineConfig.countMax) }
        healthExported = try c.decodeIfPresent(Bool.self, forKey: .healthExported)
    }

    init(sessionNumber: Int, date: Date, result: FeedbackResult, totalLevelAfter: Int,
         exercises: [SessionExercise]? = nil, actuals: [Pattern: Int]? = nil,
         setActuals: [Pattern: [Int]]? = nil, setsSkipped: [Pattern: Int]? = nil,
         skipped: Set<Pattern>? = nil, discomfort: Set<Pattern>? = nil,
         levelsAfter: [Pattern: Int]? = nil,
         durationSec: Int? = nil, healthExported: Bool? = nil) {
        self.sessionNumber = sessionNumber
        self.date = date
        self.result = result
        self.totalLevelAfter = totalLevelAfter
        self.exercises = exercises
        self.actuals = actuals
        self.setActuals = setActuals
        self.setsSkipped = setsSkipped
        self.skipped = skipped
        self.discomfort = discomfort
        self.levelsAfter = levelsAfter
        self.durationSec = durationSec
        self.healthExported = healthExported
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
    /// Sets skipped so far, per movement (§38.2). Optional like everything
    /// below it: a snapshot written before the skip existed still decodes.
    var setsSkipped: [Pattern: Int]?
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
    var interrupted: Pattern?

    /// What the flow restores into. A snapshot from before this shape kept
    /// one number per exercise, and that number was in force from the first
    /// set on — which is exactly what a one-element array says.
    /// Sanitized on the way out: unlike the journal's records this struct has
    /// no decoder of its own, and everything here comes back off disk.
    var facts: SetFacts.PerSet {
        SetFacts.sanitized(setActuals ?? actuals.mapValues { [$0] })
    }

    /// Sanitized where it is read, for the same reason as `facts`: this struct
    /// has no decoder of its own and everything here comes back off disk.
    var skips: SetFacts.Skips {
        SetFacts.sanitized(skips: setsSkipped ?? [:])
    }

    static func fingerprint(of session: Session) -> String {
        session.exercises
            .map { ex in
                let head = "\(ex.pattern.rawValue):\(ex.tier):\(ex.load):\(ex.sets)"
                // The per-set doses belong in the identity. Without them 3×8
                // and 9-8-8 share a fingerprint — same tier, same base dose,
                // same set count — and a snapshot could resume into a plan
                // that asks different numbers of its sets. Appended only for
                // an UNEVEN plan, so a uniform one keeps the exact string it
                // had before and a workout interrupted before the update still
                // resumes.
                guard let loads = ex.loads else { return head }
                return head + ":" + loads.map(String.init).joined(separator: "-")
            }
            .joined(separator: "|")
    }
}
