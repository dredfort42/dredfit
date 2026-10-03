//
//  The plan state of Today: the six rows and everything that asks about them.
//
//  Three controls have stood beside this row and none of them is left.
//  `handleRow` — "fewer sets in every movement" and "fewer movements" — asked
//  the person to predict, before the workout, how much of it they had in them;
//  that answer moved to the work screen, where it is known. `exerciseHandles`
//  offered the variation one step below; it moved into the sheet this row
//  opens (R30), for the same reason and one more: after the v2 → v3 carry-over
//  every movement sat above the first variation, so the offer stood under all
//  six rows at once.
//

import SwiftUI
import DredfitCore

struct PlanView: View {
    @Environment(AppStore.self) private var store
    @Binding var activeWorkout: ActiveWorkout?
    @Binding var destination: TodayView.Destination?
    @Binding var freshStartConfirmShown: Bool
    @Binding var startOverConfirmShown: Bool
    @Binding var pendingSuspect: SuspectStepDown?

    // MARK: - Plan state

    var body: some View {
        let session = store.nextSession
        let debuts = store.debutPatterns
        let length = store.sessionLengthRange()
        let count = session.exercises.count
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.screenDateText)
                Text("Workout \(session.sessionNumber)")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
                    // The token, not the inherited default: a Text with no
                    // foregroundStyle draws in `.primary`, which is #FFFFFF in
                    // the dark scheme against ink's #F2F2F4 — so the loudest
                    // word on the screen was one of the few outside the
                    // palette (UX review 05.09.2026, finding 15).
                    .foregroundStyle(Theme.ink)
                // A RANGE, and it is the whole of what this screen says
                // about length: the full plan, and the shortest the session
                // can be made from inside it. The question the two handles
                // used to answer — "will this fit today" — is answered here
                // without asking anyone to decide anything first. One number
                // only when the plan is already on the floor and the two ends
                // have met.
                //
                // "Why this plan?" stood beside it and is gone. It read as an
                // answer about THIS plan — these six movements, these numbers
                // — and opened a static explainer that names none of them and
                // does not know what today's plan is. The explainer itself is
                // untouched and still reachable, from the one door that
                // describes it honestly: Settings → "How it works".
                PlanLength(floor: length.floor, full: length.full, count: count)
                    .accessibilityIdentifier("plan-length")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                // Ten of those minutes are the two blocks at the ends, and on
                // the shortest sessions that is a third of the number the
                // person is judging "will this fit" by.
                PlanEndsNote(warmupMin: session.warmupMin,
                             cooldownMin: session.cooldownMin)
            }
            .padding(.top, 18)

            // Six rows, all of them the plan. The dimmed ones came with the
            // short version — the app choosing three movements of six for the
            // person — and nothing on this screen sets a movement aside any
            // more.
            List(session.exercises) { ex in
                planRow(ex, debuts: debuts)
                    .listRowSeparatorTint(Theme.hairline)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            planNotes

            // The "not getting harder" block is gone with the freeze it
            // described. Nothing rests any more — a movement the person finds
            // too hard stays in the plan and gets an easier variation, or
            // fewer sets inside the workout: the channel that took movements
            // out took them out for weeks.

            // Ahead of the comeback card deliberately: that card asks for a
            // decision about the plan, and this one explains what the plan IS
            // after an upgrade. Answering before reading is the wrong order.
            if store.showsMigrationNotice {
                MigrationCard(onDismiss: { store.dismissMigrationNotice() })
                    .padding(.top, 10)
            }

            if store.shouldOfferComeback() {
                ComebackOffer(onFreshStart: { freshStartConfirmShown = true })
                    .padding(.top, 10)
            }

            // The journal keeps finding the same movement under an unnamed
            // "tough". One contextual question — never a questionnaire — and
            // where it lands has changed: it used to route into the pain path;
            // it now routes into the handle, which changes the thing the
            // person is complaining about instead of taking it away.
            // Asked only when there IS a variation below: `makeSuspectEasier`
            // goes through `Engine.easierVariation`, which returns the state
            // unchanged on the bottom rung — so on a movement already at the
            // floor the question offered a tap that dismissed the card and
            // changed nothing, silently. The technique sheet simply does not
            // draw its block in that case (UX review 05.09.2026).
            if store.shouldAskAboutSuspect(), let suspect = store.unnamedLessSuspect(),
               let step = store.easierStep(suspect) {
                suspectPrompt(suspect, step: step)
            }

            // The price the plan pays for the handle that left it (R30): the
            // variation one step below now lives behind the technique sheet,
            // and a row that opens one is not self-evidently a door. One grey
            // line, above the primary control and below the rows it is about
            // — and spent the first time anybody goes through that door, from
            // any screen. Not per row: six copies of this sentence would be
            // the very pattern the handle was moved off the plan to end.
            if store.showsTechniqueHint {
                // Set exactly like the hints above "Went differently" and
                // "Set the time" on the work screen: the three lines that
                // stand above a primary control are one voice, and a
                // left-set 13.5 pt here read as a different kind of text
                // (owner, 02.09.2026).
                //
                // Two sentences, because the second half of the long one is
                // a promise about the plan under it: on a first workout every
                // pattern stands on variation 1, `easierPosition` returns nil
                // there, and the step below is ABSENT from all six sheets —
                // so the one line the app spends on this door was spent
                // saying what that door does not have (UX review 05.09.2026).
                Text(session.exercises.contains { store.canMakeEasier($0.pattern) }
                     ? String(localized: "plan.techniqueHint",
                              defaultValue: "Tap a movement for how it's done — and for the version one step below it.")
                     : String(localized: "plan.techniqueHintNoStep",
                              defaultValue: "Tap a movement for how it's done."))
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("technique-hint")
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }

            // The card replaces Start — its own two actions already are
            // "continue" and "start over".
            if !store.canStartWorkout {
                // Nothing to resume either — the snapshot lives in the file
                // that could not be read.
                FrozenJournalCard()
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            } else if let pending = store.pendingWorkoutCard {
                ResumeCard(snap: pending.snapshot, awaitingAnswer: pending.awaitingAnswer,
                           activeWorkout: $activeWorkout,
                           startOverConfirmShown: $startOverConfirmShown)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            } else {
                // One Start, and it runs the plan above it. There is nothing
                // left on this screen to agree to first.
                //
                // Quiet while the comeback card is up, and only then: that
                // card is a question with two answers, neither of which is
                // "start now", and its filled "Start easier" sat ABOVE a
                // larger filled Start in the same column. The bigger, lower,
                // more familiar fill won a question about the plan by
                // geometry, and the wrong answer costs a return session at
                // pre-break load plus the step down its rating earns
                // (UX review 05.09.2026). It blocks nothing: one tap, same
                // place, same word.
                startButton(quiet: store.shouldOfferComeback())
                    .padding(.top, 10)
            }
            Spacer(minLength: 0).frame(height: 14)   // breathing room above the tab bar
        }
    }

    /// The two quiet sentences the plan says about ITSELF, before any card
    /// asks for a decision.
    @ViewBuilder
    private var planNotes: some View {
        // The one surface the silent decay has. A week off takes a step off
        // every pattern at once — sub-steps first, then the dose — and until
        // now nothing said so anywhere before the next workout: the line on
        // Progress appears only AFTER it, and loses its causal half if that
        // session was rated tough. An unexplained drop reads as a verdict,
        // which is the opposite of what a quiet catch-up is
        // (UX review 05.09.2026).
        //
        // A fact, not a warning: no accent fill, nothing to answer, and it
        // goes out by itself with the next completed workout, which moves the
        // date the stamp is keyed to.
        //
        // And said ONCE. The comeback card below takes the same boolean and
        // names the same drop in its own sentence (`ComebackCard.alreadyDecayed`),
        // so a break of two weeks that had already decayed on day 9 stacked
        // three sentences about one fact — two of them near-identical —
        // directly above the decision the card is asking for (review
        // 06.09.2026). The card wins because it is the one that needs the fact
        // to make its offer readable, and it is the only surface of the two on
        // a rest day, where `planNotes` is not drawn at all.
        if store.silentDecayAppliedForCurrentBreak, !store.shouldOfferComeback() {
            Text("A week without training — the plan starts a step lower. It catches up quickly.")
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }

        // An offer of rest, not a warning (#98) — and never a number to
        // beat: the count appears only here, in the suggestion to break
        // the run. "Train anyway" and the Start button stay untouched.
        if store.todayWouldExtendALongRun {
            // The same accent card the work screen gives the maximum note,
            // and for the same reason: worth reading, blocks nothing. Grey
            // 13.5 pt under the plan was the one place nobody looks.
            // `ink` on the accentSoft fill, and neither accent: accentText
            // on accentSoft comes to 4.20:1 in the dark scheme (I-21), under
            // what this 14 pt sentence needs, while accent itself is 2.91:1
            // on that fill. ink on accentSoft is gated at 4.5 dark and 7 in
            // Increased Contrast (BrandPaletteTests). The same move the probe
            // badge, the held-set card and the maximum note already made: the
            // accent is the fill, and the words are words (UX review
            // 05.09.2026, finding 16).
            Text("A workout today would be training day \(store.wouldBeConsecutiveDay) in a row — a rest day lets the load settle.")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 10)
                // 8 here plus the 10 Start carries: 18 to the button, the
                // same gap the work screen holds above and below its own
                // primary. The two screens were asked to match, and the
                // work screen is where the number is load-bearing.
                .padding(.bottom, 8)
        }
    }

    // MARK: - The plan row

    /// `.plain` because a List row with several default-styled buttons in it is
    /// one button as far as the row is concerned: measured, a single tap on the
    /// empty strip beside the handle that used to sit here pulled it — the
    /// announced duration went 35 min to 33 and the control vanished under the
    /// finger. The handle is gone (R30), so the row is the only control on
    /// itself and the trap is closed by construction; the style stays because
    /// it is also what keeps a List row from tinting the card. It changes how
    /// nothing looks.
    ///
    /// `contentShape` is the other half of that fix and is still load-bearing:
    /// a `.plain` button answers only where it DRAWS, and this row draws a name
    /// on the left and a load on the right with a wide gap between. Without the
    /// shape a tap into the gap reaches nothing — which now costs the whole
    /// handle, not just a sheet, because the sheet is where the handle lives.
    func planRow(_ ex: SessionExercise, debuts: Set<Pattern>) -> some View {
        // Hoisted out of the label so the four facts fit a line each. The
        // easier-variation pair is asked in the order the row answers it: the
        // handle names itself, and everything else that moved the plan after
        // the last record only says that it moved (ExerciseRow.variationNote).
        let notes = ExerciseRow.notes(
            ex,
            setCameBack: store.aSetJustCameBack(in: ex),
            easedByHand: store.easedByHandAhead.contains(ex.pattern),
            variationDropped: store.aVariationJustDropped(in: ex),
            raisedSteps: store.raisedForNextPlan(ex.pattern))
        return Button {
            destination = .technique(TechniqueTarget(ex))
        } label: {
            ExerciseRow(exercise: ex,
                        badge: debuts.contains(ex.pattern)
                            ? String(localized: "new variation") : nil,
                        notes: notes)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Per pattern, so a row is addressable without reading its rendered
        // load ("3 ×" is a format and a locale, not an identity) and without
        // `element(boundBy: 0)`, which also matches the settings overlay
        // sitting above the tab content.
        .accessibilityIdentifier("plan-row-\(ex.pattern.rawValue)")
    }

    /// The plan's primary, in the two weights it now has. `quiet` borrows the
    /// bordered idiom "Train anyway" uses — same size, same place, same word,
    /// one fill less — so that while the comeback card is up the only filled
    /// control on the screen is the card's own answer.
    @ViewBuilder
    private func startButton(quiet: Bool) -> some View {
        if quiet {
            Button {
                activeWorkout = ActiveWorkout(session: store.nextSession)
            } label: {
                QuietButtonLabel(title: Text("Start"))
            }
            .accessibilityIdentifier("start-workout")
        } else {
            PrimaryButton(title: String(localized: "Start")) {
                activeWorkout = ActiveWorkout(session: store.nextSession)
            }
            // The most-tapped control in the UI suite. Identified so a
            // reworded label costs nothing: the word "Start" moved twice in a
            // week (PR #207/#208) and the tests that reach for it are in every
            // file.
            .accessibilityIdentifier("start-workout")
        }
    }

    // MARK: - The suspect question

    private func suspectPrompt(_ suspect: Pattern, step: AppStore.EasierStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tough workouts keep landing on \(suspect.displayName).")
                .dredfitFont(13.5)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            // 24 pt apart, and each answer 44 pt tall: these two were the only
            // controls on Today with no target of their own — a bare 13.5 pt
            // word is about 16 pt of hit area — and the left one is the
            // irreversible of the pair (#193's floor).
            HStack(spacing: 24) {
                suspectAnswer(String(localized: "Make it easier")) {
                    pendingSuspect = SuspectStepDown(pattern: suspect, name: step.name)
                }
                // The third answer — "just hard" — armed a hold, and the hold
                // is cancelled. The case it served is exactly what the
                // sub-step fixes without asking anyone anything.
                suspectAnswer(String(localized: "It's fine")) {
                    store.dismissSuspectPrompt()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        // The same alert the technique sheet raises before the SAME engine
        // call (owner, 01.09.2026), reusing its two translated keys. Here the
        // call had no guard at all, and its control was a 13.5 pt word with a
        // second word beside it: this plan has no undo, and the way back up is
        // a probe several appearances away (UX review 05.09.2026).
        .alert(pendingSuspect.map(suspectConfirmTitle) ?? "",
               isPresented: Binding(get: { pendingSuspect != nil },
                                    set: { if !$0 { pendingSuspect = nil } }),
               presenting: pendingSuspect) { pending in
            Button(String(localized: "Keep going"), role: .cancel) { }
            Button(String(localized: "technique.stepDown.switch", defaultValue: "Switch")) {
                store.makeSuspectEasier(pending.pattern)
            }
        } message: { _ in
            Text(verbatim: String(localized: "technique.stepDown.confirmBody", defaultValue: """
                This movement drops to the variation below. \
                The way back up is a probe, which the plan offers once the dose \
                is at the ceiling again.
                """))
        }
    }

    /// accentText, not accent: accent is 3.58:1 on the light ground and this is
    /// small text, which the palette holds to 4.5:1 (owner, 05.09.2026). The
    /// fourteen other text controls in the app already use accentText.
    private func suspectAnswer(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .dredfitFont(13.5, weight: .medium)
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Names the movement, so the question cannot be answered without reading
    /// which one it is about — the technique sheet's own rule for the same
    /// call.
    private func suspectConfirmTitle(_ suspect: SuspectStepDown) -> String {
        String(localized: "technique.stepDown.confirmTitle",
               defaultValue: "Switch to \(suspect.name)?")
    }
}
