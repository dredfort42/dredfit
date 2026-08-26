//
//  The user's own choices, stored beside the engine state and the journal
//  in the same file. Split out of AppStore.swift, which had grown to within
//  fifty lines of the lint's hard ceiling; the type is unchanged.
//

import Foundation

/// Decoding is field-by-field tolerant — every key optional with a default, so
/// files written by any older version keep loading losslessly.
struct AppSettings: Codable, Equatable {
    /// Calendar weekday numbers: 1 = Sunday, 4 = Wednesday. Fresh installs
    /// only — the decode below keeps the old single-Sunday value.
    var restWeekdays: Set<Int> = [1, 4]
    var soundsEnabled = true
    var reminderEnabled = false
    var reminderHour = 9
    var reminderMinute = 0
    var healthEnabled = false
    var healthExportedThrough = 0      // high-water sessionNumber already in Health
    var onboardingCompleted = false
    /// When the care card's checklist was acknowledged (#101). A fact, not a
    /// gate: nothing else reads it — it records that the one screen naming the
    /// contraindications was actually confirmed, not skipped past.
    var careAcknowledgedAt: Date?
    var lastReviewRequestAt: Date?
    // A date rather than a bool so it expires by itself: after the next
    // workout it is stale and a future break asks again, while the current
    // break never asks twice. Same mechanism for the silent decay below.
    var comebackDecidedFor: Date?
    /// The session number the weak-link prompt was answered for — one question
    /// per session, never a campaign.
    var weakLinkPromptAnsweredFor: Int?
    var silentDecayAppliedFor: Date?
    /// Set once, when a state written before v3 is carried over (§41.7), and
    /// cleared by the tap that closes the card on Today. It lives in the
    /// SETTINGS rather than in memory on purpose: the migration is announced
    /// exactly once, and a launch killed before the person read the card must
    /// not be the launch that spent it.
    var migrationNoticePending: Bool?
    // `pendingDiscomfort` went with the pain channel and `timeBudgetChosen` /
    // `budgetDefaultNoticeClosedAt` went with the time budget — the two flags
    // existed only to remember whether a person had ever picked a session
    // length and been told about the default, and there is no length to pick.
    // A settings file written before this wave still carries all three keys;
    // they decode away silently, because this type lists what it reads rather
    // than refusing what it does not know.

    init() {}

    private enum CodingKeys: String, CodingKey {
        case restWeekdays, soundsEnabled, reminderEnabled, reminderHour, reminderMinute
        case healthEnabled, healthExportedThrough
        case onboardingCompleted, careAcknowledgedAt, lastReviewRequestAt
        case comebackDecidedFor, weakLinkPromptAnsweredFor
        case silentDecayAppliedFor, migrationNoticePending
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // [1], not the fresh-install default: an upgrade must not add a rest
        // day the person never chose (issue #36).
        restWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .restWeekdays) ?? [1]
        soundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 9
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        healthEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthEnabled) ?? false
        healthExportedThrough = try c.decodeIfPresent(Int.self, forKey: .healthExportedThrough) ?? 0
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        careAcknowledgedAt = try c.decodeIfPresent(Date.self, forKey: .careAcknowledgedAt)
        lastReviewRequestAt = try c.decodeIfPresent(Date.self, forKey: .lastReviewRequestAt)
        comebackDecidedFor = try c.decodeIfPresent(Date.self, forKey: .comebackDecidedFor)
        weakLinkPromptAnsweredFor = try c.decodeIfPresent(Int.self, forKey: .weakLinkPromptAnsweredFor)
        // A settings file written by an older build may still carry the
        // cancelled `pendingPinned`; an unknown key decodes away silently, so
        // nothing to migrate and nothing to clean up.
        silentDecayAppliedFor = try c.decodeIfPresent(Date.self, forKey: .silentDecayAppliedFor)
        migrationNoticePending = try c.decodeIfPresent(Bool.self, forKey: .migrationNoticePending)
    }
}
