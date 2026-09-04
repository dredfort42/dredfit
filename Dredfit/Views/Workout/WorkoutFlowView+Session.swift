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

    /// The tap arms the set; the clock waits out a count-in first. It used to
    /// start the hold under the thumb, and on a hold that is not only a jolt:
    /// the seconds spent getting down into the plank came off the number the
    /// engine measures.
    ///
    /// A SET THE RUN OPENS HAS NO COUNT-IN OF ITS OWN (R32). The rest before
    /// it is the lead-in: it counts its own last three seconds down and ends
    /// on the go, and that go is this hold's start signal — the same shape the
    /// side-switch pause has always had.
    ///
    /// It used to lay a second window on top of that: fifteen seconds priced
    /// as travel, with its own 3-2-1 and its own go, so a minute of rest
    /// actually ran a minute and a quarter and sounded the start twice. The
    /// minute IS the travel time; a person who has spent it lying beside the
    /// mat does not need a quarter of one more, and the second go said
    /// "begin" about a set that had already been announced. It also spent
    /// seconds no estimate anywhere counts — `restSetSec` is what the engine
    /// budgets between sets.
    ///
    /// A TAP still earns its beat, and that asymmetry is the point:
    /// `GetReady.countInSeconds` is the pause between somebody saying "I am
    /// ready" and being counted in. That is why a rest cut short by Skip
    /// arrives here with `autoContinued: false`.
    func startHold(autoContinued: Bool = false) {
        adjusting = false
        // On the probe set the countdown is the PROBE's target — a different
        // movement, and possibly a different unit (§40.1, `pull_bar` 2→3).
        // The declaration stands in for the plan while this exercise lasts —
        // `SetFacts.holdTarget` says how, and why a set cut short still
        // governs the sets after it. The PROBE is outside it: it is one set of
        // another movement, and a time declared for this one says nothing
        // about that one (§40.4).
        var planned = current.isProbe
            ? (probeActuals[exercise.pattern] ?? current.planned)
            : SetFacts.holdTarget(actuals, exercise, set: setIndex,
                                  declared: holdDeclared)
        #if DEBUG
        // The UI suite used to set a hold's length through the adjuster on
        // this screen, which R23 removed: nothing is entered before the
        // effort. What the suite actually needed were the two ENDS of the
        // corridor — the floor, to walk a whole hold exercise inside a test's
        // budget, and the ceiling, to give a mid-hold Stop a margin no loaded
        // runner can eat (the nightly of 2026-08-04 spent 20 s delivering
        // one tap).
        //
        // A SEED OF THE PLAN, never of the number in force and never of a
        // DECLARED time: once the athlete has said something about this
        // movement — by reporting a set or by setting the clock — that is what
        // it runs at. Otherwise the scaffolding would overwrite the very thing
        // the test that set it is about: a hold stopped early carries its
        // seconds onto the sets after it, and a declared time governs every
        // set, and a flag that re-imposed 90 s would hide both.
        // Production untouched; DEBUG builds only.
        if actuals[exercise.pattern] == nil && holdDeclared == nil && !current.isProbe {
            if CommandLine.arguments.contains("--uitest-hold-short") {
                planned = SetFacts.corridor(for: .hold).lowerBound
            } else if CommandLine.arguments.contains("--uitest-hold-long") {
                planned = SetFacts.corridor(for: .hold).upperBound
            }
        }
        #endif
        // The SECOND side is re-armed through here too, not only through the
        // switch pause: a Stop inside the mis-tap grace leaves every countdown
        // nil with `holdSecondSide` still true, so "Start hold" comes back and
        // this is its only call site. Deriving from the plan there handed the
        // second side the full length again and undid the rule in silence.
        holdTotal = SetFacts.holdSideSeconds(
            planned: planned, firstSideHeld: holdSecondSide ? firstSideHeld : nil)
        holdRemaining = holdTotal
        guard !autoContinued else {
            // Straight into the hold on the rest's own go, exactly as the
            // second side starts on the switch pause's (`tickHoldSwitchPause`).
            holdCountInRemaining = 0
            holdCountInEndDate = nil
            holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
            return
        }
        holdCountInRemaining = GetReady.countInSeconds
        holdCountInEndDate = Date.now.addingTimeInterval(TimeInterval(holdCountInRemaining))
    }

    /// 3-2-1 and then the go, like every transition in the guided blocks —
    /// here the ticks are wanted, unlike inside the switch pause: the count-in
    /// IS the signal rather than something laid over one.
    func tickHoldCountIn() {
        guard let end = holdCountInEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdCountInRemaining else { return }
        if newRemaining == 0 {
            holdCountInEndDate = nil
            playGo()
            // The hold's own total was fixed at the tap, so a long absence
            // during the count-in still starts a FULL set rather than the
            // remains of one.
            holdRemaining = holdTotal
            holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < holdCountInRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { holdCountInRemaining = newRemaining }
        }
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
    ///
    /// Past the grace the seconds are written down by the thumb's own
    /// allowance (`SetFacts.holdEndedByTap`): the tap lands after the effort
    /// has stopped, and the number the button already named is the number
    /// this records.
    func stopHoldEarly() {
        guard let end = holdEndDate else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        let held = Double(holdTotal) - remaining
        if held < Self.holdMistapSeconds {
            holdEndDate = nil
            holdRemaining = holdTotal
            return
        }
        // A set that ended under a thumb is an ESTIMATE and says so on the
        // summary: the allowance below is a guess about a walk to the phone,
        // not a measurement, and a number the app guessed at must not be
        // printed with the same confidence as one the clock produced.
        holdApproxSets.insert(setIndex)
        finishHold(heldSeconds: SetFacts.holdEndedByTap(heldSeconds: Int(held.rounded())))
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
        // Only the LAST set stops here. A hold ends itself, and the flow used
        // to leave the work screen in the same frame the number was produced
        // in — but a set with another one behind it is not lost: the movement
        // comes back, and until it does the rest is what the person wants. It
        // is the last set that is terminal, because after it no screen about
        // this movement ever returns, and the seconds it recorded would stand
        // uncorrectable (owner, 30–31.08.2026).
        guard isLastSet else {
            completeSet()   // rest starts itself, exactly as it always did
            return
        }
        // The signal fires HERE, where the effort actually stopped, not on the
        // tap that follows: the person may have their eyes shut in a plank,
        // and the sound is the only thing that says the hold is over.
        playDone()
        // The PROBE keeps the settled screen it always had: its caption states
        // the outcome of the trial ("Next time: …"), which is a sentence about
        // a movement the summary below deliberately says nothing about — the
        // probe's number is its own channel and is never folded in (§40.4).
        // Every other last set of a hold lands on the summary instead, where
        // the whole movement is in front of the person and any set of it can
        // be corrected, not only this one.
        if current.isProbe {
            holdSettled = true
            persistProgress()   // a recorded hold is worth keeping before the tap
            return
        }
        startExerciseSummary()
    }

    // MARK: - The exercise summary

    /// Every set of the finished hold movement, on one screen.
    func startExerciseSummary() {
        adjusting = false
        holdDeclaring = false
        summarySet = nil
        holdSettled = false
        holdAutoRun = false
        phase = .exerciseSummary
        liveActivity.update(.init(phase: .work, title: exercise.name,
                                  detail: String(localized: "Held"), restEndDate: nil))
        persistProgress()
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
            // BOTH SIDES OF ONE SET CARRY THE SAME LOAD (owner, 27.08.2026).
            // The second side runs for what the first actually ran, not for
            // what the plan asked. Before this, a first side stopped at 20 s
            // of a planned 30 handed the second side the full 30 — and the
            // fact recorded for the set is min(side one, side two), so those
            // ten seconds loaded one side harder than the other AND counted
            // for nothing.
            //
            // `holdTotal` itself, not just the remaining and the end date:
            // `stopHoldEarly` measures what was held as `holdTotal -
            // remaining`, so leaving the old total standing would make an
            // early stop on the SECOND side report more than was held.
            holdTotal = SetFacts.holdSideSeconds(planned: holdTotal,
                                                 firstSideHeld: firstSideHeld)
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

    /// What the summary's own primary control does. It is `completeSet` and
    /// not a path of its own deliberately: the summary REPLACED the tap that
    /// logged the set, so the flow past it has to be the same flow — the rest
    /// this movement earns, or the cool-down when it was the last one.
    func leaveExerciseSummary() {
        holdApproxSets.removeAll()
        completeSet()
    }

    /// `countIn` is what `SetFacts.restHandsOverWithCountIn` decided: a rest
    /// that ran out under the person's eyes has already counted them in with
    /// its own 3-2-1, and only a tap or a go the app could not sound leaves
    /// the beat still owed.
    func advanceAfterRest(countIn: Bool) {
        if isLastSet {
            exIndex += 1
            maximumWarning = nil   // the note belongs to the exercise it was about
            setIndex = 0
            // One tap bought ONE exercise. The next movement is a decision of
            // its own, and starting it under a thumb that agreed to something
            // else is exactly what R23 is against.
            holdAutoRun = false
            // …and so is the time that tap was given. This is the ORDINARY way
            // out of an exercise — the last set rests, and the rest ends here —
            // and it went through no reset at all, so a declaration made for
            // the plank arrived at the side plank and set its clock to a
            // number nobody had asked of that movement.
            resetHoldExercise()
        } else {
            setIndex += 1
        }
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
        // …and inside the exercise nothing is asked for again: the rest ends
        // and the next set begins on its go. Which sets those are is one
        // question with one answer (`SetFacts.runOpensSet`) — the rest screen
        // asks it too, to decide whether to offer a pause.
        if runOpensSet(setIndex) {
            startHold(autoContinued: !countIn)
        }
    }

    /// The run opens this set by itself — asked of the rule, not restated.
    func runOpensSet(_ index: Int) -> Bool {
        SetFacts.runOpensSet(index, of: exercise, running: holdAutoRun)
    }

    /// The rest on screen will START the next set when it runs out, which is
    /// the only rest a pause has anything to stop. On the last set the rest
    /// leads out of the exercise, and the run is cleared on the way.
    var restStartsTheNextSet: Bool {
        guard case .rest = phase, !isLastSet else { return false }
        return runOpensSet(setIndex + 1)
    }

    // MARK: - Surviving process death

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
            restEnd = restEndDate
                ?? Date.now.addingTimeInterval(TimeInterval(max(restRemaining, 1)))
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
            atExerciseSummary: phase == .exerciseSummary ? true : nil,
            holdDeclaredSec: holdDeclared,
            approxSets: holdApproxSets.isEmpty ? nil : Array(holdApproxSets).sorted(),
            interrupted: interruptedPattern,
            warmupSec: warmupSec, cooldownSec: cooldownSec))
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
        // A restore lands past the warm-up either way, so a snapshot that
        // carries no measurement is a session killed inside a block: the
        // record falls back to the planned length rather than claiming a
        // block was declined that may have been half done.
        warmupSec = snap.warmupSec
        cooldownSec = snap.cooldownSec
        holdApproxSets = snap.approximateSets
        // A declared time outlives a process death, and it has to: coming back
        // to the plan's number after saying you would hold longer would undo
        // the decision without saying so, and the sets already recorded would
        // then be followed by a shorter one for no reason anybody could see.
        holdDeclared = snap.holdDeclaredSec
        if snap.atFeedback == true {
            phase = .feedback
            return
        }
        if snap.atExerciseSummary == true {
            phase = .exerciseSummary
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
        if phase == .exerciseSummary {
            return .init(phase: .work, title: exercise.name,
                         detail: String(localized: "Held"), restEndDate: nil)
        }
        if case .rest = phase {
            return .init(phase: .rest, title: nextLabel,
                         detail: String(localized: "Next up"),
                         restEndDate: restEndDate)
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
        adjusting = false
        clearBlockPause()
        holdEndDate = nil
        holdCountInEndDate = nil
        holdSecondSide = false
        firstSideHeld = nil
        holdPauseEndDate = nil
        holdSettled = false
        holdAutoRun = false
        holdDeclared = nil
        holdDeclaring = false
        holdApproxSets.removeAll()
        summarySet = nil
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
