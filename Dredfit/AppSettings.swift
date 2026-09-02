//
//  The user's own choices, stored beside the engine state and the journal
//  in the same file. Split out of AppStore.swift, which had grown to within
//  fifty lines of the lint's hard ceiling; the type is unchanged.
//

import Foundation

/// Decoding is field-by-field tolerant — every key optional with a default, so
/// files written by any older version keep loading losslessly.
struct AppSettings: Codable, Equatable {
    /// Calendar weekday numbers: 2 = Monday, 4 = Wednesday, 6 = Friday — four
    /// workouts a week, on Sun/Tue/Thu/Sat.
    ///
    /// THREE rest days, not two. Each of the eight rotating patterns stands in
    /// 5 of every 8 sessions, so N workouts a week are 0.625 × N appearances
    /// per pattern against an evidence corridor of 2–3 (ACSM 2011, the source
    /// §28.5 already rests on): four workouts land at 2.5, the five the old
    /// default shipped landed at 3.1. The engine says the same from its own
    /// side — the pull slot stands in EVERY session against a weekly budget of
    /// three (`weeklyRiseSlow`), so a fifth session inside one week cannot
    /// grow it at all. And the app already said it in words on two screens:
    /// "3–4 workouts a week" in How it works and "2–3 rest days a week" under
    /// the chips overlap in exactly one place, and this is it.
    ///
    /// Spread, never adjacent: the gaps come out 1-2-2-2, so no day is ever
    /// the third training day in a row — the point where the plan starts
    /// offering rest instead (`todayWouldExtendALongRun`).
    ///
    /// Fresh installs only — the decode below keeps whatever an older file
    /// holds (#36: an upgrade must not add a rest day the person never chose).
    var restWeekdays: Set<Int> = [2, 4, 6]
    var soundsEnabled = true
    var reminderEnabled = false
    var reminderHour = 9
    var reminderMinute = 0
    var healthEnabled = false
    var healthExportedThrough = 0      // high-water sessionNumber already in Health
    /// Always kilograms, whatever unit the field displayed: a file that
    /// carries pounds one day and kilograms the next cannot be read back.
    /// Absent means absent — no default stands in, because a calorie count
    /// built on a guessed 75 kg is indistinguishable in Health from a true one.
    var bodyMassKg: Double?
    /// True while the weight above came from Health rather than from the
    /// field. The phone has ONE owner, so Health is the truth about their
    /// weight and it is re-read on every activation — which makes an editable
    /// row a lie: a number typed into it would be silently replaced by the
    /// next foreground. So the row goes read-only exactly while this is set,
    /// and the field comes back for the case that needs it — Health holding no
    /// weight, or the read refused (HealthKit will not say which).
    ///
    /// Persisted rather than held in memory because the async read lands
    /// AFTER the first render: without a remembered answer the row would come
    /// up editable on every launch and turn read-only a moment later.
    var bodyMassFromHealth = false
    /// The escape hatch behind the overlap sweep. HealthKit never says whether
    /// a read was granted, so a refusal looks exactly like "no other workout
    /// found" — and that is precisely the person whose watch is recording the
    /// same session. This is how they can say so themselves.
    ///
    /// A second job since the weight started following Health: this is the one
    /// switch that says "write no estimate at all", because clearing the
    /// weight can no longer say it. The NAME is the wire key in every saved
    /// file and does not move; the label on screen names the effect.
    var watchRecordsWorkouts = false
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
    /// Whether a technique sheet has ever been opened, from any of the three
    /// doors that lead to one. It gates ONE line on Today — the sentence that
    /// says a plan row opens the sheet, and that the variation one step below
    /// lives in there (R30). A flag rather than `records.isEmpty`, because the
    /// person who most needs the sentence is the one carried over from v2:
    /// their journal is full, and a gate on history would never show it to
    /// them at all. Once they have been through the door, the sentence has no
    /// job left.
    var hasOpenedTechnique = false
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
        case healthEnabled, healthExportedThrough, bodyMassKg, watchRecordsWorkouts
        case bodyMassFromHealth
        case onboardingCompleted, careAcknowledgedAt, lastReviewRequestAt
        case comebackDecidedFor, weakLinkPromptAnsweredFor
        case silentDecayAppliedFor, migrationNoticePending, hasOpenedTechnique
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
        bodyMassKg = try c.decodeIfPresent(Double.self, forKey: .bodyMassKg)
        // Absent reads as "typed by hand", which is what every file written
        // before this key holds: the row stays editable until Health answers.
        //
        // AND never true without a weight to be true ABOUT. The pair is an
        // invariant of the code that writes it, not of the file: a backup is
        // a JSON a person can edit, and `true` with no weight left the row
        // read-only at "Not set" — calories off, no field to fix it in.
        bodyMassFromHealth = (try c.decodeIfPresent(Bool.self, forKey: .bodyMassFromHealth) ?? false)
            && bodyMassKg != nil
        watchRecordsWorkouts = try c.decodeIfPresent(Bool.self, forKey: .watchRecordsWorkouts) ?? false
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
        // Absent means "never opened one", which is exactly right for a file
        // written before this key existed: the sentence is shown once and
        // spent by the first visit to the sheet.
        hasOpenedTechnique = try c.decodeIfPresent(Bool.self, forKey: .hasOpenedTechnique) ?? false
    }
}
