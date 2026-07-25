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
//  line, a date, and the wordmark.
//

import SwiftUI
import DredfitCore

struct ShareCard: View {
    let headline: String
    let date: Date

    static let size = CGSize(width: 1080, height: 1350)

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
    static func png(headline: String, date: Date = .now) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(headline: headline, date: date))
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
    static func fileURL(headline: String, slot: Slot, date: Date = .now) -> URL? {
        guard let data = png(headline: headline, date: date) else { return nil }
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
