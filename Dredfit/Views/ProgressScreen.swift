//
//  ProgressScreen.swift
//  Dredfit
//
//  Total level, a line across sessions, per-pattern level bars.
//  One data color (accent) — one metric in two projections.
//

import SwiftUI
import DredfitCore

struct ProgressScreen: View {
    @Environment(AppStore.self) private var store

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

            sparkline
                .frame(height: 72)
                .padding(.top, 16)

            VStack(spacing: 0) {
                ForEach(Pattern.ordered, id: \.self) { p in
                    levelRow(p)
                }
                // v2.2: the vertical branch appears once it exists — with the
                // bar enabled or with progress already earned on it.
                if store.engineState.hasBar || (store.engineState.levels[.pullBar] ?? 0) > 0 {
                    levelRow(.pullBar)
                }
            }
            .padding(.top, 22)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Total-level line across sessions

    private var sparkline: some View {
        let points = store.records.map(\.totalLevelAfter)
        return Canvas { ctx, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 1))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            ctx.stroke(base, with: .color(Theme.hairline), lineWidth: 1)

            guard points.count >= 2 else { return }
            let maxV = max(points.max() ?? 1, 1)
            let stepX = size.width / CGFloat(points.count - 1)

            var line = Path()
            for (i, v) in points.enumerated() {
                let pt = CGPoint(
                    x: CGFloat(i) * stepX,
                    y: size.height - 6 - (size.height - 12) * CGFloat(v) / CGFloat(maxV))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if let lastV = points.last {
                let pt = CGPoint(
                    x: CGFloat(points.count - 1) * stepX,
                    y: size.height - 6 - (size.height - 12) * CGFloat(lastV) / CGFloat(maxV))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                         with: .color(Theme.accent))
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                           with: .color(.white), lineWidth: 2)
            }
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
