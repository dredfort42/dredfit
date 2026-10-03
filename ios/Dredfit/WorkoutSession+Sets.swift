//
//  The work itself: a set ending, the adjuster, the note about an all-out set,
//  and every way from one exercise to the next.
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// What is left of the session, in minutes — recomputed on every
    /// body pass, so a skipped set takes its minutes off at the moment it is
    /// skipped rather than at the next screen.
    ///
    /// Offered on the work and rest screens and inside the cool-down — the
    /// three screens where "how much longer" is a live question. The warm-up
    /// is left out: it stands before the work it cannot shorten, and its own
    /// offer screen already states its length. The rating is past the question
    /// entirely.
    var minutesLeft: Int? {
        var index = exIndex
        var behind = setIndex
        switch phase {
        case .work:
            break
        case .rest, .exerciseSummary:
            // The set the rest FOLLOWS is done — the flow advances after it.
            // The summary stands past a finished set for the same reason, so
            // counting its set as still ahead would quietly add a set's worth
            // of minutes to a movement that is over.
            behind += 1
            // `totalSets`, not `exercise.sets`: the probe is a set of this
            // exercise too. Counted by the working sets alone, the exercise
            // left the list on the rest that ANNOUNCES the probe by name, so
            // the header dropped the probe's own minute and then grew by it
            // when the probe's screen opened — a number moving without the
            // person having moved it (self-review 05.09.2026). Identical for
            // an exercise without one, where the two are equal.
            if behind >= totalSets { index += 1; behind = 0 }
        case .cooldown:
            // The block the header stopped answering for. The work screen
            // counts the cool-down into what is left (`ends:` below), and then
            // the number vanished on the one screen where the person is
            // actually waiting it out — so the block that was reserved four
            // minutes a moment ago reported nothing at all (UX review
            // 05.09.2026). Its own arithmetic, not the session's: what is left
            // here is stretches, and it is counted the way the offer counted
            // them. The intro screen is left out on purpose — it prints the
            // same number in its own body, and a header would say it twice.
            return cooldownMinutesLeft
        default:
            return nil
        }
        // The cool-down is the only fixed block still ahead; the warm-up is
        // behind by the time the work screen is up.
        //
        // WITH THE FACTS, not the plan alone. The clock on a hold runs from
        // `SetFacts.holdTarget` — the time the athlete declared, or the
        // shortfall a set cut short carries onto the sets after it — while
        // this number was built out of `plannedLoad`, so the header went on
        // promising 30 s a set to somebody who had just set the clock to 45,
        // and went on promising 40 to somebody whose remaining sets were now
        // 19 (UX review 05.09.2026). The two disagree exactly when the person
        // has deviated from the plan, which is when the question gets asked.
        //
        // The declaration is the CURRENT exercise's, so it travels only while
        // `index` still points at it: past the last set the flow is standing
        // in front of the next movement, and a time set for the plank says
        // nothing about the side plank (`resetHoldExercise`).
        return SessionAhead.minutes(exercises, exIndex: index, setsBehind: behind,
                                    ends: session.cooldownMin,
                                    facts: actuals,
                                    declared: index == exIndex ? holdDeclared : nil)
    }

    /// The technique sheet of a guided block is open. Freezes the running
    /// countdown: the end date comes off (the tick guards go quiet) while the
    /// remaining seconds stay put and rebuild it. The way back in from a
    /// pause freezes with it — reading is not getting back into position
    /// either.
    func freezeForPositionTechnique() {
        warmupClock.freeze()
        cooldownClock.freeze()
        blockPause.freezeForSheet()
        // And the block stops costing time while it is read: reading is not
        // stretching either, and the block's own length is wall clock
        // (UX review 05.09.2026, see `blockPausedSec`).
        beginBlockFreeze()
    }

    func resumePositionCountdown() {
        // Whatever the sheet froze is what it hands back. A way back in
        // outlives it; a pause outranks it — closing the sheet must never
        // restart a block the user stopped (issue #34 vs #61).
        blockPause.thawAfterSheet(now: now())
        guard !blockPause.isPaused else { return }
        // After the guard: a block the person had PAUSED goes on standing
        // still, and closing the interval here would stop counting a pause
        // that has not ended.
        endBlockFreeze()
        switch phase {
        case .warmup:
            warmupClock.resume(now: now())
        case .cooldown:
            cooldownClock.resume(now: now())
        default:
            break
        }
    }

    /// Strings leave the app pre-localized — the extension renders verbatim.
    func activityWorkState() -> RestActivityAttributes.ContentState {
        if isWarmingUp {
            return .init(phase: .work, title: String(localized: "WARM-UP"),
                         detail: "", restEndDate: nil)
        }
        // The probe set is one set of the NEXT variation, and the in-app
        // screen says so — the lock screen and the Dynamic Island must not
        // call it by the old movement's name while the person is doing the
        // new one (UI-truth audit, 27.08.2026).
        if current.isProbe {
            return .init(phase: .work, title: current.name,
                         detail: String(localized: "Probe"), restEndDate: nil)
        }
        return .init(phase: .work, title: exercise.name,
                     detail: String(localized: "set \(setIndex + 1) of \(totalSets)"),
                     restEndDate: nil)
    }

    func completeSet() {
        // All three ways a set ends meet here (#186): the Done tap, the hold
        // reaching zero, an early stop past the mis-tap window. A per-side
        // hold's first side goes to the switch pause instead, not here.
        //
        // §41.2: finishing the PROBE set records its target. The rule and the
        // reason live in `SetFacts.recordingProbe`, stated once: it unfreezes
        // eight ladders out of ten.
        probeActuals = SetFacts.recordingProbe(probeActuals, exercise.pattern,
                                               isProbe: current.isProbe,
                                               target: current.planned)
        // A hold's LAST set gets its summary first, and the probe's Done is
        // the one tap that can arrive here still owing one: the probe keeps a
        // settled screen of its own, so the movement it belongs to has not
        // been shown yet. Guarded on the phase rather than on a flag, because
        // this is also the summary's own exit and that pass must fall through.
        if phase != .exerciseSummary && isLastSet && exercise.unit == .hold
            && !skippedPatterns.contains(exercise.pattern) {
            startExerciseSummary()
            return
        }
        // A hold has already sounded its own ending, at the moment the effort
        // actually stopped (see `finishHold`). The tap that lands here after
        // one confirms a number; sounding "done" again would announce an end
        // that happened seconds ago — and neither does the summary's exit,
        // which is a screen past the effort, not the end of one.
        if !holdSettled && phase != .exerciseSummary { playDone() }
        holdSettled = false
        editing = nil
        if isLastSet && isLastExercise {
            // "Finish now" deliberately does not run the cool-down.
            startCooldown()
        } else if isLastSet {
            startRest(exercise.restExerciseSec)
        } else {
            startRest(exercise.restSetSec)
        }
    }

    /// A soft note when the person enters MORE than the plan on a set that
    /// is not the last one. Once per exercise per session, and the entry
    /// stands either way — it is advice about the workout, never a correction
    /// of the number.
    ///
    /// What it must NOT say is that the system measures the last set more
    /// accurately. Under a mean the ORDER OF SETS DOES NOT REACH THE ENGINE at
    /// all: 12, 8, 8 and 8, 8, 12 both collapse to 9. The advice is about
    /// training — a maximum attempt fatigues what follows it — and the wording
    /// says exactly that and nothing more.
    func noteMaximumOutOfOrder() {
        let pattern = exercise.pattern
        guard !maximumNoted.contains(pattern) else { return }
        // The rule itself is `SetFacts.maximumOutOfOrder`, where a test can
        // reach it — and where the reason it is NOT about the order of sets
        // is written down.
        guard SetFacts.maximumOutOfOrder(adjustValue, exercise, set: setIndex) else { return }
        maximumNoted.insert(pattern)
        // Reduce Motion covers this one too: the note slides up from the
        // bottom edge under a `.transition`, and with no animation running
        // that transition simply appears (UX review 05.09.2026).
        animate(.note) {
            // "A maximum" was a term this app defines nowhere, in a
            // twenty-one word paragraph on a screen read between sets. What
            // replaced it names the ACT — going all out on one set — and keeps
            // both thoughts, because the second one is not decoration: without
            // it the line reads as a correction of the number, which is the
            // one thing it must never be (UX review 05.09.2026).
            maximumWarning = String(localized:
                "Going all out on one set weakens the ones after it. What counts is the whole exercise.")
        }
    }

    /// Leaving an exercise early. There used to be two ways — a skip and a
    /// pain report — and the report is gone. A person who finds the movement
    /// too hard now reaches for a handle instead, which keeps the movement in
    /// the plan rather than taking it out for weeks.
    func leaveExercise() {
        editing = nil
        holdSwitchClock.freeze()
        holdCountInClock.freeze()
        actuals.removeValue(forKey: exercise.pattern)   // a skip wins over an actual
        // …and over the probe: a movement that was not trained resolves nothing.
        probeActuals.removeValue(forKey: exercise.pattern)
        // …and over the sets skipped inside it: the movement was not trained,
        // so there is no volume to take off it next time.
        setsSkipped.removeValue(forKey: exercise.pattern)
        skippedPatterns.insert(exercise.pattern)
        advancePastExercise()
    }

    /// The pair that makes ONE set of a per-side hold. `finishHold` clears
    /// them when a set ends normally, and every OTHER way out of a set has to
    /// clear them too. They used to survive a skip: a Stop inside the mis-tap
    /// grace is the one moment the actions row is live with `holdSecondSide`
    /// still true, and skipping from there carried it into the next set —
    /// where `finishHold` took the second-side branch, so that set ended after
    /// ONE side, and the smaller-of-the-two-sides rule capped its record with
    /// a number from the set before. The `min` does not ask whether the
    /// movement is per-side, so a stale side plank could cap a plain plank.
    func resetHoldSides() {
        holdSecondSide = false
        firstSideHeld = nil
        editing = nil
        // The settled hold belongs to the set it was held in for exactly the
        // same reason and for exactly as long: carried into the next set it
        // would offer "Done" for an effort nobody made.
        holdSettled = false
        // And the auto-run belongs to the exercise. Every call site of this
        // is a departure — a skipped set, the walk past an exercise, the end
        // of the workout — and a skip is a person saying they want the phone,
        // which is the one thing an auto-run takes away. Resetting it here rather than at the
        // four skip paths is deliberate: an omitted reset was the defect
        // class this function was written for.
        holdAutoRun = false
    }

    /// What belongs to the EXERCISE rather than to the set: the time its clock
    /// was set to, which of its sets were ended by a thumb, and what the clock
    /// measured for each. Apart from `resetHoldSides` because a SET skip
    /// keeps them — saying "hold 60" and then skipping one set must not put
    /// the sets after it back on the plan, nor drop the "≈" marks off numbers
    /// the app guessed at. Two lifetimes, two functions.
    func resetHoldExercise() {
        holdDeclared = nil
        holdApproxSets.removeAll()
        holdMeasured.removeAll()
    }

    /// Past the exercise in front of us, however it ended — into the next one,
    /// or into the cool-down when there is none. `startCooldown` degrades to
    /// the rating when nothing was performed.
    func advancePastExercise() {
        if isLastExercise {
            leaveExerciseState()
            startCooldown()
        } else {
            enterNextExercise()
            phase = .work
            liveActivity.update(activityWorkState())
            persistProgress()
        }
    }

    /// Onto the next exercise — the one place the flow moves to it, whether by
    /// a skip, by the rest after the last set, or by a restore past that rest.
    func enterNextExercise() {
        leaveExerciseState()
        exIndex += 1
        setIndex = 0
    }

    /// Everything scoped to the exercise in front of us: its sides, its
    /// settled hold, its run, its declared time, its estimate marks and its
    /// note. Cleared on the way into the next exercise (`enterNextExercise`)
    /// and on the early ways out — a skip past the last one, "Finish now".
    /// The last set's ordinary way into the cool-down leaves them standing;
    /// nothing reads them once the work is behind.
    func leaveExerciseState() {
        resetHoldSides()
        resetHoldExercise()
        maximumWarning = nil
    }

    /// Opens the adjuster on the DECLARATION — how long this hold will run —
    /// rather than on a set's record. Seeded with what the clock would use
    /// right now, so the person is nudging a real number, not typing one.
    func startDeclaringHoldTime() {
        adjustValue = SetFacts.holdTarget(actuals, exercise, set: setIndex,
                                          declared: holdDeclared)
        editing = .holdTime
    }

    /// OK on the work screen's panel: what it writes is decided by what the
    /// panel was opened on (`editing`), never by what the screen shows now.
    func commitSetEdit() {
        if editing == .holdTime {
            // A TARGET, not a record: it sets what the clock runs
            // from for this exercise and writes nothing about a
            // set. What is stored for each set is still whatever
            // that set's clock produced.
            holdDeclared = adjustValue
        } else if current.isProbe {
            // The probe's own channel: one number about one set of
            // another movement, never folded into the mean of the
            // working sets.
            probeActuals[exercise.pattern] = adjustValue
            store.markOwnNumberReported()
        } else {
            // This set only — the ones behind keep what they ran at.
            actuals = SetFacts.recording(adjustValue, in: actuals,
                                         exercise, set: setIndex)
            noteMaximumOutOfOrder()
            // The hint above is spent HERE, on a number actually
            // reported — not when the panel opens. Opening it
            // proves the control was found, which is not the same
            // as knowing what it is for, and the declaration
            // branch above is a TARGET rather than a report, so it
            // deliberately spends nothing (UX review, 05.09.2026).
            store.markOwnNumberReported()
        }
        editing = nil
        persistProgress()   // an entered actual is worth keeping
    }

    func startAdjusting() {
        adjustValue = current.isProbe
            ? (probeActuals[exercise.pattern] ?? current.planned)
            : SetFacts.inForce(actuals, exercise, set: setIndex)
        editing = .set
    }
}
