//
//  One data color (accent) — one metric in several projections.
//

import Charts
import SwiftUI
import DredfitCore

struct ProgressScreen: View {
    /// Every sheet this screen raises, behind one `.sheet(item:)`. The record
    /// is the one a tap on the chart opens.
    enum Destination: Identifiable {
        case history(WorkoutRecord)

        var id: String {
            switch self {
            case .history(let record): "history-\(record.id)"
            }
        }
    }

    @Environment(AppStore.self) private var store
    /// At accessibility sizes the stat row cannot hold number and caption
    /// side by side without pushing itself off both edges.
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chartPattern: Pattern?   // nil = the total-steps view
    /// The share card: the file that travels and the picture of it.
    @State private var card: ShareCardFactory.Card?
    /// Rendering is a main-thread 1080×1350 pass plus a PNG write — worth
    /// skipping when nothing moved.
    @State private var renderedCardKey: [Int]?
    @State private var destination: Destination?
    /// 120 of chart plus room for the date axis — and that axis is text, so
    /// the room has to grow with it.
    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 134

    private var canShare: Bool { !store.records.isEmpty }

    private var shareButton: some View {
        ShareButton(card: canShare ? card : nil, headline: summaryHeadline)
    }

    private var summaryHeadline: String {
        ShareCardFactory.summaryHeadline(workouts: store.records.count,
                                         totalSteps: store.totalProgress)
    }

