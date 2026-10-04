//
//  The share control of the Progress header.
//

import SwiftUI

// An icon, not a labelled pill: in Russian the word does not fit beside
// the number and its caption, and what would give is the number — broken
// mid-digit.
struct ShareButton: View {
    /// The rendered card, or nil while there is nothing to share.
    let card: ShareCardFactory.Card?
    let headline: String

    var body: some View {
        if let card {
            // The preview carries the PICTURE, not the headline alone: the
            // card is rendered before the sheet opens, and what it says about
            // the athlete is the one thing they would check before sending.
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
                    // what 1.4.11 asks 3:1 of, and hairline is 1.17:1 in
                    // light. `targetStroke`, the same role the milestone
                    // screen's Share button takes, not a local ink2: the two
                    // buttons are the same control and must move together.
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
