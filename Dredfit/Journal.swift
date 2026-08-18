//
//  Journal.swift
//  Dredfit
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
    var skipped: Set<Pattern>?
    /// Reported as painful mid-workout: to the engine a skip, to the journal
    /// a different fact — and the reason the pattern is resting afterwards.
    var discomfort: Set<Pattern>?
    /// Asked to hold its level (#78): performed, rated one-directionally,
    /// and not climbing afterwards. Never written when empty, like the rest.
    var pinned: Set<Pattern>?
    var levelsAfter: [Pattern: Int]?
    var durationSec: Int?
    /// Only `true` is ever written; nil means "not exported yet".
    var healthExported: Bool?

    /// v2.13 (spec §24.1): the journal is an input too. The engine heals the
    /// state it is handed, but its own snapshots come back out of this file
    /// and straight into arithmetic — the retrospective subtracts a stored
    /// level from the current one, the week summary subtracts two totals —
    /// and a hand-edited `Int.min` traps that subtraction instead of
    /// saturating. Every number here is clamped to the range it can mean; the
    /// valid domain never notices.
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
        skipped = try c.decodeIfPresent(Set<Pattern>.self, forKey: .skipped)
        discomfort = try c.decodeIfPresent(Set<Pattern>.self, forKey: .discomfort)
        pinned = try c.decodeIfPresent(Set<Pattern>.self, forKey: .pinned)
        levelsAfter = try c.decodeIfPresent([Pattern: Int].self, forKey: .levelsAfter)?
            .mapValues { clamp($0, 0, EngineConfig.levelMax) }
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
            .map { clamp($0, 0, EngineConfig.countMax) }
        healthExported = try c.decodeIfPresent(Bool.self, forKey: .healthExported)
    }

    init(sessionNumber: Int, date: Date, result: FeedbackResult, totalLevelAfter: Int,
         exercises: [SessionExercise]? = nil, actuals: [Pattern: Int]? = nil,
         setActuals: [Pattern: [Int]]? = nil,
         skipped: Set<Pattern>? = nil, discomfort: Set<Pattern>? = nil,
         pinned: Set<Pattern>? = nil, levelsAfter: [Pattern: Int]? = nil,
         durationSec: Int? = nil, healthExported: Bool? = nil) {
        self.sessionNumber = sessionNumber
        self.date = date
        self.result = result
        self.totalLevelAfter = totalLevelAfter
        self.exercises = exercises
        self.actuals = actuals
        self.setActuals = setActuals
        self.skipped = skipped
        self.discomfort = discomfort
        self.pinned = pinned
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
    /// The shape that came before — one number per exercise. Only ever
    /// DECODED (`facts` folds it into the current one), but it stays a stored
    /// property so an older snapshot round-trips rather than failing the file.
    var actuals: [Pattern: Int] = [:]
    var skipped: Set<Pattern> = []
    /// Optional, like the fields below: a snapshot written by an older build
    /// must still decode rather than take the whole file down with it.
    var discomfort: Set<Pattern>?
    /// Hold-this-level marks (#78) — a lone pin is progress worth resuming.
    var pinned: Set<Pattern>?
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
    /// Deliberately not part of the fingerprint — the session is the same
    /// either way; this is which slice of it was under way.
    var shortPlan: [Pattern]?

    /// What the flow restores into. A snapshot from before this shape kept
    /// one number per exercise, and that number was in force from the first
    /// set on — which is exactly what a one-element array says.
    /// Sanitized on the way out: unlike the journal's records this struct has
    /// no decoder of its own, and everything here comes back off disk.
    var facts: SetFacts.PerSet {
        SetFacts.sanitized(setActuals ?? actuals.mapValues { [$0] })
    }

    static func fingerprint(of session: Session) -> String {
        session.exercises
            .map { "\($0.pattern.rawValue):\($0.tier):\($0.load):\($0.sets)" }
            .joined(separator: "|")
    }
}
