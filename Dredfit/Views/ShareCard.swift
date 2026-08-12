//
//  ShareCard.swift
//  Dredfit
//
//  Rendered locally with ImageRenderer, 1080×1350 (4:5). Nothing leaves the
//  device on its own.
//
//  It deliberately never carries body metrics, weight, photos, a name or a
//  streak — nothing that turns a workout into a scoreboard.
//

import SwiftUI
import UIKit
import DredfitCore

struct ShareCard: View {
    let headline: String
    let date: Date
    /// Oldest first. Fewer than two points draws nothing.
    let levels: [Int]
    /// Nil on every card but the jubilee's.
    var subline: String?

    static let size = CGSize(width: 1080, height: 1350)

    static let curveGap: CGFloat = 56

    /// Vertical room the headline, date and curve share.
    static let contentBudget: CGFloat = 940

    /// Measured rather than guessed from a character count: the same 89
    /// characters are four lines of English and seven of Russian.
    static func headlineHeight(for headline: String) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        let font = UIFont.systemFont(ofSize: headlineSize(for: headline), weight: .heavy)
        return (headline as NSString).boundingRect(
            with: CGSize(width: size.width - 176,   // the 88 pt gutters
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil).height
    }

    /// Measured like the headline, so the curve budget stays honest.
    static func sublineHeight(for subline: String?) -> CGFloat {
        guard let subline else { return 0 }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        let font = UIFont.systemFont(ofSize: 36)
        let height = (subline as NSString).boundingRect(
            with: CGSize(width: size.width - 176,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil).height
        return height + 26   // its own top padding
    }

    /// Takes what the headline and subline leave, and gives up its place
    /// entirely when that is too thin to read as a line — the card drops the
    /// graphic rather than push its footer off the edge.
    static func curveHeight(for headline: String, subline: String? = nil) -> CGFloat {
        let free = contentBudget - headlineHeight(for: headline)
            - sublineHeight(for: subline) - curveGap
        return free < 140 ? 0 : min(300, free)
    }

    /// Thresholds are in characters so a long Russian name lands in the same
    /// step as the English one it translates.
    static func headlineSize(for headline: String) -> CGFloat {
        switch headline.count {
        case ..<90:  return 92
        case ..<150: return 70
        case ..<220: return 54
        default:     return 44
        }
    }

    /// Fixed point sizes: this is an image of a known pixel size, not a
    /// screen. Dynamic Type must not reflow what other people receive, so
    /// `dredfitFont` is intentionally not used here.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Dredfit")
                .font(.system(size: 46, weight: .heavy))
                .tracking(-1)
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Rectangle()
                .fill(Theme.accent)
                .frame(width: 132, height: 8)
                .padding(.bottom, 44)

            Text(headline)
                .font(.system(size: Self.headlineSize(for: headline), weight: .heavy))
                .tracking(Self.headlineSize(for: headline) * -0.027)
                .lineSpacing(6)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(date.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(size: 38))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.top, 34)

            if let subline {
                Text(subline)
                    .font(.system(size: 36))
                    .lineSpacing(5)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 26)
            }

            Spacer(minLength: 0)

            let curveHeight = Self.curveHeight(for: headline, subline: subline)
            if levels.count > 1 && curveHeight > 0 {
                LevelCurve(values: levels)
                    .frame(height: curveHeight)
                    .padding(.horizontal, -88)
                    .padding(.bottom, Self.curveGap)
            }

            // The domain we actually own — a card that goes out to other
            // people must not point anywhere else.
            Text(verbatim: "dredfit.com")
                .font(.system(size: 34))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(88)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background(Theme.ink)
        // An exported image, not a screen: the palette is adaptive now, but
        // what leaves the device is light for everyone. The innermost
        // environment wins, so a render wrapped in dark stays identical.
        .environment(\.colorScheme, .light)
    }
}

// MARK: - The curve

/// Drawn the way the Progress screen draws it and no other way.
private struct LevelCurve: View {
    let values: [Int]

    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let pts = points(in: proxy.size)
            ZStack(alignment: .topLeading) {
                line(pts)
                    // 6, not the chart's 2: the card is 1080 wide where the
                    // screen is ~390 — the same line at this size.
                    .stroke(Theme.accent,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 22, height: 22)
                        .position(last)
                }
            }
        }
    }

    /// Zero-based, as `chartYScale(domain: 0...max)` is on Progress: scaling
    /// from the lowest session would turn a quiet fortnight into a cliff.
    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let peak = values.max() else { return [] }
        let inset = Self.inset
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        return values.enumerated().map { index, value in
            let x = inset + width * CGFloat(index) / CGFloat(values.count - 1)
            let t = peak <= 0 ? 0 : CGFloat(value) / CGFloat(peak)
            return CGPoint(x: x, y: inset + height * (1 - t))
        }
    }

    private func line(_ pts: [CGPoint]) -> Path {
        Path { path in
            guard let first = pts.first else { return }
            path.move(to: first)
            for point in pts.dropFirst() { path.addLine(to: point) }
        }
    }
}

// MARK: - Rendering

enum ShareCardFactory {

    static func headline(for milestone: Milestone) -> String {
        switch milestone {
        case .tierUp(_, _, let exercise):
            return String(localized: "Unlocked: \(exercise)")
        case .setBand(_, let sets, _):
            return String(localized: "Now \(sets) sets")
        case .jubilee(let workouts):
            return String(localized: "Workout #\(workouts)")
        }
    }

    /// Every unlocked variation is named — a session can unlock several at
    /// once. With no unlock at all the first milestone speaks for the card.
    static func headline(for milestones: [Milestone]) -> String {
        let unlocked: [String] = milestones.compactMap { milestone in
            guard case .tierUp(_, _, let exercise) = milestone else { return nil }
            return exercise
        }
        guard !unlocked.isEmpty else {
            return milestones.first.map(headline(for:)) ?? ""
        }
        let list = unlocked.formatted(.list(type: .and, width: .narrow))
        // Same key as the single-unlock line, so every translation covers it.
        return String(localized: "Unlocked: \(list)")
    }

    /// Two strings on purpose: as one it would need a nested plural
    /// substitution (Russian inflects "workouts" but not the level).
    static func summaryHeadline(workouts: Int, totalLevel: Int) -> String {
        String(localized: "\(workouts) workouts")
            + " · "
            + String(localized: "level \(totalLevel)")
    }

    @MainActor
    static func png(headline: String, date: Date = .now,
                    subline: String? = nil, levels: [Int] = []) -> Data? {
        let renderer = ImageRenderer(
            content: ShareCard(headline: headline, date: date,
                               levels: levels, subline: subline))
        // Specified in final pixels, so scale stays at 1 — anything else
        // silently produces a 2160×2700 image.
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    /// So the two sources never overwrite each other's file while a share
    /// sheet is open on it.
    enum Slot: String {
        case milestone = "dredfit-milestone"
        case progress = "dredfit-progress"
    }

    /// One fixed name per slot, so the temporary directory never accumulates.
    @MainActor
    static func fileURL(headline: String, slot: Slot, date: Date = .now,
                        subline: String? = nil, levels: [Int] = []) -> URL? {
        guard let data = png(headline: headline, date: date,
                             subline: subline, levels: levels) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(slot.rawValue).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
