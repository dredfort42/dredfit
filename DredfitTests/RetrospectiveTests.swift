//
//  RetrospectiveTests.swift
//  DredfitTests
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class RetrospectiveTests: XCTestCase {

    private func record(daysAgo: Int, levelsAfter: [Pattern: Int]?) -> WorkoutRecord {
        WorkoutRecord(
            sessionNumber: 1,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            result: .plan,
            totalLevelAfter: levelsAfter?.values.reduce(0, +) ?? 0,
            levelsAfter: levelsAfter)
    }

    /// A flat baseline for every rotation pattern (no pull_bar by default —
    /// most journals predate the bar module).
    private func base(_ level: Int) -> [Pattern: Int] {
        Dictionary(uniqueKeysWithValues: Pattern.ordered.map { ($0, level) })
    }

    // MARK: - Movement choice

    func testPicksTheLargestGain() throws {
        var current = base(3)
        current[.hinge] = 11   // +8, everything else +3
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: base(0))],
            currentLevels: current))
        // Level 11 → tier 2 of hinge, named by the library, reps by decode.
        let decoded = Level.decode(11)
        let name = ExerciseLibrary.entry(for: .hinge).variations[decoded.tier - 1].name
        XCTAssertTrue(retro.nowLine.contains(name),
                      "\(retro.nowLine) should name the biggest gain (hinge)")
        XCTAssertTrue(retro.nowLine.contains("\(decoded.sets)×\(decoded.reps)"))
    }

    func testTieBreaksInRotationOrder() throws {
        // squat and calf both gain +5; squat comes first in Pattern.ordered.
        var current = base(2)
        current[.squat] = 5
        current[.calf] = 5
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: base(0))],
            currentLevels: current))
        let squatName = ExerciseLibrary.entry(for: .squat).variations[0].name
        XCTAssertTrue(retro.thenLine.contains(squatName),
                      "tie must resolve to the earlier rotation slot")
    }

    func testThenLineUsesTheBaseLevelEncoding() throws {
        // Base at level 9 (tier 2): the "then" reps must come from
        // repStart[2], not from a flat tier-1 floor — the v2.3 recoding is
        // exactly what this block must never contradict.
        var start = base(0); start[.pushH] = 9
        var current = base(1); current[.pushH] = 17
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: start)],
            currentLevels: current))
        let then = Level.decode(9)
        XCTAssertTrue(retro.thenLine.contains("\(then.sets)×\(then.reps)"),
                      "\(retro.thenLine) must encode level 9 via the core")
    }

    func testHoldMovementFormatsAsSeconds() throws {
        // core_anti_ext is a hold at tier 1: the line must read sets×seconds.
        var current = base(1)
        current[.coreAntiExt] = 6
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: base(0))],
            currentLevels: current))
        let now = Level.decode(6)
        XCTAssertTrue(retro.nowLine.contains("\(now.sets)×\(now.hold) s"),
                      "\(retro.nowLine) should carry the hold in seconds")
    }

    // MARK: - Degradations

    func testNoSnapshotsMeansNoRetrospective() {
        XCTAssertNil(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: nil)],
            currentLevels: base(5)))
        XCTAssertNil(Retrospective.make(records: [], currentLevels: base(5)))
    }

    func testNoGrowthMeansNoRetrospective() {
        XCTAssertNil(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: base(4))],
            currentLevels: base(4)),
            "standing still is not a story")
        XCTAssertNil(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: base(4))],
            currentLevels: base(2)),
            "a net drop must never be celebrated")
    }

    func testBaseIsTheFirstSnapshotNotTheFirstRecord() throws {
        // Record 1 predates snapshots (nil); record 2 carries one. The base
        // must be record 2 — silently skipping the nil, not failing.
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 60, levelsAfter: nil),
                      record(daysAgo: 40, levelsAfter: base(0))],
            currentLevels: base(3)))
        XCTAssertFalse(retro.thenLine.isEmpty)
    }

    func testPullBarAbsentFromBaseIsExcluded() throws {
        // The bar module joined after the first workout: current levels have
        // pull_bar, the base snapshot does not. Its +12 must not win.
        var current = base(1)
        current[.pullBar] = 12
        current[.lunge] = 3    // the honest winner: +2
        let retro = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 30, levelsAfter: base(1))],
            currentLevels: current))
        let lungeName = ExerciseLibrary.entry(for: .lunge).variations[0].name
        XCTAssertTrue(retro.thenLine.contains(lungeName),
                      "\(retro.thenLine): a pattern without a base must not compete")
    }

    // MARK: - The since line

    func testSinceLineSwitchesToMonthsAtNineWeeks() throws {
        let atEight = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 8 * 7, levelsAfter: base(0))],
            currentLevels: base(3)))
        XCTAssertTrue(atEight.sinceLine.contains("8"),
                      "\(atEight.sinceLine) should still count weeks")

        let atNine = try XCTUnwrap(Retrospective.make(
            records: [record(daysAgo: 9 * 7, levelsAfter: base(0))],
            currentLevels: base(3)))
        XCTAssertTrue(atNine.sinceLine.contains("2"),
                      "\(atNine.sinceLine) should have switched to months")
    }
}
