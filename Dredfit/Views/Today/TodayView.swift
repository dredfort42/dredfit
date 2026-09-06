//
//  Three states: plan + Start, rest day, or completed with a preview of the
//  next workout under its honest date.
//

import SwiftUI
import DredfitCore

/// The session is snapshotted at tap time, not read live inside the cover
/// closure: completeWorkout advances the engine before the cover dismisses,
/// and a live read would flip the rating screen to the NEXT session's data.
private struct ActiveWorkout: Identifiable {
    let session: Session
    var resume: WorkoutSnapshot?
    /// Straight to the rating: the card's answer to "keep this workout?".
    var settleImmediately = false
    var id: Int { session.sessionNumber }
}

/// The movement the suspect question is about and the name of what sits below
/// it — together, because the alert has to NAME the movement it is about, and
/// the name comes from the engine's answer rather than from the question.
private struct SuspectStepDown: Identifiable {
    let pattern: Pattern
    let name: String
    var id: String { pattern.rawValue }
}

struct TodayView: View {
    @Environment(AppStore.self) var store
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeWorkout: ActiveWorkout?
    @State var techniqueFor: TechniqueTarget?
    @State private var nextPreviewShown = false
    @State private var freshStartConfirmShown = false
    /// The three questions this screen asks before it acts. Each stands in
    /// FRONT of a change that cannot be taken back — the rule the four skips
    /// and the technique sheet already follow (SkipConfirmation.swift).
    @State private var startOverConfirmShown = false
    @State private var pendingSuspect: SuspectStepDown?
    @State private var historyRecord: WorkoutRecord?
    /// Not private, unlike the five above: the control it opens and the
    /// answers in it live in `TodayView+Rating.swift`, for the reason
    /// `TodayView+PlanRow` states — this type stands at the linter's body
    /// bound and an extension weighs nothing against it.
    @State var ratingChangeShown = false

