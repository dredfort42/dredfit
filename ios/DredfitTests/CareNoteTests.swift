//
//  The care card's acknowledgement (#101): one timestamp recording that the
//  contraindication checklist was on screen and confirmed — statements, not
//  questions, and nothing else is stored or gated on it.
//

import XCTest
@testable import Dredfit

@MainActor
final class CareNoteTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-care" }

    /// Completing the onboarding — reachable only through the care card's
    /// button since #101 — records the acknowledgement, and it survives a
    /// relaunch.
    func testCompletingOnboardingRecordsTheAcknowledgement() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertNil(store.settings.careAcknowledgedAt)

        store.completeOnboarding()
        XCTAssertTrue(store.settings.onboardingCompleted)
        XCTAssertNotNil(store.settings.careAcknowledgedAt)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertNotNil(reloaded.settings.careAcknowledgedAt,
                        "the acknowledgement must survive a relaunch")
    }

    /// A settings block written before the field existed decodes with a nil
    /// acknowledgement — no migration, and existing users are not asked
    /// retroactively (the onboarding requires an empty journal anyway).
    func testOldSettingsDecodeWithoutTheField() throws {
        let old = """
        {"restWeekdays":[1],"soundsEnabled":true,"reminderEnabled":false,
         "reminderHour":9,"reminderMinute":0,"onboardingCompleted":true}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertTrue(settings.onboardingCompleted)
        XCTAssertNil(settings.careAcknowledgedAt,
                     "an absent field must decode as nil, not fail or invent a date")
    }

    /// The field round-trips: what one build writes, the next one reads.
    func testAcknowledgementRoundTripsThroughCoding() throws {
        var settings = AppSettings()
        settings.careAcknowledgedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.careAcknowledgedAt, settings.careAcknowledgedAt)
    }
}
