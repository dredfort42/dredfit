//
//  One movement's row of the Progress screen: its name, how far along its
//  ladder it stands, and — once picked — what the ladder promises next.
//

import SwiftUI
import DredfitCore

struct PatternProgressRow: View {
    @Environment(AppStore.self) private var store
    /// At accessibility sizes the row cannot hold name, bar and number side
    /// by side.
    @Environment(\.dynamicTypeSize) private var typeSize
    let pattern: Pattern
    let selected: Bool
    let action: () -> Void

    /// What the ladder promises next. Below the top variation the ceiling of
    /// the current one is where the engine starts offering a PROBE — the only
    /// door into the next variation — so that is what the countdown counts to.
    /// On the top variation the same ceiling buys a set instead, and on five
    /// sets (`EngineConfig.setsMax`) there is no set left to promise.
    private enum NextMilestone {
        case probe(in: Int)
        case set(in: Int)
        case ceiling
    }

    /// Distance on the row's own scale to the MILESTONE, not to the ceiling:
    /// the ceiling costs `steps`, the crossing — the probe, or the band
    /// transition — is one more point, and every set taken off comes back
    /// first, so it is on the path too. Counting to the ceiling alone would
    /// put the label one point short of the tick the bar draws for the same
    /// milestone.
    private func nextMilestone(_ p: Pattern) -> NextMilestone {
        let position = store.engineState.position(p)
        let steps = Engine.stepsToVariationCeiling(store.engineState, p) + position.cut + 1
        guard position.variation == Library.count(p) else { return .probe(in: steps) }
        guard position.sets < EngineConfig.setsMax else { return .ceiling }
        return .set(in: steps)
    }

