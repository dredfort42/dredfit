import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class RetrospectiveTests: XCTestCase {

    private func record(daysAgo: Int,
                        positionsAfter: [Pattern: RecordedPosition]?) -> WorkoutRecord {
        WorkoutRecord(
            sessionNumber: 1,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            result: .plan,
            totalProgressAfter: positionsAfter == nil ? nil : 0,
            positionsAfter: positionsAfter)
    }

    /// A flat baseline for every rotation pattern (no pull_bar by default —
    /// most journals predate the bar module). `variation` and `dose` are what
    /// a position IS now: a scalar could not name one, because the measure of
    /// §40.2 has no inverse.
    private func base(variation: Int = 1, atCeiling: Bool = false) -> [Pattern: RecordedPosition] {
        Dictionary(uniqueKeysWithValues: Pattern.ordered.map { p in
            let grid = Dose.grid(Library.unit(p, variation))
            return (p, RecordedPosition(variation: variation, sets: 3,
                                        dose: atCeiling ? grid.max : grid.min))
        })
    }

    private func at(_ p: Pattern, variation: Int, dose: Int) -> RecordedPosition {
        RecordedPosition(variation: variation, sets: 3, dose: dose)
    }

    // MARK: - Movement choice

    func testPicksTheLargestGain() throws {
        var current = base(variation: 1)
        current[.squat] = at(.squat, variation: 1, dose: 6)          // a few rungs
        current[.hinge] = at(.hinge, variation: 3, dose: 8)          // two variations up
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: base())],
            current: current))
        XCTAssertTrue(retro.nowLine.contains(Library.name(.hinge, 3)),
                      "\(retro.nowLine) should name the biggest gain (hinge)")
        XCTAssertTrue(retro.nowLine.contains("3×8"))
    }

    func testTieBreaksInRotationOrder() throws {
        // squat and calf both gain the same number of rungs; squat comes first
        // in Pattern.allCases, which is the order the engine itself walks.
        var current = base()
        current[.squat] = at(.squat, variation: 1, dose: 8)
        current[.calf] = at(.calf, variation: 1, dose: 8)
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: base())],
            current: current))
        XCTAssertTrue(retro.thenLine.contains(Library.name(.squat, 1)),
                      "tie must resolve to the earlier rotation slot")
    }

    /// The "then" line states the movement and the dose the plan actually
    /// asked for back then — not a number re-derived from a measure, which is
    /// the thing v3 cannot do.
    func testThenLineStatesThePositionItWasRecordedAt() throws {
        var start = base()
        start[.pushH] = at(.pushH, variation: 2, dose: 9)
        var current = base()
        current[.pushH] = at(.pushH, variation: 3, dose: 12)
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: start)],
            current: current))
        XCTAssertTrue(retro.thenLine.contains(Library.name(.pushH, 2)),
                      "\(retro.thenLine) must name the movement it was recorded at")
        XCTAssertTrue(retro.thenLine.contains("3×9"),
                      "\(retro.thenLine) must state the dose it was recorded at")
    }

    func testHoldMovementFormatsAsSeconds() throws {
        var current = base()
        current[.coreAntiExt] = at(.coreAntiExt, variation: 2, dose: 30)
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: base())],
            current: current))
        XCTAssertTrue(retro.nowLine.contains("3×30 s"),
                      "\(retro.nowLine) should carry the hold in seconds")
    }

    // MARK: - Degradations

    func testNoSnapshotsMeansNoRetrospective() {
        XCTAssertNil(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: nil)],
            current: base(variation: 2)))
        XCTAssertNil(Retrospective.make(records: [], current: base(variation: 2)))
    }

    func testNoGrowthMeansNoRetrospective() {
        XCTAssertNil(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: base(variation: 2))],
            current: base(variation: 2)),
            "standing still is not a story")
        XCTAssertNil(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: base(variation: 2))],
            current: base(variation: 1)),
            "a net drop must never be celebrated")
    }

    func testBaseIsTheFirstSnapshotNotTheFirstRecord() throws {
        // Record 1 predates the snapshot (nil) — which is also every record
        // written before v3. The base must be record 2, skipped silently.
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 60, positionsAfter: nil),
                      record(daysAgo: 40, positionsAfter: base())],
            current: base(variation: 2)))
        XCTAssertFalse(retro.thenLine.isEmpty)
    }

    func testPullBarAbsentFromBaseIsExcluded() throws {
        // The bar module joined after the first workout: the current positions
        // have pull_bar, the base snapshot does not. Its big gain must not win.
        var current = base()
        current[.pullBar] = at(.pullBar, variation: 5, dose: 10)
        current[.lunge] = at(.lunge, variation: 2, dose: 5)    // the honest winner
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, positionsAfter: base())],
            current: current))
        XCTAssertTrue(retro.thenLine.contains(Library.name(.lunge, 1)),
                      "\(retro.thenLine): a pattern without a base must not compete")
    }

    // MARK: - The since line

    func testSinceLineSwitchesToMonthsAtNineWeeks() throws {
        let atEight = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 8 * 7, positionsAfter: base())],
            current: base(variation: 2)))
        XCTAssertTrue(atEight.sinceLine.contains("8"),
                      "\(atEight.sinceLine) should still count weeks")

        let atNine = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 9 * 7, positionsAfter: base())],
            current: base(variation: 2)))
        XCTAssertTrue(atNine.sinceLine.contains("2"),
                      "\(atNine.sinceLine) should have switched to months")
    }

    // MARK: - The sparse coordinates

    /// The delta that picks the movement is read off ALL SIX coordinates.
    /// On the short `Engine.progress` overload `sub` and `cut` were dropped,
    /// and the chart's `plot` was fixed for exactly that while this was not.
    ///
    /// Growth that happened ENTIRELY in sub-steps measured as zero, no
    /// pattern beat the `> 0` bar, and the whole block vanished for someone
    /// who had in fact grown.
    func testGrowthInSubStepsAloneIsSeen() throws {
        let flat = base(variation: 1)
        var current = flat
        let was = try XCTUnwrap(flat[.squat])
        current[.squat] = RecordedPosition(variation: was.variation, sets: was.sets,
                                           dose: was.dose, sub: 2)
        let retro = try XCTUnwrap(
            Retrospective.make(records: [record(daysAgo: 30, positionsAfter: flat)],
                               current: current),
            "two sub-steps are a gain — the block must not disappear")
        XCTAssertTrue(retro.nowLine.contains(Library.name(.squat, 1)),
                      "\(retro.nowLine): the movement that grew is the one to name")
    }

    /// The other direction of the same coordinate: a `cut` stands one step
    /// BELOW the position it was taken from. A base carrying one has grown by
    /// a step once the cut is gone — dropped, both sides measured the same and
    /// the gain was invisible.
    func testACutOnTheBaseCountsAsGrowthOnceItIsGone() throws {
        var flat = base(variation: 1)
        let was = try XCTUnwrap(flat[.squat])
        flat[.squat] = RecordedPosition(variation: was.variation, sets: was.sets,
                                        dose: was.dose, cut: 1)
        let retro = try XCTUnwrap(
            Retrospective.make(records: [record(daysAgo: 30, positionsAfter: flat)],
                               current: base(variation: 1)),
            "a set that was cut then and is not now is a step gained")
        XCTAssertTrue(retro.nowLine.contains(Library.name(.squat, 1)),
                      "\(retro.nowLine): the movement that grew is the one to name")
    }
}
