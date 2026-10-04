//
//  The share control of the Progress header.
//

import SwiftUI

// An icon, not a labelled pill: in Russian the word does not fit beside
// the number and its caption, and what used to give was the number —
// which broke mid-digit.
struct ShareButton: View {
    /// The rendered card, or nil while there is nothing to share.
    let card: ShareCardFactory.Card?
    let headline: String

    var body: some View {
        if let card {
            // The preview carries the PICTURE, not the headline alone. The
            // card is rendered before the sheet opens, so the one thing an
            // athlete could check before sending — what it says about them —
            // was the one thing the share sheet did not show (UX review,
            // 05.09.2026).
            ShareLink(item: card.url,
                      preview: SharePreview(headline, image: card.image)) {
                Image(systemName: "square.and.arrow.up")
                    // Capped: the ring does not grow with type size, and past
                    // ~22 pt the arrow spills out of it.
                    .dredfitFont(15, weight: .semibold, cap: 22)
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 38, height: 38)
                    // The fill is the page's own ground, so the ring is the
                    // only thing saying this glyph is a control — which is
                    // what 1.4.11 asks 3:1 of, and hairline gave 1.17:1 in
                    // light. `targetStroke`, the same role the milestone
                    // screen's Share button takes, not a local ink2: the two
                    // buttons are the same control and must move together
                    // (finding 31, UX review 05.09.2026).
                    .background(
                        Circle()
                            .fill(Theme.bg)
                            .overlay(Circle().strokeBorder(Theme.targetStroke, lineWidth: 1.5))
                    )
            }
            .accessibilityLabel(Text("Share progress"))
        }
    }
}
