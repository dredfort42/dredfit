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
                    // `ink`, not accentText, and the fill stays accentSoft:
                    // that pair comes to 4.20:1 in the dark scheme (I-21),
                    // under what small text needs — and 11 pt is the smallest
                    // text on this screen. The same move HeldSetCard already
                    // made, for the same measurement: the accent is the fill,
                    // and the word is a word (UX review, 05.09.2026).
                    .foregroundStyle(Theme.ink)
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
                // The token, not the inherited default: text with no
                // foregroundStyle draws in `.primary`, which is #FFFFFF in the
                // dark scheme against ink's #F2F2F4 — so the two loudest
                // elements of the flow were the two outside the palette
                // (UX review, 05.09.2026).
                .foregroundStyle(Theme.ink)
                .accessibilityLabel(Text(verbatim: current.name))

            // On the probe set this opens the technique of the NEW movement:
            // nobody should be asked to try something they cannot read up on
            // first.
            //
            // Never while the clock is on the person, though: the sheet covers
            // the screen and the hold keeps counting underneath it, so reading
            // about the position cost the set it describes. The guided blocks
            // FREEZE their countdown for this same tap (`openPositionTechnique`)
            // — the work screen cannot, so it takes the offer away instead
            // (UX review, 05.09.2026). opacity + disabled, like the escapes at
            // the bottom: the height stays reserved and nothing jumps.
            TechniqueButton { techniqueTarget = current.target }
                .padding(.top, 10)
                .opacity(holdUnderWay ? 0 : 1)
                .disabled(holdUnderWay)
                .accessibilityHidden(holdUnderWay)

            VStack(spacing: 4) {
                Text("\(workNumber)")
                    .dredfitFont(112, weight: .heavy, cap: 150)
                    .tracking(-4)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    // The token (see the name above), except for the five
                    // seconds of a side switch, where the number turns accent.
                    // The phone is on the floor 1.5-2 m away by then — the
                    // screen said to put it there — and at that distance a
                    // 14 pt word is about 2.6 arc minutes, under the 5' it
                    // takes to recognise a letter. Colour on a 13 mm digit
                    // survives the distance where the word does not, and the
                    // tone that used to be the only other channel is silenced
                    // by the ring switch (UX review, 05.09.2026).
                    .foregroundStyle(holdSwitchPausing ? Theme.accentText : Theme.ink)
                Text(loadCaption)
                    .dredfitFont(loadCaptionEmphasis.size, weight: loadCaptionEmphasis.weight)
                    .foregroundStyle(loadCaptionEmphasis.color)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            // One element, like the rest ring below: two made VoiceOver read
            // "8" and then "reps per side" as if they were separate facts, and
            // the number alone is meaningless. Both halves are recomputed on
            // every body pass, so the label follows a hold's countdown down.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(workNumber) ") + Text(verbatim: loadCaption))
            // The label is rebuilt every second while a hold runs, and without
            // this VoiceOver has no reason to re-read the element it is sitting
            // on — so the one number that moves was the one number it never
            // announced (UX review 05.09.2026).
            .accessibilityAddTraits(.updatesFrequently)

            HStack(spacing: 10) {
                ForEach(0..<totalSets, id: \.self) { i in
                    // The probe's dot is hollow: it is the same session and
                    // the same count of sets, but not the same movement.
                    //
                    // The sets still AHEAD take ink2, the move the header's
                    // capsules already made in the same wave: hairline is
                    // 1.17:1 on `bg` in the light scheme, so the track the
                    // filled dots are measured against was not on the screen
                    // at all — and ink2 is the only token clearing the 3:1
                    // graphics floor in both schemes (4.96 / 6.97) while
                    // staying a long way lighter than a done dot's ink (18.7),
                    // so the three states stay three (UX review 05.09.2026).
                    Circle()
                        .strokeBorder(Theme.accent,
                                      lineWidth: exercise.probe != nil && i == exercise.sets ? 2 : 0)
                        .background(Circle().fill(
                            exercise.probe != nil && i == exercise.sets
                                ? Color.clear
                                : (i < setIndex ? Theme.ink
                                   : (i == setIndex ? Theme.accent : Theme.ink2))))
                        // Off a frozen 10 pt, so the row a person with larger
                        // type reads grows with the rest of the screen.
                        .frame(width: setDotSize, height: setDotSize)
                }
            }
            .padding(.top, 30)

            // The count-in used to outrank the probe's own caption here,
            // because the big number was five seconds of getting into position
            // and nothing else on the screen said so. The caption under the
            // number says so now — in the one place a person on the floor can
            // read it — so the probe keeps its own line throughout, and this
            // slot never announces "set 4 of 4" about a movement the flow
            // calls a probe everywhere else (UX review, 05.09.2026).
            if holdExerciseIntro && exercise.sets > 1 {
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
            } else if current.isProbe {
                probeCaption
                    .padding(.top, 10)
            } else {
                // `totalSets`, not `exercise.sets`: the probe is a set of this
                // exercise on every other surface — the dots above draw it,
                // the rest screen counts it ("set 2 of 4") and so does the
                // lock screen — and only this line left it out, so the same
                // exercise was announced with two denominators
                // (UX review, 05.09.2026).
                WorkStatusCaption(secondSide: holdSecondSide,
                                  settled: holdSettled,
                                  actual: setActual,
                                  setIndex: setIndex, sets: totalSets,
                                  planned: setInForce,
                                  uneven: exercise.loads != nil
                                      || setInForce != exercise.plannedLoad(set: setIndex))
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
                //
                // The FIRST exercise of a workout, not every one of them: at
                // `store.records.isEmpty` alone this paragraph came back on
                // all six movements and before all three sets of each — up to
                // eighteen readings of the longest sentence in the flow
                // (UX review, 05.09.2026).
                //
                // …and until the CONTROL HAS BEEN USED, not until the first
                // workout is over. The two are different people: the door
                // this describes is the only fast calibration channel in the
                // app, and the person who never opened it on session one is
                // exactly the person who still needs telling. The flag is
                // one-way and spent by the first reported number, so it can
                // neither nag someone who has already answered it nor
                // disappear from someone who has not (UX review, 05.09.2026).
                //
                // And it names BOTH directions now. It used to ask "did far
                // more than planned?", while a number BELOW the plan is what
                // the engine acts on hardest (Feedback.swift) and what a first
                // session most often produces — the one door that was open
                // was described by the case least likely to be true.
                if store.showsDifferentNumberHint && exIndex == 0 && current.unit == .reps {
                    let spent = actuals[exercise.pattern] != nil
                    Text("More or fewer than planned? Tap “Went differently” — the next plan starts from your number.")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .opacity(holdUnderWay || spent ? 0 : 1)
                        // opacity alone leaves a whole paragraph readable to
                        // VoiceOver on a screen that no longer shows it, which
                        // is the ghost-control defect the placeholder button
                        // below already guards against (UX review, 05.09.2026).
                        .accessibilityHidden(holdUnderWay || spent)
                }

                // Once per exercise per session, and it never blocks the entry
                // — the number stands either way. It used to be grey 13 pt in
                // the fine-print slot directly above the black primary button,
                // which is the one place on the screen nobody reads (owner,
                // 27.08.2026).
                //
                // `ink` on the accentSoft fill, not accentText: that pair is
                // 4.20:1 in the dark scheme (I-21), under the 4.5:1 this
                // 14 pt sentence needs, while ink on accentSoft is gated at
                // 4.5 dark and 7 in Increased Contrast (BrandPaletteTests).
                // The accent stays as the fill — the note is found by the
                // colour of the card and read in ink (UX review, 05.09.2026).
                if let warning = maximumWarning {
                    Text(warning)
                        .dredfitFont(14, weight: .medium)
                        .foregroundStyle(Theme.ink)
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
                    if holdDeclaring {
                        // A TARGET, not a record: it sets what the clock runs
                        // from for this exercise and writes nothing about a
                        // set. What is stored for each set is still whatever
                        // that set's clock produced.
                        holdDeclared = adjustValue
                        holdDeclaring = false
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
                    adjusting = false
                    persistProgress()   // an entered actual is worth keeping
                }
                .padding(.bottom, 18)
            } else if current.unit == .hold && !holdSettled {
                // No "Went differently" on a hold, and the reason is the
                // TENSE rather than the slot. Before the effort it would ask
                // how a set went that nobody has performed; what belongs here
                // is a target, and that is the control above. Afterwards the
                // exercise summary asks the question properly, about every
                // set of the movement at once. No reserved height either: the
                // block under the Spacer is bottom-aligned as a group, so
                // what leaves it moves nothing below.
                //
                // A SETTLED hold keeps it, and the exception is the whole
                // point rather than a leftover: that is the PROBE's screen,
                // which the summary deliberately says nothing about (§40.4).
                if holdExerciseIntro {
                    // What the one tap actually buys, said before it is
                    // taken. Deliberately without a numeral — the count is on
                    // the line above, and a second one here would need an ICU
                    // plural in seven languages to say nothing new.
                    //
                    // "Put the phone down", never "lock the screen": a
                    // suspended app runs no timers and plays no tones, and a
                    // promise this screen cannot keep is worse than no
                    // promise (R28).
                    //
                    // The same rule read against the SOUND SWITCH, which R28
                    // never checked: with "Sounds and haptics" off, one guard
                    // silences the tone AND its haptic twin (WorkoutSignals),
                    // so a screen that says "sound counts you in and out"
                    // promises the one channel the person has already turned
                    // off — and they are lying on the floor by then, out of
                    // reach of the only channel left. So the line says what
                    // is actually there: the countdown, on a screen that does
                    // not dim mid-set (UX review, 05.09.2026). The hardware
                    // ring switch is the case this cannot see — no public API
                    // reports it — and the second line covers that reader too.
                    Text(store.settings.soundsEnabled
                         ? String(localized: "Runs on its own from here — sound counts you in and out. Put the phone down.")
                         : String(localized: "Runs on its own from here — the countdown stays on the screen. Sound is off in Settings."))
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("hold-autorun-promise")

                    // The one thing that IS entered before a hold, and the
                    // only one that can be: how long it is going to run. It
                    // is a target, not a report — nothing here claims a set
                    // was performed — which is what makes it a different
                    // control from "Went differently" rather than the same
                    // one under a kinder name. Stop takes it back down;
                    // together the two are the whole channel, and they work
                    // the same on a per-side hold, where a clock that ran
                    // past the plan could never have reached the number
                    // (the set records the smaller side).
                    SetHoldTimeButton { startDeclaringHoldTime() }
                        .padding(.bottom, 18)
                }
            } else {
                WentDifferentlyButton { startAdjusting() }
                    .padding(.bottom, 18)
                    // no adjusting mid-hold, mid-count-in or mid-pause
                    .opacity(holdUnderWay ? 0 : 1)
                    .disabled(holdUnderWay)
                    .accessibilityHidden(holdUnderWay)
            }

            if current.unit == .hold {
                if holding {
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
            //
            // `accessibilityHidden` beside the opacity, not instead of it: a
            // control at opacity 0 is still in the accessibility tree, so
            // VoiceOver found two dimmed escapes on the one screen that has
            // none — the hands-free hold, where the phone is on the floor and
            // the person cannot see what they swiped onto. The placeholder
            // above says the same thing in the opposite direction: hidden, not
            // opacity (UX review, 05.09.2026).
            .opacity(holdUnderWay || holdSettled ? 0 : 1)
            .disabled(holdUnderWay || holdSettled)
            .accessibilityHidden(holdUnderWay || holdSettled)

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
        // Before the effort a DECLARED time is what the clock will run from,
        // so it is what the screen shows: the number the person is about to
        // agree to, not the plan they have already decided against.
        if holdExerciseIntro, let holdDeclared { return holdDeclared }
        if holdSwitchPausing { return holdPauseRemaining }
        if holding { return holdRemaining }
        if current.isProbe { return probeActuals[exercise.pattern] ?? current.planned }
        return SetFacts.inForce(actuals, exercise, set: setIndex)
    }

    /// What THIS set will actually run at — the number the big digit shows.
    private var setInForce: Int {
        SetFacts.inForce(actuals, exercise, set: setIndex)
    }

    /// The caption's: this set's own number, nothing when it is the plan.
    /// The plan of THIS SET — against the flat base an untouched top set of
    /// an uneven plan read as an entered fact (UI-truth audit, 27.08.2026).
    ///
    /// And only for sets that are BEHIND. Ahead of everything recorded
    /// `inForce` carries a shortfall down (`min(last, planned)`), so on set 2
    /// of a 3×8 opened with a 6 the word "actual" stood over a set nobody had
    /// performed, about a number nobody had entered for it. The number is real
    /// — it is the plan now in force — so it keeps its place in the caption
    /// through `uneven`, under a word that measures rather than reports
    /// (UX review, 05.09.2026).
    private var setActual: Int? {
        guard setIndex < (actuals[exercise.pattern]?.count ?? 0) else { return nil }
        return SetFacts.offPlan(actuals, exercise, set: setIndex)
    }

    // MARK: - Inline actual adjuster (the panel itself is AdjustPanel.swift)

    /// Opens the adjuster on the DECLARATION — how long this hold will run —
    /// rather than on a set's record. Seeded with what the clock would use
    /// right now, so the person is nudging a real number, not typing one.
    func startDeclaringHoldTime() {
        adjustValue = SetFacts.holdTarget(actuals, exercise, set: setIndex,
                                          declared: holdDeclared)
        holdDeclaring = true
        adjusting = true
    }

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
    ///
    /// Dressed like the slot it stands in, which it was not: with no font and
    /// no colour named, all three lines drew in `.body` (17 pt) and `.primary`
    /// — a size above and a shade past the 14 pt ink2 every other state of
    /// this slot uses, so the one set the app calls optional read as the
    /// loudest sentence on the screen. The passing outcome takes the accented
    /// variant of the same slot; the failing one stays neutral, for the reason
    /// written above (UX review, 05.09.2026).
    @ViewBuilder
    private var probeCaption: some View {
        if let entered = probeActuals[exercise.pattern] {
            if entered >= current.planned && !workingSetsFellShort {
                Text("Next time: \(current.name)")
                    .dredfitFont(14, weight: .semibold)
                    .foregroundStyle(Theme.accentText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("probe-passed")
            } else {
                // Also the answer for a probe done at target AFTER working
                // sets that fell short: the engine reads that session as
                // "hard" for the pattern, and a hard pattern's probe does not
                // count (§40.4) — a promise here would be broken by numbers
                // already entered (UI-truth audit, 27.08.2026).
                Text("Not this time — the plan stays as it is.")
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("probe-stays")
            }
        } else {
            // No number here: the big one above IS this number, and the
            // caption repeated it (owner, 27.08.2026). On a hold probe the
            // big number starts counting down once the timer runs, and the
            // target then shows nowhere — which is exactly what an ORDINARY
            // hold does too, so the probe simply stops being the exception.
            Text("One set to try it.")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
    }

    /// The knowable half of the §40.4 gate — see `SetFacts.foldFallsShort`.
    private var workingSetsFellShort: Bool {
        SetFacts.foldFallsShort(actuals, of: exercise)
    }

    /// The slot under the big number, which carries THREE different kinds of
    /// thing and used to look like one.
    ///
    /// While the number is a countdown the slot names the STATE, not the unit
    /// — the state used to live in the 14 pt line under the dots, where a
    /// person lying 1.5-2 m from the phone cannot read it, while this slot
    /// said "sec" for two opposite instructions five seconds apart ("get into
    /// position and hold still" against "turn over NOW"). Under the digit is
    /// where the eye already is (UX review, 05.09.2026).
    ///
    /// A running hold names the DIRECTION instead of the unit: there is no
    /// ring on this screen, so nothing else said whether the number counts up
    /// or down, and the button beside it counts the other way. "s left" keeps
    /// the second and adds the direction — and it ends the split where the
    /// same slot said "sec" during the count-in and "seconds" five seconds
    /// later, which German printed as "s" and then "Sekunden".
    private var loadCaption: String {
        if holdCountingIn { return String(localized: "Get ready") }
        if holdSwitchPausing { return String(localized: "Switch sides") }
        if holding { return String(localized: "s left") }
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

    /// Three tiers in one slot, and each earns its own.
    ///
    /// A STATE is accented at the slot's own size: it is the screen saying
    /// something beyond the ordinary, which is what accentText means here
    /// (`WorkStatusCaption.accented`).
    ///
    /// "per side" is accented and a tier LOUDER, because it is the one word
    /// that changes what the big number means and it carried no weight at all.
    /// 26 of the library's 59 positions are one-sided; on the 21 counted in
    /// reps nothing else on the screen says so — not the dots, not the header,
    /// not the status line — and a set done twelve times in TOTAL instead of
    /// twelve per side reaches the journal as run to plan, because the app
    /// never asks for a number it was not given. 23 pt is no more legible from
    /// the floor than 17 (both under the 5' a letter needs); what carries at
    /// that distance is the colour, and the size is what puts the line where
    /// it belongs in the hierarchy (UX review, 05.09.2026).
    private var loadCaptionEmphasis: (size: CGFloat, weight: Font.Weight, color: Color) {
        if holdCountingIn || holdSwitchPausing { return (17, .semibold, Theme.accentText) }
        if holding { return (17, .medium, Theme.ink2) }
        return current.perSide
            ? (23, .semibold, Theme.accentText)
            : (17, .medium, Theme.ink2)
    }

}
