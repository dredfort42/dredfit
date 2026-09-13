//
//  What the calendar side of the store says: the week card's number and the
//  word the cards use for the next training day (`AppStore+Calendar.swift`).
//
//  The file sat at 75 % with the uncovered part concentrated in two places:
//  the branch that reads a record written before the scale changed, and the
//  hardcoded Russian and Portuguese weekday phrases. The first is closed here.
//  The second cannot be — see the note at the bottom of the file; it is a
//  locale-dependent branch of user-facing text that no gate looks at, unit
//  test plan and localization check included.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class CalendarCaptionTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-caption" }

    /// ISO week Mon 6 Jul 2026 – Sun 12 Jul 2026. Every date below names its
    /// weekday so a reader does not have to look one up.
    private var monday: Date { date(2026, 7, 6) }
    private var wednesday: Date { date(2026, 7, 8) }
    private var saturday: Date { date(2026, 7, 11) }
    private var sunday: Date { date(2026, 7, 12) }

    /// The journal is seeded directly rather than through `completeWorkout`,
    /// because `completeWorkout` always stamps a `totalProgressAfter` and the
    /// branch under test exists only for records that carry none — the ones
    /// written before v3, by a build whose number meant something else.
    private func journalEntry(_ day: Date, progress: Int?) -> WorkoutRecord {
        WorkoutRecord(sessionNumber: 1, date: day, result: .plan, totalProgressAfter: progress)
    }

    // MARK: - The week card's number

    func test_weekSummary_whenTheWeeksLastRecordPredatesTheScale_readsZeroRatherThanTheBaselineBackwards() {
        let store = AppStore(storageURL: tempURL)
        store.records = [journalEntry(date(2026, 7, 3), progress: 40),   // Friday, the week before
                         journalEntry(wednesday, progress: nil)]         // written before v3

        let week = store.weekSummary(for: wednesday)

        XCTAssertEqual(week.workouts, 1, "the workout itself happened and still counts")
        XCTAssertEqual(week.stepsDelta, 0,
                       "a week that straddles the update measures from zero: subtracting the baseline "
                       + "from a missing number would print the whole history back as a loss")
    }

    func test_weekSummary_whenTheWeekEndsLowerThanItStarted_reportsTheDropInsteadOfHidingIt() {
        let store = AppStore(storageURL: tempURL)
        store.records = [journalEntry(date(2026, 7, 3), progress: 40),
                         journalEntry(wednesday, progress: 30)]

        XCTAssertEqual(store.weekSummary(for: wednesday).stepsDelta, -10,
                       "a deload week is negative, and that is honest rather than an error to clamp away")
    }

    // MARK: - The word for the next training day

    func test_nextTrainingDateLabel_forAGivenDay_speaksFromThatDayAndNotFromToday() {
        let store = AppStore(storageURL: tempURL)
        // Saturday and Sunday off, so Monday is the next training day seen
        // from either — the same date, two different words.
        store.settings.restWeekdays = [7, 1]

        let fromSaturday = store.nextTrainingDateLabel(from: saturday)
        let fromSunday = store.nextTrainingDateLabel(from: sunday)

        XCTAssertEqual(store.nextTrainingDate(from: saturday),
                       store.nextTrainingDate(from: sunday),
                       "the fixture must aim both days at the same Monday, or the words below "
                       + "are allowed to differ for an uninteresting reason")
        XCTAssertEqual(fromSunday, String(localized: "tomorrow"),
                       "one day before it, the next training day is tomorrow")
        XCTAssertNotEqual(fromSaturday, fromSunday,
                          "two days before it, it is not — the widget carries one label PER DAY because "
                          + "a relative word baked at write time reads wrong on every later entry")
        XCTAssertNotEqual(fromSaturday, String(localized: "today"),
                          "and it is certainly not today: Saturday is a rest day here")
    }

    func test_nextTrainingDate_whenEveryWeekdayIsMarkedAsRest_stopsAfterASingleWeek() throws {
        let store = AppStore(storageURL: tempURL)
        // `toggleRestDay` refuses the seventh day, so this state can only
        // arrive from a file — a restored backup, or one edited by hand. The
        // hop limit is the whole defence: without it the search never ends.
        store.settings.restWeekdays = Set(1...7)

        let aWeekOn = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday),
                                    "the calendar must be able to step a week forward")

        XCTAssertEqual(store.nextTrainingDate(from: monday), aWeekOn,
                       "the search gives up after exactly seven hops rather than walking forever")
    }
}

// NOT COVERED HERE, and not coverable from a unit test as the code stands:
//
//  * `AppStore.russianOnWeekday(_:)` — the seven accusative forms Russian
//    needs, which the wide-weekday formatter cannot give ("в среду", not
//    "в среда").
//  * The Portuguese branch of `nextTrainingDateLabel(from:)` — "no " for a
//    masculine weekday, "na " for a feminine one.
//
// Both are chosen by `Locale.current.language.languageCode`, which is process
// state a test cannot set through any API, and the test plan pins en/US. The
// Russian strings are additionally hardcoded in the source rather than living
// in a catalog, so `check_localization.py` does not see them either: two of
// the six shipping locales have no gate of any kind on this caption.
//
// The minimal change that would make them testable: lift the decision into a
// pure function on `AppStore+Calendar.swift` —
// `static func weekdayPhrase(languageCode: Locale.LanguageCode?, weekdayIndex: Int,
//                            weekdayName: String) -> String`
// — and have `nextTrainingDateLabel(from:)` call it with
// `Locale.current.language.languageCode`. The locale then becomes a PARAMETER
// instead of the environment, and the seven Russian and seven Portuguese forms
// are one table-driven test.
