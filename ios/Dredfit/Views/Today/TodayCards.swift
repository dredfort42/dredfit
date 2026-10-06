//
//  The three pieces more than one state of Today draws.
//

import SwiftUI
import DredfitCore

    /// The door to the next plan, on the completed day and on the rest day
    /// alike: as plain text it would leave rest the one screen in the app with
    /// no way to the plan.
struct NextWorkoutCard: View {
    @Environment(AppStore.self) private var store
    let action: () -> Void

    var body: some View {
        Button {
            action()
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
}

/// One card, two screens: a break that ends on a rest day is still a break,
/// and the offer has to be where the person is.
struct ComebackOffer: View {
    @Environment(AppStore.self) private var store
    let onFreshStart: () -> Void

    var body: some View {
        ComebackCard(offersFreshStart: store.offersFreshStart(),
                     preview: store.comebackPreview(),
                     alreadyDecayed: store.silentDecayAppliedForCurrentBreak,
                     onAccept: { store.acceptComeback() },
                     onDecline: { store.declineComeback() },
                     onFreshStart: onFreshStart)
    }
}

    /// The bordered, unfilled label "Train anyway" and the quiet "Start"
    /// share, in one place so the two cannot drift apart. Takes a `Text` so
    /// the literal stays at the call site, where string extraction finds it.
struct QuietButtonLabel: View {
    let title: Text

    var body: some View {
        title
            .dredfitFont(17, weight: .medium)
            .foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.hairline, lineWidth: 1.5))
    }
}
