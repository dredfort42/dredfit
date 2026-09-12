//
//  What the history sheet says about a probe — and what it may not claim.
//
//  Until this wave it said nothing at all. The record carried the probe in its
//  own plan (`SessionExercise.probe` is in the record's CodingKeys) and the
//  screen printed the working sets beside a name: a session of "2 × 15 plus a
//  probe" read exactly like a session of two sets. What the file did NOT carry
//  was the number the probe showed — it reached the engine through
//  `completeWorkout(probes:)` and was dropped — so the outcome was
//  unrecoverable the moment the rating landed.
//
//  The line is a pure function of a record and one exercise, which is what
//  makes it testable at all: the two probe rules that stay uncovered live
//  inside a SwiftUI view as private members (see the note at the bottom of
//  ProbeChannelTests), and this one deliberately does not join them.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class HistoryProbeTests: XCTestCase {

    private let probe = SessionProbe(variation: 4, name: "Inverted row (table)",
                                     unit: .reps, load: 4, perSide: false)

    private func exercise(withProbe: Bool = true) -> SessionExercise {
        SessionExercise(pattern: .pull, name: "Mid-height inverted row", variation: 3,
                        unit: .reps, load: 15, perSide: false, sets: 2,
                        restSetSec: 60, restExerciseSec: 90, loads: nil,
                        probe: withProbe ? probe : nil)
    }

    /// `variationAfter` is what the session ENDED on — the only thing the app
    /// is allowed to read the verdict off. Re-deriving §40.4's pass rule here
    /// would be a second copy of it, free to disagree with the engine.
    private func record(variationAfter: Int, probes: [Pattern: Int]? = nil,
                        positions: Bool = true) -> WorkoutRecord {
        WorkoutRecord(
            sessionNumber: 4, date: Date(timeIntervalSince1970: 1_000), result: .plan,
            exercises: [exercise()], probes: probes,
            positionsAfter: positions
                ? [.pull: RecordedPosition(variation: variationAfter, sets: 3, dose: 4)]
                : nil)
    }

    // MARK: - With the number the wave started recording

    func testAPassedProbeNamesTheMovementAndWhatWasShown() throws {
        let line = try XCTUnwrap(HistorySheet.probeLine(
            exercise(), in: record(variationAfter: 4, probes: [.pull: 5])))
        XCTAssertTrue(line.contains("Inverted row (table)"), line)
        XCTAssertTrue(line.contains("5"), "the number the probe showed is the point: \(line)")
        XCTAssertTrue(line.contains("passed"), line)
    }

    func testAProbeThatDidNotLandSaysSoWithoutBlame() throws {
        let line = try XCTUnwrap(HistorySheet.probeLine(
            exercise(), in: record(variationAfter: 3, probes: [.pull: 2])))
        XCTAssertTrue(line.contains("2"), line)
        XCTAssertTrue(line.contains("not this time"),
                      "the same neutral words the work screen uses: \(line)")
        XCTAssertFalse(line.contains("passed"), line)
    }

    // MARK: - Without it: every record written before this wave

    /// A record with no `probes` is either an old one or a session whose probe
    /// was never performed, and the file cannot tell those apart. So the line
    /// drops the number and keeps the verdict, which is true of both.
    func testAnOlderRecordStillGetsItsVerdictFromThePositionItEndedOn() throws {
        let passed = try XCTUnwrap(HistorySheet.probeLine(
            exercise(), in: record(variationAfter: 4)))
        XCTAssertTrue(passed.contains("passed"), passed)
        XCTAssertTrue(passed.contains("Inverted row (table)"), passed)

        let unresolved = try XCTUnwrap(HistorySheet.probeLine(
            exercise(), in: record(variationAfter: 3)))
        XCTAssertTrue(unresolved.contains("not this time"), unresolved)
    }

    // MARK: - When it must say nothing

    func testAnExerciseWithoutAProbeGetsNoLine() {
        XCTAssertNil(HistorySheet.probeLine(exercise(withProbe: false),
                                            in: record(variationAfter: 3, probes: [.pull: 4])))
    }

    /// No position on record is no evidence, and a verdict without evidence is
    /// a guess. Silence beats a sentence the file cannot support.
    func testARecordWithoutPositionsClaimsNothing() {
        XCTAssertNil(HistorySheet.probeLine(exercise(),
                                            in: record(variationAfter: 4, positions: false)))
    }

    /// The stored name is frozen in the language the session was generated in;
    /// the line resolves it through the library so history follows a language
    /// switch, exactly as the movement's own name above it does.
    func testTheNameIsResolvedThroughTheLibraryNotReadFromTheSnapshot() throws {
        let stale = SessionProbe(variation: 4, name: "a name from another build",
                                 unit: .reps, load: 4, perSide: false)
        let ex = SessionExercise(pattern: .pull, name: "Mid-height inverted row",
                                 variation: 3, unit: .reps, load: 15, perSide: false,
                                 sets: 2, restSetSec: 60, restExerciseSec: 90,
                                 loads: nil, probe: stale)
        let line = try XCTUnwrap(HistorySheet.probeLine(
            ex, in: WorkoutRecord(sessionNumber: 4, date: .init(timeIntervalSince1970: 1_000),
                                  result: .plan, exercises: [ex], probes: [.pull: 4],
                                  positionsAfter: [.pull: RecordedPosition(variation: 4, sets: 3,
                                                                           dose: 4)])))
        XCTAssertEqual(line.contains("a name from another build"), false, line)
        XCTAssertTrue(line.contains(Library.name(.pull, 4)), line)
    }
}