    var body: some View {
        Group {
            if store.doneToday {
                doneView
            } else if store.restAppliesToday {
                // `restApplies`, not `isRestDay`: rest is rest FROM something,
                // and an install whose onboarding happened to end on a marked
                // weekday met "come back on Tuesday" as its very first screen
                // (UX review 05.09.2026, finding 7). `WidgetBridge`'s
                // `widgetStatus` must — and now does — branch on the same
                // predicate for TODAY, or the two disagree on day one: this
                // note stated the guarantee as a fact while the snapshot writer
                // still asked `isRestDay`, so the widget answered "Rest day"
                // to the person Today was telling to train (review 06.09.2026).
                // `isRestDay` keeps the marked weekdays for the settings rows,
                // the calendar grid and nextTrainingDate, which ask a different
                // question.
                restView
            } else {
                planView
            }
        }
        .padding(.horizontal, 24)
        .fullScreenCover(item: $activeWorkout) { active in
            WorkoutFlowView(session: active.session, resume: active.resume,
                            settleImmediately: active.settleImmediately)
        }
        // `planned: true` — these six movements are the workout about to be
        // done, so the sheet carries the step below each of them. It is the
        // handle that used to stand under this very row (R30).
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(target: ex, planned: true)
        }
        .sheet(isPresented: $nextPreviewShown) {
            NextWorkoutSheet()
        }
        // Today's own record, from the screen that is about today. It was
        // drawn, complete, and reachable only through the Calendar tab and an
        // unmarked black circle — while both prominent controls of both
        // screens answered "what is next" and neither answered "what did I
        // just do" (UX review 05.09.2026).
        .sheet(item: $historyRecord) { record in
            HistorySheet(record: record)
        }
        .alert(String(localized: "Start from scratch?"),
               isPresented: $freshStartConfirmShown) {
            // An ALERT, not a confirmationDialog: iOS 26 presents the latter
            // as an anchored popover, so the same question drew a centred card
            // in the workout and a tailed bubble pointing at a settings row.
            // An alert has no anchor — every one of these is the same window,
            // centred, whatever it was raised from.
            //
            // And the workaround the popover forced is gone with it. A popover
            // suppresses its cancel action, because tapping outside IS the
            // cancel, so the escape had to be a SECOND, role-less button. An
            // alert does not: measured on iPhone 17 Pro / iOS 26.5, the node is
            // `Alert` with no `Popover` beside it, and all four buttons stood in
            // the accessibility tree — the `.cancel` one included. So the escape
            // is one button again, carrying the role AND the name that says what
            // it does. "Cancel" answers "cancel what?"; this one does not.
            Button(String(localized: "Keep my progress"), role: .cancel) { }
            Button(String(localized: "Reset progress"), role: .destructive) {
                store.resetProgress()
            }
        } message: {
            Text("Every movement goes back to the beginning. Your history stays.")
        }
        // The plan reached a pair of eyes — the engine is told. Keyed on the
        // showing, so a scroll, a rotation or a Dynamic Type change is the
        // same showing and costs nothing, while a plan that changed under the
        // reader (a budget moved in Settings, an "I was sick" tap, a finished
        // workout) is the new showing it is.
        .task(id: planShowing) {
            guard let showing = planShowing else { return }
            store.recordPlanShown(showing.session)
        }
    }

    /// What makes a showing a showing: the plan on screen.
    ///
    /// The budget it was drawn under used to be part of the identity, because
    /// a budget could move WITHOUT moving the plan and still lift the repair's
    /// cap for one transition. Nothing on this screen writes `cut` any more,
    /// and what does — the skip inside the workout — lands with the rating,
    /// which regenerates the session anyway. `nil` on the two days the plan is
    /// not on screen at all.
    private var planShowing: PlanShowing? {
        guard !store.doneToday, !store.restAppliesToday else { return nil }
        return PlanShowing(session: store.nextSession)
    }

    private struct PlanShowing: Equatable {
        let session: Session
    }

    // MARK: - Plan state

    private var planView: some View {
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
                comebackCard
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
            if let pending = pendingWorkoutCard {
                resumeCard(pending.snapshot, awaitingAnswer: pending.awaitingAnswer)
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
    /// asks for a decision. Together in one property because `planView`'s stack
    /// stands at the ten children a ViewBuilder takes, and a note is the
    /// cheapest thing to group.
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

    // MARK: - Interrupted workout

    /// The snapshot this screen has to say something about, and WHICH thing.
    ///
    /// Inside the occasion the card offers to carry on. Past it — but before
    /// the workout counts as forgotten — the card ASKS instead of deciding
    /// (owner, 06.09.2026): three hours is a long lunch, not a lost session,
    /// and recording it unasked put a rating nobody gave into the journal.
    private var pendingWorkoutCard: (snapshot: WorkoutSnapshot, awaitingAnswer: Bool)? {
        if let snap = store.resumableWorkout() { return (snap, false) }
        if let snap = store.unfinishedWorkoutAwaitingAnswer() { return (snap, true) }
        return nil
    }

    private func resumeCard(_ snap: WorkoutSnapshot, awaitingAnswer: Bool = false) -> some View {
        let total = store.nextSession.exercises.count
        let position = min(snap.exIndex + 1, total)
        // A workout that only wants its rating has nothing to restart: the
        // work is done and unrecorded, and "Start over" — one tap, no
        // question, beside "Continue" — read as "replay" while it meant
        // "throw the whole session away" (UX review 05.09.2026).
        let onlyRatingLeft = snap.atFeedback == true
        return VStack(alignment: .leading, spacing: 0) {
            Text(awaitingAnswer
                 ? String(localized: "Keep this workout?")
                 : String(localized: "Continue the workout?"))
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            Group {
                if onlyRatingLeft {
                    // Say that, not a misleading exercise position.
                    Text("The workout is done — only the rating is left.")
                } else {
                    Text("You stopped at exercise \(position) of \(total) — everything done so far is still in place.")
                }
            }
            .dredfitFont(14.5)
            .foregroundStyle(Theme.ink2)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            // How long ago, because the same card answers a four-minute
            // interruption and a two-hour one identically, and the person
            // coming back after two hours is cold. The system spells the
            // interval, so no plural of ours has to (UX review 05.09.2026).
            //
            // Past ten minutes only: below that the interruption is plainly
            // the moment the person just left, and the relative formatter
            // would answer "now", which is a line that says nothing.
            if -snap.savedAt.timeIntervalSinceNow > 10 * 60 {
                Text("The last set was \(snap.savedAt.formatted(.relative(presentation: .named))).")
                    .dredfitFont(13)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            if awaitingAnswer && !onlyRatingLeft {
                // What the second button does, in the words the flow's own
                // "Finish now" already uses — one sentence, one vocabulary,
                // and already translated into all six languages.
                Text("“Finish now” keeps what you've done and goes to the rating — the remaining exercises are marked as skipped.")
                    .dredfitFont(13)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            HStack(spacing: 10) {
                Button {
                    activeWorkout = ActiveWorkout(session: store.nextSession, resume: snap)
                } label: {
                    Text(onlyRatingLeft
                         ? String(localized: "Rate the workout")
                         : String(localized: "resume.continue", defaultValue: "Continue"))
                        .pairedPrimaryLabel()
                }
                .accessibilityIdentifier("resume-continue")

                if awaitingAnswer && !onlyRatingLeft {
                    // The alternative to carrying on is KEEPING it, not
                    // throwing it away: the work is hours old, and "start
                    // over" is an answer nobody wants at that distance.
                    //
                    // It opens the RATING rather than recording a verdict of
                    // its own (owner, 06.09.2026): the athlete was there, and
                    // they say how it went. Same words as the control inside
                    // the flow that does the same thing, so the two cannot
                    // read as different offers.
                    Button {
                        activeWorkout = ActiveWorkout(session: store.nextSession,
                                                      resume: snap,
                                                      settleImmediately: true)
                    } label: {
                        Text("Finish now")
                            .pairedSecondaryLabel()
                    }
                    .accessibilityIdentifier("resume-keep")
                } else if !onlyRatingLeft {
                    Button {
                        startOverConfirmShown = true
                    } label: {
                        Text("Start over")
                            .pairedSecondaryLabel()
                    }
                    .accessibilityIdentifier("resume-restart")
                }
            }
            .padding(.top, 16)
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
        // The same guard, for the most expensive tap on this screen: "Start
        // over" throws away the only copy of a half-finished workout — the
        // numbers entered, the probe, the sets skipped — and it stood beside
        // "Continue" with nothing in front of it, while skipping ONE set
        // raises a question (SkipConfirmation.swift:4-9). Same two words as
        // the reset alert, because what is being kept is the same thing: the
        // work already done (UX review 05.09.2026).
        //
        // On the card rather than on the screen: an alert belongs to the
        // control that raises it, and this one is the only one of the three
        // states that has that control.
        .alert(String(localized: "Start over?"), isPresented: $startOverConfirmShown) {
            Button(String(localized: "Keep my progress"), role: .cancel) { }
            Button(String(localized: "Start over"), role: .destructive) {
                store.clearWorkoutSnapshot()
                activeWorkout = ActiveWorkout(session: store.nextSession)
            }
        } message: {
            Text("Everything done in this workout is dropped — the logged sets and the numbers. It starts from the warm-up.")
        }
    }

    // MARK: - Pieces shared by two of the three states

    /// The door to the next plan. It stood on the completed day only; the rest
    /// day carried the same sentence as plain text, which made rest the one
    /// screen in the app with no way to the plan (UX review 05.09.2026).
    private var nextWorkoutCard: some View {
        Button {
            nextPreviewShown = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker(text: String(localized: "Next"))
                    Text("Workout \(store.nextSession.sessionNumber) · \(store.nextTrainingDateLabel)")
                        .dredfitFont(16.5, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .dredfitFont(14, weight: .semibold)
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    /// One card, two screens: a break that ends on a rest day is still a break,
    /// and the offer has to be where the person is.
    private var comebackCard: some View {
        ComebackCard(offersFreshStart: store.offersFreshStart(),
                     preview: store.comebackPreview(),
                     alreadyDecayed: store.silentDecayAppliedForCurrentBreak,
                     onAccept: { store.acceptComeback() },
                     onDecline: { store.declineComeback() },
                     onFreshStart: { freshStartConfirmShown = true })
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
                Text("Start")
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.hairline, lineWidth: 1.5))
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

    // MARK: - Rest day

    /// Rest is a plan, not a lockout: training anyway stays available.
    private var restView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.screenDateText)
                Text("Rest day")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
                    // The palette, not `.primary` — see planView's heading.
                    .foregroundStyle(Theme.ink)
                Text("Next workout \(store.nextTrainingDateLabel)")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 18)

            // ink2, not ink3: this sentence is the rest day's whole argument.
            Text("Recovery is part of the plan — you get stronger between workouts, not during them.")
                .dredfitFont(15.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Spacer()

            // The rest day was the one screen with no way to the plan at all:
            // the same sentence on the completed day is a door, here it was
            // dead text over an empty Spacer, and "Train anyway" had to be
            // answered without seeing what it starts. Same card, same sheet —
            // it invites nothing (UX review 05.09.2026).
            nextWorkoutCard
                .padding(.bottom, 12)

            // The comeback offer lived in `planView` alone, so a return that
            // landed on a rest day — three days in seven as shipped — met the
            // pre-break plan with no way to start lower, and "Train anyway"
            // spends the question for good. The card is self-contained; it
            // moves as one (UX review 05.09.2026).
            if store.shouldOfferComeback() {
                comebackCard
                    .padding(.bottom, 12)
            }

            // A "train anyway" session interrupted mid-way comes back here
            // too — the rest day must not eat it.
            if let pending = pendingWorkoutCard {
                resumeCard(pending.snapshot, awaitingAnswer: pending.awaitingAnswer)
                    .padding(.bottom, 14)
            } else {
                Button {
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                } label: {
                    Text("Train anyway")
                        .dredfitFont(17, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Theme.hairline, lineWidth: 1.5))
                }
                .accessibilityIdentifier("train-anyway")
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Completed state

    private var doneView: some View {
        VStack(spacing: 0) {
            HStack {
                Kicker(text: store.today.screenDateText)
                Spacer()
            }
            .padding(.top, 18)

            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.cardBG)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .dredfitFont(44, weight: .bold, cap: 66)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }

            Text("Workout \(store.lastRecord?.sessionNumber ?? 0) completed")
                .dredfitFont(24, weight: .heavy)
                .tracking(-0.4)
                // The palette, not `.primary` — see planView's heading.
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)

            // Centred and unclipped: naming the movements the rating landed
            // on made the "tough" line the longest of the three, and this
            // Text carried neither a wrap rule nor an alignment of its own.
            Text(resultCaption)
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            // The door back to what was actually done today. A control of its
            // own rather than the heading made tappable: three UI walks read
            // "Workout N completed" as a static text, and a button around it
            // would hand XCUITest one merged element instead.
            if let record = store.lastRecord {
                Button {
                    historyRecord = record
                } label: {
                    Text("What you did today")
                        .dredfitFont(14.5, weight: .medium)
                        // accentText, not accent: 3.58:1 does not carry small
                        // text (owner, 05.09.2026).
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-record")
                .padding(.top, 18)
            }

            // Under the common door rather than beside it: correcting a
            // rating is the rarest thing anyone does on this screen — and
            // since owner decision 1 (05.09.2026) it is also the only way
            // back from a rating nobody gave, because a workout left unrated
            // is now settled as "on plan" on the athlete's behalf. Its words
            // and its alert are in `TodayView+Rating.swift`.
            changeRatingButton

            Spacer()

            nextWorkoutCard
                .padding(.bottom, 24)
        }
    }
}
