//
//  ShareCard.swift
//  Dredfit
//
//  The one image the app ever produces for other people to see (v1.4).
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
                .font(.system(size: 92, weight: .heavy))
                .tracking(-2.5)
                .lineSpacing(6)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(date.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(size: 38))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.top, 34)

            Spacer(minLength: 0)

            // The real domain. The task sheet said "dredfit.app"; the site
            // that exists is dredfit.com, and a card that goes out to other
            // people must not point at a domain we do not own.
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

    /// The Progress-tab summary: totals only, no per-exercise detail.
    ///
    /// Composed from two strings on purpose. As one string it would need a
    /// nested plural substitution (Russian inflects "workouts" but not the
    /// level); as two, the workout count reuses the catalog's existing
    /// single-argument plural and the level is a plain number.
    static func summaryHeadline(workouts: Int, totalLevel: Int) -> String {
        String(localized: "\(workouts) workouts")
            + " · "
            + String(localized: "total level \(totalLevel)")
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
