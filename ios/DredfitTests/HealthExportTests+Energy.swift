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

    /// The two sweeps are not run while there is no weight to divide by: they
    /// would be questions asked for an answer nobody uses. The WEIGHT read is
    /// not one of them — it happens every run, because the number is on the
    /// settings screen whether or not a calorie is ever computed from it. The
    /// test used to claim "nothing is read" and could not have noticed the
    /// difference: the spy did not count that read at all.
    func testWithoutABodyMassTheTwoSweepsAreSkipped() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.completeWorkout(session: store.nextSession, result: .plan)
        await store.healthExportTask?.value

        XCTAssertEqual(spy.foreignQueries, 0)
        XCTAssertTrue(spy.restingQueries.isEmpty)
        XCTAssertGreaterThan(spy.massQueries, 0, "the weight is read even so")
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

    /// The phone has one owner, so Health is the truth about their weight:
    /// a number typed before the toggle went on does not outrank the scale.
    func testHealthOverridesAnEnteredBodyMassOnEnabling() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        store.setBodyMass(90)
        _ = await store.enableHealth()
        XCTAssertEqual(store.settings.bodyMassKg, 72.5)
        XCTAssertTrue(store.settings.bodyMassFromHealth, "and the row goes read-only")
    }

    /// The defect this whole change exists for: the weight used to be copied
    /// once and then frozen, so a person who weighed themselves again kept
    /// getting calories computed from the number they had on the day they
    /// switched Health on.
    func testANewHealthWeightIsPickedUpOnActivation() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        spy.bodyMassKg = 68
        store.activate()
        await store.bodyMassTask?.value
        XCTAssertEqual(store.settings.bodyMassKg, 68)
    }

    /// A refused read and an empty Health are the same `nil` — and neither may
    /// erase the weight, because an erased weight is calories switched off.
    /// It hands the field back instead.
    func testAnAbsentHealthWeightKeepsTheTypedOneAndTheField() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(90)

        store.activate()
        await store.bodyMassTask?.value
        XCTAssertEqual(store.settings.bodyMassKg, 90)
        XCTAssertFalse(store.settings.bodyMassFromHealth, "so the row stays editable")
    }

    /// Health going quiet later — the record deleted, the read revoked — hands
    /// the field back too, keeping the last known number until it is retyped.
    func testHealthGoingQuietHandsTheFieldBack() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        spy.bodyMassKg = nil
        store.activate()
        await store.bodyMassTask?.value
        XCTAssertEqual(store.settings.bodyMassKg, 72.5, "the last reading stands")
        XCTAssertFalse(store.settings.bodyMassFromHealth)
    }

    /// Nothing is read while the integration is off — the toggle is the whole
    /// permission, and a store with Health off must not query it at all.
    func testTheWeightIsNotReadWhileHealthIsOff() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        store.activate()
        await store.bodyMassTask?.value
        XCTAssertNil(store.settings.bodyMassKg)
        XCTAssertFalse(store.settings.bodyMassFromHealth)
    }

    /// The export multiplies by the weight, so it takes its own reading rather
    /// than trusting whatever the last foreground left behind — an app open
    /// since morning would otherwise export against a stale number.
    func testTheExportRunRefreshesTheWeightFirst() async throws {
        // The baseline is MEASURED, not guessed: the same session exported
        // while Health still says 60. A hand-picked threshold would have
        // passed on the stale weight too, and proved nothing about the read.
        let stale = HealthSpy()
        stale.bodyMassKg = 60
        let staleStore = AppStore(storageURL: tempURL.appendingPathExtension("stale"),
                                  health: stale)
        _ = await staleStore.enableHealth()
        staleStore.completeWorkout(session: staleStore.nextSession, result: .plan,
                                   durationSec: 35 * 60)
        await staleStore.healthExportTask?.value
        let atSixty = try XCTUnwrap(stale.saved.first?.kcal)

        let spy = HealthSpy()
        spy.bodyMassKg = 60
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        spy.bodyMassKg = 120   // weighed again, after the toggle went on
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 35 * 60)
        await store.healthExportTask?.value

        XCTAssertEqual(store.settings.bodyMassKg, 120)
        let kcal = try XCTUnwrap(spy.saved.first?.kcal)
        XCTAssertGreaterThan(kcal, atSixty,
                             "the export multiplied by the new weight, not the enabled-day one")
    }

    /// Kicks an activation and returns once the spy's gated weight read is
    /// actually in flight. Same shape, and same reason, as the class's gated
    /// save helper: a test that moves the world before the read starts is
    /// caught by the guard at the top of the refresh and passes vacuously.
    private func activateAndWaitForGatedRead(_ store: AppStore,
                                             _ spy: HealthSpy) async {
        let before = spy.massQueries
        store.activate()
        var spins = 0
        while spy.massQueries == before && spins < 10_000 {
            spins += 1
            await Task.yield()
        }
        XCTAssertEqual(spy.massQueries, before + 1, "the gated read must be in flight")
    }

    /// The toggle is checked again AFTER the read, not only before it: the
    /// backfill loop re-reads it at every boundary for the same reason, and a
    /// reading that lands on a switched-off integration writes a weight the
    /// person believes they stopped sharing.
    func testTheToggleGoingDownMidReadStopsTheWrite() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(90)

        let gate = HealthGate()
        spy.massGate = gate
        await activateAndWaitForGatedRead(store, spy)
        store.disableHealth()
        gate.open()
        await store.bodyMassTask?.value

        XCTAssertEqual(store.settings.bodyMassKg, 90,
                       "a reading may not land after the toggle went down")
        XCTAssertFalse(store.settings.bodyMassFromHealth)
    }

    /// Two foregrounds leave two queries in flight and HealthKit decides which
    /// returns first. The superseded one is cancelled, and a cancelled run
    /// must not write — otherwise the older reading lands last and sticks.
    func testACancelledRefreshDoesNotWrite() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 68
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        store.setBodyMass(90)

        let gate = HealthGate()
        spy.massGate = gate
        await activateAndWaitForGatedRead(store, spy)
        let superseded = store.bodyMassTask
        superseded?.cancel()
        gate.open()
        await superseded?.value

        XCTAssertEqual(store.settings.bodyMassKg, 90, "the superseded run wrote nothing")
    }

    /// A backup cannot prove that THIS device's Health supplied the weight —
    /// the same rule the export mark lives by. Inherited, a restore onto a new
    /// phone showed an imported number under "Taken from Health" in a row that
    /// would not open to be corrected.
    func testARestoredBackupDoesNotInheritTheHealthOrigin() async throws {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let donor = AppStore(storageURL: tempURL, health: spy)
        _ = await donor.enableHealth()
        XCTAssertTrue(donor.settings.bodyMassFromHealth)
        let backup = try donor.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        let restoredURL = tempURL.appendingPathExtension("restored")
        defer { try? FileManager.default.removeItem(at: restoredURL) }
        // This device's Health answers nothing — as it would before the
        // permission sheet has ever been shown here.
        let fresh = AppStore(storageURL: restoredURL, health: HealthSpy())
        try fresh.importBackup(from: backup)

        XCTAssertEqual(fresh.settings.bodyMassKg, 72.5, "the number travels")
        XCTAssertFalse(fresh.settings.bodyMassFromHealth,
                       "the claim about where it came from does not")
    }

    /// "From Health" is a claim about a number, so without the number it is a
    /// lie the file can tell: the row went read-only at "Not set" — calories
    /// off, and no field left to turn them back on.
    func testAFileClaimingHealthWithoutAWeightDecodesAsTyped() throws {
        let seed = AppStore(storageURL: tempURL, health: HealthSpy())
        var settings = seed.settings
        settings.healthEnabled = true
        settings.bodyMassFromHealth = true          // and no bodyMassKg
        let data = try JSONEncoder().encode(AppData(engineState: seed.engineState,
                                                    records: [], settings: settings))
        try data.write(to: tempURL, options: .atomic)

        let store = AppStore(storageURL: tempURL, health: HealthSpy())
        XCTAssertNil(store.settings.bodyMassKg)
        XCTAssertFalse(store.settings.bodyMassFromHealth, "no number, no claim about it")
    }

    /// Where the number came from survives a relaunch: the row must not come
    /// up editable for a moment on every launch, before the async read lands.
    func testTheHealthOriginOfTheWeightPersists() async {
        let spy = HealthSpy()
        spy.bodyMassKg = 72.5
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        let reloaded = AppStore(storageURL: tempURL, health: HealthSpy())
        XCTAssertEqual(reloaded.settings.bodyMassKg, 72.5)
        XCTAssertTrue(reloaded.settings.bodyMassFromHealth)
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
