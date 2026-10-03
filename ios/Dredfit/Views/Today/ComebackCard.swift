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
    /// Whether the silent decay already took a step off this same break — an
    /// open between day 7 and day 13 of it, outside the trainee's rhythm.
    ///
    /// While the card is up it is the only place on Today that names the
    /// quiet drop — Today's own decay line stands down for it — and "As it
    /// was:" beside it describes the plan as it stands now, not as it was
    /// left.
    let alreadyDecayed: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onFreshStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome back")
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            // One literal, because the literal is the catalog key.
            // swiftlint:disable:next line_length
            Text("A break is normal. Let's start a few steps easier — the longer the break, the lower the plan meets you, and it catches up quickly.")
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if alreadyDecayed {
                Text("During the break the plan already came down a step.")
                    .dredfitFont(13.5, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            // The choice in numbers, not adjectives (#127): without them,
            // "leave as it was" hands out the old plan blind after a long
            // break.
            if let preview {
                VStack(alignment: .leading, spacing: 5) {
                    previewRow(label: String(localized: "Easier:"), value: preview.easier)
                    previewRow(label: String(localized: "As it was:"), value: preview.was)
                }
                .padding(.top, 12)
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

            if offersFreshStart {
                Button(action: onFreshStart) {
                    // ink2, not ink3: an interactive control has to pass 3:1.
                    Text("Start from scratch")
                        .dredfitFont(13.5, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        // Bordered and set apart, not a third line under the
                        // pair: it is the one control on this card that throws
                        // progress away, and must not read as a quiet extra of
                        // the "Start easier" / "Leave as it was" row. The
                        // border is the idiom "Train anyway" uses for a
                        // whole-width quiet choice, and 44 pt is the floor
                        // this project set in #193.
                        //
                        // ink3 for the stroke, not hairline: the card ground is
                        // `cardBG`, where hairline comes to ≈1.1–1.2:1 and
                        // simply is not there. ink3 reads ≈2.2:1 in the light
                        // scheme — past the floors the palette holds for quiet
                        // graphics (1.3:1, 1.5:1 under Increased Contrast), and
                        // still quieter than the label it surrounds.
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.ink3, lineWidth: 1.5))
                }
                .accessibilityIdentifier("comeback-fresh")
                .padding(.top, 14)
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
