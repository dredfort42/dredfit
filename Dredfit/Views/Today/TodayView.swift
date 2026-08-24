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
    /// nil is the full session. Resolved at tap time like the session itself.
    var shortPlan: Set<Pattern>?
    var id: Int { session.sessionNumber }
}

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeWorkout: ActiveWorkout?
    @State private var techniqueFor: SessionExercise?
    @State private var nextPreviewShown = false
    @State private var freshStartConfirmShown = false
    @State private var howItWorksShown = false

    var body: some View {
        Group {
            if store.doneToday {
                doneView
            } else if store.isRestDay(store.today) {
                // Must agree with the widget and nextTrainingDate.
                restView
            } else {
                planView
            }
        }
        .padding(.horizontal, 24)
        .fullScreenCover(item: $activeWorkout) { active in
            WorkoutFlowView(session: active.session, resume: active.resume,
                            shortPlan: active.shortPlan)
        }
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(exercise: ex)
        }
        .sheet(isPresented: $nextPreviewShown) {
            NextWorkoutSheet()
        }
        .sheet(isPresented: $howItWorksShown) {
            HowItWorksView()
        }
        .confirmationDialog(String(localized: "Start from scratch?"),
                            isPresented: $freshStartConfirmShown,
                            titleVisibility: .visible) {
            Button(String(localized: "Reset levels"), role: .destructive) {
                store.resetProgress()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Levels go back to the beginning. Your history stays.")
        }
        // The plan reached a pair of eyes — the engine is
        // told. Keyed on the showing, so a scroll, a rotation or a Dynamic
        // Type change is the same showing and costs nothing, while a plan that
        // changed under the reader (a budget moved in Settings, an "I was
        // sick" tap, a finished workout) is the new showing it is.
        .task(id: planShowing) {
            guard let showing = planShowing else { return }
            store.recordPlanShown(showing.session)
        }
    }

    /// What makes a showing a showing: the plan on screen.
    ///
    /// The budget it was drawn under used to be part of
    /// the identity, because a budget could move WITHOUT moving the plan and
    /// still lift the repair's cap for one transition. The handle writes
    /// `cut`, a coordinate of the position, so a handle that moves moves the
    /// session — and the session is already here.
    /// `nil` on the two days the plan is not on screen at all.
    /// The session handle, and the whole point of it — the
    /// person sees the recalculated duration BEFORE agreeing to it. The number
    /// is the engine's own `estimatedTotalMin` on both sides of the arrow, not
    /// an app-side estimate: "how long will this take" is a question the engine
    /// answers now, and this is where it says so.
    ///
    /// The control disappears at the floor rather than going grey: unlike the
    /// per-movement handle there is no single movement it could explain itself
    /// about, and "every exercise is already at two sets" is a sentence nobody
    /// needs on the screen they are about to start from.
    /// The two per-movement handles, on the movement
    /// they act on. They live here rather than inside the workout because
    /// `nextSession` is generated from the state on every access, so a tap
    /// redraws this row, the announced duration and the plan together. Inside
    /// the workout they would have to mutate a session the engine is going to
    /// read the plan from when the rating lands.
    ///
    /// "Easier version" carries its RESULT, not its promise: the name and dose
    /// the movement would have after the tap. The engine lands it through the
    /// ordinary gate, so on `pull_bar` the drop from negatives to a hang is a
    /// change of unit and the preview is the only way to see that coming.
    @ViewBuilder
    private func exerciseHandles(_ ex: SessionExercise) -> some View {
        let pattern = ex.pattern
        HStack(spacing: 16) {
            if let preview = store.easierPreview(pattern) {
                Button {
                    store.makeEasier(pattern)
                } label: {
                    Text("Easier · \(preview)")
                        .dredfitFont(12.5)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityIdentifier("easier-\(pattern.rawValue)")
            }
            Spacer(minLength: 0)
            if store.canTakeSetOff(pattern) {
                Button {
                    store.takeSetOff(pattern)
                } label: {
                    Text("Fewer sets")
                        .dredfitFont(12.5)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityIdentifier("fewer-sets-\(pattern.rawValue)")
            }
            if store.canGiveSetBack(pattern) {
                Button {
                    store.giveSetBack(pattern)
                } label: {
                    Text("More sets")
                        .dredfitFont(12.5)
                        .foregroundStyle(Theme.ink2)
                }
                .accessibilityIdentifier("more-sets-\(pattern.rawValue)")
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var sessionHandleRow: some View {
        let length = store.sessionLengthPreview()
        HStack(spacing: 16) {
            if let shorter = length.shorter {
                Button {
                    store.makeSessionShorter()
                } label: {
                    Text("Shorter today · \(length.now) → \(shorter) min")
                        .dredfitFont(13, weight: .medium)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityIdentifier("session-shorter")
                .accessibilityHint(Text(String(localized: "Takes one set off every movement. Your levels do not change.")))
            }
            if store.isSessionShortened {
                Button {
                    store.restoreFullSession()
                } label: {
                    Text("Full workout")
                        .dredfitFont(13, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                }
                .accessibilityIdentifier("session-full")
            }
        }
    }

    private var planShowing: PlanShowing? {
        guard !store.doneToday, !store.isRestDay(store.today) else { return nil }
        return PlanShowing(session: store.nextSession)
    }

    private struct PlanShowing: Equatable {
        let session: Session
    }

    // MARK: - Plan state

    private var planView: some View {
        let session = store.nextSession
        let debuts = store.debutPatterns
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.screenDateText)
                Text("Workout \(session.sessionNumber)")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("≈ \(Int(session.estimatedTotalMin.rounded())) min · \(session.exercises.count) exercises")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                    // A quiet way into the existing explainer for everyone who
                    // skipped onboarding and can't interpret "+1 step".
                    Button {
                        howItWorksShown = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .dredfitFont(13)
                            Text("Why this plan?")
                                .dredfitFont(13, weight: .medium)
                                .underline(color: Theme.ink3)
                        }
                        .foregroundStyle(Theme.ink2)
                    }
                    .accessibilityIdentifier("why-this-plan")
                }
                sessionHandleRow
            }
            .padding(.top, 18)

            List(session.exercises) { ex in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        techniqueFor = ex
                    } label: {
                        ExerciseRow(exercise: ex,
                                    badge: debuts.contains(ex.pattern)
                                        ? String(localized: "new variation") : nil,
                                    note: ExerciseRow.note(store.setsNote(for: ex)))
                    }
                    exerciseHandles(ex)
                }
                .listRowSeparatorTint(Theme.hairline)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // The "not getting harder" block is gone with
            // the freeze it described. Nothing rests any more — a movement the
            // person finds too hard stays in the plan and gets an easier
            // variation or fewer sets, which is the point of the wave: the
            // channel that took movements out took them out for weeks.

            // An offer of rest, not a warning (#98) — and never a number to
            // beat: the count appears only here, in the suggestion to break
            // the run. "Train anyway" and the Start button stay untouched.
            if store.todayWouldExtendALongRun {
                Text("A workout today would be training day \(store.wouldBeConsecutiveDay) in a row — a rest day lets the load settle.")
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("long-run-line")
            }

            if store.shouldOfferComeback() {
                ComebackCard(offersFreshStart: store.offersFreshStart(),
                             preview: store.comebackPreview(),
                             onAccept: { store.acceptComeback() },
                             onDecline: { store.declineComeback() },
                             onFreshStart: { freshStartConfirmShown = true })
                    .padding(.top, 10)
            }

            // The journal keeps finding the same movement under
            // an unnamed "tough". One contextual question — never a
            // questionnaire.: it used to route into the pain
            // path; it now routes into the handle, which changes the thing the
            // person is complaining about instead of taking it away.
            if store.shouldAskAboutSuspect(), let suspect = store.unnamedLessSuspect() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tough sessions keep landing on \(suspect.displayName).")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button("Make it easier") { store.makeSuspectEasier(suspect) }
                            .accessibilityIdentifier("weak-link-easier")
                        // The third answer — "just hard" —
                        // armed a hold, and the hold is cancelled. The case it
                        // served is exactly what the sub-step fixes without
                        // asking anyone anything.
                        Button("It's fine") { store.dismissSuspectPrompt() }
                            .accessibilityIdentifier("weak-link-fine")
                    }
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .accessibilityIdentifier("weak-link-prompt")
            }

            // The card replaces Start — its own two actions already are
            // "continue" and "start over".
            if let snap = store.resumableWorkout() {
                resumeCard(snap)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            } else {
                PrimaryButton(title: String(localized: "Start")) {
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                }
                    .padding(.top, 10)

                // Secondary by design: the full workout stays the default
                // every day, and the choice is never remembered.
                if let plan = ShortWorkout.plan(session: session,
                                                counter: store.engineState.counter,
                                                levels: store.engineState.levels) {
                    Button {
                        activeWorkout = ActiveWorkout(session: store.nextSession,
                                                      shortPlan: plan)
                    } label: {
                        Text("Short on time? Short version · ≈ \(ShortWorkout.estimatedMin(session: session, plan: plan)) min")
                            .dredfitFont(15, weight: .medium)
                            .foregroundStyle(Theme.ink2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("start-short")
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0).frame(height: 14)   // breathing room above the tab bar
        }
    }

    // MARK: - Interrupted workout

    private func resumeCard(_ snap: WorkoutSnapshot) -> some View {
        // The card must count in the list the person was walking through.
        let total = snap.shortPlan?.count ?? store.nextSession.exercises.count
        let position = min(snap.exIndex + 1, total)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Continue the workout?")
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            Group {
                if snap.atFeedback == true {
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

            HStack(spacing: 10) {
                Button {
                    activeWorkout = ActiveWorkout(session: store.nextSession,
                                                  resume: snap,
                                                  shortPlan: snap.shortPlan.map(Set.init))
                } label: {
                    Text(String(localized: "resume.continue", defaultValue: "Continue"))
                        .pairedPrimaryLabel()
                }
                .accessibilityIdentifier("resume-continue")

                Button {
                    store.clearWorkoutSnapshot()
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                } label: {
                    Text("Start over")
                        .pairedSecondaryLabel()
                }
                .accessibilityIdentifier("resume-restart")
            }
            .padding(.top, 16)
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
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
                Text("Next workout \(store.nextTrainingDateLabel)")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 18)

            // ink2, not ink3: this sentence is the rest day's whole argument.
            Text("Recovery is part of the plan — the load only sticks if you let it settle.")
                .dredfitFont(15.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Spacer()

            // A "train anyway" session interrupted mid-way comes back here
            // too — the rest day must not eat it.
            if let snap = store.resumableWorkout() {
                resumeCard(snap)
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
                .padding(.top, 24)

            Text(resultCaption)
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 6)

            Spacer()

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
            .padding(.bottom, 24)
        }
    }

    private var resultCaption: String {
        switch store.lastRecord?.result {
        case .less: return String(localized: "Rating: tough — the next one will be easier")
        case .plan: return String(localized: "Rating: on plan — the next asks a little more")
        case .more: return String(localized: "Rating: easy — progressing as fast as each movement allows")
        case nil:   return ""
        }
    }
}
