//
//  The user's own choices, stored beside the engine state and the journal
//  in the same file. Split out of AppStore.swift, which had grown to within
//  fifty lines of the lint's hard ceiling; the type is unchanged.
//

import Foundation
import DredfitCore

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
    /// "3–4 workouts a week" in How it works and "3–4 rest days a week" under
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
    /// Whether the athlete has ever reported a number of their own — used the
    /// adjuster on the work screen, once, in any workout. It gates ONE hint,
    /// the line that says the plan's number is an offer and both directions
    /// are allowed (UX review 05.09.2026, finding 11). A flag rather than a
    /// count: the hint answers "is this control here", and that question is
    /// answered forever by the first use.
    var hasReportedOwnNumber = false
    /// Warm-up moves and cool-down positions the athlete asked not to see
    /// again, by `WarmupMove.id` / `CooldownPosition.id` (finding 49). The
    /// SETTINGS remember the choice; the two composers do the filtering, and
    /// they — not this list — owe the guarantee that a block is never empty.
    /// `AppStore.maxHiddenBlockMoves` caps it for the same reason.
    var hiddenBlockMoveIDs: Set<String> = []
    /// Whether the countdown tones are allowed to play while the ringer
    /// switch is off (finding 53). Off by default: a phone silenced in a gym
    /// is silenced on purpose, and this is the athlete saying otherwise.
    ///
    /// Read by `RootView`, which pushes it into `CountdownSounds` — the audio
    /// category is process state, so the stored answer has to be re-applied
    /// once per launch as well as on the tap that changes it.
    var playsTonesInSilentMode = false
    /// The theme the app runs in (finding 54). Applied in exactly ONE place —
    /// `RootView`'s `.preferredColorScheme` — because only from there does it
    /// also cover the workout's full-screen cover and every sheet.
    var appearance: AppearanceChoice = .system
    /// The gap, in training days, the comeback question was answered at. The
    /// date above says WHICH break was answered; this says how long it was at
    /// the time, so a break that keeps growing can ask once more when it
    /// crosses a threshold that adds an offer (`shouldOfferComeback`).
    var comebackDecidedAtGap: Int?
    /// Who moved the plan AHEAD, and why — see `PlanMoves`. The handle's slot
    /// alone, stamped `counter + 1`.
    var planMoves: PlanMoves?
    /// The same facts for the workout BEHIND — the last rated session. Its own
    /// slot because the two are stamped one session apart and a single one
    /// held whichever was written last: pulling a handle for the next plan
    /// built a fresh record and erased what the rating had just named, so the
    /// history line the athlete was invited to check against the plan fell
    /// back to the generic wording, for good and without saying so
    /// (review 06.09.2026).
    var ratingMoves: PlanMoves?
    /// What it takes to change the last rating — see `RatingUndo`.
    var lastRatingUndo: RatingUndo?
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
        case hasReportedOwnNumber, hiddenBlockMoveIDs, playsTonesInSilentMode
        case appearance, comebackDecidedAtGap, planMoves, ratingMoves, lastRatingUndo
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
        hasReportedOwnNumber = try c.decodeIfPresent(Bool.self, forKey: .hasReportedOwnNumber) ?? false
        hiddenBlockMoveIDs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenBlockMoveIDs) ?? []
        playsTonesInSilentMode = try c
            .decodeIfPresent(Bool.self, forKey: .playsTonesInSilentMode) ?? false
        // `try?`: a raw value this build does not know THROWS, and the throw
        // would leave AppData's plain `try` on the settings — and with it the
        // journal — in quarantine. A file written by a build that grows a
        // fourth choice opens here on the system theme instead.
        appearance = (try? c.decodeIfPresent(AppearanceChoice.self, forKey: .appearance)) ?? .system
        comebackDecidedAtGap = try c.decodeIfPresent(Int.self, forKey: .comebackDecidedAtGap)
        // `try?`, not `try`, for these two alone: they carry a whole engine
        // state and a whole session, and AppData decodes the settings with a
        // plain `try` — one unreadable shape here would quarantine the file
        // and cost the journal. Losing an undo costs one button.
        planMoves = try? c.decodeIfPresent(PlanMoves.self, forKey: .planMoves)
        // Absent in every file written before the slot was split, which is
        // right: it fills on the next rating, and until then the history line
        // says the generic thing it already said.
        ratingMoves = try? c.decodeIfPresent(PlanMoves.self, forKey: .ratingMoves)
        lastRatingUndo = try? c.decodeIfPresent(RatingUndo.self, forKey: .lastRatingUndo)
    }
}

/// The theme the app runs in, when the athlete does not want the system's.
/// A stored choice and nothing more — mapping it onto a `ColorScheme` belongs
/// to the one view that applies it, so nothing here imports SwiftUI.
enum AppearanceChoice: String, Codable, CaseIterable {
    case system, light, dark
}

