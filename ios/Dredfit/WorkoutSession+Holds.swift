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
    /// down, and a static dot there would leave the rest — the beat you are
    /// allowed to miss — the only one the tile counts down. It does NOT
    /// promise a sound from under the lock: a suspended app plays nothing,
    /// and the tile shows seconds, which is the one thing it can keep.
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

    /// The tap arms the set; the clock waits out a count-in first. Started
    /// under the thumb, a hold is not only a jolt: the seconds spent getting
    /// down into the plank would come off the number the engine measures.
    ///
    /// A SET THE RUN OPENS HAS NO COUNT-IN OF ITS OWN, unless a tap cut the
    /// rest short or its go came too late to be heard
    /// (`SetFacts.restHandsOverWithCountIn`). The rest before it is the
    /// lead-in: it counts its own last three seconds down and ends on the go,
    /// and that go is this hold's start signal — the same shape the
    /// side-switch pause has.
    ///
    /// Nothing is laid on top of that rest. The rest IS the travel time: a
    /// person who has spent it lying beside the mat needs no more, a second
    /// 3-2-1 and go would announce a set that has already been announced, and
    /// its seconds would be ones no estimate anywhere counts — `restSetSec`
    /// is what the engine budgets between sets.
    ///
    /// A TAP still earns its beat, and that asymmetry is the point:
    /// `GetReady.countInSeconds` is the pause between somebody saying "I am
    /// ready" and being counted in. That is why a rest cut short by Skip
    /// arrives here with `autoContinued: false`.
    func startHold(autoContinued: Bool = false) {
        guard phase == .work else { return }
        editing = nil
        // Read where the screen reads it, so the number named before the tap
        // is the one counted — `targetInForce` says what that is on the probe
        // set and under a declared time.
        var planned = targetInForce
        #if DEBUG
        // The UI suite needs the two ENDS of the corridor — the floor, to walk
        // a whole hold exercise inside a test's budget, and the ceiling, to
        // give a mid-hold Stop a margin no loaded runner can eat (a nightly
        // run has spent 20 s delivering one tap).
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
        // this is its only call site. Deriving from the plan there would hand
        // the second side the full length again and undo the rule in silence.
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
            // The rule the rest applies, in its own words: "a signal nobody
            // could hear cannot be what started a plank" — otherwise a call
            // taken inside the count-in would put the athlete in a plank that
            // had already started. Same rule, same constant: count them in
            // again rather than start under a signal played to a suspended
            // app.
            guard overshoot <= SetFacts.restGoHeardWithinSec else {
                let again = holdCountInClock.start(GetReady.countInSeconds, now: now())
                showHoldActivity(until: again, detail: String(localized: "Get ready"))
                return
            }
            holdCountInClock.freeze()
            playGo()
            // …and said, for the reason the two blocks say their boundaries
            // out loud: VoiceOver stays where it was while the screen turns
            // into a running hold, and the go is behind the sounds switch.
            // The words are the movement's own name, exactly as at a block's
            // go.
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
            // A second before the signalling window, exactly as the rest does
            // it. `prepare()` holds the Taptic Engine for a few seconds only,
            // and this count-in opens after a silence as long as any: Skip
            // rest plays nothing at all, and a tap on Start hold can come half
            // a minute after the screen appeared. Unprimed, the first tick
            // pays the engine's wake-up and lands late — in silent mode, where
            // the haptic is the whole channel, the 3-2-1 is heard as "2-1-go".
            // Here rather than at the tap, so the restart above is warmed too.
            if second == Self.countdownSignalSeconds + 1 && store.settings.soundsEnabled {
                signals.prime()
            }
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
            // Silent: `finishHold` sounds what comes next — the switch, or the
            // set's done, by itself on a last set and through `completeSet`
            // otherwise (#186). Sounding a done here would double it.
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
    /// Otherwise one mis-tap consumes the set and records a bogus actual.
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
        // Only the LAST set stops here. A set with another one behind it is
        // not lost: the movement comes back, and until it does the rest is
        // what the person wants. The last set is terminal — after it no
        // screen about this movement returns, and the seconds it recorded
        // would stand uncorrectable.
        guard isLastSet else {
            completeSet()   // the rest starts itself
            return
        }
        // The signal fires HERE, where the effort actually stopped, not on the
        // tap that follows: the person may have their eyes shut in a plank,
        // and the sound is the only thing that says the hold is over.
        playDone()
        // The PROBE keeps a settled screen of its own: its caption states the
        // outcome of the trial ("Next time: …"), which is a sentence about a
        // movement the summary below deliberately says nothing about — the
        // probe's number is its own channel and is never folded in. Every
        // other last set of a hold lands on the summary instead, where the
        // whole movement is in front of the person.
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
        // and the phone is on the floor by then: the tile counts the pause
        // down and names it.
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
            // second side. Otherwise a call taken inside this pause would
            // start the second side while the phone is still in the athlete's
            // hand, and `finishHold` would record min(side one, side two) as a
            // full set nobody held.
            guard overshoot <= SetFacts.restGoHeardWithinSec else {
                let again = holdSwitchClock.start(Cooldown.switchPauseSeconds, now: now())
                // The pause's OWN words, the way the count-in's restart
                // repeats "Get ready": the seconds on the tile belong to the
                // pause, and naming the stage that comes NEXT would put
                // "second side" on a phone on the floor while the screen
                // beside it still says "Switch sides".
                showHoldActivity(until: again, detail: String(localized: "Switch sides"))
                return
            }
            holdSwitchClock.freeze()
            playGo()
            // Spoken as well, like every other go in the flow: the switch is
            // the moment nobody can afford to miss, and the tone is behind the
            // sounds switch.
            announce(SplitStageWords(halves: .sides).secondHalf)
            // BOTH SIDES OF ONE SET CARRY THE SAME LOAD. The second side runs
            // for what the first actually ran, not for what the plan asked: a
            // first side stopped at 20 s of a planned 30 must not hand the
            // second side the full 30 — the fact recorded for the set is
            // min(side one, side two), so those ten seconds would load one
            // side harder than the other AND count for nothing.
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

    /// Snapped to a storable number (`SetFacts.snap`), and onto the set
    /// actually held: stopping at 40 s of 55 in the third set is the third
    /// set's fact.
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

    /// Thin wrappers: each signal's tone + haptic pair lives in
    /// WorkoutSignals, gated here by the one sounds toggle.
    func playTick() { signals.tick(store.settings.soundsEnabled) }
    func playGo() { signals.go(store.settings.soundsEnabled) }
    func playSwitch() { signals.switchSides(store.settings.soundsEnabled) }
    func playDone() { signals.done(store.settings.soundsEnabled) }
    func playWorkoutDone() { signals.workoutDone(store.settings.soundsEnabled) }
    func playMilestone() { signals.milestone(store.settings.soundsEnabled) }

    /// "Start exercise": one tap buys every set of the hold.
    func startHoldExercise() {
        holdAutoRun = true
        startHold()
    }

    /// What the summary's own primary control does. It is `completeSet` and
    /// not a path of its own deliberately: the summary stands where the tap
    /// that logs the set would be, so the flow past it has to be the same
    /// flow — the rest this movement earns, or the cool-down when it was the
    /// last one.
    func leaveExerciseSummary() {
        guard phase == .exerciseSummary else { return }
        holdApproxSets.removeAll()
        holdMeasured.removeAll()
        completeSet()
    }

    /// The screen a hold exercise OPENS on: nothing running, nothing behind,
    /// and one tap away from all of it. What it adds — the shape of the
    /// exercise and the promise under it — belongs to this moment only; once
    /// the run is under way the caption has states of its own to report.
    var holdExerciseIntro: Bool {
        current.unit == .hold && !current.isProbe && !holdAutoRun
            && setIndex == 0 && !holdSettled
            && !holding && !holdCountingIn && !holdSwitchPausing
    }

    /// The clock is on the person: a hold is running, counting them in, or
    /// holding the pause between sides. Named once because four things on
    /// this screen stand down for exactly this, and three flags spelled out by
    /// hand at each is how they drift apart — escapes dimmed and disabled but
    /// still in the accessibility tree, a technique button neither.
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

    /// What the set under way runs at: the number `startHold` sets the clock
    /// from, and the one the work screen names before it (`workNumber`) — on
    /// a second side both cut it to what the first side ran.
    ///
    /// One reading for both, because the screen is the promise the clock
    /// keeps. A declared time stands in for the plan for the whole exercise
    /// (`SetFacts.holdTarget`), so it is the number the screen names: the one
    /// the person agreed to, not the plan they decided against. That has to
    /// hold on every set the run does not open — after an absence in the
    /// rest, a Stop inside the mis-tap grace, a skipped set or a restore —
    /// where a screen reading the plan would name 15 and the clock would then
    /// count the declared 45.
    ///
    /// The PROBE set runs at the probe's own number, entered or not: it is one
    /// set of another movement, possibly in another unit, and a time declared
    /// for this movement says nothing about that one.
    var targetInForce: Int {
        current.isProbe
            ? (probeActuals[exercise.pattern] ?? current.planned)
            : SetFacts.holdTarget(actuals, exercise, set: setIndex, declared: holdDeclared)
    }

    /// The big number on the work screen, in order of precedence: the
    /// count-in, the pause between sides and a running hold each show the
    /// seconds they have left, and with nothing running it is what the set
    /// asks for — on a hold, the number the next Start puts on the clock.
    ///
    /// Here and not in the view because it is a promise the clock is held to,
    /// and a rule stated inside a SwiftUI view is a rule no gating test can
    /// reach.
    var workNumber: Int {
        if holdCountingIn { return holdCountInClock.remaining }
        if holdSwitchPausing { return holdSwitchClock.remaining }
        if holding { return holdClock.remaining }
        // A second side handed back by a Stop inside the mis-tap grace still
        // runs for what the first side ran, the way `startHold` re-arms it,
        // so that is the number it names rather than the set's own.
        return SetFacts.holdSideSeconds(planned: targetInForce,
                                        firstSideHeld: holdSecondSide ? firstSideHeld : nil)
    }
}
