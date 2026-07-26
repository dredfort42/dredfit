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
//  line, a date, the wordmark — and the level curve, which is the same fact
//  the Progress screen already draws, not a new one about the person.
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

    static let size = CGSize(width: 1080, height: 1350)

    /// The ground. Flat ink read as a slab; this keeps the same near-black
    /// but lets it warm towards the accent in one corner.
    private static let groundTop = Color(red: 0x1A / 255, green: 0x16 / 255, blue: 0x13 / 255)
    private static let groundBottom = Color(red: 0x0C / 255, green: 0x0D / 255, blue: 0x0F / 255)

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

    /// The curve takes what the headline leaves, capped so it never becomes
    /// the point of the card — and gives up its place entirely when what is
    /// left is too thin to read as a line. A calibration workout tiering up
    /// on seven patterns is the story; the card drops the graphic rather than
    /// push its own footer off the edge.
    static func curveHeight(for headline: String) -> CGFloat {
        let free = contentBudget - headlineHeight(for: headline) - curveGap
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

            Spacer(minLength: 0)

            let curveHeight = Self.curveHeight(for: headline)
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
        .background {
            ZStack {
                LinearGradient(colors: [Self.groundTop, Theme.ink, Self.groundBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Theme.accent.opacity(0.20), .clear],
                               center: UnitPoint(x: 0.88, y: 0.06),
                               startRadius: 0, endRadius: 760)
            }
        }
    }
}

// MARK: - The curve

/// The total-level history, drawn the way the Progress screen draws it:
/// straight segments between sessions, no smoothing invented between them.
private struct LevelCurve: View {
    let values: [Int]

    /// Keeps the stroke and the end dot off the edges they would clip against.
    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let pts = points(in: proxy.size)
            ZStack(alignment: .topLeading) {
                area(pts, in: proxy.size)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.26), .clear],
                                         startPoint: .top, endPoint: .bottom))
                line(pts)
                    .stroke(Theme.accent,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 22, height: 22)
                        .position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let inset = Self.inset
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        return values.enumerated().map { index, value in
            let x = inset + width * CGFloat(index) / CGFloat(values.count - 1)
            // A deload week can flatten the whole span; centre it rather than
            // dividing by zero or pinning the line to the floor.
            let t = hi == lo ? 0.5 : CGFloat(value - lo) / CGFloat(hi - lo)
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

    /// The fill runs to the card's own edges even though the line stops short
    /// of them — inset on both would leave a hard vertical seam where the
    /// shading ends, and that reads as a border nobody drew.
    private func area(_ pts: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = pts.first, let last = pts.last else { return }
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: first.y))
            for point in pts { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: size.width, y: last.y))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
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
    static func png(headline: String, date: Date = .now, levels: [Int] = []) -> Data? {
        let renderer = ImageRenderer(
            content: ShareCard(headline: headline, date: date, levels: levels))
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
                        levels: [Int] = []) -> URL? {
        guard let data = png(headline: headline, date: date, levels: levels) else { return nil }
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
