import XCTest
import SwiftUI
import DredfitCore
@testable import Dredfit

@MainActor
final class ShareCardTests: XCTestCase {

    func testCardRendersAtTheSpecifiedPixelSize() throws {
        let data = try XCTUnwrap(ShareCardFactory.png(headline: "Unlocked: Pistol squat"),
                                 "the renderer produced nothing")
        let image = try XCTUnwrap(UIImage(data: data))
        // 4:5 at the size the spec calls for — not a scaled multiple of it.
        XCTAssertEqual(image.size.width, 1080)
        XCTAssertEqual(image.size.height, 1350)
        XCTAssertEqual(image.scale, 1, "scale must stay 1 or the PNG is 2160×2700")
    }

    func testCardIsWrittenAsAPNGFile() throws {
        let url = try XCTUnwrap(ShareCardFactory.fileURL(headline: "Workout #50",
                                                         slot: .milestone))
        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
        // PNG magic number — proof it is really a PNG, not just named one.
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testTheTwoSlotsDoNotShareAFile() throws {
        let milestone = try XCTUnwrap(ShareCardFactory.fileURL(headline: "Workout #50",
                                                               slot: .milestone))
        let progress = try XCTUnwrap(ShareCardFactory.fileURL(headline: "12 workouts",
                                                              slot: .progress))
        XCTAssertNotEqual(milestone, progress,
                          "one file for both would let a new card overwrite an open share")
    }

    // MARK: - Scheme pinning

    /// The card is an exported graphic: now that the palette is adaptive,
    /// the viewer's scheme must not leak into what other people receive.
    /// The card pins its own environment, so even a dark render is light.
    func testACardRenderedInDarkSchemeIsPixelIdenticalToLight() throws {
        let card = ShareCard(headline: "Workout #50", date: Self.pinned,
                             levels: [12, 18, 26])
        let dark = try XCTUnwrap(png(of: card.environment(\.colorScheme, .dark)))
        let light = try XCTUnwrap(png(of: card.environment(\.colorScheme, .light)))
        XCTAssertEqual(dark, light,
                       "the exported card must not follow the viewer's scheme")
    }

    /// The factory path, same scale and PNG encoding as ShareCardFactory.
    private func png(of view: some View) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    // MARK: - The level curve

    /// A fixed date so two renders differ only by the curve, never by the
    /// line under the headline.
    private static let pinned = Date(timeIntervalSince1970: 1_785_000_000)

    func testOneSessionIsNotYetACurve() throws {
        let none = try XCTUnwrap(ShareCardFactory.png(headline: "Workout #1",
                                                      date: Self.pinned))
        let one = try XCTUnwrap(ShareCardFactory.png(headline: "Workout #1",
                                                     date: Self.pinned, levels: [12]))
        XCTAssertEqual(none, one, "a single session is a dot, not a history")
        let two = try XCTUnwrap(ShareCardFactory.png(headline: "Workout #1",
                                                     date: Self.pinned, levels: [12, 26]))
        XCTAssertNotEqual(none, two, "two sessions are a curve and must show up")
    }

    func testAFlatHistoryStillRenders() throws {
        let zeros = try XCTUnwrap(ShareCardFactory.png(headline: "Workout #2",
                                                       levels: [0, 0, 0]))
        XCTAssertFalse(zeros.isEmpty)
        let data = try XCTUnwrap(ShareCardFactory.png(headline: "Now 4 sets",
                                                      levels: [96, 96, 96, 96]))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size.width, 1080)
        XCTAssertEqual(image.size.height, 1350)
    }

    /// The curve is whatever the words did not need — never the other way
    func testTheCurveOnlyTakesWhatTheHeadlineLeaves() {
        XCTAssertGreaterThan(ShareCard.curveHeight(for: "Unlocked: Pistol squat"), 0)
        // 89 characters still take the full 92 pt, and at that size they fill
        // seven lines — there is nothing left to draw in.
        let tall = headline(ofLength: 89)
        XCTAssertEqual(ShareCard.curveHeight(for: tall), 0,
                       "a headline that fills the card must leave the curve nothing")
        XCTAssertLessThanOrEqual(claimed(tall), ShareCard.contentBudget)
    }

    // MARK: - Wording

    func testHeadlineForEachMilestoneKind() {
        XCTAssertEqual(
            ShareCardFactory.headline(for: .tierUp(pattern: .squat, tier: 3,
                                                   exercise: "Pistol squat")),
            "Unlocked: Pistol squat")
        XCTAssertEqual(
            ShareCardFactory.headline(for: .jubilee(workouts: 100)),
            "Workout #100")
        XCTAssertEqual(
            ShareCardFactory.headline(for: .setBand(pattern: .pushH, sets: 4,
                                                    exercise: "Push-up")),
            "Now 4 sets")
    }

