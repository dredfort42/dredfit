//
//  MilestoneView.swift
//  Dredfit
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
    let levels: [Int]
    var retrospective: Retrospective?
    let onDone: () -> Void

    @State private var ruleDrawn = false
    @State private var cardURL: URL?

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

            // Keyed, not literal: "Done" is taken by the workout's set
            // button. The same English word takes different translations.
            PrimaryButton(title: String(localized: "milestone.done",
                                        defaultValue: "Done"),
                          action: onDone)
                .accessibilityIdentifier("milestone-done")
                .padding(.bottom, 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.1)) { ruleDrawn = true }
            // ShareLink wants the item up front.
            if !milestones.isEmpty {
                // Only when this workout IS an anniversary.
                let isJubilee = milestones.contains {
                    if case .jubilee = $0 { return true } else { return false }
                }
                let subline = (isJubilee ? retrospective : nil).map {
                    "\($0.comparisonLine)\n\($0.sinceLine)"
                }
                cardURL = ShareCardFactory.fileURL(headline: cardHeadline,
                                                   slot: .milestone,
                                                   subline: subline,
                                                   levels: levels)
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
            // the only Russian form this can take.
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

    /// Only tier-ups: a set band is the same ability grown, and a jubilee is
    /// about the habit, not a movement.
    private func lifeLine(_ milestone: Milestone) -> String? {
        switch milestone {
        case .tierUp(let pattern, let tier, _):
            return LifeBenefit.text(for: pattern, tier: tier)
        case .setBand, .jubilee:
            return nil
        }
    }
}
