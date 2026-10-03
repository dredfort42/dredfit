import XCTest
import DredfitCore
@testable import Dredfit

/// The exporter on its own: what it asks Health, and what it hands over for a
/// record. The flags and the order of the backfill are the store's, and
/// HealthExportTests covers them end to end.
@MainActor
final class HealthExporterTests: XCTestCase {

    private let end = Date(timeIntervalSince1970: 1_900_000_000)

    private func record(minutes: Int, daysBefore days: Int = 0) -> WorkoutRecord {
        WorkoutRecord(sessionNumber: 1 + days, date: end - Double(days) * 86_400, result: .plan,
                      durationSec: minutes * 60)
    }

    func testWithoutAWeightHealthIsAskedNothing() async {
        let spy = HealthSpy()
        let exporter = HealthExporter(health: spy)
        let none = await exporter.energyContext(bodyMassKg: nil, watchRecordsWorkouts: false,
                                                pending: { [self] in [record(minutes: 30)] })
        let watched = await exporter.energyContext(bodyMassKg: 70, watchRecordsWorkouts: true,
                                                   pending: { [self] in [record(minutes: 30)] })
        XCTAssertNil(none.bodyMassKg)
        XCTAssertNil(watched.bodyMassKg, "a watch already measured the energy")
        XCTAssertEqual(spy.foreignQueries, 0)
    }

    func testTheSweepStartsWhereTheEarliestPendingWorkoutStarted() async {
        let spy = HealthSpy()
        spy.foreign = [DateInterval(start: end - 86_400 - 1_200, duration: 60)]
        let context = await HealthExporter(health: spy).energyContext(
            bodyMassKg: 70, watchRecordsWorkouts: false,
            pending: { [self] in [record(minutes: 30, daysBefore: 1), record(minutes: 30)] })
        XCTAssertEqual(context.bodyMassKg, 70)
        XCTAssertEqual(spy.foreignQueries, 1, "one query over the whole journal, not one per record")
        XCTAssertEqual(context.foreign, spy.foreign,
                       "a foreign workout inside the older record is found too")
    }

    func testAnExportCarriesTheRecordsIntervalAndID() async {
        let spy = HealthSpy()
        let saved = await HealthExporter(health: spy)
            .export(record(minutes: 30), context: HealthExporter.EnergyContext())
        XCTAssertTrue(saved)
        XCTAssertEqual(spy.saved, [SavedWorkout(start: end - 1_800, end: end, kcal: nil,
                                                journalID: record(minutes: 30).id)])
    }

    func testARefusedSaveIsReportedAsNotExported() async {
        let spy = HealthSpy()
        spy.allFail = true
        let saved = await HealthExporter(health: spy)
            .export(record(minutes: 30), context: HealthExporter.EnergyContext())
        XCTAssertFalse(saved, "the store flags a record only on a confirmed save")
    }

    func testABodyMassOutsideReasonIsNoBodyMass() {
        XCTAssertNil(HealthExporter.sanitizedBodyMass(0))
        XCTAssertNil(HealthExporter.sanitizedBodyMass(-70))
        XCTAssertNil(HealthExporter.sanitizedBodyMass(.nan))
        XCTAssertNil(HealthExporter.sanitizedBodyMass(.infinity))
        XCTAssertEqual(HealthExporter.sanitizedBodyMass(72.5), 72.5)
        XCTAssertEqual(HealthExporter.sanitizedBodyMass(900), 500)
    }
}
