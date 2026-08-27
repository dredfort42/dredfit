//
//  The widget snapshot tests, moved out of AppStoreTests.swift, which had
//  grown past nine hundred lines. It is still over the linter's file ceiling
//  after this — the point is that the snapshot is its own subject, not that
//  the count now passes. The code moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Widget snapshot
//
// An extension keeps these out of the test class's own body, which the linter
// bounds separately from file length and wherever the extension sits; XCTest
// discovers test methods in extensions just fine.
extension AppStoreTests {
    func testWidgetSnapshotMirrorsWeekStatuses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        store.completeWorkout(session: store.nextSession, result: .plan)   // today → done

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = cal.timeZone
        let monday = try XCTUnwrap(iso.dateInterval(of: .weekOfYear, for: today)).start

        XCTAssertEqual(snap.days.count, 14, "the snapshot must cover two weeks")
        XCTAssertEqual(snap.days[0].date, monday,
                       "it must start on Monday so any entry can draw its own week")
        let todayEntry = try XCTUnwrap(snap.days.first { $0.date == today })
        XCTAssertEqual(todayEntry.status, .done)

        for day in snap.days where day.date > today {
            XCTAssertEqual(day.status, store.isRestDay(day.date) ? .rest : .workout,
                           "future days must mirror the rest-day settings")
        }
        for day in snap.days where day.date < today {
            XCTAssertEqual(day.status, store.isRestDay(day.date) ? .rest : .unmarked,
                           "a past training day with nothing recorded stays unmarked — "
                           + "the Calendar does not accuse and neither does the widget")
        }
        for day in snap.days {
            XCTAssertNil(day.sessionNumber, "a finished day carries no session number")
        }
    }

    func testWidgetSnapshotCarriesTheStepsWeekAndPlan() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        store.completeWorkout(session: store.nextSession, result: .plan)

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        XCTAssertEqual(snap.totalSteps, store.totalProgress)
        XCTAssertEqual(snap.week?.workouts, store.weekSummary().workouts)
        XCTAssertEqual(snap.week?.stepsDelta, store.weekSummary().stepsDelta)
        XCTAssertEqual(snap.planSessionNumber, store.nextSession.sessionNumber)
        // The write day's own label is the one the app shows right now; the
        // week tally is stamped with its Monday so the widget can keep it
        // inside the week it belongs to.
        let today = Calendar.current.startOfDay(for: .now)
        let todayEntry = try XCTUnwrap(snap.days.first { $0.date == today })
        XCTAssertEqual(todayEntry.nextLabel, store.nextTrainingDateLabel)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = Calendar.current.timeZone
        XCTAssertEqual(snap.weekStart,
                       try XCTUnwrap(iso.dateInterval(of: .weekOfYear, for: today)).start)

        let plan = try XCTUnwrap(snap.plan)
        XCTAssertEqual(plan.count, store.nextSession.exercises.count)
        XCTAssertEqual(plan.first?.name, store.nextSession.exercises.first?.name)
        XCTAssertFalse(plan.contains { $0.detail.isEmpty },
                       "the widget cannot format loads itself — they arrive ready")
    }

    /// Relative words are per day, not per write: a rest-day entry rendered
    /// days after the app was last opened must not repeat the write day's
    /// "on X" phrasing — each entry speaks from its own day instead.
    func testWidgetSnapshotLabelsSpeakFromTheirOwnDay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let tomorrowWD = cal.component(.weekday,
                                       from: try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: today)))
        for wd in [1, 4] where wd != tomorrowWD { store.toggleRestDay(wd) }
        if ![1, 4].contains(tomorrowWD) { store.toggleRestDay(tomorrowWD) }
        store.completeWorkout(session: store.nextSession, result: .plan)

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        // The word the VIEW produces, not the English literal. `nextLabel` is
        // `String(localized: "tomorrow")` (AppStore+Calendar), so under
        // -AppleLanguages (ru) the equality in the loop went red while the
        // inequality just after this passed for the wrong reason — a Russian
        // label is never the string "tomorrow" either. The project rule is the
        // same one: assert on the string the view produces, never on a
        // base-language literal.
        let tomorrow = String(localized: "tomorrow")
        let todayEntry = try XCTUnwrap(snap.days.first { $0.date == today })
        XCTAssertNotEqual(todayEntry.nextLabel, tomorrow,
                          "from the write day the rest day is in the way — its label is \"on X\"")
        for day in snap.days {
            switch day.status {
            case .rest where day.date > today:
                XCTAssertEqual(day.nextLabel, tomorrow,
                               "\(day.date): a rest-day entry must speak from its own day")
            case .workout:
                XCTAssertNil(day.nextLabel,
                             "\(day.date): a planned day IS the workout — no label")
            default:
                break   // past days and today are covered elsewhere
            }
        }
    }

    func testWidgetSnapshotFromAnOlderBuildStillDecodes() throws {
        let legacy = #"{"days":[{"date":768614400,"status":"workout","sessionNumber":3}]}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))

        XCTAssertEqual(snap.days.count, 1)
        XCTAssertEqual(snap.days[0].status, .workout)
        XCTAssertEqual(snap.days[0].sessionNumber, 3)
        XCTAssertNil(snap.totalSteps)
        XCTAssertNil(snap.week)
        XCTAssertNil(snap.plan)
        XCTAssertNil(snap.weekStart)
        XCTAssertNil(snap.days[0].nextLabel)
    }

    /// The other half of the same promise, for the week: a snapshot written
    /// before the scale changed carries its delta under the retired key. The
    /// week itself must survive — a throw inside `Week` fails the whole
    /// decode and blanks the widget until the app is next opened — while the
    /// number stays absent rather than being read as a step count.
    func testWidgetSnapshotWeekFromBeforeTheScaleChangeStillDecodes() throws {
        let legacy = #"{"days":[],"week":{"workouts":3,"levelsDelta":6}}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))

        XCTAssertEqual(snap.week?.workouts, 3, "the week must not be lost with the key")
        XCTAssertNil(snap.week?.stepsDelta,
                     "a delta counted in the retired unit must not resurface as steps")
    }

    /// The home screen must not be told "nothing done" over a history the
    /// app cannot currently read — a frozen launch must leave the widget's
    /// last published snapshot untouched.
    func testFrozenLaunchLeavesTheWidgetSnapshotAlone() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let seed = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        seed.completeWorkout(session: seed.nextSession, result: .plan)
        let published = try Data(contentsOf: url)

        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }
        let frozen = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        frozen.refreshWidgetSnapshot()   // what backgrounding does
        XCTAssertEqual(try Data(contentsOf: url), published,
                       "the widget must keep showing the last state that was real")
    }
}
