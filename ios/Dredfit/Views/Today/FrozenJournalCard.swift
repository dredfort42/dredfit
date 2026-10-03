//
//  Stands where "Start" would, while the journal could not be read.
//
//  A workout done on a frozen launch is kept in memory only (persist() will
//  not overwrite the file that holds the real history), so starting one would
//  lose it. Try again is the whole of the scene's activation, not just its
//  read: a thaw that skipped the rest would leave an abandoned workout
//  unsettled and the plan without its silent decay. It cannot promise to
//  help — the file may still be unreadable, and a launch that has been used
//  is never reloaded — so the words promise neither it nor the relaunch.
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
                Text("Your saved history can't be read right now, so a workout started now can't be saved. Try again, or close Dredfit and open it again.")
                    .dredfitFont(14.5)
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("frozen-card-text")

            Button {
                store.activate()
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
