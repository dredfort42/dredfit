//
//  Shown once on Today after an upgrade from a build before v3 (§41.7).
//
//  The migration is precise — movements, doses, the bar and the counter all
//  come across — so this says what changed rather than what was lost. It
//  exists because the only line in the app that ever explained the new shape
//  shows on an EMPTY journal, and an upgrading trainee's journal is full.
//

import SwiftUI

struct MigrationCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your progress came across")
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            Text("The exercises were rebuilt: every movement now has more variations, and the plan follows what you actually do. You pick up where you left off — same movements, same numbers.")
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("Your whole history is here. A few exercises go by new names.")
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
