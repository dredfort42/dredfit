//
//  The work screen — the one a set is actually performed on — and the pieces
//  only it reads. What a tap on it does is `WorkoutSession`'s.
//

import SwiftUI
import DredfitCore

extension WorkoutFlowView {

    // MARK: - Work

    var workView: some View {
        VStack(spacing: 0) {
            Spacer()
            if flow.current.isProbe {
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
                    // text on this screen. The accent is the fill, and the
                    // word is a word.
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("probe-badge")
            }
            Text(flow.current.name)
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                // The token, not the inherited default: text with no
                // foregroundStyle draws in `.primary`, which is #FFFFFF in the
                // dark scheme against ink's #F2F2F4 — and the two loudest
                // elements of the flow would be the two outside the palette.
                .foregroundStyle(Theme.ink)
                .accessibilityLabel(Text(verbatim: flow.current.name))

            // On the probe set this opens the technique of the NEW movement:
            // nobody should be asked to try something they cannot read up on
            // first.
            //
            // Never while the clock is on the person, though: the sheet covers
            // the screen and the hold keeps counting underneath it, so reading
            // about the position would cost the set it describes. The guided
            // blocks FREEZE their countdown for this same tap
            // (`openPositionTechnique`) — the work screen cannot, so it takes
            // the offer away instead. opacity + disabled, like the escapes at
            // the bottom: the height stays reserved and nothing jumps.
            TechniqueButton { techniqueTarget = flow.current.target }
                .padding(.top, 10)
                .opacity(flow.holdUnderWay ? 0 : 1)
                .disabled(flow.holdUnderWay)
                .accessibilityHidden(flow.holdUnderWay)

            VStack(spacing: 4) {
                Text("\(flow.workNumber)")
                    .dredfitFont(112, weight: .heavy, cap: 150)
                    .tracking(-4)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    // The token (see the name above), except for the pause of
                    // a side switch, where the number turns accent. The phone
                    // is on the floor 1.5-2 m away by then — the screen said
                    // to put it there — and at that distance a 14 pt word is
                    // about 2.6 arc minutes, under the 5' it takes to
                    // recognise a letter. Colour on a 13 mm digit survives the
                    // distance where the word does not, and the tone, the only
                    // other channel, can be silenced by the ring switch.
                    .foregroundStyle(flow.holdSwitchPausing ? Theme.accentText : Theme.ink)
                Text(loadCaption)
                    .dredfitFont(loadCaptionEmphasis.size, weight: loadCaptionEmphasis.weight)
                    .foregroundStyle(loadCaptionEmphasis.color)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            // One element, like the rest ring: two would make VoiceOver read
            // "8" and then "reps per side" as if they were separate facts, and
            // the number alone is meaningless. Both halves are recomputed on
            // every body pass, so the label follows a hold's countdown down.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(flow.workNumber) ") + Text(verbatim: loadCaption))
            // The label is rebuilt every second while a hold runs, and without
            // this VoiceOver has no reason to re-read the element it is sitting
            // on — the one number that moves would be the one number it never
            // announces.
            .accessibilityAddTraits(.updatesFrequently)

            HStack(spacing: 10) {
                ForEach(0..<flow.totalSets, id: \.self) { i in
                    // The probe's dot is hollow: it is the same session and
                    // the same count of sets, but not the same movement.
                    //
                    // The sets still AHEAD take ink2, as the header's capsules
                    // do: hairline is 1.17:1 on `bg` in the light scheme, so a
                    // track drawn in it would not be on the screen at all —
                    // and ink2 is the only token clearing the 3:1 graphics
                    // floor in both schemes (4.96 / 6.97) while staying a long
                    // way lighter than a done dot's ink (18.7), so the three
                    // states stay three.
                    Circle()
                        .strokeBorder(Theme.accent,
                                      lineWidth: flow.exercise.probe != nil && i == flow.exercise.sets ? 2 : 0)
                        .background(Circle().fill(
                            flow.exercise.probe != nil && i == flow.exercise.sets
                                ? Color.clear
                                : (i < flow.setIndex ? Theme.ink
                                   : (i == flow.setIndex ? Theme.accent : Theme.ink2))))
                        // Off a frozen 10 pt, so the row a person with larger
                        // type reads grows with the rest of the screen.
                        .frame(width: setDotSize, height: setDotSize)
                }
            }
            .padding(.top, 30)

            // The count-in does not outrank the probe's own caption here: the
            // caption under the big number says "Get ready" (`loadCaption`) —
            // in the one place a person on the floor can read it — so the
            // probe keeps its own line throughout, and this slot never
            // announces "set 4 of 4" about a movement the flow calls a probe
            // everywhere else.
            if flow.holdExerciseIntro && flow.exercise.sets > 1 {
                // "set 1 of 3" is not the question on this screen: ONE tap
                // buys the whole exercise, so what the person is deciding
                // about is the whole exercise — how many sets it is and how
                // long it will wait between them. Held back on a single-set
                // plan, where there is no rest between anything and "1 sets"
                // would be false twice over.
                Text("\(flow.exercise.sets) sets · \(flow.exercise.restSetSec) s rest between")
                    .dredfitFont(14)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 10)
                    .accessibilityIdentifier("hold-sets-and-rest")
            } else if flow.current.isProbe {
                probeCaption
                    .padding(.top, 10)
            } else {
                // `totalSets`, not `exercise.sets`: the probe is a set of this
                // exercise on every other surface — the dots above draw it,
                // the rest screen counts it ("set 2 of 4") and so does the
                // lock screen — and leaving it out here would announce the
                // same exercise with two denominators.
                WorkStatusCaption(secondSide: flow.holdSecondSide,
                                  actual: setActual,
                                  setIndex: flow.setIndex, sets: flow.totalSets,
                                  // The SET's number, not the big digit's: that
                                  // one counts down while a hold runs, and on a
                                  // second side this line names the side and
                                  // prints no number at all.
                                  planned: flow.targetInForce,
                                  // Whether the number is worth printing is
                                  // asked of the plan and the record, never of
                                  // a declared time: the person set that one
                                  // themselves, and on an even plan it would
                                  // stand under every set saying nothing new.
                                  uneven: flow.exercise.loads != nil
                                      || SetFacts.offPlan(flow.actuals, flow.exercise,
                                                          set: flow.setIndex) != nil)
                    .padding(.top, 10)
            }

            Spacer()

            // The messages stand down while a number is being entered: one
            // thing to read at a time.
            //
            // The hint FIRST, the note second. The hint keeps its height when
            // hidden, and the order is what keeps that height from sitting
            // between the note and the button below: the note has to stand the
            // same 18 pt above the pair that the escapes stand below it, and
            // that the rest offer stands above Start on Today.
            if flow.editing == nil {
                // Opacity, not `if`: the reserved height keeps the layout still
                // when the hint's job is done mid-exercise.
                // Reps only. A hold's screen carries no "Went differently"
                // before the effort — no set's number is entered there before
                // it — so on a hold this hint would name a control that is not
                // on the screen: an instruction nobody can perform.
                //
                // The FIRST exercise of a workout, not every one of them:
                // otherwise this paragraph would come back on all six
                // movements and before all three sets of each — up to
                // eighteen readings of the longest sentence in the flow.
                //
                // …and until the CONTROL HAS BEEN USED, not until the first
                // workout is over. The two are different people: the door
                // this describes is the one way a movement in reps reports a
                // number of its own — the number the next plan starts from —
                // and the person who never opened it on session one is
                // exactly the person who still needs telling. The flag is
                // one-way and spent by the first reported number, so it can
                // neither nag someone who has already answered it nor
                // disappear from someone who has not.
                //
                // And it names BOTH directions: a number BELOW the plan is
                // what the engine acts on hardest (Feedback.swift) and what a
                // first session most often produces.
                if store.showsDifferentNumberHint && flow.exIndex == 0 && flow.current.unit == .reps {
                    let spent = flow.actuals[flow.exercise.pattern] != nil
                    Text("More or fewer than planned? Tap “Went differently” — the next plan starts from your number.")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .opacity(flow.holdUnderWay || spent ? 0 : 1)
                        // opacity alone leaves a whole paragraph readable to
                        // VoiceOver on a screen that no longer shows it, which
                        // is the ghost-control defect the placeholder button
                        // below guards against too.
                        .accessibilityHidden(flow.holdUnderWay || spent)
                }

                // Once per exercise per session, and it never blocks the entry
                // — the number stands either way. A card, not grey fine print:
                // grey 13 pt directly above the black primary button is the
                // one place on the screen nobody reads.
                //
                // `ink` on the accentSoft fill, not accentText: that pair is
                // 4.20:1 in the dark scheme (I-21), under the 4.5:1 this
                // 14 pt sentence needs, while ink on accentSoft is gated at
                // 4.5 dark and 7 in Increased Contrast (BrandPaletteTests).
                // The accent stays as the fill — the note is found by the
                // colour of the card and read in ink.
                if let warning = flow.maximumWarning {
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
            if flow.editing != nil {
                AdjustPanel(value: $flow.adjustValue, unit: flow.current.unit,
                            onConfirm: flow.commitSetEdit)
                .padding(.bottom, 18)
            } else if flow.current.unit == .hold && !flow.holdSettled {
                // No "Went differently" on a hold, and the reason is the
                // TENSE rather than the slot. Before the effort it would ask
                // how a set went that nobody has performed; what belongs here
                // is a target, and that is "Set the time"
                // (`SetHoldTimeButton`). Afterwards the exercise summary asks
                // it, with every set of the movement on one screen. No
                // reserved height either: the block under the Spacer is
                // bottom-aligned as a group, so what leaves it moves nothing
                // below.
                //
                // A SETTLED hold keeps it, and the exception is the whole
                // point rather than a leftover: that is the PROBE's screen,
                // which the summary deliberately says nothing about.
                if flow.holdExerciseIntro {
                    // What the one tap actually buys, said before it is
                    // taken. Deliberately without a numeral — the count is on
                    // the line above, and a second one here would need an ICU
                    // plural in seven languages to say nothing new.
                    //
                    // "Put the phone down", never "lock the screen": a
                    // suspended app runs no timers and plays no tones, and a
                    // promise this screen cannot keep is worse than no
                    // promise.
                    //
                    // The same rule read against the SOUND SWITCH: with
                    // "Sounds and haptics" off, one guard silences the tone
                    // AND its haptic twin (WorkoutSignals), so a screen that
                    // says "sound counts you in and out" would promise the one
                    // channel the person has already turned off — and they are
                    // lying on the floor by then, out of reach of the only
                    // channel left. So the line says what is actually there:
                    // the countdown, on a screen that does not dim mid-set.
                    // The hardware ring switch is the case this cannot see —
                    // no public API reports it.
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
                    SetHoldTimeButton { flow.startDeclaringHoldTime() }
                        .padding(.bottom, 18)
                }
            } else {
                WentDifferentlyButton { flow.startAdjusting() }
                    .padding(.bottom, 18)
                    // no adjusting mid-hold, mid-count-in or mid-pause
                    .opacity(flow.holdUnderWay ? 0 : 1)
                    .disabled(flow.holdUnderWay)
                    .accessibilityHidden(flow.holdUnderWay)
            }

            if flow.current.unit == .hold {
                if flow.holding {
                    // The control names the figure it will write: two to
                    // four seconds are spent reaching for the phone, and a
                    // person who cannot see what the tap records has no way to
                    // judge whether it is worth taking.
                    HoldStopButton(records: flow.holdStopRecords) { flow.stopHoldEarly() }
                } else if flow.holdSwitchPausing || flow.holdCountingIn {
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
                } else if flow.holdSettled {
                    // The probe's hold is behind; this tap only logs it. Same
                    // title and same identifier as the reps button, because it
                    // is the same act — the set ends when the person says the
                    // number is right, not when a clock says the effort is
                    // over.
                    PrimaryButton(title: String(localized: "Done")) { flow.completeSet() }
                        .accessibilityIdentifier("exercise-done")
                } else if flow.holdAutoRun || flow.current.isProbe {
                    // ONE set, not the exercise. Two ways in: a Stop inside
                    // the mis-tap grace hands an armed set back, and the probe
                    // is a different movement — possibly in a different unit
                    // — which the auto-run deliberately does not start for
                    // you.
                    PrimaryButton(title: String(localized: "Start hold")) { flow.startHold() }
                        .accessibilityIdentifier("hold-start")
                } else {
                    // One tap for the whole exercise: a tap per set would be
                    // taken between sets by someone lying on the floor.
                    PrimaryButton(title: String(localized: "Start exercise"),
                                  action: flow.startHoldExercise)
                    .accessibilityIdentifier("hold-start-exercise")
                }
            } else {
                PrimaryButton(title: String(localized: "Done")) { flow.completeSet() }
                    .accessibilityIdentifier("exercise-done")
            }

            ExerciseActionsRow(onSkipSet: setSkipAction,
                               skipsProbe: flow.onProbeSet,
                               escape: exerciseEscape)
            // 18, the measure of this whole stack: the same gap stands between
            // the note and "Went differently", between it and the button, and
            // here between the button and the escapes. Here it is a margin as
            // well — the button between them LOGS THE SET, and a thumb that
            // lands a few points off does not miss, it finishes the set at
            // plan.
            .padding(.top, 18)
            .padding(.bottom, 10)
            // No adjusting/skipping mid-hold, mid-count-in or mid-pause —
            // and none once a settled hold is behind either: the set was
            // performed and its number is on the screen, so a skip there would
            // contradict the very fact the person is being shown.
            //
            // `accessibilityHidden` beside the opacity, not instead of it: a
            // control at opacity 0 is still in the accessibility tree, so
            // VoiceOver would find two dimmed escapes on the one screen that
            // has none — the hands-free hold, where the phone is on the floor
            // and the person cannot see what they swiped onto. The placeholder
            // above says the same thing in the opposite direction: hidden, not
            // opacity.
            .opacity(flow.holdUnderWay || flow.holdSettled ? 0 : 1)
            .disabled(flow.holdUnderWay || flow.holdSettled)
            .accessibilityHidden(flow.holdUnderWay || flow.holdSettled)

        }
    }

    /// The caption's: this set's own number, nothing when it is the plan.
    /// The plan of THIS SET — against the flat base an untouched top set of
    /// an uneven plan would read as an entered fact.
    ///
    /// And only for sets with a number on record. Ahead of everything
    /// recorded `inForce` carries a shortfall down (`min(last, planned)`), so
    /// on set 2 of a 3×8 opened with a 6 the word "actual" would stand over a
    /// set nobody has performed, about a number nobody entered for it. The
    /// number is real — it is the plan now in force — so it keeps its place in
    /// the caption through `uneven`, under a word that measures rather than
    /// reports.
    private var setActual: Int? {
        guard flow.setIndex < (flow.actuals[flow.exercise.pattern]?.count ?? 0) else { return nil }
        return SetFacts.offPlan(flow.actuals, flow.exercise, set: flow.setIndex)
    }

    // MARK: - Inline actual adjuster (the panel itself is AdjustPanel.swift)

    /// What the probe set says under its number. Before a number is entered it
    /// says what the set is for; afterwards it states the outcome
    /// (`WorkoutSession.probeOutcome`) — and every outcome but a pass is
    /// NEUTRAL, because honesty is never punished: staying on a movement you
    /// can already do is not a failure, and the copy must not read like one.
    ///
    /// The failing line states the consequence — the thing the reader will
    /// actually see tomorrow — rather than naming "the current variation": at
    /// that moment the title is the NEXT movement with a "Probe" badge over
    /// it, so "the current one" is a name the reader would have to
    /// reconstruct, where the passing line names its movement outright. It
    /// deliberately does NOT promise the probe comes back next time: a
    /// session later rated "hard" on this pattern suppresses it.
    ///
    /// Dressed like the slot it stands in: with no font and no colour named,
    /// the lines would draw in `.body` (17 pt) and `.primary` — a size above
    /// and a shade past the 14 pt ink2 every other state of this slot uses —
    /// and the one set the app calls optional would read as the loudest
    /// sentence on the screen. The passing outcome takes the accented variant
    /// of the same slot; the others stay neutral, for the reason written
    /// above.
    @ViewBuilder
    private var probeCaption: some View {
        switch flow.probeOutcome {
        case .passed(let name):
            Text("Next time: \(name)")
                .dredfitFont(14, weight: .semibold)
                .foregroundStyle(Theme.accentText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("probe-passed")
        case .planMoves(let name):
            // The same words as a pass and none of its accent: the plan moves
            // because the working sets fell short, and that is the neutral
            // outcome, not a promotion.
            Text("Next time: \(name)")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("probe-plan-moves")
        case .stays:
            Text("Not this time — the plan stays as it is.")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("probe-stays")
        case nil:
            // No number here: the big one above IS this number, and the
            // caption would repeat it. On a hold probe the big number starts
            // counting down once the timer runs, and the target then shows
            // nowhere — which is exactly what an ORDINARY hold does too.
            Text("One set to try it.")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
    }

    /// The slot under the big number, which carries THREE different kinds of
    /// thing.
    ///
    /// While the number is a countdown the slot names the STATE, not the
    /// unit: the 14 pt line under the dots is out of reach for a person lying
    /// 1.5-2 m from the phone, and a unit here would say the same "sec" for
    /// two opposite instructions ("get into position and hold still" against
    /// "turn over NOW"). Under the digit is where the eye already is.
    ///
    /// A running hold names the DIRECTION instead of the unit: there is no
    /// ring on this screen, so nothing else says whether the number counts up
    /// or down, and the button beside it counts the other way. "s left" keeps
    /// the second and adds the direction.
    private var loadCaption: String {
        if flow.holdCountingIn { return String(localized: "Get ready") }
        if flow.holdSwitchPausing { return String(localized: "Switch sides") }
        if flow.holding { return String(localized: "s left") }
        // The unit only: the 112 pt number above already says how many, and
        // printing it twice is the kind of noise that makes a screen feel
        // busy. The count is still PASSED for reps, because the word has to
        // agree with a number it does not print: Russian declines the unit
        // by count (повтор / повтора / повторов), and one form under every
        // number would put "4 повторов" on screen. In the catalog the value
        // is a substitution (`%#@reps@`) whose plural forms carry no number
        // token, so the argument picks the form and never reaches the screen
        // a second time — a whole-string plural variation cannot do this:
        // `xcstringstool` refuses a form that does not print the number.
        // Holds stay one form per language: the corridor starts at 5 s, so no
        // value a hold caption can show takes a singular in any shipping
        // language but Russian, and Russian abbreviates the unit ("сек"),
        // which does not decline at all.
        switch (flow.current.unit, flow.current.perSide) {
        case (.reps, false): return String(localized: "\(flow.workNumber) reps")
        case (.reps, true):  return String(localized: "\(flow.workNumber) reps per side")
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
    /// that changes what the big number means, and in the ordinary tier it
    /// would carry no weight at all. 26 of the library's 59 positions are
    /// one-sided; on the 21 counted in reps nothing else on the screen says so
    /// — not the dots, not the header, not the status line — and a set done
    /// twelve times in TOTAL instead of twelve per side reaches the journal as
    /// run to plan, because the app never asks for a number it was not given.
    /// 23 pt is no more legible from the floor than 17 (both under the 5' a
    /// letter needs); what carries at that distance is the colour, and the
    /// size is what puts the line where it belongs in the hierarchy.
    private var loadCaptionEmphasis: (size: CGFloat, weight: Font.Weight, color: Color) {
        if flow.holdCountingIn || flow.holdSwitchPausing { return (17, .semibold, Theme.accentText) }
        if flow.holding { return (17, .medium, Theme.ink2) }
        return flow.current.perSide
            ? (23, .semibold, Theme.accentText)
            : (17, .medium, Theme.ink2)
    }

}
