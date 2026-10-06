//
//  The state file exactly as release 2.4.4 writes it, frozen as bytes.
//
//  Every other fixture in the suite is either an OLD shape (the migration
//  suites) or a minimal v3 one built from `Pattern.allCases`, which carries
//  only the three required engine fields. Every optional field is read
//  leniently — absent or unreadable, it opens at its default — so a renamed
//  key or a changed wire shape would fail no test: the field would just be
//  forgotten on the next launch. This literal carries the keys a real 2.4.4
//  file holds for every engine field and the main settings, and the test
//  reads a value back from each engine map. Optional settings that default
//  to nil are not all here; add one with a non-default value when it matters.
//
//  Hand-written on purpose, and never to be regenerated from the current
//  types: it has to keep holding the bytes 2.4.4 put on disk after those
//  types move.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class StateFileFixtureTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-fixture" }

    /// `[Pattern: X]` is an UNKEYED array alternating raw value and value
    /// (Pattern is not CodingKeyRepresentable); the inner `[Int: Int]` of
    /// `shown` is a keyed object, because Swift special-cases integer keys.
    /// Dates are seconds since the reference date, JSONEncoder's default.
    /// `discomfort` and `pendingWorkout` are left out: nothing writes the
    /// first any more, and the second is resumable state, not history.
    private static let release244StateFile = """
    {"engineState":{"counter":12,"hasBar":true,
      "vars":["squat",3,"push_h",2,"hinge",2,"pull",2,"push_v",1,"lunge",4,
              "core_anti_ext",2,"core_rot",1,"calf",2,"pull_bar",1],
      "doses":["squat",9,"push_h",8,"hinge",10,"pull",7,"push_v",6,"lunge",10,
               "core_anti_ext",30,"core_rot",20,"calf",12,"pull_bar",15],
      "sets":["lunge",4],
      "sub":["squat",1],
      "cut":["pull",1],
      "shown":["squat",{"2":15,"3":9},"core_anti_ext",{"1":45,"2":30}],
      "setsHold":["lunge",2],
      "shownWork":["squat",27],
      "shownOrd":["squat",17],
      "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",1,"push_v",0,"lunge",0,
                    "core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0],
      "lastHard":["pull"],
      "lessRun":1,
      "creditPaused":["pull_bar"],
      "returnRun":1,
      "lessHist":["pull",5],
      "rampWindow":4,
      "weekGain":["squat",2],
      "weekAgeDays":3.5},
     "records":[
      {"sessionNumber":11,"date":779900000,"result":"plan","totalProgressAfter":140,
       "healthExported":true},
      {"sessionNumber":12,"date":780000000,"result":"more","totalProgressAfter":143,
       "exercises":[{"pattern":"squat","name":"Split squat","variation":3,"unit":"reps",
                     "load":9,"perSide":true,"sets":3,"restSetSec":60,"restExerciseSec":90,
                     "loads":[10,9,9],
                     "probe":{"variation":4,"name":"Bulgarian split squat","unit":"reps",
                              "load":6,"perSide":true}}],
       "actuals":["squat",9],
       "setActuals":["squat",[10,9,8]],
       "probes":["squat",6],
       "setsSkipped":["pull",1],
       "skipped":["calf"],
       "positionsAfter":["squat",{"variation":3,"sets":3,"dose":9,"sub":1},
                         "pull",{"variation":2,"sets":3,"dose":7,"cut":1}],
       "durationSec":1980,"warmupSec":300,"cooldownSec":240,
       "healthExported":true,
       "interrupted":"calf",
       "raisedSteps":["squat",1],
       "raisedLanded":["squat",1]}],
     "settings":{"restWeekdays":[1,4],"soundsEnabled":false,"reminderEnabled":true,
      "reminderHour":19,"reminderMinute":30,"healthEnabled":true,"healthExportedThrough":12,
      "bodyMassKg":78.5,"bodyMassFromHealth":true,"bodyMassDate":779990000,
      "watchRecordsWorkouts":false,"onboardingCompleted":true,"hasOpenedTechnique":true,
      "hasReportedOwnNumber":true,"playsTonesInSilentMode":true,"appearance":"dark",
      "planMoves":{"session":13,"byHand":["squat"],"byRating":[]},
      "ratingMoves":{"session":12,"byHand":[],"byRating":["pull"]}}}
    """

    private func loadFixture() throws -> AppStore {
        try Data(Self.release244StateFile.utf8).write(to: tempURL)
        let corruptURL = tempURL.deletingLastPathComponent()
            .appendingPathComponent(tempURL.deletingPathExtension().lastPathComponent + ".corrupt.json")
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        let store = makeStore()
        // Both a reset engine state and a dropped record copy the file aside,
        // so its absence is the whole-file verdict.
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path),
                       "the 2.4.4 file must decode without anything set aside")
        XCTAssertEqual(store.engineState.counter, 12, "the engine state must not start clean")
        XCTAssertEqual(store.records.count, 2)
        return store
    }

    func testRelease244EngineStateReadsEveryKey() throws {
        let state = try loadFixture().engineState
        XCTAssertTrue(state.hasBar)
        XCTAssertEqual(state.vars[.lunge], 4)
        XCTAssertEqual(state.doses[.coreAntiExt], 30)
        XCTAssertEqual(state.sets[.lunge], 4)
        XCTAssertEqual(state.sub[.squat], 1)
        XCTAssertEqual(state.cut[.pull], 1)
        XCTAssertEqual(state.shownDose(.squat, variation: 2), 15)
        XCTAssertEqual(state.shownDose(.coreAntiExt, variation: 1), 45)
        XCTAssertEqual(state.setsHold[.lunge], 2)
        XCTAssertEqual(state.shownWork[.squat], 27)
        XCTAssertEqual(state.shownOrd[.squat], 17)
        XCTAssertEqual(state.failStreak[.pull], 1)
        XCTAssertEqual(state.lastHard, [.pull])
        XCTAssertEqual(state.lessRun, 1)
        XCTAssertEqual(state.creditPaused, [.pullBar])
        XCTAssertEqual(state.returnRun, 1)
        XCTAssertEqual(state.lessHist[.pull], 5)
        XCTAssertEqual(state.rampWindow, 4)
        XCTAssertEqual(state.weekGain[.squat], 2)
        XCTAssertEqual(state.weekAgeDays, 3.5)
    }

    func testRelease244RecordReadsEveryKey() throws {
        let record = try XCTUnwrap(loadFixture().records.last)
        XCTAssertEqual(record.sessionNumber, 12)
        XCTAssertEqual(record.date, Date(timeIntervalSinceReferenceDate: 780_000_000))
        XCTAssertEqual(record.result, .more)
        XCTAssertEqual(record.totalProgressAfter, 143)
        let squat = try XCTUnwrap(record.exercises?.first)
        XCTAssertEqual(squat.variation, 3)
        XCTAssertEqual(squat.loads, [10, 9, 9])
        XCTAssertEqual(squat.probe?.variation, 4)
        XCTAssertEqual(record.actuals?[.squat], 9)
        XCTAssertEqual(record.setActuals?[.squat], [10, 9, 8])
        XCTAssertEqual(record.probes?[.squat], 6)
        XCTAssertEqual(record.setsSkipped?[.pull], 1)
        XCTAssertEqual(record.skipped, [.calf])
        XCTAssertEqual(record.positionsAfter?[.squat]?.sub, 1)
        XCTAssertEqual(record.positionsAfter?[.pull]?.cut, 1)
        XCTAssertEqual(record.durationSec, 1980)
        XCTAssertEqual(record.warmupSec, 300)
        XCTAssertEqual(record.cooldownSec, 240)
        XCTAssertEqual(record.healthExported, true)
        XCTAssertEqual(record.interrupted, .calf)
        XCTAssertEqual(record.raisedSteps?[.squat], 1)
        XCTAssertEqual(record.raisedLanded?[.squat], 1)
    }

    func testRelease244SettingsReadEveryKey() throws {
        let settings = try loadFixture().settings
        XCTAssertEqual(settings.restWeekdays, [1, 4])
        XCTAssertFalse(settings.soundsEnabled)
        XCTAssertTrue(settings.reminderEnabled)
        XCTAssertEqual(settings.reminderHour, 19)
        XCTAssertEqual(settings.reminderMinute, 30)
        XCTAssertTrue(settings.healthEnabled)
        XCTAssertEqual(settings.healthExportedThrough, 12)
        XCTAssertEqual(settings.bodyMassKg, 78.5)
        XCTAssertTrue(settings.bodyMassFromHealth)
        XCTAssertEqual(settings.bodyMassDate, Date(timeIntervalSinceReferenceDate: 779_990_000))
        XCTAssertTrue(settings.onboardingCompleted)
        XCTAssertTrue(settings.hasOpenedTechnique)
        XCTAssertTrue(settings.hasReportedOwnNumber)
        XCTAssertTrue(settings.playsTonesInSilentMode)
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.planMoves?.byHand, [.squat])
        XCTAssertEqual(settings.ratingMoves?.byRating, [.pull])
        XCTAssertNil(settings.migrationNoticePending, "a v3 file is not a migration")
    }
}
