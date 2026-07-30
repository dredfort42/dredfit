//
//  ShareCard.swift
//  Dredfit
//
//  The one image the app ever produces for other people to see.
//  Rendered locally with ImageRenderer, 1080×1350 (4:5), and handed to the
//  system share sheet as a file. Nothing leaves the device on its own.
//
//  What it deliberately never carries: body metrics, weight, photos, a name,
//  a streak, or anything that turns a workout into a scoreboard. A milestone
//  line, a date, the wordmark — and the level curve, drawn exactly as the
//  Progress screen draws it, because it is the same fact and not a new one.
//

import SwiftUI
import UIKit
import DredfitCore

struct ShareCard: View {
    let headline: String
    let date: Date
    /// Total level after each session, oldest first. Fewer than two points
    /// draws nothing: one workout is a dot, not a history.
    let levels: [Int]
    /// The jubilee's "then → now" lines (issue #26) — the one exception to
    /// "a milestone line and nothing else", because it is still the same
    /// fact: what the workouts added up to. Nil on every other card.
    var subline: String?

    static let size = CGSize(width: 1080, height: 1350)

    /// Space between the curve and the footer.
    static let curveGap: CGFloat = 56

    /// Vertical room between the accent rule and the footer: everything the
    /// headline, the date and the curve have to share.
    static let contentBudget: CGFloat = 940

    /// How tall the headline actually renders in the card's own column.
    /// Measured rather than guessed from a character count: the same 89
    /// characters are four lines of English and seven of Russian, and the
    /// curve may only ever have what the words leave behind.
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

    /// How tall the subline renders — measured like the headline, at its own
    /// type size, so the curve budget below stays honest.
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

    /// The curve takes what the headline (and the jubilee subline, when there
    /// is one) leaves, capped so it never becomes the point of the card — and
    /// gives up its place entirely when what is left is too thin to read as a
    /// line. A calibration workout tiering up on seven patterns is the story;
    /// the card drops the graphic rather than push its own footer off the edge.
    static func curveHeight(for headline: String, subline: String? = nil) -> CGFloat {
        let free = contentBudget - headlineHeight(for: headline)
            - sublineHeight(for: subline) - curveGap
        return free < 140 ? 0 : min(300, free)
    }

    /// The headline steps down as it grows. One unlock is a poster line; three
    /// at once is a list, and it still has to fit between the accent rule and
    /// the date — the card has ~940 pt of vertical room for it. Thresholds are
    /// in characters so a long Russian name lands in the same step as the
    /// English one it translates.
    static func headlineSize(for headline: String) -> CGFloat {
        switch headline.count {
        case ..<90:  return 92
        case ..<150: return 70
        case ..<220: return 54
        default:     return 44
        }
    }

    /// Fixed point sizes on purpose — this is an image of a known pixel size,
    /// not a screen. Dynamic Type must not reflow what other people receive,
    /// so `dredfitFont` is intentionally not used here.
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
                // −2.5 at the full 92 pt, proportional below it.
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
                    // Out past the card's own padding: the curve reads as the
                    // ground the card sits on, not as a chart pasted onto it.
                    .padding(.horizontal, -88)
                    .padding(.bottom, Self.curveGap)
            }

            // dredfit.com is the domain we actually own — a card that goes
            // out to other people must not point anywhere else.
            Text(verbatim: "dredfit.com")
                .font(.system(size: 34))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(88)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background(Theme.ink)
    }
}

// MARK: - The curve

/// The total-level history, drawn the way the Progress screen draws it and
/// no other way: an accent line of straight segments, a dot on the latest
/// session, and a scale that starts at zero. No fill and no shading — the app
/// does not own a single gradient, and the card is not the place to invent one.
private struct LevelCurve: View {
    let values: [Int]

    /// Keeps the stroke and the end dot off the edges they would clip against.
    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let pts = points(in: proxy.size)
            ZStack(alignment: .topLeading) {
                line(pts)
                    // 6, not the chart's 2: the card is 1080 wide where the
                    // screen is ~390, so this is the same line at this size.
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

    /// Zero-based, as `chartYScale(domain: 0...max)` is on Progress. Scaling
    /// from the lowest session instead would turn a quiet fortnight into a
    /// cliff — the same numbers, told as a bigger story than they are.
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

    /// The headline for a milestone, in the share card's voice.
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

    /// The headline for everything one workout earned.
    ///
    /// A session can unlock several variations at once — calibration routinely
    /// hands out three or four — so every unlocked one is named. Taking only
    /// the first read, to the person sharing it, as if the rest had not
    /// happened. With no unlock at all the first milestone still speaks for
    /// the card: a set band or a jubilee is one fact, not a list.
    static func headline(for milestones: [Milestone]) -> String {
        let unlocked: [String] = milestones.compactMap { milestone in
            guard case .tierUp(_, _, let exercise) = milestone else { return nil }
            return exercise
        }
        guard !unlocked.isEmpty else {
            return milestones.first.map(headline(for:)) ?? ""
        }
        // Narrow: commas only. The wide form ("A, B and C") spends the card's
        // biggest type on a conjunction.
        let list = unlocked.formatted(.list(type: .and, width: .narrow))
        // Same key as the single-unlock line — the list goes where the one
        // name used to, so every translation already covers it.
        return String(localized: "Unlocked: \(list)")
    }

    /// The Progress-tab summary: totals only, no per-exercise detail.
    ///
    /// Composed from two strings on purpose. As one string it would need a
    /// nested plural substitution (Russian inflects "workouts" but not the
    /// level); as two, the workout count reuses the catalog's existing
    /// single-argument plural and the level is a plain number.
    ///
    /// "level", not "total level": the same one word the Progress header uses
    /// beside the number, so the card says what the screen says.
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
        // The card is already specified in final pixels, so scale stays at 1
        // — anything else would silently produce a 2160×2700 image.
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    /// Where a card is written, so the two sources never overwrite each
    /// other's file while a share sheet is open on it.
    enum Slot: String {
        case milestone = "dredfit-milestone"
        case progress = "dredfit-progress"
    }

    /// Writes the card where `ShareLink` can pick it up as a real PNG file.
    /// One fixed name per slot: cards are regenerated freely, and the
    /// temporary directory never accumulates them.
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
