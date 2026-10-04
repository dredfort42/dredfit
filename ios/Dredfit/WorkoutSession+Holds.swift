//
//  Holds: the count-in, the clock, the side switch, Stop, and the summary a
//  hold movement ends on.
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// The lock screen's copy of a running hold.
    ///
    /// `.hold` rather than `.work` is what puts a countdown on the tile at
    /// all (`RestLiveActivity`), and it is the phase that needs one: the hold
    /// is the one screen whose own copy asks the athlete to put the phone
    /// down, and it was the phase showing a static dot while the rest — the
    /// beat you are allowed to miss — counted down beside it (UX review
    /// 05.09.2026). It does NOT promise a sound from under the lock: a
    /// suspended app plays nothing (R28), and the tile shows seconds, which is
    /// the one thing it can keep.
    func showHoldActivity(until end: Date, detail: String) {
        liveActivity.update(.init(phase: .hold, title: current.name,
                                  detail: detail, restEndDate: end))
    }

    /// What the tile calls the set a hold is running — the same words
    /// `activityWorkState` uses, so the lock screen does not rename the set
    /// halfway through it.
    var holdActivityDetail: String {
        current.isProbe
            ? String(localized: "Probe")
            : String(localized: "set \(setIndex + 1) of \(totalSets)")
    }

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
        guard phase == .work else { return }
        editing = nil
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
        holdClock.show(holdTotal)
        guard !autoContinued else {
            // Straight into the hold on the rest's own go, exactly as the
            // second side starts on the switch pause's (`tickHoldSwitchPause`).
            holdCountInClock.stand(at: 0)
            let end = holdClock.start(holdTotal, now: now())
            showHoldActivity(until: end, detail: holdActivityDetail)
            return
        }
        let countInEnd = holdCountInClock.start(GetReady.countInSeconds, now: now())
        // The count-in opens after a silence as long as any — Skip rest plays
        // nothing at all, and a tap on Start hold can come half a minute after
        // the screen appeared — and on the second before its 3-2-1.
        primeBeforeTheCount(showing: holdCountInClock.remaining)
        // The count-in goes to the tile too — it is the beat that ends on the
        // go, and a phone already on the floor shows it where the eye is.
        showHoldActivity(until: countInEnd, detail: String(localized: "Get ready"))
    }

    /// 3-2-1 and then the go, like every transition in the guided blocks —
    /// here the ticks are wanted, unlike inside the switch pause: the count-in
    /// IS the signal rather than something laid over one.
    func tickHoldCountIn() {
        switch holdCountInClock.read(now: now()) {
        case .unchanged:
            return
        case .ended(let overshoot):
            // The rest applies this rule and says it in words: "a signal
            // nobody could hear cannot be what started a plank". The count-in
            // did not apply it to ITSELF — the comment beside it only covered
            // the LENGTH of the set, not the moment it began — so a call taken
            // inside these five seconds put the athlete in a plank that had
            // already started (UX review 05.09.2026). Same rule, same
            // constant: count them in again rather than start under a signal
            // played to a suspended app.
            guard overshoot <= SetFacts.restGoHeardWithinSec else {
                let again = holdCountInClock.start(GetReady.countInSeconds, now: now())
                primeBeforeTheCount(showing: holdCountInClock.remaining)
                showHoldActivity(until: again, detail: String(localized: "Get ready"))
                return
            }
            holdCountInClock.freeze()
            playGo()
            // …and said, for the reason the two blocks say their boundaries
            // out loud: VoiceOver stays where it was while the screen turns
            // into a running hold, and the go is behind the sounds switch
            // (UX review 05.09.2026). The words are the movement's own name,
            // exactly as at a block's go.
            announce(current.name)
            // The hold's own total was fixed at the tap, so a long absence
            // during the count-in still starts a FULL set rather than the
            // remains of one.
            let holdEnd = holdClock.start(holdTotal, now: now())
            showHoldActivity(until: holdEnd, detail: holdActivityDetail)
        case .second(let second):
            if holdCountInClock.signals(second, within: Self.countdownSignalSeconds) {
                playTick()
            }
            // Never fires while the count-in is four seconds — the start has
            // primed it — but a longer count-in reaches its four here, so the
            // prime does not hang on the count-in's length: a length change
            // silently stopping a prime keyed to one second is how it broke.
            primeBeforeTheCount(showing: second)
            animate(.countdown) { holdCountInClock.show(second) }
        }
    }

    /// A hold that ran to the end of its clock is credited in full, however
    /// late the tick that noticed it — the overshoot is not read here.
    func tickHold() {
        switch holdClock.read(now: now()) {
        case .unchanged:
            return
        case .ended:
            // Silent: completeSet() owns the end-of-set signal now, whatever
            // ended it (#186). Sounding a done here would double it.
            finishHold(heldSeconds: holdTotal)
        case .second(let second):
            if holdClock.signals(second, within: Self.countdownSignalSeconds) {
                playTick()
            }
            animate(.countdown) { holdClock.show(second) }
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
        guard let end = holdClock.endDate else { return }
        let remaining = max(0, end.timeIntervalSince(now()))
        let held = Double(holdTotal) - remaining
        if held < Self.holdMistapSeconds {
            holdClock.stand(at: holdTotal)
            // The set is handed back, so the tile stops counting to a date
            // nothing is running to any more (see `showHoldActivity`).
            liveActivity.update(activityWorkState())
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
        holdClock.freeze()
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
            // The effort is over and the screen waits for a tap: the tile goes
            // back to naming the set rather than counting to a date that has
            // already passed.
            liveActivity.update(activityWorkState())
            persistProgress()   // a recorded hold is worth keeping before the tap
            return
        }
        startExerciseSummary()
    }

    /// Every set of the finished hold movement, on one screen.
    func startExerciseSummary() {
        editing = nil
        holdSettled = false
        holdAutoRun = false
        phase = .exerciseSummary
        liveActivity.update(.init(phase: .work, title: exercise.name,
                                  detail: String(localized: "Held"), restEndDate: nil))
        persistProgress()
    }

    func startHoldSwitchPause() {
        playSwitch()
        let end = holdSwitchClock.start(Cooldown.switchPauseSeconds, now: now())
        // The one instruction of this whole exercise that is not "keep still",
        // and the phone is on the floor by then: the tile counts the five
        // seconds and names them (UX review 05.09.2026).
        showHoldActivity(until: end, detail: String(localized: "Switch sides"))
    }

    /// No 3-2-1 inside the pause: ticks would bury the switch tone.
    func tickHoldSwitchPause() {
        switch holdSwitchClock.read(now: now()) {
        case .unchanged:
            return
        case .ended(let overshoot):
            // The same rule the count-in applies to itself, and the same
            // constant: a signal nobody could hear cannot be what started the
            // second side. Two five-second pauses forty lines apart, and only
            // one of them checked (self-review 05.09.2026) — a call taken
            // inside this one used to start the second side while the phone
            // was still in the athlete's hand, and `finishHold` then recorded
            // min(side one, side two) as a full set nobody held.
            guard overshoot <= SetFacts.restGoHeardWithinSec else {
                let again = holdSwitchClock.start(Cooldown.switchPauseSeconds, now: now())
                // The pause's OWN words, the way the count-in's restart
                // repeats "Get ready". This branch named the stage that comes
                // NEXT, so a phone on the floor said "second side" while the
                // screen beside it still said "Switch sides" and the five
                // seconds on the tile belonged to the pause (review
                // 06.09.2026).
                showHoldActivity(until: again, detail: String(localized: "Switch sides"))
                return
            }
            holdSwitchClock.freeze()
            playGo()
            // Spoken as well, like every other go in the flow: the switch is
            // the moment nobody can afford to miss, and the tone is behind the
            // sounds switch (UX review 05.09.2026).
            announce(SplitStageWords(halves: .sides).secondHalf)
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
            let holdEnd = holdClock.start(holdTotal, now: now())
            showHoldActivity(until: holdEnd,
                             detail: SplitStageWords(halves: .sides).secondHalf)
        case .second(let second):
            animate(.countdown) { holdSwitchClock.show(second) }
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
        // The clock's own word on this set, kept apart from the fact it may
        // later be corrected into — see `holdMeasured`.
        holdMeasured[setIndex] = held
    }

    static let countdownSignalSeconds = 3

    /// Wakes the haptics one second before a 3-2-1. `prepare()` holds the
    /// Taptic Engine for a few seconds only, and a countdown reaches its last
    /// seconds after a silence long enough to let it go cold: unprimed, the
    /// first tick pays the engine's wake-up and lands late — in silent mode,
    /// where the haptic is the whole channel, the 3-2-1 is felt as "2-1-go".
    ///
    /// `second` is the one a countdown has just come to show, by a tick or by
    /// a start: `Countdown.read` reports only a NEW second, so a countdown
    /// started on this one never reports it, and a caller that asks from both
    /// places primes it whichever way it got here. The count-in and the
    /// hands-free rest ask from both. A rest paused on its four and resumed
    /// is primed a second time, on purpose: the first has gone cold by then.
    func primeBeforeTheCount(showing second: Int) {
        if second == Self.countdownSignalSeconds + 1 && store.settings.soundsEnabled {
            signals.prime()
        }
    }

    /// Thin wrappers: each signal's tone + haptic pair lives in
    /// WorkoutSignals, gated here by the one sounds toggle.
    func playTick() { signals.tick(store.settings.soundsEnabled) }
    func playGo() { signals.go(store.settings.soundsEnabled) }
    func playSwitch() { signals.switchSides(store.settings.soundsEnabled) }
    func playDone() { signals.done(store.settings.soundsEnabled) }
    func playWorkoutDone() { signals.workoutDone(store.settings.soundsEnabled) }
    func playMilestone() { signals.milestone(store.settings.soundsEnabled) }

    /// "Start exercise": one tap buys every set of the hold (R23).
    func startHoldExercise() {
        holdAutoRun = true
        startHold()
    }

    /// What the summary's own primary control does. It is `completeSet` and
    /// not a path of its own deliberately: the summary REPLACED the tap that
    /// logged the set, so the flow past it has to be the same flow — the rest
    /// this movement earns, or the cool-down when it was the last one.
    func leaveExerciseSummary() {
        guard phase == .exerciseSummary else { return }
        holdApproxSets.removeAll()
        holdMeasured.removeAll()
        completeSet()
    }

    /// The screen a hold exercise OPENS on: nothing running, nothing behind,
    /// and one tap away from all of it. What 6c adds — the shape of the
    /// exercise and the promise under it — belongs to this moment only; once
    /// the run is under way the caption has states of its own to report.
    var holdExerciseIntro: Bool {
        current.unit == .hold && !current.isProbe && !holdAutoRun
            && setIndex == 0 && !holdSettled
            && !holding && !holdCountingIn && !holdSwitchPausing
    }

    /// The clock is on the person: a hold is running, counting them in, or
    /// holding the five seconds between sides. Named once because four things
    /// on this screen stand down for exactly this, each of them spelling the
    /// same three flags out by hand — which is how the escapes came to be
    /// dimmed and disabled but still in the accessibility tree, and the
    /// technique button to be neither (UX review, 05.09.2026).
    var holdUnderWay: Bool { holding || holdCountingIn || holdSwitchPausing }

    /// What a Stop right now would RECORD — nil inside the mis-tap grace,
    /// where the tap cancels the set and writes nothing at all, so a figure on
    /// the button would be a straight lie.
    ///
    /// Compared as `> holdMistapSeconds` rather than `>=`, and the second is
    /// not pedantry: `holdClock.remaining` is the rounded second, so an integer 3
    /// covers a real 2.5 s that `stopHoldEarly` will still read as a mis-tap.
    /// At 4 the two can no longer disagree.
    var holdStopRecords: Int? {
        let held = holdTotal - holdClock.remaining
        guard Double(held) > Self.holdMistapSeconds else { return nil }
        return SetFacts.holdEndedByTap(heldSeconds: held)
    }
}
