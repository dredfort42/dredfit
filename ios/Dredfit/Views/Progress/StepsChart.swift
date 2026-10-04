//
//  The level chart: the line of steps, the bands of the breaks, and the tap
//  that opens the nearest record.
//

import Charts
import SwiftUI
import DredfitCore

/// Internal, along with StepPoint and BreakBand: whether the date axis it
/// configures actually DRAWS every label it asks for is only provable by
/// rendering this view, which ProgressChartAxisTests does — and a private view
/// is out of a test's reach.
struct StepsChart: View {
    /// The label of a break grows with Dynamic Type, so the room it needs does.
    @Environment(\.dynamicTypeSize) private var typeSize
    let points: [StepPoint]
    let bands: [BreakBand]
    /// The date a tap on the chart landed nearest to; the screen knows which
    /// record that is and where to show it.
    let onOpen: (Date) -> Void

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

    var body: some View {
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
                AxisMarks(values: Self.xAxisDates(points)) { value in
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
        onOpen(nearest.date)
    }
}
