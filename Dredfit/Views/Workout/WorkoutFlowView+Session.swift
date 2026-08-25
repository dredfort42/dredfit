//
//  The holds, the signals and the snapshot of the workout flow, moved out
//  of WorkoutFlowView when that file neared the lint's hard ceiling. It is
//  the machinery a set runs on rather than a screen; the code moved
//  unchanged, and only the members it reaches for lost their `private`.
//

import SwiftUI
import DredfitCore

// MARK: - Holds, signals and session persistence

// A file of its own, which is exactly why the state these reach for is
// declared without `private`: Swift's `private` is file-scoped, and this
// block moved out when WorkoutFlowView.swift crossed the lint's hard ceiling
// of 1200 lines. The widening is the price of the move, not an invitation —
// nothing outside the five WorkoutFlowView files touches those members.
extension WorkoutFlowView {

    // MARK: - Hold countdown

    func startHold() {
        adjusting = false
        // On the probe set the countdown is the PROBE's target — a different
        // movement, and possibly a different unit (§40.1, `pull_bar` 2→3).
        holdTotal = current.isProbe
            ? (probeActuals[exercise.pattern] ?? current.planned)
            : SetFacts.inForce(actuals, exercise, set: setIndex)
        holdRemaining = holdTotal
        holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
    }

    func tickHold() {
        guard let end = holdEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdRemaining else { return }
        if newRemaining == 0 {
            // Silent: completeSet() owns the end-of-set signal now, whatever
            // ended it (#186). Sounding a done here would double it.
            finishHold(heldSeconds: holdTotal)
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < holdRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { holdRemaining = newRemaining }
        }
    }

    static let holdMistapSeconds = 3.0

    /// "Stop" sits exactly where "Start hold" was, so a stop within the first
    /// seconds is an accidental double-tap: the set stays available.
    /// Otherwise one mis-tap consumes the set and records a bogus actual —
    /// which on the first workout also feeds the zero-level calibration.
    func stopHoldEarly() {
        guard let end = holdEndDate else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        let held = Double(holdTotal) - remaining
        if held < Self.holdMistapSeconds {
            holdEndDate = nil
            holdRemaining = holdTotal
            return
        }
        finishHold(heldSeconds: Int(held.rounded()))
    }

    /// Per-side holds run the pause and the second side by themselves; the
    /// recorded actual is the smaller of the two sides.
    func finishHold(heldSeconds: Int) {
        holdEndDate = nil
        if current.perSide && !holdSecondSide {
            firstSideHeld = heldSeconds
            holdSecondSide = true
            startHoldSwitchPause()
            return
        }
        let held = min(heldSeconds, firstSideHeld ?? heldSeconds)
        holdSecondSide = false
        firstSideHeld = nil
        recordHoldActual(heldSeconds: held)
        completeSet()
    }

    // MARK: - The side-switch pause (issue #35)

    func startHoldSwitchPause() {
        playSwitch()
        holdPauseRemaining = Cooldown.switchPauseSeconds
        holdPauseEndDate = Date.now.addingTimeInterval(TimeInterval(holdPauseRemaining))
    }

    /// No 3-2-1 inside the pause: ticks would bury the switch tone.
    func tickHoldSwitchPause() {
        guard let end = holdPauseEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdPauseRemaining else { return }
        if newRemaining == 0 {
            holdPauseEndDate = nil
            playGo()
            holdRemaining = holdTotal
            holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
        } else {
            withAnimation(.linear(duration: 0.3)) { holdPauseRemaining = newRemaining }
        }
    }

    /// Onto the grid the manual adjuster steps on, and onto the set actually
    /// held: stopping at 40 s of 55 in the third set is the third set's fact.
    func recordHoldActual(heldSeconds: Int) {
        let held = SetFacts.snap(Double(heldSeconds), unit: .hold)
        // The probe's number goes to the probe's channel — see `probeActuals`.
        if current.isProbe {
            probeActuals[exercise.pattern] = held
            return
        }
        actuals = SetFacts.recording(held, in: actuals, exercise, set: setIndex)
    }

    // MARK: - Audible countdown of the last rest seconds

