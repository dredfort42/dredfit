//
//  The card for a workout that was interrupted: carry on, keep it, or start over.
//

import SwiftUI
import DredfitCore

extension AppStore {
    /// The snapshot this screen has to say something about, and WHICH thing.
    ///
    /// Inside the occasion the card offers to carry on. Past it — but before
    /// the workout counts as forgotten — the card ASKS instead of deciding
    /// (owner, 06.09.2026): three hours is a long lunch, not a lost session,
    /// and recording it unasked put a rating nobody gave into the journal.
    var pendingWorkoutCard: (snapshot: WorkoutSnapshot, awaitingAnswer: Bool)? {
        if let snap = resumableWorkout() { return (snap, false) }
        if let snap = unfinishedWorkoutAwaitingAnswer() { return (snap, true) }
        return nil
    }
}

struct ResumeCard: View {
    @Environment(AppStore.self) private var store
    let snap: WorkoutSnapshot
    let awaitingAnswer: Bool
    @Binding var activeWorkout: ActiveWorkout?
    @Binding var startOverConfirmShown: Bool

    var body: some View {
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
}
