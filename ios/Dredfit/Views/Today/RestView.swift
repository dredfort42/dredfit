//
//  The rest-day state of Today.
//

import SwiftUI
import DredfitCore

struct RestView: View {
    @Environment(AppStore.self) private var store
    @Binding var activeWorkout: ActiveWorkout?
    @Binding var destination: TodayView.Destination?
    @Binding var freshStartConfirmShown: Bool
    @Binding var startOverConfirmShown: Bool

    /// Rest is a plan, not a lockout: training anyway stays available.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.screenDateText)
                Text("Rest day")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
                    // The palette, not `.primary` — see PlanView's heading.
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
            NextWorkoutCard { destination = .nextWorkout }
                .padding(.bottom, 12)

            // The comeback offer lived in `PlanView` alone, so a return that
            // landed on a rest day — three days in seven as shipped — met the
            // pre-break plan with no way to start lower, and "Train anyway"
            // spends the question for good. The card is self-contained; it
            // moves as one (UX review 05.09.2026).
            if store.shouldOfferComeback() {
                ComebackOffer(onFreshStart: { freshStartConfirmShown = true })
                    .padding(.bottom, 12)
            }

            // A "train anyway" session interrupted mid-way comes back here
            // too — the rest day must not eat it.
            if !store.canStartWorkout {
                // "Train anyway" starts the same unsaveable workout as Start.
                FrozenJournalCard()
                    .padding(.bottom, 14)
            } else if let pending = store.pendingWorkoutCard {
                ResumeCard(snap: pending.snapshot, awaitingAnswer: pending.awaitingAnswer,
                           activeWorkout: $activeWorkout,
                           startOverConfirmShown: $startOverConfirmShown)
                    .padding(.bottom, 14)
            } else {
                Button {
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                } label: {
                    QuietButtonLabel(title: Text("Train anyway"))
                }
                .accessibilityIdentifier("train-anyway")
                .padding(.bottom, 14)
            }
        }
    }
}
