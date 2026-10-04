//
//  What survives a backgrounded app or a process death, and the two ways out
//  of a workout that is not finished: "Finish now" and discarding it.
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// The other half of `awaySec`: the absence a living process comes back
    /// from. Only the background is leaving — Control Center or a
    /// pulled-down notification is not, and the person is still here. No
    /// persist here: the next transition writes the larger `awaySec` with a
    /// later `savedAt`, so a later kill cannot count the absence twice, and a
    /// kill while away is `restore`'s to measure.
    func sceneLeft() {
        absence.leave(now: now(), restEndDate: restClock.endDate)
    }

    func sceneCameBack() {
        // Read before `comeBack` spends the stamp.
        let wasAway = absence.isAway
        awaySec += absence.comeBack(now: now())
        // Time away can outlast `prepare()`, so a countdown that comes back on
        // its four or inside its 3-2-1 is primed. Control Center is not time
        // away: the countdown went on ticking in front of the person, and its
        // ticks primed it.
        if wasAway { primeComingBack() }
    }

    /// Called on every phase transition and whenever an actual changes.
    func persistProgress() {
        var restEnd: Date?
        var restTotal: Int?
        var restPlan: Int?
        if case .rest(let total) = phase {
            // A PAUSED rest has no end date, and the snapshot cannot carry the
            // pause: written as nil it reads back as "no rest was running",
            // and `restore` would then hand the person the set they had just
            // finished a second time. What is persisted instead is the rest
            // this will be the moment the pause ends — the seconds it froze
            // with, counted from now. A process death outlives no pause.
            restEnd = restClock.endDate
                ?? now().addingTimeInterval(TimeInterval(max(restClock.remaining, 1)))
            restTotal = total
            restPlan = restPlanned
        }
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: session.sessionNumber,
            exIndex: exIndex, setIndex: setIndex,
            restEndDate: restEnd, restTotalSec: restTotal, restPlannedSec: restPlan,
            setActuals: actuals, setsSkipped: setsSkipped, probes: probeActuals,
            skipped: skippedPatterns,
            workoutStart: workoutStart ?? now(), savedAt: now(),
            fingerprint: WorkoutSnapshot.fingerprint(of: session),
            // Process death during the cool-down restores to the rating the
            // work is fully behind. The intro screen counts as "the work is
            // behind" too — process death there must not resume into the last
            // exercise.
            atFeedback: phase == .feedback || phase == .cooldown
                || phase == .cooldownIntro ? true : nil,
            atExerciseSummary: phase == .exerciseSummary ? true : nil,
            holdDeclaredSec: holdDeclared,
            approxSets: holdApproxSets.isEmpty ? nil : Array(holdApproxSets).sorted(),
            holdMeasuredSec: holdMeasured.isEmpty ? nil : holdMeasured,
            interrupted: interruptedPattern,
            warmupSec: warmupSec, cooldownSec: cooldownSec,
            awaySec: awaySec == 0 ? nil : awaySec,
            raisedSteps: raisedSteps.isEmpty ? nil : raisedSteps))
    }

    /// A rest still running resumes inside it; one that ran out lands on the
    /// set it was leading into (the advance the timer would have made). Holds
    /// never restore mid-count — the set starts over. Indices are clamped
    /// defensively even though the snapshot was validated.
    func restore(from snap: WorkoutSnapshot) {
        exIndex = min(max(snap.exIndex, 0), exercises.count - 1)
        // The probe is a set of this exercise too, so the clamp counts it:
        // restoring onto the last working set would silently drop the probe.
        setIndex = min(max(snap.setIndex, 0), max(0, totalSets - 1))
        actuals = snap.facts
        setsSkipped = snap.skips
        probeActuals = snap.probeFacts
        skippedPatterns = snap.skipped
        workoutStart = snap.workoutStart
        // The absence begins where the workout stopped owing the athlete
        // anything — NOT at the last write. `savedAt` is the moment of the
        // last phase transition; nothing stamps the moment the app stopped
        // living, so a rest of 60–120 s is an unwritten tail of a session that
        // was still running. Counting that tail as absence made an ordinary
        // kill for memory during a rest subtract real minutes: a phone locked
        // at the top of a 90 s rest and opened at its end reported a workout a
        // minute and a half shorter than it was, which is the mirror of the
        // lie the away time was added to fix (review 06.09.2026). A rest
        // running on schedule is training whether or not the process survived
        // it, so the gap is measured from its end. What is left over is the
        // absence, and it accumulates across however many resumes.
        //
        // The work screen carries no such end date, so a kill inside a hold
        // still charges the set to the absence; closing that needs the moment
        // of leaving stamped on the snapshot itself.
        awaySec = (snap.awaySec ?? 0)
            + SetFacts.awayGained(savedAt: snap.savedAt,
                                  restEndDate: snap.restEndDate, now: now())
        interruptedPattern = snap.interrupted
        // A restore lands past the warm-up either way, so a snapshot that
        // carries no measurement is a session killed inside a block: the
        // record falls back to the planned length rather than claiming a
        // block was declined that may have been half done.
        warmupSec = snap.warmupSec
        cooldownSec = snap.cooldownSec
        holdApproxSets = snap.approximateSets
        holdMeasured = snap.measuredHold
        // A declared time outlives a process death, and it has to: coming back
        // to the plan's number after saying you would hold longer would undo
        // the decision without saying so, and the sets already recorded would
        // then be followed by a shorter one for no reason anybody could see.
        holdDeclared = snap.holdDeclaredSec
        raisedSteps = snap.raises
        if snap.atFeedback == true {
            phase = .feedback
            return
        }
        if snap.atExerciseSummary == true {
            phase = .exerciseSummary
            return
        }
        if let end = snap.restEndDate, let total = snap.restTotalSec, end > now() {
            restClock.run(until: end, now: now())
            // An older snapshot has no planned value; the total it carries is
            // the closest honest stand-in, and it keeps the button live.
            restPlanned = snap.restPlannedSec ?? total
            phase = .rest(seconds: total)
        } else {
            if snap.restEndDate != nil, !(isLastSet && isLastExercise) {
                if isLastSet {
                    // The declaration and the marks restored above belong to
                    // the movement behind.
                    enterNextExercise()
                } else {
                    setIndex += 1
                }
            }
            phase = .work
        }
    }

    /// What a fresh Live Activity opens with — a resumed workout can start
    /// mid-rest.
    func currentActivityState() -> RestActivityAttributes.ContentState {
        if phase == .exerciseSummary {
            return .init(phase: .work, title: exercise.name,
                         detail: String(localized: "Held"), restEndDate: nil)
        }
        if case .rest = phase {
            return .init(phase: .rest, title: nextLabel,
                         detail: restActivityDetail, restEndDate: restClock.endDate)
        }
        return activityWorkState()
    }

    var hasProgress: Bool {
        if case .rest = phase { return true }
        if phase == .exerciseSummary { return true }
        return exIndex > 0 || setIndex > 0
            || !actuals.isEmpty || !skippedPatterns.isEmpty
    }

    /// Every exercise not fully completed keeps its level via the engine's
    /// skip path, and the flow proceeds to the rating.
    func finishNow() {
        // Every exercise is already behind. Without this the generic path
        // would call the completed last exercise "not finished". The cool-down
        // QUESTION is behind the work too — leaving from it must end the same
        // way leaving from the block does.
        if phase == .cooldown || phase == .cooldownIntro {
            finishCooldown()
            return
        }
        editing = nil
        clearBlockPause()
        holdClock.freeze()
        holdCountInClock.freeze()
        holdSwitchClock.freeze()
        leaveExerciseState()
        // A movement is BEHIND US in two places, not one. The summary of a
        // finished hold is the same fact as the rest after a last set: every
        // set is done and its seconds are on the screen. Counting it as
        // unfinished handed a FULLY PERFORMED movement to the engine as a
        // skip and erased the very numbers that screen exists to confirm
        // (UX review 05.09.2026, 🔴 02).
        var currentIsDone = false
        if case .rest = phase, isLastSet { currentIsDone = true }
        if case .exerciseSummary = phase { currentIsDone = true }
        // In rest the set that just ended is still `setIndex` — the flow
        // advances after the rest, not before it.
        var setsBehind = setIndex
        if case .rest = phase { setsBehind = setIndex + 1 }
        // The arithmetic itself lives in `SetFacts`, where a test can reach it
        // and where the settlement of a workout that was never rated reads the
        // very same rules — the two used to describe one interruption
        // differently depending on whether the app stayed alive.
        let settled = SetFacts.settlement(in: exercises,
                                          exIndex: exIndex,
                                          setsBehind: setsBehind,
                                          currentIsDone: currentIsDone,
                                          alreadySkipped: setsSkipped)
        setsSkipped = settled.setsSkipped
        // "not finished", not "skipped": the engine still freezes the level
        // like any skip, the label is the only difference.
        interruptedPattern = settled.interrupted
        for pattern in settled.skipped {
            actuals.removeValue(forKey: pattern)   // a skip wins over an actual
            probeActuals.removeValue(forKey: pattern)
            skippedPatterns.insert(pattern)
        }
        restClock.stand(at: 0)
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }

    /// The workout is thrown away: nothing of it is kept for Today to offer.
    func discard() {
        store.clearWorkoutSnapshot()
    }
}
