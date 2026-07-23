//
//  ComebackCard.swift
//  Dredfit
//
//  Shown on Today after a break of two weeks or more (v1.5). The engine is
//  event-driven: without this, a plan three weeks old is still waiting at the
//  old level, the first workout back is punishing, and the user leaves for
//  good.
//
//  The tone is the point. No count of missed workouts, no streak broken, no
//  apology asked for. A break is a normal thing that happens to people, and
//  the app's only job is to make coming back easy.
//

import SwiftUI

struct ComebackCard: View {
    let offersFreshStart: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onFreshStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome back")
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            Text("A break is normal. Let's start a couple of steps easier — a gentler way back into the rhythm, and the levels catch up quickly.")
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("Start easier")
                        .dredfitFont(15.5, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("comeback-accept")

                Button(action: onDecline) {
                    Text("Leave as it was")
                        .dredfitFont(15.5, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.hairline, lineWidth: 1.5))
                }
                .accessibilityIdentifier("comeback-decline")
            }
            .padding(.top, 16)

            // Only after a very long break: at that point the old levels are
            // not optimistic, they are meaningless.
            if offersFreshStart {
                Button(action: onFreshStart) {
                    // ink2, not ink3: quiet by design, but still an
                    // interactive control that has to pass 3:1 contrast.
                    Text("Start from scratch")
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .accessibilityIdentifier("comeback-fresh")
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
    }
}
