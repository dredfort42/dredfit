//
//  Stands where "Start" would, while the journal could not be read.
//
//  A workout done on a frozen launch is kept in memory only (persist() will
//  not overwrite the file that holds the real history), so starting one meant
//  losing it. Retry is the second read the scene's activation already makes;
//  once the launch has been used it cannot lift the freeze, which is why the
//  words also name the one thing that always works.
//

import SwiftUI

struct FrozenJournalCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same words as the note under Settings' backup rows: one problem,
            // one way of naming it.
            VStack(alignment: .leading, spacing: 8) {
                Text("Your history couldn't be read")
                    .dredfitFont(20, weight: .heavy)
                    .tracking(-0.3)
                    .foregroundStyle(Theme.ink)
                // One literal, because the literal is the catalog key.
                // swiftlint:disable:next line_length
                Text("You can't start a workout yet, because it couldn't be saved. Unlock the phone and try again. If that doesn't help, close Dredfit and open it again.")
                    .dredfitFont(14.5)
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("frozen-card-text")

            Button {
                store.reloadIfNeeded()
            } label: {
                Text("Try again")
                    .pairedPrimaryLabel()
            }
            .padding(.top, 16)
            .accessibilityIdentifier("frozen-retry")
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("frozen-card")
    }
}
