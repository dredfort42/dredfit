import XCTest
import SwiftUI
import DredfitCore
@testable import Dredfit

/// The date axis under the level chart, measured in ink.
///
/// `xAxisDates` asks for three dates; whether Swift Charts DRAWS them is a
/// layout fact, and no assertion on the dates themselves can reach it. The
/// shipped screen asked for three and drew two — the label of the last date
/// ran into the trailing y-axis column and Charts dropped it — so the axis
/// ended weeks before the line did on every App Store frame of this screen
/// (2.1.0). Hence a render: this is one of the few facts in the app that only
/// pixels can settle.
@MainActor
final class ProgressChartAxisTests: XCTestCase {

    // The chart at the size the screen gives it: 402 pt of iPhone less the
    // card's two 24 pt gutters, and the height ProgressScreen pins.
    private let width: CGFloat = 354
    private let height: CGFloat = 134
    private let scale: CGFloat = 3

    func testEveryDateTheAxisAsksForIsDrawn() throws {
        let screen = ProgressScreen()
        let points = Self.points(dayOffsets: [0, 20, 40, 62, 95])
        // Pinned, not derived: a "fix" that stops asking for the last date
        // would make the axis honest again by deleting the very information
        // that made the defect visible, and must fail here.
        XCTAssertEqual(screen.xAxisDates(points).count, 3,
                       "first, middle and last is the ask this axis makes")

        let ink = try labelInk(of: screen.stepsChart(points, []))
        XCTAssertEqual(ink.labels.count, screen.xAxisDates(points).count,
                       "the axis asked for \(screen.xAxisDates(points).count) dates and drew "
                       + "\(ink.labels.count): Charts drops a label that does not fit")
        let last = try XCTUnwrap(ink.labels.last)
        XCTAssertLessThanOrEqual(last.upperBound, ink.width - Int(6 * scale),
                                 "the last label must clear the y-axis digits, not overprint them")
    }

    /// Two workouts are the least this chart draws at all, and both of its
    /// ends are labelled — the last one by the same trailing edge.
    func testTheSmallestChartLabelsBothOfItsEnds() throws {
        let screen = ProgressScreen()
        let points = Self.points(dayOffsets: [0, 47])
        XCTAssertEqual(screen.xAxisDates(points).count, 2)
        let ink = try labelInk(of: screen.stepsChart(points, []))
        XCTAssertEqual(ink.labels.count, 2, "a two-point chart labels both ends")
    }

    /// The rule itself, so that "simplifying" it back to one anchor for all
    /// labels fails here as well as in the render: anchoring every label by
    /// its trailing edge pushes the FIRST one off the left edge, where Charts
    /// drops it for the same reason.
    func testOnlyTheLastLabelIsAnchoredByItsTrailingEdge() {
        XCTAssertNil(ProgressScreen.xLabelAnchor(index: 0, count: 3))
        XCTAssertNil(ProgressScreen.xLabelAnchor(index: 1, count: 3))
        XCTAssertEqual(ProgressScreen.xLabelAnchor(index: 2, count: 3), .topTrailing)
        XCTAssertEqual(ProgressScreen.xLabelAnchor(index: 1, count: 2), .topTrailing)
    }

    // MARK: - Ink

    private static func points(dayOffsets: [Int]) -> [ProgressScreen.StepPoint] {
        // A fixed origin: the labels are dates, and a moving "today" would
        // change their width from run to run.
        let origin = Date(timeIntervalSince1970: 1_780_000_000)
        return dayOffsets.enumerated().map { index, day in
            ProgressScreen.StepPoint(id: index,
                                     date: origin.addingTimeInterval(Double(day) * 86_400),
                                     value: 3 + index, result: .plan,
                                     ownNumber: false, ownSkips: false)
        }
    }

    private struct Ink {
        /// Column spans of the date labels, left to right.
        let labels: [ClosedRange<Int>]
        let width: Int
    }

    /// The date labels are the bottom-most ink in the chart, and they are the
    /// only ink in that band: the y-axis digits are centred on their grid
    /// lines, so even the "0" one — which straddles the plot floor — stops
    /// well above where the dates begin.
    private func labelInk(of chart: some View) throws -> Ink {
        let renderer = ImageRenderer(content: chart.frame(width: width, height: height))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.uiImage?.cgImage, "the chart did not render")
        let (w, h) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // The view has no background of its own, so anything drawn is opaque
        // ink and everything else is clear.
        func isInk(_ x: Int, _ y: Int) -> Bool { pixels[(y * w + x) * 4 + 3] > 8 }

        var bottom = -1
        for y in (0..<h).reversed() where (0..<w).contains(where: { isInk($0, y) }) {
            bottom = y
            break
        }
        guard bottom >= 0 else { return Ink(labels: [], width: w) }
        let band = max(0, bottom - Int(11 * scale))
        var columns = Set<Int>()
        for y in band...bottom {
            for x in 0..<w where isInk(x, y) { columns.insert(x) }
        }
        // 8 pt apart or more is a different label: the widest gap inside one
        // — the space in "May 29" — measures 5 pt.
        return Ink(labels: Self.spans(of: columns, apartBy: Int(8 * scale)), width: w)
    }

    private static func spans(of columns: Set<Int>, apartBy gap: Int) -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        var start = -1, previous = -1
        for column in columns.sorted() {
            if start < 0 { start = column } else if column - previous > gap {
                spans.append(start...previous)
                start = column
            }
            previous = column
        }
        if start >= 0 { spans.append(start...previous) }
        return spans
    }
}
