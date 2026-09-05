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
    var id: Int { session.sessionNumber }
}

struct TodayView: View {
    @Environment(AppStore.self) var store
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeWorkout: ActiveWorkout?
    @State var techniqueFor: TechniqueTarget?
    @State private var nextPreviewShown = false
    @State private var freshStartConfirmShown = false

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
            WorkoutFlowView(session: active.session, resume: active.resume)
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
        let length = store.sessionLengthRange()
        let count = session.exercises.count
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.screenDateText)
                Text("Workout \(session.sessionNumber)")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
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

            // The "not getting harder" block is gone with the freeze it
            // described. Nothing rests any more — a movement the person finds
            // too hard stays in the plan and gets an easier variation, or
            // fewer sets inside the workout: the channel that took movements
            // out took them out for weeks.

            // An offer of rest, not a warning (#98) — and never a number to
            // beat: the count appears only here, in the suggestion to break
            // the run. "Train anyway" and the Start button stay untouched.
            if store.todayWouldExtendALongRun {
                // The same accent card the work screen gives the maximum note,
                // and for the same reason: worth reading, blocks nothing. Grey
                // 13.5 pt under the plan was the one place nobody looks.
                // accentText on accentSoft, not accent — accent itself is
                // 2.91:1 on that fill.
                Text("A workout today would be training day \(store.wouldBeConsecutiveDay) in a row — a rest day lets the load settle.")
                    .dredfitFont(14, weight: .medium)
                    .foregroundStyle(Theme.accentText)
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

            // Ahead of the comeback card deliberately: that card asks for a
            // decision about the plan, and this one explains what the plan IS
            // after an upgrade. Answering before reading is the wrong order.
            if store.showsMigrationNotice {
                MigrationCard(onDismiss: { store.dismissMigrationNotice() })
                    .padding(.top, 10)
            }

            if store.shouldOfferComeback() {
                ComebackCard(offersFreshStart: store.offersFreshStart(),
                             preview: store.comebackPreview(),
                             onAccept: { store.acceptComeback() },
                             onDecline: { store.declineComeback() },
                             onFreshStart: { freshStartConfirmShown = true })
                    .padding(.top, 10)
            }

            // The journal keeps finding the same movement under an unnamed
            // "tough". One contextual question — never a questionnaire — and
            // where it lands has changed: it used to route into the pain path;
            // it now routes into the handle, which changes the thing the
            // person is complaining about instead of taking it away.
            if store.shouldAskAboutSuspect(), let suspect = store.unnamedLessSuspect() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tough workouts keep landing on \(suspect.displayName).")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button("Make it easier") { store.makeSuspectEasier(suspect) }
                        // The third answer — "just hard" — armed a hold, and
                        // the hold is cancelled. The case it served is exactly
                        // what the sub-step fixes without asking anyone
                        // anything.
                        Button("It's fine") { store.dismissSuspectPrompt() }
                    }
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
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
                Text(String(localized: "plan.techniqueHint",
                            defaultValue: "Tap a movement for how it's done — and for the version one step below it."))
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
            if let snap = store.resumableWorkout() {
                resumeCard(snap)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            } else {
                // One Start, and it runs the plan above it. There is nothing
                // left on this screen to agree to first.
                PrimaryButton(title: String(localized: "Start")) {
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                }
                    // The most-tapped control in the UI suite. Identified so a
                    // reworded label costs nothing: the word "Start" moved
                    // twice in a week (PR #207/#208) and the tests that reach
                    // for it are in every file.
                    .accessibilityIdentifier("start-workout")
                    .padding(.top, 10)
            }
            Spacer(minLength: 0).frame(height: 14)   // breathing room above the tab bar
        }
    }

    // MARK: - Interrupted workout

    private func resumeCard(_ snap: WorkoutSnapshot) -> some View {
        let total = store.nextSession.exercises.count
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
                    activeWorkout = ActiveWorkout(session: store.nextSession, resume: snap)
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
            Text("Recovery is part of the plan — you get stronger between workouts, not during them.")
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
        case .plan: return String(localized: "Rating: on plan — the next one adds a step to the movements that have room for one")
        case .more: return String(localized: "Rating: easy — progressing as fast as each movement allows")
        case nil:   return ""
        }
    }
}
