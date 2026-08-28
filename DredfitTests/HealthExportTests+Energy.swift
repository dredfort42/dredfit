import XCTest
import DredfitCore
@testable import Dredfit

/// The calorie half of the Health export: what makes a number appear, what
/// makes it stay away, and where the weight behind it comes from.
///
/// An extension rather than more of `HealthExportTests` — the class was
/// already within a hundred lines of the linter's body ceiling, which is a CI
/// error and not a style opinion.
@MainActor
extension HealthExportTests {

    /// No weight, no calorie — and the workout still exports. A number built
    /// on a default weight is indistinguishable in Health from a true one,
    /// which is the whole reason there is no default.
    func testWithoutABodyMassTheWorkoutExportsWithoutCalories() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 35 * 60)
        await store.healthExportTask?.value

        XCTAssertEqual(spy.saved.count, 1, "the workout still reaches Health")
        XCTAssertNil(spy.saved[0].kcal, "no weight may produce no calories")
        XCTAssertEqual(store.healthBackfillCount, 0, "and the record is done, not stuck")
    }

    /// Nothing is read from Health while there is no weight to divide by: the
    /// queries would be two questions asked for an answer nobody uses.
    func testWithoutABodyMassNothingIsReadFromHealth() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.completeWorkout(session: store.nextSession, result: .plan)
        await store.healthExportTask?.value

        XCTAssertEqual(spy.foreignQueries, 0)
        XCTAssertTrue(spy.restingQueries.isEmpty)
    }

    func testABodyMassProducesCalories() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 35 * 60)
        await store.healthExportTask?.value

        let kcal = try XCTUnwrap(spy.saved.first?.kcal)
        XCTAssertGreaterThan(kcal, 30)
        XCTAssertLessThan(kcal, 400, "a bodyweight session is not a marathon")
    }

    /// A session also recorded on a watch already carries its own measured
    /// energy. Ours would be counted a second time — so it is dropped, and
    /// only it: the workout itself still exports.
    func testAnOverlappingForeignWorkoutSuppressesOnlyTheCalories() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        let end = date(2026, 7, 14)
        spy.foreign = [DateInterval(start: end.addingTimeInterval(-20 * 60), end: end)]
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 35 * 60, date: end)
        await store.healthExportTask?.value

        XCTAssertEqual(spy.saved.count, 1, "the workout must still reach Health")
        XCTAssertNil(spy.saved[0].kcal, "the calories are the double count, not the workout")
    }

    /// A workout on a neighbouring day is not this session.
    func testADistantForeignWorkoutLeavesTheCaloriesAlone() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        spy.foreign = [DateInterval(start: date(2026, 7, 12),
                                    end: date(2026, 7, 12).addingTimeInterval(3600))]
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 35 * 60, date: date(2026, 7, 14))
        await store.healthExportTask?.value

        XCTAssertNotNil(spy.saved.first?.kcal)
    }

    /// The manual half of the guard, for the person whose read was refused —
    /// HealthKit reports a refusal as "nothing found", which is the wrong
    /// answer for exactly the person wearing a watch.
    func testTheWatchToggleSuppressesCalories() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        store.setWatchRecordsWorkouts(true)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 35 * 60)
        await store.healthExportTask?.value

        XCTAssertEqual(spy.saved.count, 1)
        XCTAssertNil(spy.saved[0].kcal)
        XCTAssertEqual(spy.foreignQueries, 0, "there is nothing left to look for")
    }

    /// The sweep is ONE query for the whole journal, not one per record: a
    /// first backfill of a year of workouts must not become a hundred and
    /// fifty round trips through HealthKit.
    func testTheForeignSweepRunsOncePerBackfill() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.setBodyMass(80)
        for day in 10...14 {
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  durationSec: 35 * 60, date: date(2026, 7, day))
        }
        _ = await store.enableHealth()
        await store.backfillHealth()

        XCTAssertEqual(spy.saved.count, 5)
        XCTAssertEqual(spy.foreignQueries, 1, "one sweep covers the whole journal")
    }

    /// The basal rate must be read over the interval the SUM covers. A paused
    /// session holds more resting energy than it has plan minutes, and reading
    /// the plan's length instead would inflate the rate and eat the calories.
    func testTheRestingSumIsReadOverTheExportedInterval() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 50 * 60, date: date(2026, 7, 14))
        await store.healthExportTask?.value

        XCTAssertEqual(spy.restingQueries.count, 1)
        XCTAssertEqual(spy.restingQueries[0].duration, 50 * 60, accuracy: 1)
        XCTAssertEqual(spy.restingQueries[0].end, date(2026, 7, 14))
    }

    // MARK: - Where the weight comes from

    /// Enabling pulls the weight out of Health so most people never type one.
    func testEnablingHealthAdoptsTheRecordedBodyMass() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        XCTAssertEqual(store.settings.bodyMassKg, 72.5)
    }

    /// A weight the person typed is theirs. A Health record that disagrees
    /// does not get to overwrite it behind their back.
    func testAnEnteredBodyMassSurvivesEnablingHealth() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        store.setBodyMass(90)
        _ = await store.enableHealth()
        XCTAssertEqual(store.settings.bodyMassKg, 90)
    }

    /// A denied read looks exactly like an empty Health profile, and both must
    /// leave the field empty rather than filled with something.
    func testARefusedBodyMassReadLeavesTheFieldEmpty() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        XCTAssertNil(store.settings.bodyMassKg)
    }

    func testAnImpossibleBodyMassIsNotStored() {
        let store = AppStore(storageURL: tempURL, health: HealthSpy())
        for mass in [0.0, -5.0, .nan, .infinity] {
            store.setBodyMass(mass)
            XCTAssertNil(store.settings.bodyMassKg, "\(mass) kg is not a body")
        }
        store.setBodyMass(900)
        XCTAssertEqual(store.settings.bodyMassKg, 500, "clamped, not refused")
    }

    /// The weight and the watch answer both survive a relaunch — they decide
    /// what every future export writes.
    func testBodyMassAndWatchAnswerPersist() {
        let store = AppStore(storageURL: tempURL, health: HealthSpy())
        store.setBodyMass(77.5)
        store.setWatchRecordsWorkouts(true)
        let reloaded = AppStore(storageURL: tempURL, health: HealthSpy())
        XCTAssertEqual(reloaded.settings.bodyMassKg, 77.5)
        XCTAssertTrue(reloaded.settings.watchRecordsWorkouts)
    }

    // MARK: - Whose workout is it

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
    /// planned minutes regardless billed nine minutes of stretching to a
    /// person who declined both.
    func testDecliningBothBlocksLowersTheCalorie() async throws {
        let withBlocks = HealthSpy()
        let a = AppStore(storageURL: tempURL, health: withBlocks)
        _ = await a.enableHealth()
        a.setBodyMass(80)
        a.completeWorkout(session: a.nextSession, result: .plan, durationSec: 35 * 60)
        await a.healthExportTask?.value

        let declined = HealthSpy()
        let b = AppStore(storageURL: tempURL.appendingPathExtension("b"), health: declined)
        _ = await b.enableHealth()
        b.setBodyMass(80)
        b.completeWorkout(session: b.nextSession, result: .plan, durationSec: 35 * 60,
                          warmupSec: 0, cooldownSec: 0)
        await b.healthExportTask?.value

        let full = try XCTUnwrap(withBlocks.saved.first?.kcal)
        let bare = try XCTUnwrap(declined.saved.first?.kcal)
        XCTAssertLessThan(bare, full, "nine minutes nobody spent must not be billed")
    }

    /// A block half done is charged for the half — not all, not nothing.
    func testAPartlyDoneBlockLandsBetween() async throws {
        var kcal: [Double] = []
        for seconds in [0, 150, 300] {
            let spy = HealthSpy()
            let store = AppStore(storageURL: tempURL.appendingPathExtension("\(seconds)"),
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
        let store = AppStore(storageURL: tempURL, health: spy)
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
        let store = AppStore(storageURL: tempURL, health: HealthSpy())
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 30 * 60, warmupSec: 0, cooldownSec: 210)
        let reloaded = AppStore(storageURL: tempURL, health: HealthSpy())
        let record = try XCTUnwrap(reloaded.records.last)
        XCTAssertEqual(record.warmupSec, 0)
        XCTAssertEqual(record.cooldownSec, 210)
    }

    /// A record written before the flow measured its blocks must keep reading
    /// as "unknown", which falls back to the plan — not as "declined".
    func testAnOlderRecordFallsBackToThePlannedBlocks() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
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
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(80)
        store.completeWorkout(session: store.nextSession, result: .plan, durationSec: 35 * 60)
        await store.healthExportTask?.value

        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(spy.saved.first?.journalID, record.id)
        XCTAssertFalse(record.id.isEmpty)
    }
}
