import XCTest
import DredfitCore
@testable import Dredfit

/// The rest of the calorie half of the Health export: telling our own workout
/// from a foreign one, the blocks that did not happen, and the identity the
/// energy sample carries. Split from `HealthExportTests+Energy` to keep each
/// file under the linter's file-length ceiling.
@MainActor
extension HealthExportTests {

    /// The trap this whole filter exists for: our own exported workout, found
    /// by the next run, would look like a watch recording of the same session
    /// and silently switch calories off forever.
    func testOurOwnWorkoutsAreNotForeign() {
        let start = date(2026, 7, 14)
        let origins = [
            WorkoutOrigin(bundleID: "app.dredfit", start: start,
                          end: start.addingTimeInterval(1800)),
            WorkoutOrigin(bundleID: "com.apple.workout", start: start,
                          end: start.addingTimeInterval(1800)),
            WorkoutOrigin(bundleID: nil, start: start, end: start.addingTimeInterval(600)),
        ]
        let foreign = HealthKitWorkoutWriter.foreignIntervals(in: origins,
                                                             excluding: "app.dredfit")
        XCTAssertEqual(foreign.map(\.duration), [1800, 600],
                       "only our own bundle is filtered out")
    }

    /// A sample whose end precedes its start would trap `DateInterval`.
    func testABackwardsForeignSampleDoesNotTrap() {
        let start = date(2026, 7, 14)
        let foreign = HealthKitWorkoutWriter.foreignIntervals(
            in: [WorkoutOrigin(bundleID: "other", start: start,
                               end: start.addingTimeInterval(-60))],
            excluding: "app.dredfit")
        XCTAssertEqual(foreign.first?.duration, 0)
    }

    // MARK: - Blocks that did not happen

    /// The warm-up and the cool-down each end on one tap. Charging their
    /// planned minutes regardless would bill ten minutes to a person who
    /// declined both.
    func testDecliningBothBlocksLowersTheCalorie() async throws {
        let withBlocks = HealthSpy()
        let a = makeStore(health: withBlocks)
        _ = await a.enableHealth()
        a.setBodyMass(80)
        a.completeWorkout(session: a.nextSession, result: .plan, durationSec: 35 * 60)
        await a.healthExportTask?.value

        let declined = HealthSpy()
        let b = makeStore(storageURL: tempURL.appendingPathExtension("b"), health: declined)
        _ = await b.enableHealth()
        b.setBodyMass(80)
        b.completeWorkout(session: b.nextSession, result: .plan, durationSec: 35 * 60,
                          warmupSec: 0, cooldownSec: 0)
        await b.healthExportTask?.value

        let full = try XCTUnwrap(withBlocks.saved.first?.kcal)
        let bare = try XCTUnwrap(declined.saved.first?.kcal)
        XCTAssertLessThan(bare, full, "ten minutes nobody spent must not be billed")
    }

    /// A block half done is charged for the half — not all, not nothing.
    func testAPartlyDoneBlockLandsBetween() async throws {
        var kcal: [Double] = []
        for seconds in [0, 150, 300] {
            let spy = HealthSpy()
            let store = makeStore(storageURL: tempURL.appendingPathExtension("\(seconds)"),
                                  health: spy)
            _ = await store.enableHealth()
            store.setBodyMass(80)
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  durationSec: 35 * 60, warmupSec: seconds, cooldownSec: 0)
            await store.healthExportTask?.value
            kcal.append(try XCTUnwrap(spy.saved.first?.kcal))
        }
        XCTAssertLessThan(kcal[0], kcal[1])
        XCTAssertLessThan(kcal[1], kcal[2])
    }

    /// The owner's rule: a session in which nothing was performed gets no
    /// calorie at all, even though its blocks really did take minutes.
    func testASessionWithEverythingSkippedWritesNoCalorie() async {
        let spy = HealthSpy()
        let store = makeStore(health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        let session = store.nextSession
        store.completeWorkout(session: session, result: .plan,
                              skipped: Set(session.exercises.map(\.pattern)),
                              durationSec: 35 * 60)
        await store.healthExportTask?.value

        XCTAssertEqual(spy.saved.count, 1, "the workout is still a fact and still exports")
        XCTAssertNil(spy.saved[0].kcal)
    }

    /// The measurement is part of what happened, so it has to survive the
    /// relaunch that the record itself survives.
    func testBlockMeasurementsSurviveAReload() throws {
        let store = makeStore(health: HealthSpy())
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 30 * 60, warmupSec: 0, cooldownSec: 210)
        let reloaded = makeStore(health: HealthSpy())
        let record = try XCTUnwrap(reloaded.records.last)
        XCTAssertEqual(record.warmupSec, 0)
        XCTAssertEqual(record.cooldownSec, 210)
    }

    /// A record written before the flow measured its blocks must keep reading
    /// as "unknown", which falls back to the plan — not as "declined".
    func testAnOlderRecordFallsBackToThePlannedBlocks() async throws {
        let spy = HealthSpy()
        let store = makeStore(health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        store.completeWorkout(session: store.nextSession, result: .plan, durationSec: 35 * 60)
        await store.healthExportTask?.value

        let record = try XCTUnwrap(store.records.last)
        XCTAssertNil(record.warmupSec)
        XCTAssertNil(record.cooldownSec)
        XCTAssertNotNil(spy.saved.first?.kcal, "unknown blocks still price at the plan")
    }

    // MARK: - Provenance

    /// The sample carries the identity of the journal entry it came from —
    /// the only way to answer "why does this one differ" against a person's
    /// own history later.
    func testTheEnergySampleCarriesTheRecordIdentity() async throws {
        let spy = HealthSpy()
        let store = makeStore(health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        store.completeWorkout(session: store.nextSession, result: .plan, durationSec: 35 * 60)
        await store.healthExportTask?.value

        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(spy.saved.first?.journalID, record.id)
        XCTAssertFalse(record.id.isEmpty)
    }
}
