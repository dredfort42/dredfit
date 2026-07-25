//
//  ProgressScreen.swift
//  Dredfit
//
//  Total level, the week summary, a level chart over time and per-pattern
//  level bars. One data color (accent) — one metric in several projections.
//

import Charts
import SwiftUI
import DredfitCore

struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    @State private var chartPattern: Pattern?   // nil = the total-level view
    @State private var cardURL: URL?            // the share card
    /// What the current card was rendered from. Rendering is a main-thread
    /// 1080×1350 pass plus a PNG write — worth skipping when nothing moved
    /// (every tab switch, and the double onChange after each workout).
    @State private var renderedCardKey: [Int]?

    /// Nothing to show off before the first workout — the card would read
    /// "0 workouts · total level 0".
    private var canShare: Bool { !store.records.isEmpty }

    // A labelled pill that lives next to the stat it shares, not floating in
    // the top corner beside the global settings gear. Echoes the pattern-chip
    // capsule style right below it.
    @ViewBuilder
    private var shareButton: some View {
        if canShare, let cardURL {
            ShareLink(item: cardURL,
                      preview: SharePreview(summaryHeadline)) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .dredfitFont(13, weight: .semibold)
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1.5))
                )
            }
            .accessibilityIdentifier("progress-share")
            .accessibilityLabel(Text("Share progress"))
        }
    }

    private var summaryHeadline: String {
        ShareCardFactory.summaryHeadline(workouts: store.records.count,
                                         totalLevel: store.totalLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header carries its own gutters; the ScrollView below spans
            // the full width so the selected row's tint can reach 8 pt into
            // the gutters (as designed) without the scroll bounds slicing
            // its rounded corners flat.
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: String(localized: "Progress"))
                    .padding(.top, 18)

                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        // The identifier lets UI tests assert on THIS value — a
                        // bare staticTexts["0"] query can match an axis label.
                        Text("\(store.totalLevel)")
                            .dredfitFont(56, weight: .heavy, cap: 84)
                            .tracking(-2)
                            .monospacedDigit()
                            .accessibilityIdentifier("total-level")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("total level")
                            Text("\(store.records.count) workouts")
                        }
                        .dredfitFont(14.5)
                        .foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: 8)
                    shareButton
                }
                .padding(.top, 12)

                weekSummaryLine
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // The chips row is gone: it was the same list of patterns
                    // twice. The rows below drive the chart; this line names
                    // the current projection and offers the way back.
                    HStack(alignment: .firstTextBaseline) {
                        Kicker(text: chartTitle)
                        Spacer()
                        if effectivePattern != nil {
                            Button {
                                chartPattern = nil
                            } label: {
                                Text("Show all")
                                    .dredfitFont(13, weight: .semibold)
                                    .foregroundStyle(Theme.accentText)
                            }
                        }
                    }
                    .padding(.top, 16)

                    levelChart
                        .frame(height: 134)   // 120 of chart + room for the date axis
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Pattern.ordered, id: \.self) { p in
                            levelRow(p)
                        }
                        // The vertical branch appears once it exists — with the
                        // bar enabled or with progress already earned on it.
                        if barBranchExists {
                            levelRow(.pullBar)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .onAppear { refreshCard() }
        // The totals move with every workout; a stale card would share numbers
        // the user is no longer looking at.
        .onChange(of: store.records.count) { refreshCard() }
        .onChange(of: store.totalLevel) { refreshCard() }
    }

    private func refreshCard() {
        guard canShare else {
            cardURL = nil
            renderedCardKey = nil
            return
        }
        let key = [store.records.count, store.totalLevel]
        guard key != renderedCardKey else { return }
        renderedCardKey = key
        cardURL = ShareCardFactory.fileURL(headline: summaryHeadline, slot: .progress)
    }

    private var barBranchExists: Bool {
        store.engineState.hasBar || (store.engineState.levels[.pullBar] ?? 0) > 0
    }

    /// The projection actually shown. If the bar was turned off while its
    /// chip was selected, the chip is gone — fall back to the total view so
    /// the chart never renders an empty, unselectable state.
    private var effectivePattern: Pattern? {
        if chartPattern == .pullBar && !barBranchExists { return nil }
        return chartPattern
    }

    // MARK: - Week summary

    /// "This week · 2 workouts · +6 levels". Calm: no streaks, no guilt —
    /// a deload week honestly shows a minus.
    private var weekSummaryLine: some View {
        let week = store.weekSummary()
        let sign = week.levelsDelta >= 0 ? "+" : ""
        return (Text("This week")
            + Text(" · ")
            + Text("\(week.workouts) workouts")
            + Text(" · \(sign)", comment: "A separator dot followed by the sign of the level change.")
            + Text("\(week.levelsDelta) levels"))
            .dredfitFont(13.5)
            .monospacedDigit()
            .foregroundStyle(Theme.ink2)
    }

    // MARK: - Level chart

    private struct LevelPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Int
    }

    /// First, middle and last workout dates — the sparse x-axis. Dates can
    /// coincide (several workouts in one span), so duplicates collapse.
    private func xAxisDates(_ points: [LevelPoint]) -> [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let mid = points[points.count / 2].date
        var dates = [first]
        if mid > first && mid < last { dates.append(mid) }
        if last > first { dates.append(last) }
        return dates
    }

    /// The selected projection: the total level when no row is picked, or a
    /// pattern's level from the journal snapshots. Older records without
    /// snapshots are simply skipped — the line starts where history does.
    private var chartPoints: [LevelPoint] {
        if let p = effectivePattern {
            return store.records
                .compactMap { r in r.levelsAfter?[p].map { (r.date, $0) } }
                .enumerated()
                .map { LevelPoint(id: $0.offset, date: $0.element.0, value: $0.element.1) }
        }
        return store.records.enumerated()
            .map { LevelPoint(id: $0.offset, date: $0.element.date, value: $0.element.totalLevelAfter) }
    }

    /// "TOTAL LEVEL", or the projected pattern with its current variation
    /// ("PUSH — PUSH-UP") — the Kicker uppercases it.
    private var chartTitle: String {
        guard let p = effectivePattern else { return String(localized: "total level") }
        let decoded = Level.decode(store.engineState.levels[p] ?? 0)
        let variation = ExerciseLibrary.entry(for: p).variations[decoded.tier - 1].name
        return "\(p.displayName) — \(variation)"
    }

    @ViewBuilder
    private var levelChart: some View {
        let points = chartPoints
        if points.count >= 2 {
            Chart {
                ForEach(points) { pt in
                    LineMark(x: .value("date", pt.date), y: .value("level", pt.value))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    PointMark(x: .value("date", last.date), y: .value("level", last.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(50)
                }
            }
            .chartYScale(domain: 0...max(points.map(\.value).max() ?? 1, 8))
            // A rising line with no time axis can't answer "how fast" — three
            // sparse dates are enough without turning the chart into a grid.
            .chartXAxis {
                AxisMarks(values: xAxisDates(points)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel()
                        // Chart axis marks are not Views — no dredfitFont here.
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.hairline, lineWidth: 1.5)
                .overlay(
                    Text("The chart will appear after a couple of workouts")
                        .dredfitFont(12.5)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                )
        }
    }

    // MARK: - Pattern level bar

    /// What the row's small print says about where the level is heading.
    /// Below tier 4 the next band boundary unlocks a variation; at tier 4 it
    /// adds a set (32, 40); at the ceiling there is nothing left to promise.
    private enum NextMilestone {
        case variation(in: Int)
        case set(in: Int)
        case ceiling
    }

    private func nextMilestone(level: Int, tier: Int) -> NextMilestone {
        let boundary = (level / EngineConfig.stepsPerTier + 1) * EngineConfig.stepsPerTier
        if tier < EngineConfig.tiers { return .variation(in: boundary - level) }
        if boundary <= EngineConfig.levelMax { return .set(in: boundary - level) }
        return .ceiling
    }

    private func levelRow(_ p: Pattern) -> some View {
        let level = store.engineState.levels[p] ?? 0
        let decoded = Level.decode(level)
        let variation = ExerciseLibrary.entry(for: p).variations[decoded.tier - 1].name
        let selected = effectivePattern == p
        // The row IS the chart selector — the chips row it replaced was the
        // same list of patterns a second time. A second tap on the selected
        // row deselects it, back to the total view; "Show all" stays as the
        // visible way out for anyone who won't guess the toggle.
        return Button {
            chartPattern = selected ? nil : p
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.displayName)
                        .dredfitFont(13.5, weight: .medium)
                        .foregroundStyle(Theme.ink)
                    // "Push-up · 2/4" — which exercise this level buys and
                    // where it sits in the four-variation progression. The
                    // pieces are either core-localized (the name) or
                    // language-neutral (the count), so the line is verbatim.
                    Text(verbatim: "\(variation) · \(decoded.tier)/\(EngineConfig.tiers)")
                        .dredfitFont(11)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(Text(verbatim: variation + ", ") + Text("variation \(decoded.tier) of 4"))
                }
                .frame(width: 116, alignment: .leading)
                levelBar(level: level)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(level)")
                        .dredfitFont(13.5, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    nextMilestoneLabel(nextMilestone(level: level, tier: decoded.tier))
                        .dredfitFont(10.5)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 72, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            // The tint says "this is what the chart shows"; it reaches 8 pt
            // into the gutters so the highlight breathes past the text.
            .background(selected ? Theme.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        // Colour alone doesn't reach VoiceOver — state has to be a trait.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func levelBar(level: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(Theme.accent)
                    .frame(width: max(geo.size.width
                        * CGFloat(level) / CGFloat(EngineConfig.levelMax), level > 0 ? 6 : 0))
                // Band boundaries — where a variation (or, past tier 4, a
                // set) unlocks. The geometry uses the same 0...levelMax scale
                // as the fill so the ticks agree with the number.
                ForEach(1..<(EngineConfig.levelMax / EngineConfig.stepsPerTier + 1), id: \.self) { band in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 8)
                        .offset(x: geo.size.width
                            * CGFloat(band * EngineConfig.stepsPerTier) / CGFloat(EngineConfig.levelMax))
                }
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private func nextMilestoneLabel(_ milestone: NextMilestone) -> some View {
        switch milestone {
        case .variation(let steps): Text("next in \(steps)")
        case .set(let steps): Text("+1 set in \(steps)")
        case .ceiling: EmptyView()
        }
    }
}