    /// Both halves keep their intrinsic width: a four-digit total meeting a
    /// Russian caption must not be squeezed into wrapping — into a number
    /// broken mid-digit ("1 27" / "0"). The share button yields instead. At
    /// accessibility sizes the caption moves under the number.
    @ViewBuilder
    private var statRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    totalNumber
                    Spacer(minLength: 8)
                    shareButton
                }
                stepsCaption
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                // Only the button is centred, so this pair measures as one
                // block and the caption keeps the number's baseline.
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    totalNumber
                    stepsCaption.fixedSize()
                }
                Spacer(minLength: 8)
                shareButton
            }
        }
    }

    private var totalNumber: some View {
        // A bare staticTexts["0"] query can match a chart axis label.
        Text("\(store.totalProgress)")
            .dredfitFont(56, weight: .heavy, cap: 84)
            // Named, not inherited. Without it SwiftUI hands the largest
            // number on the screen `.primary` — #FFFFFF in dark against the
            // ink token's #F2F2F4, and #000000 in light against #111214 — so
            // the one element the palette is most careful about would be the
            // one element outside it.
            .foregroundStyle(Theme.ink)
            .tracking(-2)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("total-steps")
    }

    private var stepsCaption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stepsLabel)
            Text("\(store.records.count) workouts")
        }
        .dredfitFont(14.5)
        .foregroundStyle(Theme.ink2)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    /// One word, in every language: that is what keeps a four-digit total
    /// and a Russian caption on the same row. The word is "step" because the
    /// scale counts growth events along the ladders, which is exactly what
    /// the glossary already calls steps.
    private var stepsLabel: String {
        String(localized: "progress.stepsLabel",
               defaultValue: "steps",
               comment: "Caption beside the big total-steps number. One word: it shares one row with the number and the share button.")
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

                    StepsChart(points: points, bands: bands) { date in
                        destination = store.record(on: date).map(Destination.history)
                    }
                        .frame(height: chartHeight)
                        .padding(.top, 8)

                    breakFactLine(bands)

                    VStack(spacing: 6) {
                        ForEach(Pattern.ordered, id: \.self) { p in
                            progressRow(p)
                        }
                        if barBranchExists {
                            progressRow(.pullBar)
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .sheet(item: $destination) { destination in
            switch destination {
            case .history(let record):
                HistorySheet(record: record)
            }
        }
        .onAppear { refreshCard() }
        .onChange(of: store.records.count) { refreshCard() }
        .onChange(of: store.totalProgress) { refreshCard() }
        // The card prints its day: a tab left alive past midnight kept
        // yesterday's date until the numbers moved.
        .onChange(of: store.today) { refreshCard() }
    }

    private func refreshCard() {
        guard canShare else {
            card = nil
            renderedCardKey = nil
            return
        }
        // Everything the card DRAWS — its numbers, its day and its curve — so
        // the main-thread render runs exactly when the picture would change.
        // Keyed on the two numbers alone it would keep the day it was first
        // drawn on, and a restored journal with the same count would keep the
        // old curve.
        let curve = store.progressCurve()
        let day = Calendar.current.ordinality(of: .day, in: .era, for: store.today) ?? 0
        let key = [store.records.count, store.totalProgress, day] + curve
        guard key != renderedCardKey else { return }
        renderedCardKey = key
        // `progressCurve()` rather than a second walk of the journal: it is
        // cut at the reset, so the milestone card and this one draw the same
        // line — and after a reset neither sends out the old peak under a
        // headline that says 0.
        card = ShareCardFactory.card(headline: summaryHeadline, slot: .progress,
                                     steps: curve)
    }

    private var barBranchExists: Bool {
        store.engineState.hasBar || Engine.progress(store.engineState, .pullBar) > 0
    }

    /// If the bar was turned off while its row was selected, fall back to the
    /// total view rather than render an empty, unselectable chart.
    private var effectivePattern: Pattern? {
        if chartPattern == .pullBar && !barBranchExists { return nil }
        return chartPattern
    }

    // MARK: - Breaks

    private func breakBands(_ points: [StepsChart.StepPoint]) -> [StepsChart.BreakBand] {
        let cal = Calendar.current
        return zip(points, points.dropFirst()).enumerated().compactMap { index, pair in
            let (before, after) = pair
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: before.date),
                                          to: cal.startOfDay(for: after.date)).day ?? 0
            guard days >= EngineConfig.silentDecayGapDays else { return nil }
            // Three ways the returning session can lower the level by itself
            // — "tough", an exact number, and sets skipped mid-workout (they
            // land as a cut after the rating). Under any of them, the break
            // gets no credit for the drop.
            let ownDoing = after.result == .less || after.ownNumber || after.ownSkips
            let fell = after.value < before.value && !ownDoing
            return StepsChart.BreakBand(id: index, from: before.date, to: after.date,
                             days: days, costSteps: fell)
        }
    }

    /// One line, and it claims no more than happened: the causal half only
    /// where the steps actually fell.
    @ViewBuilder
    private func breakFactLine(_ bands: [StepsChart.BreakBand]) -> some View {
        // The freshest band that actually COST steps, and only failing that
        // the longest. Choosing by length alone would put the explanation on
        // a harmless gap while the visible drop beside it went unexplained —
        // and would withhold "The plan met you lower.", the half of the line
        // written so a dip does not read as a failure.
        if let band = bands.last(where: { $0.costSteps })
            ?? bands.max(by: { $0.days < $1.days }) {
            Text(breakFact(band, of: bands.count))
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func breakFact(_ band: StepsChart.BreakBand, of count: Int) -> String {
        var line = String(localized: "A break of \(band.days) days.")
        if band.costSteps { line += " " + String(localized: "The plan met you lower.") }
        if count > 1 { line += " " + String(localized: "Others are marked too.") }
        return line
    }

    // MARK: - Level chart

    /// Records without a position snapshot are skipped, and so are the ones
    /// written before v3 — their numbers belong to a scale this chart does
    /// not draw. The line starts where the measured ladder does.
    private var chartPoints: [StepsChart.StepPoint] {
        let plotted = store.recordsSinceReset.compactMap { record in
            effectivePattern.map { plot(record, $0) } ?? plotTotal(record)
        }
        return plotted.enumerated().map { index, point in
            StepsChart.StepPoint(id: index, date: point.date, value: point.value,
                                 result: point.result, ownNumber: point.ownNumber,
                                 ownSkips: point.ownSkips)
        }
    }

    /// One record's contribution to the chart, before it is given an index.
    /// A struct rather than a tuple because the lint bounds a tuple at two
    /// members and four of these travel together.
    private struct Plotted {
        let date: Date
        let value: Int
        let result: FeedbackResult
        let ownNumber: Bool
        let ownSkips: Bool
    }

    private func plot(_ record: WorkoutRecord, _ p: Pattern) -> Plotted? {
        guard let position = record.positionsAfter?[p] else { return nil }
        // All five recorded coordinates: replotted without `sub` and `cut`, a
        // snapshot would sit off the number beside the row. Older records
        // carry neither key and plot with both at zero.
        return Plotted(date: record.date,
                       value: Engine.progress(p, variation: position.variation,
                                              sets: position.sets, dose: position.dose,
                                              sub: position.sub ?? 0,
                                              cut: position.cut ?? 0),
                       result: record.result,
                       ownNumber: record.actuals?[p] != nil,
                       ownSkips: record.setsSkipped?[p] != nil)
    }

    private func plotTotal(_ record: WorkoutRecord) -> Plotted? {
        guard let steps = record.totalProgressAfter else { return nil }
        return Plotted(date: record.date, value: steps, result: record.result,
                       ownNumber: !(record.actuals?.isEmpty ?? true),
                       ownSkips: !(record.setsSkipped?.isEmpty ?? true))
    }

    /// The variation alone. Behind "\(p.displayName) — " the kicker runs out
    /// of width and truncates its TAIL — and the tail is the differentiator
    /// ("on a step", "with a pause"), so two rungs of one ladder would draw
    /// the same title. The movement is named by the row that was just tapped
    /// and tinted.
    private var chartTitle: String {
        guard let p = effectivePattern else { return String(localized: "total steps") }
        return Library.name(p, store.engineState.position(p).variation)
    }

    // MARK: - Per-pattern progress bar

    private func progressRow(_ p: Pattern) -> some View {
        let selected = effectivePattern == p
        // The row IS the chart selector. A second tap deselects, back to the
        // total view; "Show all" is the visible way out for anyone who won't
        // guess the toggle.
        return PatternProgressRow(pattern: p, selected: selected) {
            chartPattern = selected ? nil : p
        }
    }
}
