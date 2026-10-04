import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ComebackTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-comeback" }

    /// The dose every seeded movement stands at, and the one a comeback walks
    /// down from: the ceiling of `pull`'s second variation. Above the dose
    /// floor a return is measured in rungs of dose — one rep per set — so the
    /// assertions below on where a comeback lands, all on `pull`, read the
    /// dose and nothing else.
    static let seededDose = 15

    private func storeWithLastWorkout(daysAgo: Int) throws -> AppStore {
        // Midnights, not elapsed seconds — see AppStoreTestCase.daysAgo for
        // why (#172, DST). 13/14 and 89/90 are precisely the edges this
        // suite is about, so the seed has to land on the right calendar day.
        // `self.` is load-bearing: the parameter above shadows the inherited
        // method of the same name.
        let date = try self.daysAgo(daysAgo)
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",2" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(Self.seededDose)" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        // The journal of what was shown, which a descent out of a variation
        // lands under. In the comebacks below, `pull` — the one movement
        // asserted on — stays inside variation 2; the hold ladders, seeded on
        // their 15 s floor, cross into variation 1.
        let shown = Pattern.allCases
            .map { "\"\($0.rawValue)\",{\"1\":\(Self.seededDose),\"2\":\(Self.seededDose)}" }
            .joined(separator: ",")
        // Dates encode as seconds since the reference date by default.
        let stamp = date.timeIntervalSinceReferenceDate
        let json = """
        {"engineState":{"counter":11,"vars":[\(vars)],"doses":[\(doses)],
                        "shown":[\(shown)],"failStreak":[\(zeros)]},
         "records":[{"sessionNumber":11,"date":\(stamp),"result":"plan",
                     "totalProgressAfter":100}],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        let store = makeStore()
        XCTAssertEqual(store.engineState.doses[.pull], Self.seededDose,
                       "the seed must actually load — a state that failed to decode "
                       + "would start clean and make every assertion here vacuous")
        return store
    }

    // MARK: - When the card appears

    func testNoCardBelowTwoWeeks() throws {
        for days in [0, 1, 7, 13] {
            let store = try storeWithLastWorkout(daysAgo: days)
            XCTAssertFalse(store.shouldOfferComeback(), "\(days) days is not a break yet")
        }
    }

    func testCardAppearsFromFourteenDays() throws {
        for days in [14, 30, 200] {
            let store = try storeWithLastWorkout(daysAgo: days)
            XCTAssertTrue(store.shouldOfferComeback(), "\(days) days should offer the card")
        }
    }

    func testNoCardWithoutHistory() {
        let store = makeStore()
        XCTAssertFalse(store.shouldOfferComeback(),
                       "a fresh install has nothing to come back from")
        XCTAssertNil(store.gapDays())
    }

    /// `gapDays` counts the midnights in between, not whole elapsed days (#172).
    func test_gapDays_afterTwentyCalendarDays_countsTheMidnights() throws {
        let store = try storeWithLastWorkout(daysAgo: 20)
        XCTAssertEqual(store.gapDays(), 20,
                       "twenty midnights lie between the last workout and now")
    }

    // MARK: - What the answers do

    func testStartEasierLowersThePlanAndClosesTheQuestion() throws {
        let store = try storeWithLastWorkout(daysAgo: 35)

        store.acceptComeback()

        // 35 days is a three-rung drop, read where it lands: on the dose.
        XCTAssertEqual(store.engineState.doses[.pull], Self.seededDose - 3)
        XCTAssertEqual(store.engineState.counter, 11, "a comeback is not a workout")
        XCTAssertEqual(store.records.count, 1, "nothing is written to the journal")
        XCTAssertFalse(store.shouldOfferComeback(), "the question is answered for this break")
    }

    func testLeaveAsItWasChangesNothingButStillCloses() throws {
        let store = try storeWithLastWorkout(daysAgo: 35)

        store.declineComeback()

        XCTAssertEqual(store.engineState.doses[.pull], Self.seededDose, "the plan is untouched")
        XCTAssertFalse(store.shouldOfferComeback(), "but the card does not come back")
    }

    func testDecisionSurvivesRelaunch() throws {
        let store = try storeWithLastWorkout(daysAgo: 40)
        store.declineComeback()

        let reloaded = makeStore()
        XCTAssertFalse(reloaded.shouldOfferComeback(),
                       "the answer is persisted, not just held in memory")
    }

    func testTheQuestionIsAskedAgainAfterTheNextWorkout() throws {
        let store = try storeWithLastWorkout(daysAgo: 40)
        store.declineComeback()
        XCTAssertFalse(store.shouldOfferComeback())

        // A workout happens, then another long break of a different length.
        // A repeat of the same gap is the trainee's rhythm and stays quiet —
        // CadenceTests cover that side.
        // Calendar arithmetic, like the seed: a DST transition inside the
        // window must not turn this 30-day gap into 29 or 31.
        let thirtyDaysAgo = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -30, to: .now),
                                          "the calendar must be able to step 30 days back")
        store.completeWorkout(session: store.nextSession, result: .plan, date: thirtyDaysAgo)
        XCTAssertTrue(store.shouldOfferComeback(),
                      "a break off the rhythm is a new question")
    }

    // MARK: - Fresh start

    func testFreshStartOnlyOfferedAfterANinetyDayBreak() throws {
        // From a quarter away, not half a year — after 90 days "as it was" is
        // blind enough that "from scratch" must be on the card.
        XCTAssertFalse(try storeWithLastWorkout(daysAgo: 89).offersFreshStart(),
                       "89 midnights is one short of the offer")
        XCTAssertTrue(try storeWithLastWorkout(daysAgo: 90).offersFreshStart(),
                      "90 midnights is the boundary, and it is inclusive")
    }

    func testFreshStartResetsProgressButKeepsHistoryAndTheBar() throws {
        let store = try storeWithLastWorkout(daysAgo: 200)
        store.setHasBar(true)

        store.resetProgress()

        XCTAssertEqual(store.engineState.vars[.pull], 1, "back to the first variation")
        XCTAssertEqual(store.engineState.doses[.pull], Dose.grid(Library.unit(.pull, 1)).min,
                       "and to the floor of the grid")
        XCTAssertEqual(store.engineState.counter, 0)
        XCTAssertEqual(store.records.count, 1, "the journal survives")
        XCTAssertTrue(store.engineState.hasBar,
                      "the pull-up bar did not disappear from the doorway")
    }

    // MARK: - Migration

    /// A file this old migrates both halves: what the person chose — rest
    /// days, reminders, Health — and what they earned.
    func testV14FileKeepsItsSettingsAndMigratesTheEngine() throws {
        let v14 = """
        {"engineState":{"counter":6,
          "levels":["squat",9,"push_h",8,"hinge",7,"pull",6,"push_v",5,"lunge",4,
                    "core_anti_ext",3,"core_rot",2,"calf",1,"pull_bar",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",1,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0]},
         "records":[],
         "settings":{"restWeekdays":[3],"soundsEnabled":false,
                     "reminderEnabled":true,"reminderHour":18,"reminderMinute":45,
                     "healthEnabled":true,"healthExportedThrough":5,
                     "onboardingCompleted":true}}
        """
        try Data(v14.utf8).write(to: tempURL)
        let store = makeStore()

        // everything the old file knew survives
        XCTAssertEqual(store.settings.restWeekdays, [3])
        XCTAssertEqual(store.settings.reminderHour, 18)
        XCTAssertEqual(store.settings.reminderMinute, 45)
        XCTAssertTrue(store.settings.healthEnabled)
        XCTAssertEqual(store.settings.healthExportedThrough, 5)
        XCTAssertTrue(store.settings.onboardingCompleted)
        // …and so does the engine. Old level 6 is tier 1 of the removed
        // encoding at 3×14, and tier 1 of `pull` maps to variation 1 —
        // the dose is what makes it a migration and not a reset, which is why
        // it is asserted beside the variation and not left to speak for it.
        XCTAssertEqual(store.engineState.vars[.pull], 1)
        XCTAssertEqual(store.engineState.doses[.pull], 14)
        // The streak is EVIDENCE, not progress: dropping it would make the
        // person say "hard" twice more before the engine takes anything off.
        XCTAssertEqual(store.engineState.failStreak[.pull], 1)
        // The counter is where they are in the rotation cycle, and resetting it
        // would restart the cycle under someone mid-way through it.
        XCTAssertEqual(store.engineState.counter, 6)
        // and the new field defaults to "never asked"
        XCTAssertNil(store.settings.comebackDecidedFor)
    }

    func testComebackFieldSurvivesReload() throws {
        let store = try storeWithLastWorkout(daysAgo: 30)
        store.acceptComeback()
        let stamped = store.settings.comebackDecidedFor

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.settings.comebackDecidedFor, stamped)
    }
}
