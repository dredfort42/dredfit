//
//  MilestoneView.swift
//  Dredfit
//
//  One screen for everything a workout earned — never a carousel.
//  Calm by design: no confetti, no badges, no score. The single motion is
//  an accent rule drawing itself once.
//
//  Row count is not fixed at one: calibration can hand a first workout
//  several tier-ups at once, so the layout has to hold 2–4 rows without
//  breaking. The headline size steps down as rows are added and the whole
//  thing scrolls.
//

import SwiftUI
import DredfitCore

struct MilestoneView: View {
    let milestones: [Milestone]
    /// The level history up to the workout that earned these milestones —
    /// the card celebrates that moment, not whatever came after it.
    let levels: [Int]
    let onDone: () -> Void

    @State private var ruleDrawn = false
    @State private var cardURL: URL?

    /// Headline size by row count — four unlocks on one screen must still
    /// read as a list, not as four competing headlines.
    private var headlineSize: CGFloat {
        switch milestones.count {
        case 1:  return 34
        case 2:  return 28
        default: return 23
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Centred while it fits, scrollable once it doesn't: one unlock
            // should not sit alone at the top of an empty screen, and four
            // unlocks at large type must still be reachable. The spacers
            // collapse to nothing as soon as the content outgrows the viewport.
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

            // The card names every variation this workout unlocked, not just
            // the first row on screen.
            if let cardURL {
                ShareLink(item: cardURL, preview: SharePreview(cardHeadline)) {
                    Text("Share")
                        .dredfitFont(17, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Theme.hairline, lineWidth: 1.5))
                }
                .accessibilityIdentifier("milestone-share")
                .padding(.bottom, 10)
            }

            // Keyed, not literal: "Done" is already taken by the workout's set
            // button, where it means "I did this set". Here it means "finished
            // reading" — the same English word takes different translations,
            // so the two need separate keys.
            PrimaryButton(title: String(localized: "milestone.done",
                                        defaultValue: "Done"),
                          action: onDone)
                .accessibilityIdentifier("milestone-done")
                .padding(.bottom, 16)
        }
        // Horizontal padding and background come from WorkoutFlowView, as with
        // the other phases of the flow.
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.1)) { ruleDrawn = true }
            // Rendered once here rather than per tap: ShareLink wants the item
            // up front, and a card is cheap enough to make eagerly.
            if !milestones.isEmpty {
                cardURL = ShareCardFactory.fileURL(headline: cardHeadline,
                                                   slot: .milestone,
                                                   levels: levels)
            }
        }
    }

    /// What the card says — shared by the render and the share-sheet preview,
    /// so the two can never drift apart.
    private var cardHeadline: String { ShareCardFactory.headline(for: milestones) }

    /// The one permitted animation: a short accent rule drawing left to right.
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The kicker is a label for the headline, not a separate thought.
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy

    private func kicker(_ milestone: Milestone) -> String {
        // Natural case here — Kicker does the uppercasing, so the catalog
        // holds text rather than styling (and the share card can reuse the
        // jubilee key as-is).
        switch milestone {
        case .tierUp, .setBand:
            return String(localized: "New variation")
        case .jubilee(let workouts):
            return String(localized: "Workout #\(workouts)")
        }
    }

    private func headline(_ milestone: Milestone) -> String {
        switch milestone {
        case .tierUp(_, _, let exercise):
            return exercise
        case .setBand(_, let sets, _):
            return String(localized: "Now \(sets) sets")
        case .jubilee(let workouts):
            // Every jubilee value ends in 0 or 5, so the genitive plural is
            // the only Russian form this can ever take.
            return String(localized: "\(workouts) workouts behind you")
        }
    }

    private func caption(_ milestone: Milestone) -> String? {
        switch milestone {
        case .tierUp(let pattern, let tier, _):
            return "\(pattern.displayName) · " + String(localized: "variation \(tier) of 4")
        case .setBand(let pattern, _, let exercise):
            return "\(pattern.displayName) · \(exercise)"
        case .jubilee:
            return nil
        }
    }
}
