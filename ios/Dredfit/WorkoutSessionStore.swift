//
//  The workout in progress as the journal sees it: whether a snapshot still
//  describes the plan ahead, the two windows that bound how long it is worth
//  picking up, and what settling a forgotten one records. Pure; the store
//  applies the windows, keeps the snapshot and writes what this decides.
//

import Foundation
import DredfitCore

enum WorkoutSessionStore {

    /// Older than this is a different training occasion, not an interrupted
    /// one — but "not the same occasion" is not "abandoned": that is
    /// `forgottenAfter`, a window of its own.
    static let resumeWindow: TimeInterval = 3 * 60 * 60

    /// Past this the workout was not interrupted, it was FORGOTTEN, and only
    /// then is it recorded without being asked about.
    ///
    /// Elapsed time, not the calendar day `trainingDays` counts. That rule is
    /// right about rhythm — midnights are what "yesterday" means to a person —
    /// and wrong here: a session left at 23:30 and opened at 00:30 is one
    /// midnight and one hour, and recording it unasked after an hour is the
    /// very thing this threshold exists to prevent.
    ///
    /// Twelve hours, so a session and the next opening of the app fall on
    /// opposite sides of a night or a working day: an evening workout left at
    /// 21:00 is still a question the next morning, and one left in the morning
    /// stops being one by the evening.
    static let forgottenAfter: TimeInterval = 12 * 60 * 60

    /// The snapshot is only worth anything while it still describes the plan
    /// the engine would hand out: the bar toggle and an accepted comeback
    /// regenerate a different session under the same number, and then its
    /// indices and numbers belong to a plan nobody trained.
    static func valid(_ snap: WorkoutSnapshot?, plan session: Session, counter: Int) -> WorkoutSnapshot? {
        guard let snap,
              snap.sessionNumber == counter + 1,
              snap.fingerprint == WorkoutSnapshot.fingerprint(of: session),
              snap.hasProgress
        else { return nil }
        return snap
    }

    /// What `completeWorkout` is handed for a workout nobody came back to.
    struct Settlement {
        var overrides: [Pattern: Double]
        var setActuals: SetFacts.PerSet
        var skipped: Set<Pattern>
        var setsSkipped: SetFacts.Skips
        var skippedSets: SetFacts.SkippedSets
        var probes: [Pattern: Int]
        var durationSec: Int
        var warmupSec: Int?
        var cooldownSec: Int?
        var interrupted: Pattern?
        var raised: [Pattern: Int]
        var date: Date
    }

    /// What a workout nobody came back to records. Dated from `savedAt`, never
    /// `.now`: settling yesterday's session this morning would otherwise move
    /// it into today's calendar, today's Health export and today's gap
    /// arithmetic.
    static func settlement(of snap: WorkoutSnapshot, in session: Session) -> Settlement {
        let settled = SetFacts.settlement(
            in: session.exercises,
            exIndex: snap.exIndex,
            // In rest the set that just ended is still `setIndex`.
            // Capped before the `+ 1`: the index comes off disk, and Int.max
            // would trap here inside `activate()` on every launch.
            setsBehind: snap.restEndDate != nil ? min(snap.setIndex, Int.max - 1) + 1 : snap.setIndex,
            currentIsDone: snap.atFeedback == true || snap.atExerciseSummary == true,
            alreadySkipped: snap.skips)
        let skipped = settled.skipped.union(snap.skipped)
        var facts = snap.facts
        var probes = snap.probeFacts
        var skippedSets = snap.skippedSets
        // A skip wins over an actual, the same way it does in the flow.
        for pattern in skipped {
            facts.removeValue(forKey: pattern)
            probes.removeValue(forKey: pattern)
            skippedSets.removeValue(forKey: pattern)
        }
        return Settlement(
            overrides: SetFacts.overrides(facts, skipping: skippedSets, in: session.exercises),
            setActuals: facts,
            skipped: skipped,
            setsSkipped: settled.setsSkipped,
            skippedSets: skippedSets,
            probes: probes,
            // Minus the measured absence, exactly as the flow's own path does
            // it: the same break must not be charged to the workout or not
            // depending only on whether the process survived to the rating.
            durationSec: max(0, Int(snap.savedAt.timeIntervalSince(snap.workoutStart))
                                - (snap.awaySec ?? 0)),
            warmupSec: snap.warmupSec,
            // Short of the end of the work the cool-down was still ahead:
            // never reached, so zero, as `finishNow` records the same
            // interruption. Past it (`atFeedback`) the snapshot already says
            // what the block was: zero from its offer or for a block never
            // reached, the measurement once it ended, and nil for a workout
            // left inside it, which stays unknown.
            cooldownSec: snap.atFeedback == true ? snap.cooldownSec : 0,
            interrupted: snap.interrupted ?? settled.interrupted,
            // Decided on the summaries of movements that are behind; a
            // movement the settlement skips cannot carry one — the summary
            // is the last set's screen, and a skipped movement never got
            // there.
            raised: snap.raises.filter { !skipped.contains($0.key) },
            // The END, as every record is dated: the Health export reads a
            // record's date as the moment the workout ended, and `savedAt` is
            // where `durationSec` above ends too.
            date: snap.savedAt)
    }
}
