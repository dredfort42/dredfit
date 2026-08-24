//
//  ProgressScreen.swift
//  Dredfit
//
//  One data color (accent) — one metric in several projections.
//

import Charts
import SwiftUI
import DredfitCore

struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    /// At accessibility sizes the stat row cannot hold number and caption
    /// side by side without pushing itself off both edges.
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chartPattern: Pattern?   // nil = the total-level view
    @State private var cardURL: URL?            // the share card
    /// Rendering is a main-thread 1080×1350 pass plus a PNG write — worth
    /// skipping when nothing moved.
    @State private var renderedCardKey: [Int]?

    private var canShare: Bool { !store.records.isEmpty }

    // An icon, not a labelled pill: in Russian the word does not fit beside
    // the number and its caption, and what used to give was the number —
    // which broke mid-digit.
    @ViewBuilder
    private var shareButton: some View {
        if canShare, let cardURL {
            ShareLink(item: cardURL,
                      preview: SharePreview(summaryHeadline)) {
                Image(systemName: "square.and.arrow.up")
                    // Capped: the ring does not grow with type size, and past
                    // ~22 pt the arrow spills out of it.
                    .dredfitFont(15, weight: .semibold, cap: 22)
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Theme.bg)
                            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1.5))
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

    /// Both halves keep their intrinsic width: a four-digit total meeting a
    /// Russian caption must not be squeezed into wrapping — a number broken
    /// mid-digit ("1 27" / "0") was exactly the bug. The share button yields
    /// instead. At accessibility sizes the caption moves under the number.
    @ViewBuilder
    private var statRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    totalNumber
                    Spacer(minLength: 8)
                    shareButton
                }
                levelCaption
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                // Only the button is centred, so this pair measures as one
                // block and the caption keeps the number's baseline.
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    totalNumber
                    levelCaption.fixedSize()
                }
                Spacer(minLength: 8)
                shareButton
            }
        }
    }

    private var totalNumber: some View {
        // A bare staticTexts["0"] query can match a chart axis label.
        Text("\(store.totalLevel)")
            .dredfitFont(56, weight: .heavy, cap: 84)
            .tracking(-2)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("total-level")
    }

    private var levelCaption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(levelLabel)
            Text("\(store.records.count) workouts")
        }
        .dredfitFont(14.5)
        .foregroundStyle(Theme.ink2)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    /// One word, in every language: that is what keeps a four-digit total
    /// and a Russian caption on the same row.
    private var levelLabel: String {
        String(localized: "progress.levelLabel",
               defaultValue: "level",
               comment: "Caption beside the big total-level number. One word: it shares one row with the number and the share button.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The ScrollView spans the full width so the selected row's tint
            // can reach into the gutters without the bounds slicing it.
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: String(localized: "Progress"))
                    .padding(.top, 18)

                statRow
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // The row must not move when a pattern is picked — the
                    // chart would slide out from under the finger. So the
                    // title stays on one line and "Show all" keeps its space
                    // when it has nothing to do.
                    HStack(alignment: .firstTextBaseline) {
                        Kicker(text: chartTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Button {
                            chartPattern = nil
                        } label: {
                            Text("Show all")
                                .dredfitFont(13, weight: .semibold)
                                .foregroundStyle(Theme.accentText)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .opacity(effectivePattern != nil ? 1 : 0)
                        .disabled(effectivePattern == nil)
                        .accessibilityHidden(effectivePattern == nil)
                    }
                    .padding(.top, 16)

                    // Both the chart and the line under it read the same two
                    // derivations; computing them once keeps a long history
                    // from being walked twice on every invalidation.
                    let points = chartPoints
                    let bands = breakBands(points)

                    levelChart(points, bands)
                        .frame(height: 134)   // 120 of chart + room for the date axis
                        .padding(.top, 8)

                    breakFactLine(bands)

                    VStack(spacing: 6) {
                        ForEach(Pattern.ordered, id: \.self) { p in
                            levelRow(p)
                        }
                        if barBranchExists {
                            levelRow(.pullBar)
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .onAppear { refreshCard() }
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
        cardURL = ShareCardFactory.fileURL(headline: summaryHeadline, slot: .progress,
                                           levels: store.levelCurve())
    }

    private var barBranchExists: Bool {
        store.engineState.hasBar || (store.engineState.levels[.pullBar] ?? 0) > 0
    }

    /// If the bar was turned off while its row was selected, fall back to the
    /// total view rather than render an empty, unselectable chart.
    private var effectivePattern: Pattern? {
        if chartPattern == .pullBar && !barBranchExists { return nil }
        return chartPattern
    }

    // MARK: - Breaks

    /// A gap between two adjacent points wide enough for the silent decay to
    /// have run. Gaps are calendar facts, so the bands are identical in every
    /// projection; only `costLevels` is read per projection.
    private struct BreakBand: Identifiable {
        let id: Int
        let from: Date
        let to: Date
        let days: Int
        /// The level on the far side is lower than on the near side AND the
        /// session that produced that point cannot be the thing that lowered
        /// it. "Tough" takes its own step down, so under it a drop is not the
        /// break's to claim — someone who declined "start easier" and then
        /// had a hard session back would otherwise be told the plan met them
        /// lower when it met them exactly where they left it. "On plan" and
        /// "easy" only ever raise a level, so under those a drop across the
        /// gap is the silent decay or an accepted comeback, and saying so is
        /// safe.
        let costLevels: Bool
    }

    private func breakBands(_ points: [LevelPoint]) -> [BreakBand] {
        let cal = Calendar.current
        return zip(points, points.dropFirst()).enumerated().compactMap { index, pair in
            let (before, after) = pair
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: before.date),
                                          to: cal.startOfDay(for: after.date)).day ?? 0
            guard days >= EngineConfig.silentDecayGapDays else { return nil }
            // Two ways the returning session can lower the level by itself —
            // "tough" and an exact number. Under either, the break gets no
            // credit for the drop.
            let ownDoing = after.result == .less || after.ownNumber
            let fell = after.value < before.value && !ownDoing
            return BreakBand(id: index, from: before.date, to: after.date,
                             days: days, costLevels: fell)
        }
    }

    /// The band is drawn whatever its width; its label is not. A label wider
    /// than its band would spill over the line it is explaining.
    private func labelFits(_ band: BreakBand, in points: [LevelPoint]) -> Bool {
        guard let first = points.first?.date, let last = points.last?.date,
              last > first else { return false }
        // The band is a fraction of the axis; the label is not — it grows
        // with Dynamic Type, so the width it needs has to grow with it.
        let needed = typeSize.isAccessibilitySize ? 0.30 : 0.14
        return band.to.timeIntervalSince(band.from) / last.timeIntervalSince(first) >= needed
    }

    /// One line, and it must not repeat the mistake the rating caption made:
    /// the causal half is claimed only where the levels actually fell.
    @ViewBuilder
    private func breakFactLine(_ bands: [BreakBand]) -> some View {
        if let longest = bands.max(by: { $0.days < $1.days }) {
            Text(breakFact(longest, of: bands.count))
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityIdentifier("break-fact")
        }
    }

    private func breakFact(_ band: BreakBand, of count: Int) -> String {
        var line = String(localized: "A break of \(band.days) days.")
        if band.costLevels { line += " " + String(localized: "The plan met you lower.") }
        if count > 1 { line += " " + String(localized: "Others are marked too.") }
        return line
    }

    // MARK: - Level chart

    private struct LevelPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Int
        /// The answer that produced this point, carried because a break may
        /// not claim a drop that the returning session explains by itself.
        let result: FeedbackResult
        /// That session carried a number of its own for what this point
        /// plots. An actual is uncapped downwards and outranks the rating for
        /// its movement, so it is the second way a session can lower a level
        /// without the break having anything to do with it.
        let ownNumber: Bool
    }

    /// Dates can coincide (several workouts in one span), so duplicates
    /// collapse.
    private func xAxisDates(_ points: [LevelPoint]) -> [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let mid = points[points.count / 2].date
        var dates = [first]
        if mid > first && mid < last { dates.append(mid) }
        if last > first { dates.append(last) }
        return dates
    }

    /// Older records without snapshots are skipped — the line starts where
    /// history does.
    private var chartPoints: [LevelPoint] {
        if let p = effectivePattern {
            return store.records
                .compactMap { r in
                    r.levelsAfter?[p].map { (r.date, $0, r.result, r.actuals?[p] != nil) }
                }
                .enumerated()
                .map { LevelPoint(id: $0.offset, date: $0.element.0,
                                  value: $0.element.1, result: $0.element.2,
                                  ownNumber: $0.element.3) }
        }
        return store.records.enumerated()
            .map { LevelPoint(id: $0.offset, date: $0.element.date,
                              value: $0.element.totalLevelAfter, result: $0.element.result,
                              ownNumber: !($0.element.actuals?.isEmpty ?? true)) }
    }

    private var chartTitle: String {
        guard let p = effectivePattern else { return String(localized: "total level") }
        let decoded = Level.decode(store.engineState.levels[p] ?? 0)
        let variation = ExerciseLibrary.entry(for: p).variations[decoded.tier - 1].name
        return "\(p.displayName) — \(variation)"
    }

    /// Both ends are dates, and Swift Charts extracts a mark's labels into
    /// the catalog — so they reuse the key the line marks already use instead
    /// of adding two of their own that no reader will ever see.
    @ChartContentBuilder
    private func breakBandMark(_ band: BreakBand, in points: [LevelPoint]) -> some ChartContent {
        RectangleMark(xStart: .value("date", band.from),
                      xEnd: .value("date", band.to))
            .foregroundStyle(Theme.hairline.opacity(0.55))
            .annotation(position: .overlay, alignment: .center) {
                if labelFits(band, in: points) {
                    Text("\(band.days) days")
                        .dredfitFont(10)
                        .foregroundStyle(Theme.ink3)
                }
            }
    }

    @ViewBuilder
    private func levelChart(_ points: [LevelPoint], _ bands: [BreakBand]) -> some View {
        if points.count >= 2 {
            Chart {
                // Behind the line and carrying no meaning of its own: the
                // silent decay lands between two entries, so without a band
                // the drop appears inside a workout the athlete completed.
                ForEach(bands) { breakBandMark($0, in: points) }
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
                        // Chart axis marks are not Views — no dredfitFont.
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

    /// Below tier 4 the next band boundary unlocks a variation; at tier 4 it
    /// adds a set; at the ceiling there is nothing left to promise.
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
        // The row IS the chart selector. A second tap deselects, back to the
        // total view; "Show all" is the visible way out for anyone who won't
        // guess the toggle.
        return Button {
            chartPattern = selected ? nil : p
        } label: {
            // The all-patterns view answers "where am I", not "what is next
            // on each" — the detail belongs to the projected pattern only.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    // Wide enough for "Горизонтальный жим" on one line: at
                    // 116 the long names wrapped.
                    Text(p.displayName)
                        .dredfitFont(13.5, weight: .medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: 152, alignment: .leading)
                    levelBar(level: level)
                    Text("\(level)")
                        .dredfitFont(13.5, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 44, alignment: .trailing)
                }
                if selected {
                    // Verbatim: the pieces are either core-localized (the
                    // name) or language-neutral (the count).
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(variation) · \(decoded.tier)/\(EngineConfig.tiers)")
                            .accessibilityLabel(Text(verbatim: variation + ", ")
                                                + Text("variation \(decoded.tier) of 4"))
                        Spacer(minLength: 8)
                        nextMilestoneLabel(nextMilestone(level: level, tier: decoded.tier))
                            .monospacedDigit()
                    }
                    .dredfitFont(11)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    private func levelBar(level: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(Theme.accent)
                    .frame(width: max(geo.size.width
                        * CGFloat(level) / CGFloat(EngineConfig.levelMax), level > 0 ? 6 : 0))
                // Same 0...levelMax scale as the fill, so the ticks agree
                // with the number.
                ForEach(1..<(EngineConfig.levelMax / EngineConfig.stepsPerTier + 1), id: \.self) { band in
                    Rectangle()
                        .fill(Theme.bg)
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
