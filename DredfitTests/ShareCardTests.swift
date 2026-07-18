//
//  ShareCardTests.swift
//  DredfitTests
//
//  The card is the only artefact that leaves the device, so its size and
//  its wording are both worth pinning down.
//

import XCTest
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

    func testSummaryHeadlineCarriesOnlyTotals() {
        let headline = ShareCardFactory.summaryHeadline(workouts: 42, totalLevel: 137)
        XCTAssertEqual(headline, "42 workouts · total level 137")
    }
}
