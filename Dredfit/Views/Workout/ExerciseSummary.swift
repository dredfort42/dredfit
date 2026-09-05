//
//  Every set of a finished hold movement, on one screen, with any number one
//  tap from being corrected.
//
//  It replaces the settled hold that used to stand on the work screen. That
//  showed ONE number — the last set's — and the sets before it had never been
//  correctable at all: the only writer the work screen has records the set
//  under way and truncates what follows, because on that screen the sets after
//  it have not happened yet. Here they have, so the writer is
//  `SetFacts.recordingSet`, which changes one and leaves the rest standing.
//
//  The leaf views live apart from the flow (WorkoutFlowView+Summary.swift)
//  for the reason every other screen in this folder does: what a card looks
//  like is not what the phase decides.
//

import SwiftUI
import DredfitCore

/// One set of the movement as the summary prints it.
struct HeldSet: Identifiable {
    /// 0-based, like everything the flow counts sets with.
    let index: Int
    let seconds: Int
    let planned: Int
    /// The number is an ESTIMATE rather than a measurement: the set ended
    /// under a thumb, which pays a guessed three-second reach allowance.
    /// Printed as "≈", because a number the app guessed at must not be shown
    /// with the confidence of one the clock produced.
    let approximate: Bool

    var id: Int { index }
    /// How far past this set's own plan it landed, or nil when it did not.
    var over: Int? { seconds > planned ? seconds - planned : nil }
}

/// One tappable number. 44 pt is the floor for the target, not for the card:
/// the number alone is 40 pt tall at the default text size and a card that
/// only just cleared it would fail the moment somebody turned text up (R18).
struct HeldSetCard: View {
    let held: HeldSet
    /// True when the exercise asks different numbers of different sets, in
    /// which case the plan belongs on each card: "planned 55 s each" would be
    /// a sentence about a plan that does not exist.
    let unevenPlan: Bool
    let action: () -> Void

    private var accented: Bool { held.over != nil }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                // Verbatim: a bare numeral with a maths sign carries no words
                // to translate, and the "≈" is drawn in the number's OWN
                // colour rather than a quieter one — a mark that says "this
                // figure is an estimate" is not decoration (R16).
                Text(verbatim: held.approximate ? "≈\(held.seconds)" : "\(held.seconds)")
                    .dredfitFont(34, weight: .heavy, cap: 46)
                    .monospacedDigit()
                caption
                    .dredfitFont(12, weight: .medium)
                    .monospacedDigit()
            }
            // `ink` on BOTH fills, not accentText on the accented one, and
            // the difference is measured rather than a preference:
            // accentText on accentSoft comes to 4.20:1 in the dark scheme
            // (I-21), under what small text needs, while ink on accentSoft is
            // gated at 4.5 dark and 7 in Increased Contrast
            // (BrandPaletteTests). Nothing is lost — "above plan" is said in
            // words on the caption ("· +7"), so the fill is a second signal
            // rather than the only one.
            .foregroundStyle(Theme.ink)
            .frame(minWidth: 78, minHeight: 72)
            .padding(.horizontal, 10)
            .background(accented ? Theme.accentSoft : Theme.cardBG,
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityIdentifier("summary-set-\(held.index + 1)")
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text(String(localized: "Change this number")))
    }

    /// In order of precedence, and each answers a different question. An
    /// estimate says so first — it is a statement about how much the number
    /// can be trusted, which outranks anything it can be compared against.
    private var caption: Text {
        if held.approximate { return Text("set \(held.index + 1) · stopped by hand") }
        if let over = held.over { return Text("set \(held.index + 1) · +\(over)") }
        if unevenPlan { return Text("set \(held.index + 1) · planned \(held.planned)") }
        return Text("set \(held.index + 1)")
    }

    /// Spoken as a sentence, with the plan in it: "48" and "set 2" read out
    /// as two facts leave the listener nothing to measure the number against,
    /// and the whole point of the screen is the comparison.
    private var spoken: String {
        held.approximate
            ? String(localized: """
                set \(held.index + 1), approximately \(held.seconds) seconds, \
                planned \(held.planned)
                """)
            : String(localized: """
                set \(held.index + 1), \(held.seconds) seconds, \
                planned \(held.planned)
                """)
    }
}

/// The row of cards: one line while they fit, two lines when they do not, and
/// a column when even that is too wide. Five sets, an accessibility text size
/// and an iPhone SE are all real at once — the pattern is the app's own, and
/// the caller wraps this in the scroll that makes the last case survivable.
struct HeldSetsRow: View {
    let sets: [HeldSet]
    let unevenPlan: Bool
    let onEdit: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) { cards(sets) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { cards(sets) }
                VStack(spacing: 10) {
                    HStack(spacing: 10) { cards(Array(sets.prefix(3))) }
                    if sets.count > 3 {
                        HStack(spacing: 10) { cards(Array(sets.dropFirst(3))) }
                    }
                }
                VStack(spacing: 10) { cards(sets) }
            }
        }
    }

    @ViewBuilder
    private func cards(_ sets: [HeldSet]) -> some View {
        ForEach(sets) { held in
            HeldSetCard(held: held, unevenPlan: unevenPlan) { onEdit(held.index) }
        }
    }
}
