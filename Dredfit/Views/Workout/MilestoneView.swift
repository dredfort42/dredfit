//
//  One screen for everything a workout earned. Calibration can hand a first
//  workout several tier-ups at once, so the layout holds 2–4 rows: the
//  headline steps down as rows are added and the whole thing scrolls.
//

import SwiftUI
import DredfitCore

struct MilestoneView: View {
    let milestones: [Milestone]
    /// Up to the workout that earned these — the card celebrates that
    /// moment, not whatever came after it.
    let steps: [Int]
    var retrospective: Retrospective?
    let onDone: () -> Void

    @State private var ruleDrawn = false
    /// The file that travels AND a picture of it — `SharePreview` shows the
    /// headline alone unless it is handed an `image:` (finding 35).
    @State private var card: ShareCardFactory.Card?
    /// The one animation on this screen is decoration — a 56 pt rule sweeping
    /// out from nothing — and decoration is exactly what "Reduce Motion" is
    /// asked for (UX review 05.09.2026).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var headlineSize: CGFloat {
        switch milestones.count {
        case 1:  return 34
        case 2:  return 28
        default: return 23
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Centred while it fits, scrollable once it doesn't: the spacers
            // collapse as soon as the content outgrows the viewport.
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 0)
                        accentRule
                        ForEach(milestones) { milestone in
                            row(milestone).padding(.top, milestones.count > 2 ? 26 : 34)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity,
                           minHeight: proxy.size.height,
                           alignment: .leading)
                }
            }

            if let card {
                // The card is rendered and written before the sheet opens, so
                // the one person who could not see what they were about to
                // send was the sender (UX review 05.09.2026). It carries a
                // date, the word-mark and the whole curve besides the words
                // the headline repeats.
                ShareLink(item: card.url,
                          preview: SharePreview(cardHeadline, image: card.image)) {
                    Text("Share")
                        .dredfitFont(17, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        // The outline is the whole button — nothing else says
                        // it is one — so it owes 3:1 and hairline gave 1.17:1
                        // in light (finding 31, 1.4.11).
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Theme.targetStroke, lineWidth: 1.5))
                }
                .padding(.bottom, 10)
            }

            // Keyed, not literal: "Done" is taken by the workout's set
            // button. The same English word takes different translations.
            PrimaryButton(title: String(localized: "milestone.done",
                                        defaultValue: "Done"),
                          action: onDone)
                .accessibilityIdentifier("milestone-done")
                .padding(.bottom, 16)
        }
        .onAppear {
            // Drawn, not swept, when motion is turned down: the rule ends in
            // the same place either way, so nothing but the sweep is lost.
            if reduceMotion {
                ruleDrawn = true
            } else {
                withAnimation(.easeOut(duration: 0.55).delay(0.1)) { ruleDrawn = true }
            }
            // ShareLink wants the item up front.
            if !milestones.isEmpty {
                // Only when this workout IS an anniversary.
                let isJubilee = milestones.contains {
                    if case .jubilee = $0 { return true } else { return false }
                }
                let subline = (isJubilee ? retrospective : nil).map {
                    "\($0.comparisonLine)\n\($0.sinceLine)"
                }
                card = ShareCardFactory.card(headline: cardHeadline,
                                             slot: .milestone,
                                             subline: subline,
                                             steps: steps)
            }
        }
    }

    /// Shared by the render and the share-sheet preview so they cannot drift.
    private var cardHeadline: String { ShareCardFactory.headline(for: milestones) }

    private var accentRule: some View {
        Rectangle()
            .fill(Theme.accent)
            .frame(width: 56, height: 3)
            .scaleEffect(x: ruleDrawn ? 1 : 0, anchor: .leading)
            .accessibilityHidden(true)
    }

    private func row(_ milestone: Milestone) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Kicker(text: kicker(milestone))
            Text(headline(milestone))
                .dredfitFont(headlineSize, weight: .heavy)
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let caption = caption(milestone) {
                Text(caption)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = noteLine(milestone) {
                Text(note)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("milestone-note")
            }
            if let life = lifeLine(milestone) {
                Text(life)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("milestone-life")
            }
            if case .jubilee = milestone, let retro = retrospective {
                Text(retro.comparisonLine)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("jubilee-retro")
                Text(retro.sinceLine)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The kicker labels the headline, it is not a separate thought.
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy

    private func kicker(_ milestone: Milestone) -> String {
        // Natural case: Kicker uppercases, so the catalog holds text rather
        // than styling and the share card reuses the jubilee key as-is.
        switch milestone {
        case .variationUp:
            return String(localized: "New variation")
        case .setBand:
            // The same movement grown, not a new one — the caption below and
            // the life-line rule both already said so, and the kicker used to
            // contradict them both (UI-truth audit, 27.08.2026; the wording
            // BACKLOG logged).
            //
            // "More volume" was the fix that overshot (UX review 05.09.2026):
            // entering a band resets the dose to ⌊sets × ceiling ÷ (sets+1)⌋,
            // so by the reference fixture ALL TEN transitions carry the same
            // total work or less (3×15 → 4×11 is 45 → 44; 3×45 s → 4×30 s is
            // 135 → 120), while the dose per set falls by a fifth to a third.
            // The screen announced more volume in the one moment volume does
            // not rise. The axis that did move is the sets, and it is the one
            // the headline names.
            return String(localized: "More sets")
        case .jubilee(let workouts):
            return String(localized: "Workout #\(workouts)")
        }
    }

    private func headline(_ milestone: Milestone) -> String {
        switch milestone {
        case .variationUp(_, _, let exercise):
            return exercise
        case .setBand(_, let sets, _):
            return String(localized: "Now \(sets) sets")
        case .jubilee(let workouts):
            // Every jubilee value ends in 0 or 5, so the genitive plural is
            // the only Russian form this can take.
            return String(localized: "\(workouts) workouts behind you")
        }
    }

    private func caption(_ milestone: Milestone) -> String? {
        switch milestone {
        case .variationUp(let pattern, let variation, _):
            // The ladders are no longer all four rungs long (§40.1: four to
            // seven), so the total is read from the library rather than typed.
            return "\(pattern.displayName) · "
                + String(localized: "variation \(variation) of \(Library.count(pattern))")
                + " · " + entryPlan(pattern, variation)
        case .setBand(let pattern, _, let exercise):
            return "\(pattern.displayName) · \(exercise)"
        case .jubilee:
            return nil
        }
    }

    /// What entering a variation costs, said where it is celebrated rather
    /// than found in the plan the next morning (UX review 05.09.2026).
    ///
    /// The figure is not read from anywhere because it cannot vary: a passed
    /// probe enters at three sets of the grid's floor and nothing else
    /// (`Feedback.resolveProbe` — "ENTRY IS ALWAYS 3×4 (3×15 s)"), so this is
    /// the same statement the engine makes, not a guess about it. It is the
    /// largest drop in numbers the product shows — 3×15 becomes 3×4 — and
    /// until now it was spelled out in one place only: section 10 of "How it
    /// works", behind the settings sheet.
    private func entryPlan(_ pattern: Pattern, _ variation: Int) -> String {
        let unit = Library.unit(pattern, variation)
        let dose = Dose.grid(unit).min
        let sets = EngineConfig.setsBase
        let side = Library.sides(pattern, variation) > 1
            ? String(localized: " /side") : ""
        switch unit {
        case .reps: return String(localized: "we start at \(sets) × \(dose)\(side)")
        case .hold: return String(localized: "we start at \(sets) × \(dose) s\(side)")
        }
    }

    /// The trade a set band makes, for the only milestone whose numbers move
    /// in two directions at once (UX review 05.09.2026).
    ///
    /// Both halves are true at every transition the fixture holds: a set is
    /// added, and the dose per set lands strictly below the one already shown
    /// (`Engine.bandEntryDose`). The exact new dose is not printed here —
    /// `Milestone.setBand` carries the movement and the set count, not the
    /// position — and the sentence has to hold for all ten transitions
    /// anyway.
    private func noteLine(_ milestone: Milestone) -> String? {
        switch milestone {
        case .setBand:
            return String(localized: "Each set asks a little less — there's one more of them.")
        case .variationUp, .jubilee:
            return nil
        }
    }

    /// Only new variations: a set band is the same ability grown, and a
    /// jubilee is about the habit, not a movement.
    private func lifeLine(_ milestone: Milestone) -> String? {
        switch milestone {
        case .variationUp(let pattern, let variation, _):
            return LifeBenefit.text(for: pattern, variation: variation)
        case .setBand, .jubilee:
            return nil
        }
    }
}