    func testHeadlineNamesEveryUnlockedVariation() {
        let headline = ShareCardFactory.headline(for: [
            .tierUp(pattern: .lunge, tier: 2, exercise: "Bulgarian split squat"),
            .tierUp(pattern: .pushH, tier: 2, exercise: "Push-up"),
            .tierUp(pattern: .hinge, tier: 2, exercise: "Single-leg glute bridge"),
        ])
        XCTAssertEqual(headline,
                       "Unlocked: Bulgarian split squat, Push-up, Single-leg glute bridge",
                       "sharing three unlocks must not send only the first")
    }

    func testHeadlineForASingleUnlockIsUnchangedByTheList() {
        XCTAssertEqual(
            ShareCardFactory.headline(for: [.tierUp(pattern: .squat, tier: 3,
                                                    exercise: "Pistol squat")]),
            "Unlocked: Pistol squat")
    }

    func testHeadlineFallsBackToTheFirstMilestoneWhenNothingUnlocked() {
        // A set band and a jubilee are each one fact — there is no list to make.
        XCTAssertEqual(
            ShareCardFactory.headline(for: [.setBand(pattern: .pushH, sets: 4,
                                                     exercise: "Push-up"),
                                            .jubilee(workouts: 50)]),
            "Now 4 sets")
    }

    func testUnlocksLeadTheHeadlineOverSetBandsAndJubilees() {
        let headline = ShareCardFactory.headline(for: [
            .tierUp(pattern: .squat, tier: 2, exercise: "Split squat"),
            .setBand(pattern: .pushH, sets: 4, exercise: "Push-up"),
            .jubilee(workouts: 50),
        ])
        XCTAssertEqual(headline, "Unlocked: Split squat")
    }

    // MARK: - Fit

    /// What the headline and the curve claim between them. Measured here
    /// independently of the card's own arithmetic — the point is to catch the
    /// two disagreeing, which is exactly how the footer would fall off.
    private func claimed(_ headline: String) -> CGFloat {
        let curve = ShareCard.curveHeight(for: headline)
        return headlineHeight(headline) + (curve > 0 ? curve + ShareCard.curveGap : 0)
    }

    /// Height the headline actually occupies inside the card's text column,
    /// measured with the font the card renders it in. Tracking is negative,
    /// so this is the pessimistic reading.
    private func headlineHeight(_ headline: String) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        let font = UIFont.systemFont(ofSize: ShareCard.headlineSize(for: headline),
                                     weight: .heavy)
        return (headline as NSString).boundingRect(
            with: CGSize(width: ShareCard.size.width - 176,   // the 88 pt gutters
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil).height
    }

    func testASingleUnlockKeepsTheFullSizeHeadline() {
        XCTAssertEqual(ShareCard.headlineSize(for: "Unlocked: Pistol squat"), 92)
        XCTAssertEqual(ShareCard.headlineSize(for: "Workout #100"), 92)
    }

    func testEveryUnlockAWorkoutCanEarnStillFitsTheCard() {
        // Worst case: a calibration workout tiering up on all seven patterns,
        // with the longest names the library holds — and in Russian, where the
        // same line is roughly half again as long.
        let names = ["Болгарский сплит-присед", "Отжимание с ногами на возвышении",
                     "Ягодичный мостик на одной ноге", "Подтягивание австралийское",
                     "Отжимание в стойке у стены", "Приседание на одной ноге",
                     "Планка с подъемом руки и ноги"]
        let headline = "Разблокировано: " + names.joined(separator: ", ")
        XCTAssertLessThanOrEqual(claimed(headline), ShareCard.contentBudget,
                                 "the headline would push the date off the card")
    }

    /// A headline of a given length built from real exercise names, English
    /// and Russian both. Filler of repeated wide glyphs would measure half
    /// again as wide as anything the library can actually produce and would
    /// fail the budget on text the card will never be handed.
    private func headline(ofLength length: Int) -> String {
        let names = ["Bulgarian split squat", "Отжимание с ногами на возвышении",
                     "Single-leg glute bridge", "Приседание на одной ноге"]
        var text = "Unlocked: "
        var index = 0
        while text.count < length {
            text += names[index % names.count] + ", "
            index += 1
        }
        return String(text.prefix(length))
    }

    func testHeadlineAtEveryStepBoundaryFits() {
        // The size steps down at 90, 150 and 220 characters, so the tallest
        // headline in each step is the one just under its ceiling.
        for length in [89, 149, 219, 300] {
            let text = headline(ofLength: length)
            XCTAssertLessThanOrEqual(claimed(text), ShareCard.contentBudget,
                                     "\(length) characters overflow the card")
        }
    }

    func testSummaryHeadlineCarriesOnlyTotals() {
        let headline = ShareCardFactory.summaryHeadline(workouts: 42, totalLevel: 137)
        // "level", the same word the Progress header uses beside the number.
        XCTAssertEqual(headline, "42 workouts · level 137")
    }
}
