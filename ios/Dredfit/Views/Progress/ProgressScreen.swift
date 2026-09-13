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
    @State private var chartPattern: Pattern?   // nil = the total-steps view
    /// The share card: the file that travels and the picture of it.
    @State private var card: ShareCardFactory.Card?
    /// Rendering is a main-thread 1080×1350 pass plus a PNG write — worth
    /// skipping when nothing moved.
    @State private var renderedCardKey: [Int]?
    /// The record a tap on the chart opens.
    @State private var historyRecord: WorkoutRecord?
    /// 120 of chart plus room for the date axis — and that axis is text now,
    /// so the room has to grow with it (UX review, 05.09.2026).
    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 134

    private var canShare: Bool { !store.records.isEmpty }

    // An icon, not a labelled pill: in Russian the word does not fit beside
    // the number and its caption, and what used to give was the number —
    // which broke mid-digit.
    @ViewBuilder
    private var shareButton: some View {
        if canShare, let card {
            // The preview carries the PICTURE, not the headline alone. The
            // card is rendered before the sheet opens, so the one thing an
            // athlete could check before sending — what it says about them —
            // was the one thing the share sheet did not show (UX review,
            // 05.09.2026).
            ShareLink(item: card.url,
                      preview: SharePreview(summaryHeadline, image: card.image)) {
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

    private var summaryHeadline: String {
        ShareCardFactory.summaryHeadline(workouts: store.records.count,
                                         totalSteps: store.totalProgress)
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
            // the one element the palette is most careful about was the one
            // element outside it (UX review 05.09.2026).
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
    /// scale counts growth events along the ladders (§40.2), which is exactly
    /// what the glossary already calls steps.
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

                    stepsChart(points, bands)
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
        .sheet(item: $historyRecord) { record in
            HistorySheet(record: record)
        }
        .onAppear { refreshCard() }
        .onChange(of: store.records.count) { refreshCard() }
        .onChange(of: store.totalProgress) { refreshCard() }
    }

    private func refreshCard() {
        guard canShare else {
            card = nil
            renderedCardKey = nil
            return
        }
        let key = [store.records.count, store.totalProgress]
        guard key != renderedCardKey else { return }
        renderedCardKey = key
        // `progressCurve()` rather than a second walk of the journal: it is
        // cut at the reset too now, so the milestone card and this one draw
        // the same line — and after a reset neither sends out the old peak
        // under a headline that says 0 (UX review 05.09.2026, finding 36).
        card = ShareCardFactory.card(headline: summaryHeadline, slot: .progress,
                                     steps: store.progressCurve())
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

    /// A gap between two adjacent points wide enough for the silent decay to
    /// have run. Gaps are calendar facts, so the bands are identical in every
    /// projection; only `costSteps` is read per projection.
    struct BreakBand: Identifiable {
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
        let costSteps: Bool
    }

    private func breakBands(_ points: [StepPoint]) -> [BreakBand] {
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
            return BreakBand(id: index, from: before.date, to: after.date,
                             days: days, costSteps: fell)
        }
    }

    /// The band is drawn whatever its width; its label is not. A label wider
    /// than its band would spill over the line it is explaining.
    private func labelFits(_ band: BreakBand, in points: [StepPoint]) -> Bool {
        guard let first = points.first?.date, let last = points.last?.date,
              last > first else { return false }
        // The band is a fraction of the axis; the label is not — it grows
        // with Dynamic Type, so the width it needs has to grow with it.
        //
        // Both fractions moved by a tenth with the label, 0.14 → 0.155 and
        // 0.30 → 0.33, because they were measured against a 10 pt label and
        // it is 11 pt now. The language that decides this is Italian: "14
        // giorni" is 41.6 pt at 10 and 45.2 at 11, against the 42.4 pt that
        // 0.14 of the plot buys on the narrowest screen. Left alone, the one
        // band narrow enough to be interesting would have its label spill
        // over the line it is explaining.
        let needed = typeSize.isAccessibilitySize ? 0.33 : 0.155
        return band.to.timeIntervalSince(band.from) / last.timeIntervalSince(first) >= needed
    }

    /// One line, and it must not repeat the mistake the rating caption made:
    /// the causal half is claimed only where the steps actually fell.
    @ViewBuilder
    private func breakFactLine(_ bands: [BreakBand]) -> some View {
        // The freshest band that actually COST steps, and only failing that
        // the longest. Choosing by length alone put the explanation on a
        // harmless gap while the visible drop beside it went unexplained —
        // and then withheld "The plan met you lower.", the half of the line
        // written so a dip would not read as a failure (UX review,
        // 05.09.2026).
        if let band = bands.last(where: { $0.costSteps })
            ?? bands.max(by: { $0.days < $1.days }) {
            Text(breakFact(band, of: bands.count))
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func breakFact(_ band: BreakBand, of count: Int) -> String {
        var line = String(localized: "A break of \(band.days) days.")
        if band.costSteps { line += " " + String(localized: "The plan met you lower.") }
        if count > 1 { line += " " + String(localized: "Others are marked too.") }
        return line
    }

    // MARK: - Level chart

    struct StepPoint: Identifiable {
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
        /// …and the third way: sets skipped mid-workout land as a cut AFTER
        /// the rating, so even an "on plan" return can lower this point by
        /// itself. Without this the line under the chart credited the break
        /// for a drop the session's own skips caused (UI-truth audit,
        /// 27.08.2026).
        let ownSkips: Bool
    }

    /// Records without a position snapshot are skipped, and so are the ones
    /// written before v3 — their numbers belong to a scale this chart does
    /// not draw. The line starts where the measured ladder does.
    private var chartPoints: [StepPoint] {
        let plotted = store.recordsSinceReset.compactMap { record in
            effectivePattern.map { plot(record, $0) } ?? plotTotal(record)
        }
        return plotted.enumerated().map { index, point in
            StepPoint(id: index, date: point.date, value: point.value,
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
        // All six coordinates: a snapshot replotted without `sub` and `cut`
        // sat up to two steps off the number beside the row (UI-truth audit,
        // 27.08.2026). Older records carry neither key and plot as before.
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

    /// The variation alone. Behind "\(p.displayName) — " the kicker ran out
    /// of width and truncated its TAIL — and the tail is the differentiator
    /// ("on a step", "with a pause"), so two rungs of one ladder drew the
    /// same title in six of the seven languages. The movement is named by the
    /// row that was just tapped and tinted (UX review, 05.09.2026).
    private var chartTitle: String {
        guard let p = effectivePattern else { return String(localized: "total steps") }
        return Library.name(p, store.engineState.position(p).variation)
    }

    /// Both ends are dates, and Swift Charts extracts a mark's labels into
    /// the catalog — so they reuse the key the line marks already use instead
    /// of adding two of their own that no reader will ever see.
    @ChartContentBuilder
    private func breakBandMark(_ band: BreakBand, in points: [StepPoint]) -> some ChartContent {
        RectangleMark(xStart: .value("date", band.from),
                      xEnd: .value("date", band.to))
            .foregroundStyle(Theme.restFill)
            .annotation(position: .overlay, alignment: .center) {
                if labelFits(band, in: points) {
                    // ink, not ink2, because the FILL changed under it. The
                    // band used to be hairline at 55 % over bg, measured only
                    // for the text on it: against the page that ground is
                    // 1.09:1 light and 1.17:1 dark — fainter than the very
                    // hairline this project calls too faint for a 13 pt legend
                    // dot, so the line "Others are marked too." pointed at
                    // marks nobody could see, and a narrow band (the
                    // interesting kind, since its label is dropped) showed
                    // nothing at all. restFill is the token for exactly this
                    // role — quiet but visible, 1.28:1 light and 1.64:1 dark —
                    // and the calendar's rest day already uses it. On it ink2
                    // would read 3.84:1, under the 4.5:1 this label was moved
                    // to ink2 for in the first place; ink gives 14.6:1 light
                    // and 10.8:1 dark (UX review, 05.09.2026).
                    //
                    // 11, not 10: nothing else in the interface is smaller
                    // than 11, and the calendar's weekday header — the other
                    // 11 — is what this matches.
                    //
                    // dredfitFont, unlike the axis labels below: an
                    // annotation IS a View, and `labelFits` reserves a wider
                    // band at accessibility sizes precisely because this
                    // label grows.
                    Text("\(band.days) days")
                        .dredfitFont(11)
                        .foregroundStyle(Theme.ink)
                }
            }
    }

    /// Internal, along with StepPoint and BreakBand: whether the date axis
    /// it configures actually DRAWS every label it asks for is only provable
    /// by rendering this view, which ProgressChartAxisTests does — and a
    /// private view is out of a test's reach.
    @ViewBuilder
    func stepsChart(_ points: [StepPoint], _ bands: [BreakBand]) -> some View {
        if points.count >= 2 {
            Chart {
                // Behind the line and carrying no meaning of its own: the
                // silent decay lands between two entries, so without a band
                // the drop appears inside a workout the athlete completed.
                ForEach(bands) { breakBandMark($0, in: points) }
                ForEach(points) { pt in
                    LineMark(x: .value("date", pt.date), y: .value("steps", pt.value))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    PointMark(x: .value("date", last.date), y: .value("steps", last.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(50)
                }
            }
            .chartYScale(domain: 0...max(points.map(\.value).max() ?? 1, 8))
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            openRecord(near: location, proxy, geo, in: points)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisDates(points)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                                   anchor: Self.xLabelAnchor(index: value.index,
                                                             count: value.count))
                        .font(.caption2)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel()
                        // A text STYLE, not a point size. An axis mark is not
                        // a View, so `dredfitFont` cannot reach it — but what
                        // Charts takes is a `Font`, and `.caption2` scales
                        // with the reader's setting where `.system(size: 10)`
                        // froze both axes of the only chart in the app: a
                        // graph whose scale cannot be read is a picture. ink2,
                        // not ink3: ink3 is a graphics tone (2.35:1 on bg in
                        // light) and these are words (UX review, 05.09.2026).
                        .font(.caption2)
                        .foregroundStyle(Theme.ink2)
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

    /// The chart is where "why did it drop" gets asked, and until now it had
    /// no gesture at all: the only door into a session was its circle in the
    /// calendar grid, three taps of "‹" away for a workout three months back.
    /// The band and the line under it explain a break; a drop the athlete's
    /// own answer caused has no prose anywhere, and only the record can
    /// answer it (UX review, 05.09.2026).
    ///
    /// Nearest point in x rather than a hit box on the mark: the line is 2 pt
    /// wide and dates crowd towards the right of a long history.
    private func openRecord(near location: CGPoint, _ proxy: ChartProxy,
                            _ geo: GeometryProxy, in points: [StepPoint]) {
        guard let plot = proxy.plotFrame else { return }
        let x = location.x - geo[plot].origin.x
        guard let tapped = proxy.value(atX: x, as: Date.self) else { return }
        let nearest = points.min {
            abs($0.date.timeIntervalSince(tapped)) < abs($1.date.timeIntervalSince(tapped))
        }
        guard let nearest else { return }
        historyRecord = store.record(on: nearest.date)
    }

    // MARK: - Per-pattern progress bar

    /// What the ladder promises next. Below the top variation the ceiling of
    /// the current one is where §40.4 starts offering a PROBE — the only door
    /// into the next movement — so that is what the countdown counts to. On
    /// the top variation the same ceiling buys a set instead (§40.5), and at
    /// 5×15 there is nothing left to promise.
    private enum NextMilestone {
        case probe(in: Int)
        case set(in: Int)
        case ceiling
    }

    /// Distance on the row's own scale to the MILESTONE, not to the ceiling:
    /// the ceiling costs `steps`, the crossing — the probe, or the band
    /// transition — is one more point, and every set taken off comes back
    /// first (§37.6), so it is on the path too. Counting to the ceiling alone
    /// put the label one point short of the tick the bar draws for the same
    /// milestone (UI-truth audit, 27.08.2026).
    private func nextMilestone(_ p: Pattern) -> NextMilestone {
        let position = store.engineState.position(p)
        let steps = Engine.stepsToVariationCeiling(store.engineState, p) + position.cut + 1
        guard position.variation == Library.count(p) else { return .probe(in: steps) }
        guard position.sets < EngineConfig.setsMax else { return .ceiling }
        return .set(in: steps)
    }

    private func progressRow(_ p: Pattern) -> some View {
        let steps = Engine.progress(store.engineState, p)
        let position = store.engineState.position(p)
        let variation = Library.name(p, position.variation)
        let total = Library.count(p)
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
                    selectedDetail(p, variation, position, of: total)
                        .dredfitFont(11)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        // 0.85, not 0.7: at the old floor this line rendered
                        // at 7.7 pt AND still lost its tail, and the tail is
                        // the dose — the one number no other part of this
                        // screen carries (UX review, 05.09.2026).
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
    /// move, so at AX3 and up the name was cut to a few letters and a
    /// two-digit step count was truncated inside its column; at accessibility
    /// sizes the bar drops under the pair instead, which is the move `statRow`
    /// above already makes (UX review, 05.09.2026).
    @ViewBuilder
    private func rowHead(_ p: Pattern, steps: Int, selected: Bool) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    patternName(p)
                    Spacer(minLength: 8)
                    stepsNumber(steps)
                    disclosure(selected)
                }
                progressBar(p, steps: steps)
            }
        } else {
            HStack(spacing: 12) {
                // Wide enough for "Горизонтальный жим" on one line: at
                // 116 the long names wrapped.
                patternName(p).frame(width: 152, alignment: .leading)
                progressBar(p, steps: steps)
                HStack(spacing: 6) {
                    stepsNumber(steps).frame(width: 44, alignment: .trailing)
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

    private func stepsNumber(_ steps: Int) -> some View {
        Text("\(steps)")
            .dredfitFont(13.5, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The row carried no sign at all that it could be tapped, so the answer
    /// to "what comes next" — which lives inside the opened row and nowhere
    /// else — was reachable only by poking at random (UX review, 05.09.2026).
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
    /// variation name next to the countdown drove this line into its scale
    /// floor and truncated it anyway; the rule that the row above must not
    /// move when a pattern is picked does not reach here, because this line
    /// does not exist until it is (UX review, 05.09.2026).
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

    /// "Bulgarian split squat · 3/6 · 3×11" — the movement, where it stands on
    /// its ladder, and the dose. This is what replaced "level 18": a level
    /// named neither, and §40.2 has no scalar that could.
    private func detailLine(_ variation: String, _ position: Position, of total: Int) -> String {
        "\(variation) · \(position.variation)/\(total) · \(position.sets)×\(position.dose)"
    }

    /// The scale is the pattern's OWN ladder (§40.2), so the ladders no longer
    /// share one denominator: seven variations of squats and four of lunges
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
        // "movement" named the whole ladder everywhere else in the app — the
        // milestone kicker, the plan badge, the explainer's first section —
        // while here it named one rung of it, so "next movement in 4" could
        // be read as a different exercise altogether. And what this counts to
        // is not the change of variation but the PROBE that opens it (§40.4),
        // one event earlier, so the honest words are the glossary's two
        // (UX review, 05.09.2026).
        case .probe(let steps): Text("next variation probe in \(steps)")
        case .set(let steps): Text("+1 set in \(steps)")
        case .ceiling: EmptyView()
        }
    }
}
