//
//  v2.13 (spec §23 / #134, #147): the trainee's own rhythm is not a break,
//  and the training day changes at 4 a.m., not midnight.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class CadenceTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!
    private let cal = Calendar.current

    /// A fixed Monday noon, so every date in these tests is deterministic
    /// no matter when the suite runs.
    private var base: Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12))!
    }

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-cadence-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    private func date(day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        // Not date(bySettingHour:) — that one searches forward and would jump
        // to the next day for any hour earlier than noon.
        var comps = cal.dateComponents([.year, .month, .day],
                                       from: cal.date(byAdding: .day, value: day, to: base)!)
        comps.hour = hour
        comps.minute = minute
        return cal.date(from: comps)!
    }

    /// A store whose journal holds one workout per given date, with every
    /// pattern parked at `level`.
    private func store(workoutsAt dates: [Date], level: Int = 20) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let records = dates.enumerated().map { i, d in
            "{\"sessionNumber\":\(i + 1),\"date\":\(d.timeIntervalSinceReferenceDate)," +
            "\"result\":\"plan\",\"totalLevelAfter\":\(level * 9)}"
        }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(dates.count),"levels":[\(levels)],"failStreak":[\(zeros)]},
         "records":[\(records)],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    // MARK: - The training day (v2.24, spec §35.4 / #147)

    /// v2.24: RE-MARKED from whole elapsed 24-hour periods to CALENDAR days in
    /// the local zone, with the cause. Everything about rhythm is calendar-
    /// shaped in the trainee's head — "yesterday", "every Sunday", "two weeks
    /// off" — and elapsed-hours arithmetic disagreed with all of it: Monday
    /// 23:00 → Tuesday 01:00 was ZERO days. The thresholds themselves did not
    /// move; what a day IS did.
    func testTrainingDaysAreCalendarDays() {
        let start = date(day: 0, hour: 23)
        XCTAssertEqual(AppStore.trainingDays(from: start, to: start.addingTimeInterval(2 * 3600)), 1,
                       "23:00 Monday and 01:00 Tuesday are two different days")
        XCTAssertEqual(AppStore.trainingDays(from: date(day: 0, hour: 0, minute: 30),
                                             to: date(day: 0, hour: 23, minute: 30)), 0,
                       "almost a whole day inside one date is still no day at all")
        XCTAssertEqual(AppStore.trainingDays(from: start, to: start.addingTimeInterval(7 * 86400)), 7)
        XCTAssertEqual(AppStore.trainingDays(from: date(day: 0, hour: 9),
                                             to: date(day: 20, hour: 9)), 20,
                       "daytime training is counted as before")
        XCTAssertEqual(AppStore.trainingDays(from: start, to: start.addingTimeInterval(-3600)), 0,
                       "a clock set backwards never yields a negative gap")
    }

    /// The autumn clock change makes one day 25 hours long. Elapsed-hours
    /// arithmetic read that as 1 day only by luck and read the 23-hour spring
    /// day as 0; `startOfDay` is right about both. The zone is named
    /// explicitly — the test must not depend on where the runner sits.
    func testTheClockChangeNeitherAddsNorEatsADay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        // 25.10.2026, 03:00 -> 02:00. Evening before to evening after.
        let autumnEve = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 22)))
        let autumnNext = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 22)))
        XCTAssertEqual(
            AppStore.trainingDays(from: autumnEve, to: autumnNext, calendar: cal), 1,
            "the 25-hour day is exactly one day")

        // 29.03.2026, 02:00 -> 03:00 — the 23-hour day, the other direction.
        let springEve = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 3, day: 28, hour: 22)))
        let springNext = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 3, day: 29, hour: 22)))
        XCTAssertEqual(
            AppStore.trainingDays(from: springEve, to: springNext, calendar: cal), 1,
            "and so is the 23-hour one")
    }

    /// A flight west moves the phone's zone between two workouts, which can
    /// put the later one on an EARLIER local date than the arithmetic expects.
    /// The gap the engine reads is clamped at zero either way — no negative
    /// gap ever reaches `applySilentDecay` or `applyComeback`.
    func testAZoneChangeBetweenSessionsNeverGoesNegative() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))

        // Trained in Tokyo on the morning of the 2nd, then flew east across the
        // date line and trained again "the same evening" — which in Honolulu is
        // still the 1st.
        let inTokyo = try XCTUnwrap(tokyo.date(from: DateComponents(
            year: 2026, month: 6, day: 2, hour: 9)))
        let afterFlight = inTokyo.addingTimeInterval(4 * 3600)
        XCTAssertEqual(
            AppStore.trainingDays(from: inTokyo, to: afterFlight, calendar: honolulu), 0,
            "a westward flight must not produce a negative gap")
        XCTAssertEqual(
            AppStore.trainingDays(from: afterFlight, to: inTokyo, calendar: honolulu), 0,
            "and neither must reading the journal backwards")
    }

    func testShiftWorkerRitualIsCarriedByTheRhythmNotByTheDayCount() throws {
        // True 6.0-day cadence with the hour drifting 23:00 <-> 01:00 across
        // midnight. v2.24: RE-MARKED from [5, 6, 5] to [5, 7, 5], with the
        // cause. Under calendar days the drift genuinely straddles midnights,
        // so the ritual reads 7/5 rather than 6/5 — and the thing that keeps it
        // out of the decay is the rhythm detector (§23.2), not the definition
        // of a day: a 7 that matches an earlier 7 within ±1 is this trainee's
        // own rhythm. The price is one decay on the FIRST such gap, before
        // there is any rhythm to recognise — named in spec §35.4, not hidden.
        var dates = [date(day: 0, hour: 23)]
        for i in 0..<4 {
            let drift: TimeInterval = i.isMultiple(of: 2) ? 2 * 3600 : -2 * 3600
            dates.append(dates[dates.count - 1].addingTimeInterval(6 * 86400 + drift))
        }
        let s = try store(workoutsAt: dates)
        XCTAssertEqual(s.recentGaps, [5, 7, 5])
        let next = try XCTUnwrap(dates.last).addingTimeInterval(6 * 86400 + 2 * 3600)
        XCTAssertEqual(s.gapDays(now: next), 7)
        XCTAssertTrue(s.isRhythmBreak(7),
                      "a 7 among 7s is the ritual, not a break in it")
    }

    // MARK: - The fractional gap the engine reads (v2.19, spec §30.8)

    /// `trainingDays` counts midnights, which is right for the decay, the
    /// comeback and the rhythm — and wrong for the one argument the engine's
    /// weekly window reads. `gapFraction` keeps the fraction of real elapsed
    /// time (spec §30.8); the two must not be confused, and v2.24 did not
    /// touch the second one.
    func testTheFractionalGapKeepsWhatTheTrainingDayThrowsAway() throws {
        let s = try store(workoutsAt: [date(day: 0, hour: 8)])
        let sameEvening = date(day: 0, hour: 20)
        XCTAssertEqual(s.gapDays(now: sameEvening), 0, "half a day is no training day")
        XCTAssertEqual(try XCTUnwrap(s.gapFraction(now: sameEvening)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.gapFraction(now: date(day: 3, hour: 8))), 3,
                       "and a whole gap is still the whole gap")
        XCTAssertEqual(try XCTUnwrap(s.gapFraction(now: date(day: 0, hour: 2))), 0,
                       "a clock set backwards never yields a negative gap")
    }

    func testAnEmptyJournalHasNoGapAtAll() {
        let fresh = AppStore(storageURL: tempURL)
        XCTAssertNil(fresh.gapFraction(), "nothing to measure from")
    }

    /// The defect end to end: two workouts in one day used to hand the engine
    /// a gap of zero, so the weekly window never aged and its growth budget
    /// was spent once for good.
    func testTwoWorkoutsInOneDayStillAgeTheWeeklyWindow() throws {
        let s = try store(workoutsAt: [date(day: 0, hour: 8)], level: 0)
        s.completeWorkout(session: s.nextSession, result: .plan,
                          date: date(day: 0, hour: 20))
        XCTAssertEqual(s.engineState.weekAgeDays, 0.5, accuracy: 1e-9,
                       "the window ages by the half day that really passed")
    }

    // MARK: - The rhythm and the silent decay (#134)

    func testWeeklyRhythmSkipsSilentDecayAndLeavesNoStamp() throws {
        let s = try store(workoutsAt: [0, 7, 14, 21].map { date(day: $0) })
        s.applySilentDecayIfNeeded(now: date(day: 28))
        XCTAssertEqual(s.engineState.levels[.pull], 20, "a 7-day gap in a 7-day rhythm is not a break")
        XCTAssertNil(s.settings.silentDecayAppliedFor, "a skipped decay leaves no stamp")
    }

    func testRhythmToleratesOneDayOfJitter() throws {
        let s = try store(workoutsAt: [0, 7, 14, 21].map { date(day: $0) })
        s.applySilentDecayIfNeeded(now: date(day: 29))
        XCTAssertEqual(s.engineState.levels[.pull], 20, "8 is within ±1 of the 7-day rhythm")

        let jittered = try store(workoutsAt: [0, 6, 14, 21].map { date(day: $0) })
        XCTAssertEqual(jittered.recentGaps, [6, 8, 7])
        jittered.applySilentDecayIfNeeded(now: date(day: 28))
        XCTAssertEqual(jittered.engineState.levels[.pull], 20, "jitter 6-8 is still one rhythm")
    }

    func testRhythmIsRememberedThroughAnOutlier() throws {
        // The matching gap is NOT the most recent one — a rule that consulted
        // only the last gap would decay here (the review's surviving mutation).
        let s = try store(workoutsAt: [0, 7, 14, 24].map { date(day: $0) })
        XCTAssertEqual(s.recentGaps, [7, 7, 10])
        s.applySilentDecayIfNeeded(now: date(day: 31))
        XCTAssertEqual(s.engineState.levels[.pull], 20,
                       "gap 7 matches the weekly rhythm remembered through the 10-day slip")
    }

    func testMidCycleOpenIsNotABreak() throws {
        // Reminders fire on every non-rest day: a 10-day-cadence trainee
        // opens the app on days 7-9 of the cycle. That silence has not yet
        // outgrown the rhythm — no decay, no stamp.
        let s = try store(workoutsAt: [0, 10, 20, 30].map { date(day: $0) })
        for day in [37, 38, 39] {
            s.applySilentDecayIfNeeded(now: date(day: day))
        }
        XCTAssertEqual(s.engineState.levels[.pull], 20)
        XCTAssertNil(s.settings.silentDecayAppliedFor)
    }

    func testMidCycleOpenDoesNotSummonTheCard() throws {
        // An every-three-weeks ritual: opening the app on days 14-19 of the
        // cycle must not show the card whose primary button drops levels.
        let s = try store(workoutsAt: [0, 21, 42, 63].map { date(day: $0) })
        XCTAssertFalse(s.shouldOfferComeback(now: date(day: 77)), "day 14 of the cycle")
        XCTAssertFalse(s.shouldOfferComeback(now: date(day: 82)), "day 19 of the cycle")
        XCTAssertTrue(s.shouldOfferComeback(now: date(day: 86)),
                      "two days past the ritual the break is real")
    }

    func testOneVacationDoesNotShieldTheNextAbsence() throws {
        // The mid-cycle window comes only from repeating gaps: a weekly
        // trainee with one 60-day vacation behind them must still get the
        // card when they vanish for 30 days.
        let s = try store(workoutsAt: [0, 7, 14, 74].map { date(day: $0) })
        XCTAssertEqual(s.recentGaps, [7, 7, 60])
        XCTAssertTrue(s.shouldOfferComeback(now: date(day: 104)))
    }

    func testOneOffBreakInATwiceAWeekRhythmStillDecays() throws {
        let s = try store(workoutsAt: [0, 3, 7, 10].map { date(day: $0) })
        XCTAssertEqual(s.recentGaps, [3, 4, 3])
        s.applySilentDecayIfNeeded(now: date(day: 18))
        XCTAssertEqual(s.engineState.levels[.pull], 19, "an 8-day gap is a real one-off break here")
        XCTAssertNotNil(s.settings.silentDecayAppliedFor)
    }

    func testSameBreakCanStillDecayAfterOutgrowingTheRhythm() throws {
        let s = try store(workoutsAt: [0, 7, 14, 21].map { date(day: $0) })
        s.applySilentDecayIfNeeded(now: date(day: 29))
        XCTAssertEqual(s.engineState.levels[.pull], 20, "gap 8 matched the rhythm")
        s.applySilentDecayIfNeeded(now: date(day: 31))
        XCTAssertEqual(s.engineState.levels[.pull], 19,
                       "no stamp was left, so the same break decays once it outgrows the rhythm")
    }

    // MARK: - The rhythm and the comeback card (#134)

    func testFortnightRhythmSilencesTheCard() throws {
        let s = try store(workoutsAt: [0, 14, 28].map { date(day: $0) })
        XCTAssertFalse(s.shouldOfferComeback(now: date(day: 42)),
                       "a steady 14-day rhythm gets no card at all")
        s.acceptComeback(now: date(day: 42))
        XCTAssertEqual(s.engineState.levels[.pull], 20, "and no drop through the guarded accept")
        XCTAssertEqual(s.engineState.returnRun, 0)
    }

    func testBrokenRhythmStillOffersTheCard() throws {
        let weekly = try store(workoutsAt: [0, 7, 14, 21].map { date(day: $0) })
        XCTAssertTrue(weekly.shouldOfferComeback(now: date(day: 41)),
                      "a 20-day gap breaks the weekly rhythm — a real break")

        let firstEver = try store(workoutsAt: [date(day: 0)])
        XCTAssertEqual(firstEver.recentGaps, [])
        XCTAssertTrue(firstEver.shouldOfferComeback(now: date(day: 20)),
                      "one workout has no rhythm yet")
    }

    func testNonStackingSurvivesASkippedDecay() throws {
        let s = try store(workoutsAt: [0, 7, 14, 21].map { date(day: $0) })
        s.applySilentDecayIfNeeded(now: date(day: 29))
        XCTAssertEqual(s.comebackDrop(now: date(day: 36)), 2,
                       "no silent decay was taken, so the comeback is the full table amount")
    }

    // SNIPPED v2.26 (§37.0): `testIllnessTapStaysForRhythmBreaks`. The quiet
    // "I was sick" offer is gone with the lens it armed. The rhythm-break rule
    // it leaned on — a 14+ day gap that is the person's own rhythm carries no
    // comeback card — is asserted by the comeback tests in this same file.
}