    static let countdownSignalSeconds = 3
    /// One tap of extra rest. The cap on repeats is twice the planned rest.
    static let restExtensionSeconds = 15

    /// Thin wrappers: each signal's tone + haptic pair lives in
    /// WorkoutSignals, gated here by the one sounds toggle.
    func playTick() { WorkoutSignals.tick(store.settings.soundsEnabled) }
    func playGo() { WorkoutSignals.go(store.settings.soundsEnabled) }
    func playSwitch() { WorkoutSignals.switchSides(store.settings.soundsEnabled) }
    func playDone() { WorkoutSignals.done(store.settings.soundsEnabled) }
    func playWorkoutDone() { WorkoutSignals.workoutDone(store.settings.soundsEnabled) }
    func playMilestone() { WorkoutSignals.milestone(store.settings.soundsEnabled) }

    func advanceAfterRest() {
        if isLastSet {
            exIndex += 1
            maximumWarning = nil   // the note belongs to the exercise it was about
            setIndex = 0
        } else {
            setIndex += 1
        }
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }

    // MARK: - Surviving process death

    /// Called on every phase transition and whenever an actual changes.
    func persistProgress() {
        var restEnd: Date?
        var restTotal: Int?
        var restPlan: Int?
        if case .rest(let total) = phase {
            restEnd = restEndDate
            restTotal = total
            restPlan = restPlanned
        }
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: session.sessionNumber,
            exIndex: exIndex, setIndex: setIndex,
            restEndDate: restEnd, restTotalSec: restTotal, restPlannedSec: restPlan,
            setActuals: actuals, setsSkipped: setsSkipped, probes: probeActuals,
            skipped: skippedPatterns,
            workoutStart: workoutStart ?? .now, savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: session),
            // Process death during the cool-down restores to the rating the
            // work is fully behind. The intro screen counts as "the work is
            // behind" too — process death there must not resume into the last
            // exercise.
            atFeedback: phase == .feedback || phase == .cooldown
                || phase == .cooldownIntro ? true : nil,
            interrupted: interruptedPattern))
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
        interruptedPattern = snap.interrupted
        if snap.atFeedback == true {
            phase = .feedback
            return
        }
        if let end = snap.restEndDate, let total = snap.restTotalSec, end > .now {
            restEndDate = end
            restRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
            // An older snapshot has no planned value; the total it carries is
            // the closest honest stand-in, and it keeps the button live.
            restPlanned = snap.restPlannedSec ?? total
            phase = .rest(seconds: total)
        } else {
            if snap.restEndDate != nil, !(isLastSet && isLastExercise) {
                if isLastSet {
                    exIndex += 1
                    maximumWarning = nil   // the note belongs to its own exercise
                    setIndex = 0
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
        if case .rest = phase {
            return .init(phase: .rest, title: nextLabel,
                         detail: String(localized: "Next up"),
                         restEndDate: restEndDate)
        }
        return activityWorkState()
    }

    var hasProgress: Bool {
        if case .rest = phase { return true }
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
        adjusting = false
        clearBlockPause()
        holdEndDate = nil
        holdSecondSide = false
        firstSideHeld = nil
        holdPauseEndDate = nil
        var firstUnfinished = exIndex
        if case .rest = phase, isLastSet { firstUnfinished = exIndex + 1 }
        // "not finished", not "skipped": the engine still freezes the level
        // like any skip, the label is the only difference.
        if firstUnfinished == exIndex {
            let midway: Bool
            if case .rest = phase {
                midway = true   // a between-set rest means a set is behind
            } else {
                midway = setIndex > 0 || actuals[exercise.pattern] != nil
            }
            if midway { interruptedPattern = exercise.pattern }
        }
        if firstUnfinished < exercises.count {
            for ex in exercises[firstUnfinished...] {
                actuals.removeValue(forKey: ex.pattern)   // a skip wins over an actual
                probeActuals.removeValue(forKey: ex.pattern)
                setsSkipped.removeValue(forKey: ex.pattern)
                skippedPatterns.insert(ex.pattern)
            }
        }
        restEndDate = nil
        restRemaining = 0
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }

    func discardWorkout() {
        store.clearWorkoutSnapshot()
        dismiss()
    }
}
