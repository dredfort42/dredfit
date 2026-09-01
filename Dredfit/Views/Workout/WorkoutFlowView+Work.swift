//
//  The work screen — the one a set is actually performed on — and the pieces
//  only it reads. It moved out of WorkoutFlowView.swift when the hands-free
//  hold wave arrived: that file stood at 1101 lines against the lint's hard
//  ceiling of 1200, and this wave adds a phase to it. A file split is what
//  cures THAT ceiling; an extension only cures the other one (a type body at
//  600). The code moved unchanged apart from the edits of the wave itself.
//
//  Swift's `private` is file-scoped, so the members this screen reaches for
//  lost theirs on the way out — the same price the four siblings before it
//  paid, and for the same reason. Nothing outside the WorkoutFlowView files
//  touches them.
//

import SwiftUI
import DredfitCore

extension WorkoutFlowView {

    // MARK: - Work

    var workView: some View {
        VStack(spacing: 0) {
            Spacer()
            if current.isProbe {
                // The badge is the whole announcement: one set of a movement
                // that is not yet yours, to find out whether it is. It is not
                // a question and there is nothing to answer — the number goes
                // in through the same per-set control as every other set.
                Text("Probe")
                    .dredfitFont(11, weight: .heavy)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("probe-badge")
            }
            Text(current.name)
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .accessibilityLabel(Text(verbatim: current.name))

            // On the probe set this opens the technique of the NEW movement:
            // nobody should be asked to try something they cannot read up on
            // first.
            TechniqueButton { techniqueTarget = current.target }
                .padding(.top, 10)

            VStack(spacing: 4) {
                Text("\(workNumber)")
                    .dredfitFont(112, weight: .heavy, cap: 150)
                    .tracking(-4)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(loadCaption)
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 20)
            // One element, like the rest ring below: two made VoiceOver read
            // "8" and then "reps per side" as if they were separate facts, and
            // the number alone is meaningless. Both halves are recomputed on
            // every body pass, so the label follows a hold's countdown down.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(workNumber) ") + Text(verbatim: loadCaption))

            HStack(spacing: 10) {
                ForEach(0..<totalSets, id: \.self) { i in
                    // The probe's dot is hollow: it is the same session and
                    // the same count of sets, but not the same movement.
                    Circle()
                        .strokeBorder(Theme.accent,
                                      lineWidth: exercise.probe != nil && i == exercise.sets ? 2 : 0)
                        .background(Circle().fill(
                            exercise.probe != nil && i == exercise.sets
                                ? Color.clear
                                : (i < setIndex ? Theme.ink
                                   : (i == setIndex ? Theme.accent : Theme.hairline))))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 30)

            // The count-in outranks the probe's own caption: the big number
            // above is five seconds of getting into position, and nothing else
            // on the screen would say so.
            if holdTailing {
                // The one new element on this screen (R25): how far past the
                // plan the clock has banked, and where the next step lands.
                // The ladder is the shape of it, the line is the numbers.
                VStack(spacing: 8) {
                    HoldTailSteps(banked: holdTailBanked, planned: holdTotal,
                                  cap: SetFacts.holdTailCap(planned: holdTotal),
                                  step: SetFacts.holdTailStepSeconds)
                    Text("+\(holdTailBanked - holdTotal) banked · next step at \(holdTailNextStep)")
                        .dredfitFont(14, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                }
                .padding(.top, 10)
            } else if holdExerciseIntro && exercise.sets > 1 {
                // "set 1 of 3" is not the question on this screen any more.
                // ONE tap buys the whole exercise, so what the person is
                // deciding about is the whole exercise: how many sets it is
                // and how long it will wait between them (R24). Held back on
                // a single-set plan, where there is no rest between anything
                // and "1 sets" would be false twice over.
                Text("\(exercise.sets) sets · \(exercise.restSetSec) s rest between")
                    .dredfitFont(14)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 10)
                    .accessibilityIdentifier("hold-sets-and-rest")
            } else if current.isProbe && !holdCountingIn {
                probeCaption
                    .padding(.top, 10)
            } else {
                WorkStatusCaption(countingIn: holdCountingIn,
                                  switchingSides: holdSwitchPausing,
                                  secondSide: holdSecondSide,
                                  settled: holdSettled,
                                  actual: setActual,
                                  setIndex: setIndex, sets: exercise.sets,
                                  planned: exercise.plannedLoad(set: setIndex),
                                  uneven: exercise.loads != nil)
                    .padding(.top, 10)
            }

            Spacer()

            // The messages stand down while a number is being entered: one
            // thing to read at a time.
            //
            // The hint FIRST, the note second. Both are reserved height when
            // hidden, and the order is what keeps that height from sitting
            // between the note and the button below: the note has to stand the
            // same 18 pt above the pair that the escapes stand below it, and
            // that the rest offer stands above Start on Today (owner,
            // 27.08.2026).
            if !adjusting {
                // Opacity, not `if`: the reserved height keeps the layout still
                // when the hint's job is done mid-exercise.
                // Reps only since R23. The hold screen no longer carries
                // "Went differently" — nothing is entered before the effort
                // there — so on a hold this hint named a control that is not
                // on the screen, which is exactly the unperformable
                // instruction R23 exists to remove.
                if store.records.isEmpty && current.unit == .reps {
                    Text("Did far more than planned? Tap “Went differently” and enter what you actually did — the next plan starts from what you showed.")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .opacity(holding || holdSwitchPausing || holdCountingIn
                                 || actuals[exercise.pattern] != nil ? 0 : 1)
                }

                // Once per exercise per session, and it never blocks the entry
                // — the number stands either way. It used to be grey 13 pt in
                // the fine-print slot directly above the black primary button,
                // which is the one place on the screen nobody reads (owner,
                // 27.08.2026). accentText on accentSoft, not accent: accent
                // itself is 2.91:1 on that fill (see the badge pill on Today).
                if let warning = maximumWarning {
                    Text(warning)
                        .dredfitFont(14, weight: .medium)
                        .foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("maximum-note")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            // The entry opens IN THE SLOT OF THE BUTTON THAT OPENS IT, directly
            // over the primary one it will hand back to. Nothing below moves:
            // the block after the Spacer is bottom-aligned as a group, so what
            // is added or removed above the button changes where the group
            // starts, never where the button sits.
            if adjusting {
                AdjustPanel(value: $adjustValue, unit: current.unit) {
                    if current.isProbe {
                        // The probe's own channel: one number about one set of
                        // another movement, never folded into the mean of the
                        // working sets.
                        probeActuals[exercise.pattern] = adjustValue
                    } else {
                        // This set only — the ones behind keep what they ran at.
                        actuals = SetFacts.recording(adjustValue, in: actuals,
                                                     exercise, set: setIndex)
                        noteMaximumOutOfOrder()
                    }
                    adjusting = false
                    persistProgress()   // an entered actual is worth keeping
                }
                .padding(.bottom, 18)
            } else if current.unit == .hold && !holdSettled {
                // R23: NOTHING is entered BEFORE the effort on a hold. The
                // control that used to stand here asked for a number about a
                // set nobody had performed yet, and the one moment it was
                // genuinely needed — a hold that ran long — is the moment both
                // hands are on the floor. No reserved height either: the block
                // under the Spacer is bottom-aligned as a group, so what
                // leaves it moves nothing below.
                //
                // A SETTLED hold keeps it, and the exception is the whole
                // point rather than a leftover. There the effort is behind and
                // its seconds are on the screen, which is the correction R23
                // is arguing FOR — and it is the last set of the movement, so
                // nothing about it ever comes back (#220, 31.08.2026). The
                // exercise summary takes the job over, and this exception goes
                // with the settled state when it does.
                if holdTailing {
                    // Why the clock and the button disagree, said once: the
                    // big number is the seconds actually running, the button
                    // is the seconds already earned. Without this the gap
                    // reads as a bug rather than as the rule that makes
                    // reaching for the phone free.
                    Text("Each step is banked when the tone sounds. Stop whenever you like — the number is already earned.")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("hold-tail-note")
                } else if holdExerciseIntro {
                    // What the one tap actually buys, said before it is
                    // taken. Deliberately without a numeral — the count is on
                    // the line above, and a second one here would need an ICU
                    // plural in seven languages to say nothing new.
                    //
                    // "Put the phone down", never "lock the screen": a
                    // suspended app runs no timers and plays no tones, and a
                    // promise this screen cannot keep is worse than no
                    // promise (R28).
                    Text("Runs on its own from here — sound counts you in and out. Put the phone down.")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("hold-autorun-promise")
                }
            } else {
                WentDifferentlyButton { startAdjusting() }
                    .padding(.bottom, 18)
                    // no adjusting mid-hold, mid-count-in or mid-pause
                    .opacity(holding || holdSwitchPausing || holdCountingIn ? 0 : 1)
                    .disabled(holding || holdSwitchPausing || holdCountingIn)
            }

            if current.unit == .hold {
                if holdTailing {
                    // It names the BANK, not the clock: what a tap stores is
                    // the last completed step, and the two to four seconds
                    // between deciding to stop and reaching the glass cannot
                    // change it.
                    HoldStopButton(records: holdTailBanked) { endHoldTail(measured: true) }
                } else if holding {
                    // The control names the figure it will write (R29): two to
                    // four seconds are spent reaching for the phone, and a
                    // person who cannot see what the tap records has no way to
                    // judge whether it is worth taking.
                    HoldStopButton(records: holdStopRecords) { stopHoldEarly() }
                } else if holdSwitchPausing || holdCountingIn {
                    // hidden, not opacity: the button must leave the
                    // accessibility tree while keeping its reserved space.
                    // A count-in is armed already — a second tap on the slot
                    // it left must not land on anything.
                    //
                    // Its own identifier, not the live one's: should `.hidden()`
                    // ever stop pruning the tree, a query for the real control
                    // must not resolve to this placeholder.
                    PrimaryButton(title: String(localized: "Start hold")) { }.hidden()
                        .accessibilityIdentifier("hold-start-spacer")
                } else if holdSettled {
                    // The last hold is behind; this tap only logs it. Same
                    // title and same identifier as the reps button, because it
                    // is the same act — the set ends when the person says the
                    // number is right, not when a clock says the effort is
                    // over.
                    PrimaryButton(title: String(localized: "Done")) { completeSet() }
                        .accessibilityIdentifier("exercise-done")
                } else if holdAutoRun || current.isProbe {
                    // ONE set, not the exercise. Two ways in, and both are
                    // about a set that has already been armed once: a Stop
                    // inside the mis-tap grace hands the set back, and the
                    // probe is a different movement — possibly in a different
                    // unit (§40.1) — which the auto-run deliberately does not
                    // start for you.
                    PrimaryButton(title: String(localized: "Start hold")) { startHold() }
                        .accessibilityIdentifier("hold-start")
                } else {
                    // One tap for the whole exercise (R23). Three sets of a
                    // hold cost four touches before this, three of them taken
                    // between sets by someone lying on the floor.
                    PrimaryButton(title: String(localized: "Start exercise")) {
                        holdAutoRun = true
                        startHold()
                    }
                    .accessibilityIdentifier("hold-start-exercise")
                }
            } else {
                PrimaryButton(title: String(localized: "Done")) { completeSet() }
                    .accessibilityIdentifier("exercise-done")
            }

            ExerciseActionsRow(onSkipSet: setSkipAction,
                               skipsProbe: onProbeSet,
                               escape: exerciseEscape)
            // 18, the measure of this whole stack: the same gap stands between
            // the note and "Went differently", between it and the button, and
            // here between the button and the escapes. It was 18 to begin with
            // for a reason that still holds — the button between them LOGS THE
            // SET, and a thumb that lands a few points off does not miss, it
            // finishes the set at plan.
            .padding(.top, 18)
            .padding(.bottom, 10)
            // No adjusting/skipping mid-hold, mid-count-in or mid-pause —
            // and none once a settled hold is behind either: the set was
            // performed and its number is on the screen, so a skip there would
            // contradict the very fact the person is being shown.
            .opacity(holding || holdSwitchPausing || holdCountingIn
                     || holdSettled || holdTailing ? 0 : 1)
            .disabled(holding || holdSwitchPausing || holdCountingIn
                      || holdSettled || holdTailing)

        }
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

    /// Where the next step of the tail lands — never past the cap, which is
    /// where the tail closes itself.
    var holdTailNextStep: Int {
        min(holdTailBanked + SetFacts.holdTailStepSeconds,
            SetFacts.holdTailCap(planned: holdTotal))
    }

    /// What a Stop right now would RECORD — nil inside the mis-tap grace,
    /// where the tap cancels the set and writes nothing at all, so a figure on
    /// the button would be a straight lie.
    ///
    /// Compared as `> holdMistapSeconds` rather than `>=`, and the second is
    /// not pedantry: `holdRemaining` is the rounded second, so an integer 3
    /// covers a real 2.5 s that `stopHoldEarly` will still read as a mis-tap.
    /// At 4 the two can no longer disagree.
    var holdStopRecords: Int? {
        let held = holdTotal - holdRemaining
        guard Double(held) > Self.holdMistapSeconds else { return nil }
        return SetFacts.holdEndedByTap(heldSeconds: held)
    }

    /// In order of precedence.
    private var workNumber: Int {
        if holdCountingIn { return holdCountInRemaining }
        // The seconds ACTUALLY RUNNING, which is deliberately not the number
        // on the button: 62 held, 60 banked. Both are true and the note under
        // the ladder says why — collapsing them into one would either claim
        // seconds that are not earned or hide seconds that are being held.
        if holdTailing { return holdTailSeconds }
        if holdSwitchPausing { return holdPauseRemaining }
        if holding { return holdRemaining }
        if current.isProbe { return probeActuals[exercise.pattern] ?? current.planned }
        return SetFacts.inForce(actuals, exercise, set: setIndex)
    }

    /// The caption's: this set's own number, nothing when it is the plan.
    /// The plan of THIS SET — against the flat base an untouched top set of
    /// an uneven plan read as an entered fact (UI-truth audit, 27.08.2026).
    private var setActual: Int? {
        SetFacts.offPlan(actuals, exercise, set: setIndex)
    }

    // MARK: - Inline actual adjuster (the panel itself is AdjustPanel.swift)

    private func startAdjusting() {
        adjustValue = current.isProbe
            ? (probeActuals[exercise.pattern] ?? current.planned)
            : SetFacts.inForce(actuals, exercise, set: setIndex)
        adjusting = true
    }

    /// What the probe set says under its number. Before a number is entered it
    /// states the target; afterwards it states the outcome — and the failing
    /// outcome is NEUTRAL, because honesty is never punished (§40.4): staying
    /// on a movement you can already do is not a failure, and the copy must
    /// not read like one.
    ///
    /// The failing line used to read "We'll stay with the current variation",
    /// and it needed explaining for two reasons (owner, 27.08.2026). It said
    /// "variation", a word this app's own vocabulary does not use anywhere
    /// else on screen. And it pointed at something NOT ON SCREEN: at that
    /// moment the title is the NEXT movement with a "Probe" badge over it, so
    /// "the current one" is a name the reader has to reconstruct — where the
    /// passing line names its movement outright. What replaced it states the
    /// consequence instead, which is the thing the reader will actually see
    /// tomorrow, and deliberately does NOT promise the probe comes back next
    /// time: a session later rated "hard" on this pattern suppresses it.
    @ViewBuilder
    private var probeCaption: some View {
        if let entered = probeActuals[exercise.pattern] {
            if entered >= current.planned && !workingSetsFellShort {
                Text("Next time: \(current.name)")
                    .accessibilityIdentifier("probe-passed")
            } else {
                // Also the answer for a probe done at target AFTER working
                // sets that fell short: the engine reads that session as
                // "hard" for the pattern, and a hard pattern's probe does not
                // count (§40.4) — a promise here would be broken by numbers
                // already entered (UI-truth audit, 27.08.2026).
                Text("Not this time — the plan stays as it is.")
                    .accessibilityIdentifier("probe-stays")
            }
        } else {
            // No number here: the big one above IS this number, and the
            // caption repeated it (owner, 27.08.2026). On a hold probe the
            // big number starts counting down once the timer runs, and the
            // target then shows nowhere — which is exactly what an ORDINARY
            // hold does too, so the probe simply stops being the exception.
            Text("One set to try it.")
        }
    }

    /// The knowable half of the §40.4 gate — see `SetFacts.foldFallsShort`.
    private var workingSetsFellShort: Bool {
        SetFacts.foldFallsShort(actuals, of: exercise)
    }

    private var loadCaption: String {
        // During the switch pause and the count-in the big number is a
        // countdown, not the load.
        if holdSwitchPausing || holdCountingIn { return String(localized: "sec") }
        // The unit only: the 112 pt number above already says how many, and
        // printing it twice is the kind of noise that makes a screen feel
        // busy. Because the caption no longer agrees with a number, these
        // keys need no ICU plurals — one form per language.
        switch (current.unit, current.perSide) {
        case (.reps, false): return String(localized: "reps")
        case (.reps, true):  return String(localized: "reps per side")
        case (.hold, false): return String(localized: "seconds")
        case (.hold, true):  return String(localized: "seconds per side")
        }
    }

}
