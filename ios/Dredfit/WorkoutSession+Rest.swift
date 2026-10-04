//
//  The rest between sets and exercises — and the one rest that starts the
//  next set by itself, on a hands-free hold run.
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// What the lock screen calls the rest it is counting down. Two rests look
    /// identical and end differently — an ordinary one hands the screen back
    /// and waits for a tap, the rest inside a hands-free hold run STARTS the
    /// next set on its own go — and the tile said "Next up" about both, so the
    /// one rest that cannot be missed looked exactly like the one that can
    /// (UX review 05.09.2026). The words are the rest screen's own
    /// (FlowChrome+Rest), keyed off the same fact, so the two cannot drift.
    var restActivityDetail: String {
        restStartsTheNextSet
            ? String(localized: "Starts by itself")
            : String(localized: "Next up")
    }

    /// Reading about what comes next must not cost the set it describes.
    ///
    /// The sheet covers the screen while the rest keeps counting underneath
    /// it, and on a hands-free run the end of that rest is what STARTS the
    /// next hold — so the person came back from a technique page into a plank
    /// already under way. The guided blocks freeze their countdown for exactly
    /// this tap (`freezeForPositionTechnique`); this is that tap on the one
    /// rest with something to lose (UX review 05.09.2026). An ordinary rest is
    /// left running: it hands the screen back and waits, and freezing it would
    /// only make the workout longer.
    func freezeRestForTechnique() {
        // A paused rest is already held and its tile already says so: the
        // sheet has nothing to freeze, and re-sending the tile would replace
        // "Paused" with "Starts by itself" on a rest that is not moving.
        guard restStartsTheNextSet, !blockPause.isPaused else { return }
        restClock.freeze()
        // The tile counts down to a DATE, so a frozen rest has to take the
        // date away — the same reason `pauseBlock` does.
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: nil))
        // A frozen rest is persisted as the seconds it froze with, for the
        // reason `persistProgress` states about a paused one: written with
        // no date it reads back as "no rest was running".
        persistProgress()
    }

    /// "Skip rest": the rest ends now, and the set it leads into earns its
    /// count-in — a tap is not a rest that ran out under the person's eyes.
    func skipRest() {
        guard case .rest = phase else { return }
        clearBlockPause()
        restClock.stand(at: 0)
        advanceAfterRest(countIn: true)
    }

    /// Closing the sheet hands the frozen rest back as the pause does
    /// (`restartFrozenStage`): the seconds it froze with, floored at the
    /// count-in (`BlockPause.restAfterPause`). The end of this rest STARTS
    /// the next hold, and closing the page two seconds out would drop the
    /// person into a plank with the phone still in their hand. Started, not
    /// resumed: a resumed countdown keeps the lower second on screen, and the
    /// 3-2-1 would lose its 3. A rest held by the PAUSE stays held — the
    /// person's own stop outranks the sheet's, the same order
    /// `resumePositionCountdown` keeps.
    func resumeRestCountdown() {
        guard case .rest(let total) = phase, !restClock.isRunning, !blockPause.isPaused else { return }
        restClock.start(BlockPause.restAfterPause(remaining: restClock.remaining, total: total),
                        now: now())
        // A page read for longer than `prepare()` holds lets the engine go
        // cold, and a rest frozen in its last seconds comes back on its four,
        // which no tick reports.
        primeComingBack()
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: restClock.endDate))
        persistProgress()
    }

    /// The cap is twice the rest this transition planned, so the dial cannot
    /// turn a workout into an evening.
    var canExtendRest: Bool {
        guard case .rest(let total) = phase, restPlanned > 0 else { return false }
        return total + Self.restExtensionSeconds <= restPlanned * 2
    }

    /// Moves the end date, not a counter: the second on screen keeps deriving
    /// from the date, so a backgrounded phone comes back to the right number.
    /// The new total goes into the phase because the ring divides by it —
    /// otherwise the arc would run past 100%.
    ///
    /// The last-seconds signal needs no "already played" flag to reset: it
    /// fires on a second below the one shown (`Countdown.signals`), and an
    /// extension raises the one shown, so the new countdown signals again on
    /// its own way down.
    func extendRest() {
        guard case .rest(let total) = phase, restClock.isRunning, canExtendRest else { return }
        restClock.extend(by: Self.restExtensionSeconds, now: now())
        phase = .rest(seconds: total + Self.restExtensionSeconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: restClock.endDate))
        persistProgress()
    }

    var nextLabel: String {
        if isLastSet {
            if isLastExercise { return String(localized: "Workout rating") }
            let next = exercises[exIndex + 1]
            return "\(next.name) · \(next.display)"
        }
        if exercise.probe != nil && setIndex + 1 == exercise.sets, let probe = exercise.probe {
            return String(localized: "Probe: \(probe.name) · \(probe.display)")
        }
        return String(localized: "\(exercise.name) · set \(setIndex + 2) of \(totalSets)")
    }

    /// Rest is never entered on the final set of the last exercise (that goes
    /// straight to the cool-down), so the index is always in range.
    ///
    /// The technique offered during a rest is the technique of what comes
    /// NEXT, and after the last working set of a probing exercise that is the
    /// PROBE's movement — the one thing on this screen nobody has done before.
    var restTechniqueTarget: TechniqueTarget {
        if isLastSet && !isLastExercise {
            return TechniqueTarget(exercises[exIndex + 1])
        }
        if let probe = exercise.probe, setIndex + 1 == exercise.sets {
            return TechniqueTarget(probe: probe, of: exercise.pattern)
        }
        return TechniqueTarget(exercise)
    }

    func startRest(_ seconds: Int) {
        #if DEBUG
        // --uitest-fast: the full-flow driver must never depend on the runner
        // tapping Skip in time. Production untouched; DEBUG builds only.
        let seconds = CommandLine.arguments.contains("--uitest-fast") ? 1 : seconds
        #endif
        restClock.start(seconds, now: now())
        restPlanned = seconds
        phase = .rest(seconds: seconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: restClock.endDate))
        persistProgress()
    }

    func tickRest() {
        switch restClock.read(now: now()) {
        case .unchanged:
            return
        case .ended(let overshoot):
            restClock.stand(at: 0)
            // A suspended app comes back to a rest that ended while it could
            // sound nothing; the beat is still owed then (R32).
            let countIn = SetFacts.restHandsOverWithCountIn(endedByTap: false,
                                                            overshootSec: overshoot)
            // THE RUN IS A PROMISE TO SOMEBODY WHO IS HERE. Past the absence
            // threshold the phone was somewhere else — a call, a pocket — and
            // starting the next hold one count-in after the app comes back
            // drops a plank on someone who is still walking to the mat. The
            // threshold is `BlockPause.absenceSeconds`, the same one the two
            // blocks freeze on, and it means the same thing here (UX review
            // 05.09.2026). The exercise is not over: the work screen comes
            // back with its own button and one tap buys the sets that are left.
            if restStartsTheNextSet, overshoot > Double(BlockPause.absenceSeconds) {
                holdAutoRun = false
            }
            // …and then the go, which marks the end of the rest — and on a
            // hands-free run is also the start of the hold, because the set
            // opens on it. When the rest hands over WITH a count-in instead,
            // that count-in ends on a go of its own a few seconds later, so
            // this one announced the same beginning twice (UX review
            // 05.09.2026). Read AFTER the clearing above, so a dropped run
            // takes its count-in — and this suppression — with it.
            let countInFollows = countIn && restStartsTheNextSet
            if !countInFollows { playGo() }
            // Spoken as well as sounded, for the reason the two blocks state:
            // the subtree VoiceOver was in is replaced outright by the next
            // screen, so without this the end of a rest reaches nobody who
            // cannot see it — and the tone is behind the sounds switch.
            announce(nextLabel)
            advanceAfterRest(countIn: countIn)
        case .second(let second):
            // no tick spam after backgrounding
            if restClock.signals(second, within: Self.countdownSignalSeconds) {
                playTick()
            }
            // A second or two BEFORE the signalling window, which is what the
            // generator's `prepare()` is worth: primed at the top of a
            // two-minute rest it has long gone cold by the 3 (UX review
            // 05.09.2026).
            primeBeforeTheCount(showing: second)
            animate(.countdown) { restClock.show(second) }
        }
    }

    /// One tap of extra rest. The cap on repeats is twice the planned rest.
    static let restExtensionSeconds = 15

    /// `countIn` is what `SetFacts.restHandsOverWithCountIn` decided: a rest
    /// that ran out under the person's eyes has already counted them in with
    /// its own 3-2-1, and only a tap or a go the app could not sound leaves
    /// the beat still owed.
    func advanceAfterRest(countIn: Bool) {
        // Only a rest ends into the next set. Its callers already stand in a
        // rest; this keeps it true for any later one.
        guard case .rest = phase else { return }
        if isLastSet {
            // One tap bought ONE exercise: the next movement is a decision of
            // its own (R23), and the run and the declared time stay behind.
            enterNextExercise()
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
}
