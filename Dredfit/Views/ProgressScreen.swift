//
//  ProgressScreen.swift
//  Dredfit
//
//  Total level, the week summary, a level chart over time (v1.3) and
//  per-pattern level bars. One data color (accent) — one metric in
//  several projections.
//

import Charts
import SwiftUI
import DredfitCore

struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    @State private var chartPattern: Pattern?   // nil = the total-level view

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: String(localized: "Progress"))
                .padding(.top, 18)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(store.totalLevel)")
                    .font(.system(size: 56, weight: .heavy))
                    .tracking(-2)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text("total level")
                    Text("\(store.records.count) workouts")
                }
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 12)

            weekSummaryLine
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    patternChips
                        .padding(.top, 16)

                    levelChart
                        .frame(height: 120)
                        .padding(.top, 12)

                    VStack(spacing: 0) {
                        ForEach(Pattern.ordered, id: \.self) { p in
                            levelRow(p)
                        }
                        // v2.2: the vertical branch appears once it exists — with the
                        // bar enabled or with progress already earned on it.
                        if barBranchExists {
                            levelRow(.pullBar)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 24)
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

    // MARK: - Week summary (v1.3)

    /// "This week · 2 workouts · +6 levels". Calm: no streaks, no guilt —
    /// a deload week honestly shows a minus.
    private var weekSummaryLine: some View {
        let week = store.weekSummary()
        let sign = week.levelsDelta >= 0 ? "+" : ""
        return (Text("This week")
            + Text(" · ")
            + Text("\(week.workouts) workouts")
            + Text(" · \(sign)")
            + Text("\(week.levelsDelta) levels"))
            .font(.system(size: 13.5))
            .monospacedDigit()
            .foregroundStyle(Theme.ink2)
    }

    // MARK: - Level chart (v1.3)

    private struct LevelPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Int
    }

    /// The selected projection: the total level for "All", or a pattern's
    /// level from the journal snapshots. Records made before snapshots
    /// existed (v1.0) are simply skipped — the line starts where history does.
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

    private var patternChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil)
                ForEach(Pattern.ordered, id: \.self) { p in
                    chip(p)
                }
                if barBranchExists {
                    chip(.pullBar)
                }
            }
        }
    }

    private func chip(_ p: Pattern?) -> some View {
        let selected = effectivePattern == p
        return Button {
            chartPattern = p
        } label: {
            Text(p?.displayName ?? String(localized: "All"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selected ? Theme.accentSoft : Color.white)
                        // strokeBorder insets the line inside the shape so its
                        // outer half is never clipped on the straight edges.
                        .overlay(Capsule().strokeBorder(selected ? Theme.accent : Theme.hairline,
                                                        lineWidth: 1.5))
                )
                .foregroundStyle(selected ? Theme.accent : Theme.ink2)
        }
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
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.hairline, lineWidth: 1.5)
                .overlay(
                    Text("The chart will appear after a couple of workouts")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                )
        }
    }

    // MARK: - Pattern level bar

    private func levelRow(_ p: Pattern) -> some View {
        let level = store.engineState.levels[p] ?? 0
        return HStack(spacing: 12) {
            Text(p.displayName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 118, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(geo.size.width
                            * CGFloat(level) / CGFloat(EngineConfig.levelMax), level > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
            Text("\(level)")
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 9.5)
    }
}
