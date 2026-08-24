//
//  ComebackCard.swift
//  Dredfit
//
//  Shown on Today after a break of two weeks or more. The engine is
//  event-driven: without this an old plan waits at the old level.
//

import SwiftUI

struct ComebackCard: View {
    let offersFreshStart: Bool
    /// The two offers as the same movement in numbers (#127): what the plan
    /// holds if left alone, and what "easier" actually is. Nil hides the rows.
    let preview: (was: String, easier: String)?
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

            // The choice in numbers, not adjectives (#127): after a long
            // break "leave as it was" used to hand out the old plan blind.
            if let preview {
                VStack(alignment: .leading, spacing: 5) {
                    previewRow(label: String(localized: "Easier:"), value: preview.easier)
                    previewRow(label: String(localized: "As it was:"), value: preview.was)
                }
                .padding(.top, 12)
                .accessibilityIdentifier("comeback-preview")
            }

            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("Start easier")
                        .pairedPrimaryLabel()
                }
                .accessibilityIdentifier("comeback-accept")

                Button(action: onDecline) {
                    Text("Leave as it was")
                        .pairedSecondaryLabel()
                }
                .accessibilityIdentifier("comeback-decline")
            }
            .padding(.top, 16)

            // v2.12 (#133): the "I was sick" path — the easier start plus a
            // recovery fortnight at one tier gentler, in a single tap.
            // v2.26 (spec §37.0): the "I was sick" tap is gone. The lens it
            // armed made the plan HEAVIER in 76 cells out of 480, which is the
            // opposite of what the button offered. Someone coming back short
            // on strength reaches for the session handle on the plan itself,
            // where the recalculated duration is visible before they agree.
            .padding(.top, 4)

            if offersFreshStart {
                Button(action: onFreshStart) {
                    // ink2, not ink3: an interactive control has to pass 3:1.
                    Text("Start from scratch")
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .accessibilityIdentifier("comeback-fresh")
            }
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .dredfitFont(13, weight: .semibold)
                .foregroundStyle(Theme.ink2)
            Text(value)
                .dredfitFont(13)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
