//
//  Shown once on Today after an upgrade from a build before v3 (§41.7).
//
//  The migration is positional (§41.7) — movements, doses, the bar and the
//  counter come across — but not to the digit: doses snap down to the new
//  grids, ten hold cells of 480 rise to the 15 s floor, and a band above a
//  non-top variation comes off. So the card names the step moves instead of
//  promising "same numbers" (UI-truth audit, 27.08.2026). It
//  exists because the only line in the app that ever explained the new shape
//  shows on an EMPTY journal, and an upgrading trainee's journal is full.
//

import SwiftUI

struct MigrationCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your progress carried over")
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            Text("The exercises were rebuilt: the ladders have more variations, and the plan follows what you actually do. You pick up where you left off.")
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("Your whole history is here. A few exercises go by new names, and a few numbers moved a step to fit the new ladders.")
                .dredfitFont(13)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button(action: onDismiss) {
                Text("Got it")
                    .pairedPrimaryLabel()
            }
            .padding(.top, 16)
            .accessibilityIdentifier("migration-dismiss")
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
    }
}