/// Why the plan stands where it does, remembered at the moment it moved.
///
/// It cannot be read back out of the journal afterwards: between two entries
/// the state is also moved by the silent decay and by an accepted comeback, so
/// the difference of two records credits the workout with a descent that was
/// not its doing (UX review 05.09.2026, findings 27 and 64 — the skeptic's
/// objection to "(+3)" in finding 56 is the same one). So the two movers that
/// CAN name themselves do, in the moment: the handle and the rating.
///
/// TWO slots hold this shape, one session apart — `planMoves` for the plan
/// ahead and `ratingMoves` for the workout just rated. One slot could not: the
/// stamps differ by one, so whichever was written last threw the other away.
struct PlanMoves: Codable, Equatable {
    /// The session these facts belong to — the `sessionNumber` of the workout,
    /// which is `engineState.counter + 1` while the plan is still ahead and
    /// `engineState.counter` once the rating has landed on it.
    /// Anything else is a stale stamp and reads as "nothing to say".
    var session: Int
    /// Movements the athlete lowered by hand ("easier"), for that session.
    var byHand: [Pattern] = []
    /// Movements the rating's descent actually landed on.
    var byRating: [Pattern] = []
}

/// What it takes to un-apply the last rating and apply another one: the state
/// BEFORE `applyFeedback` and the session it was applied to. Everything else
/// the redo needs is in the journal entry itself.
///
/// In the settings rather than in memory because the workout that most needs
/// correcting is the one nobody rated: since owner decision 1 (05.09.2026) it
/// is settled as "on plan" while the app is not even running, and the person
/// meets it only on the next launch.
struct RatingUndo: Codable, Equatable {
    var state: EngineState
    var session: Session
}

// MARK: - The switches that touch nothing but the settings

/// Here rather than in AppStore.swift for the same reason `AppStore+Backup`,
/// `+Health` and `+Reminders` are where they are: that file sits against the
/// linter's 1200-line ceiling, which is a CI error rather than a style
/// opinion. Every one of these writes ONE field and persists — each decision
/// that also moves the engine stays in AppStore.swift proper.
extension AppStore {

    /// Writes the choice and nothing else. The audio category follows from
    /// `RootView`, which observes this field — deliberately not from here, so
    /// that the third writer of the settings block gets the same treatment:
    /// importing a backup replaces `settings` wholesale and calls none of
    /// these setters (UX review 05.09.2026, finding 53).
    func setPlaysTonesInSilentMode(_ on: Bool) {
        settings.playsTonesInSilentMode = on
        persist()
    }

    /// Same shape, same reason: `RootView` reads the field and applies it with
    /// one `.preferredColorScheme`, so an imported backup arrives themed too.
    func setAppearance(_ choice: AppearanceChoice) {
        settings.appearance = choice
        persist()
    }

    /// The hint that the plan's number is an offer, both ways. Shown until the
    /// athlete has once said a number of their own; the first use answers the
    /// question the hint asks, so it is one-way and never comes back.
    var showsDifferentNumberHint: Bool { !settings.hasReportedOwnNumber }

    /// Called by the adjuster when a number is actually REPORTED, never when
    /// the panel merely opens: an opened panel proves the control was found,
    /// which is not the same as knowing what it is for. `persist` only on the
    /// transition — this is spent once in a lifetime and read on every set.
    func markOwnNumberReported() {
        guard !settings.hasReportedOwnNumber else { return }
        settings.hasReportedOwnNumber = true
        persist()
    }

    /// Three is the cap, and it is a floor argument rather than a taste: the
    /// warm-up composes six moves out of a pool of nine, so three hidden still
    /// leaves a full block to compose, and the cool-down keeps its two fixed
    /// positions plus a rest pose. Past that the honest answer is not a
    /// shorter warm-up but no warm-up, and nothing here offers that.
    static let maxHiddenBlockMoves = 3

    func isBlockMoveHidden(_ id: String) -> Bool {
        settings.hiddenBlockMoveIDs.contains(id)
    }

    /// False when the list is full — the control says so instead of silently
    /// doing nothing (the caller disables it; the guard below is the backstop).
    var canHideAnotherBlockMove: Bool {
        settings.hiddenBlockMoveIDs.count < Self.maxHiddenBlockMoves
    }

    func setBlockMoveHidden(_ id: String, _ hidden: Bool) {
        if hidden {
            guard canHideAnotherBlockMove, !settings.hiddenBlockMoveIDs.contains(id) else { return }
            settings.hiddenBlockMoveIDs.insert(id)
        } else {
            guard settings.hiddenBlockMoveIDs.contains(id) else { return }
            settings.hiddenBlockMoveIDs.remove(id)
        }
        persist()
    }
}