    var body: some View {
        let p = pattern
        let steps = Engine.progress(store.engineState, p)
        let position = store.engineState.position(p)
        let variation = Library.name(p, position.variation)
        let total = Library.count(p)
        return Button {
            action()
        } label: {
            // The all-patterns view answers "where am I", not "what is next
            // on each" — the detail belongs to the projected pattern only.
            VStack(alignment: .leading, spacing: 3) {
                rowHead(p, steps: steps, selected: selected)
                    // "Squat, 18" was a number with no scale: the bar carries
                    // the scale visually and carries nothing at all to
                    // VoiceOver. The element is this row only — the selected
                    // line below keeps its own label, and a label on the
                    // Button would swallow it.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: p.displayName + ", ")
                        + Text("step \(steps) of \(Engine.ladderSpan(p))"))
                if selected {
                    // ink, not ink2: this line only exists on the accented
                    // fill, where ink2 is 4.03:1 in the light scheme — under
                    // the 4.5 small text needs.
                    selectedDetail(p, variation, position, of: total)
                        .dredfitFont(11)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        // 0.85, not 0.7: at 0.7 this line would render at
                        // 7.7 pt AND still lose its tail, and the tail is the
                        // dose — the one number no other part of this screen
                        // carries.
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(selected ? Theme.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        // Colour alone doesn't reach VoiceOver — state has to be a trait.
        .accessibilityAddTraits(selected ? [.isSelected] : [])

    }

    /// The head of a movement row: name, scale, number, and the marker that
    /// says the row does something.
    ///
    /// One line while the type is ordinary. The 152 pt the name is given and
    /// the 44 pt the number is given are literals that Dynamic Type does not
    /// move, so at AX3 and up the name would be cut to a few letters and a
    /// two-digit step count truncated inside its column; at accessibility
    /// sizes the bar drops under the pair instead, which is the move
    /// `ProgressScreen.statRow` already makes.
    @ViewBuilder
    private func rowHead(_ p: Pattern, steps: Int, selected: Bool) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    patternName(p)
                    Spacer(minLength: 8)
                    stepsNumber(steps, selected: selected)
                    disclosure(selected)
                }
                progressBar(p, steps: steps)
            }
        } else {
            HStack(spacing: 12) {
                // Wide enough for "Горизонтальный жим" on one line: at
                // 116 the long names wrap.
                patternName(p).frame(width: 152, alignment: .leading)
                progressBar(p, steps: steps)
                HStack(spacing: 6) {
                    stepsNumber(steps, selected: selected).frame(width: 44, alignment: .trailing)
                    disclosure(selected)
                }
            }
        }
    }

    private func patternName(_ p: Pattern) -> some View {
        Text(p.displayName)
            .dredfitFont(13.5, weight: .medium)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    /// ink on the accented fill of the selected row, for the reason the
    /// detail line gives.
    private func stepsNumber(_ steps: Int, selected: Bool) -> some View {
        Text("\(steps)")
            .dredfitFont(13.5, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(selected ? Theme.ink : Theme.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// Without a sign that the row can be tapped, the answer to "what comes
    /// next" — which lives inside the opened row and nowhere else — would be
    /// reachable only by poking at random.
    ///
    /// Down/up rather than the `chevron.right` of Today and Settings: there it
    /// means a sheet opens, and this row opens nothing — it projects the chart
    /// above and closes again on a second tap. Capped for the same reason the
    /// share ring is: in the compact row the columns beside it are literals,
    /// and a marker that grew would take the width from the bar.
    private func disclosure(_ selected: Bool) -> some View {
        Image(systemName: selected ? "chevron.up" : "chevron.down")
            .dredfitFont(11, weight: .semibold, cap: 15)
            .foregroundStyle(Theme.ink2)
    }

    /// One line while both halves fit it, two when they do not. A long
    /// variation name next to the countdown would drive one line into its
    /// scale floor and truncate it anyway; the rule that the row above must
    /// not move when a pattern is picked does not reach here, because this
    /// line does not exist until it is.
    ///
    /// Verbatim: the pieces are either core-localized (the name) or
    /// language-neutral (the numbers).
    @ViewBuilder
    private func selectedDetail(_ p: Pattern, _ variation: String,
                                _ position: Position, of total: Int) -> some View {
        let detail = Text(verbatim: detailLine(variation, position, of: total))
            .accessibilityLabel(Text(verbatim: variation + ", ")
                + Text("variation \(position.variation) of \(total)"))
        let milestone = nextMilestoneLabel(nextMilestone(p)).monospacedDigit()
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                detail
                Spacer(minLength: 8)
                milestone
            }
            VStack(alignment: .leading, spacing: 2) {
                detail
                milestone
            }
        }
    }

    /// "Bulgarian split squat · 3/6 · 3×11" — the variation, where it stands
    /// on its ladder, and the dose: one level number could name neither.
    private func detailLine(_ variation: String, _ position: Position, of total: Int) -> String {
        "\(variation) · \(position.variation)/\(total) · \(position.sets)×\(position.dose)"
    }

    /// The scale is the pattern's OWN ladder, so the ladders do not share one
    /// denominator: six variations of squats and four of lunges
    /// are different distances, and a bar that pretended otherwise would put
    /// two people on the same mark for different work. The ticks stand where
    /// each variation begins.
    private func progressBar(_ p: Pattern, steps: Int) -> some View {
        let span = max(Engine.ladderSpan(p), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(Theme.accent)
                    .frame(width: max(geo.size.width * CGFloat(steps) / CGFloat(span),
                                      steps > 0 ? 6 : 0))
                ForEach(Engine.variationBoundaries(p), id: \.self) { boundary in
                    Rectangle()
                        .fill(Theme.bg)
                        .frame(width: 2, height: 8)
                        .offset(x: geo.size.width * CGFloat(boundary) / CGFloat(span))
                }
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private func nextMilestoneLabel(_ milestone: NextMilestone) -> some View {
        switch milestone {
        // "movement" names the whole ladder in this app, so "next movement in
        // 4" here would read as a different exercise altogether. And what this
        // counts to is not the change of variation but the PROBE that opens
        // it, one event earlier, so the honest words are the glossary's two.
        case .probe(let steps): Text("next variation probe in \(steps)")
        case .set(let steps): Text("+1 set in \(steps)")
        case .ceiling: EmptyView()
        }
    }
}
