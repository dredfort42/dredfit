//
//  Writes that touch nothing but the settings. Each goes through `update`,
//  which persists in the same call; every write that also moves the engine
//  stays in AppStore.kt. Port of ios/Dredfit/AppStore+SettingsWrites.swift.
//
//  Not here yet: `setReminderEnabled`, which asks the system for permission —
//  it arrives with reminders/, as does the rescheduling iOS runs after a rest
//  day or a reminder time changes. The settings themselves are written now,
//  so a backup carries them across untouched.
//

package com.dredfit.store

import com.dredfit.core.SwiftJson
import java.time.Instant

/** Refuses to turn the last training day into rest: `nextTrainingDate`
 *  relies on at least one. `weekday` is iOS numbering, 1 = Sunday. */
fun AppStore.toggleRestDay(weekday: Int) {
    val days = settings.restWeekdays.toMutableSet()
    if (weekday in days) {
        days.remove(weekday)
    } else {
        days.add(weekday)
        if (days.size >= 7) return
    }
    update { it.copy(settings = it.settings.copy(restWeekdays = days)) }
}

fun AppStore.setSounds(on: Boolean) {
    update { it.copy(settings = it.settings.copy(soundsEnabled = on)) }
}

fun AppStore.setReminderTime(hour: Int, minute: Int) {
    update { it.copy(settings = it.settings.copy(reminderHour = hour, reminderMinute = minute)) }
}

// MARK: - Onboarding

/** Only the care card's explicit button gets here (#101), so completing also
 *  records the acknowledgement. */
fun AppStore.completeOnboarding(now: Instant = clock.instant()) {
    update { it.copy(settings = it.settings.copy(onboardingCompleted = true, careAcknowledgedAt = SwiftJson.swiftDate(now))) }
}

// MARK: - Comeback after a break

fun AppStore.declineComeback(now: Instant = clock.instant()) {
    closeComebackQuestion(now)
}

/** Stamps the answer against the last workout's date, and the gap it was
 *  answered at, so a break that keeps growing can ask once more. */
fun AppStore.closeComebackQuestion(now: Instant = clock.instant()) {
    update { state ->
        state.copy(settings = state.settings.copy(
            comebackDecidedFor = state.records.lastOrNull()?.date,
            comebackDecidedAtGap = gapDays(now)))
    }
}

// MARK: - App Store review

fun AppStore.recordReviewRequest(date: Instant = clock.instant()) {
    update { it.copy(settings = it.settings.copy(lastReviewRequestAt = SwiftJson.swiftDate(date))) }
}

// MARK: - The weak-link prompt (#135)

/** Dismisses the prompt for this session without changing the plan. */
fun AppStore.dismissSuspectPrompt() {
    update { it.copy(settings = it.settings.copy(weakLinkPromptAnsweredFor = it.records.lastOrNull()?.sessionNumber)) }
}

// MARK: - One-shot hints

/** Gated on having been through the door, never on an empty journal: the
 *  person carried over from v2 is exactly who the sentence is for. */
val AppStore.showsTechniqueHint: Boolean get() = !settings.hasOpenedTechnique

/** Written only on the transition: the sheet opens many times in a life. */
fun AppStore.markTechniqueOpened() {
    if (settings.hasOpenedTechnique) return
    update { it.copy(settings = it.settings.copy(hasOpenedTechnique = true)) }
}

/** The one-shot card on Today explaining what an upgrade did. */
val AppStore.showsMigrationNotice: Boolean get() = settings.migrationNoticePending == true

fun AppStore.dismissMigrationNotice() {
    update { it.copy(settings = it.settings.copy(migrationNoticePending = false)) }
}

// MARK: - The switches in AppSettings.swift's own extension

fun AppStore.setPlaysTonesInSilentMode(on: Boolean) {
    update { it.copy(settings = it.settings.copy(playsTonesInSilentMode = on)) }
}

fun AppStore.setAppearance(choice: AppearanceChoice) {
    update { it.copy(settings = it.settings.copy(appearance = choice)) }
}

/** The hint that the plan's number is an offer, both ways — until the first use. */
val AppStore.showsDifferentNumberHint: Boolean get() = !settings.hasReportedOwnNumber

fun AppStore.markOwnNumberReported() {
    if (settings.hasReportedOwnNumber) return
    update { it.copy(settings = it.settings.copy(hasReportedOwnNumber = true)) }
}

/** Three still leaves a full warm-up to compose (six of nine). */
const val MAX_HIDDEN_BLOCK_MOVES = 3

fun AppStore.isBlockMoveHidden(id: String): Boolean = id in settings.hiddenBlockMoveIDs

val AppStore.canHideAnotherBlockMove: Boolean get() = settings.hiddenBlockMoveIDs.size < MAX_HIDDEN_BLOCK_MOVES

fun AppStore.setBlockMoveHidden(id: String, hidden: Boolean) {
    if (hidden) {
        if (!canHideAnotherBlockMove || id in settings.hiddenBlockMoveIDs) return
        update { it.copy(settings = it.settings.copy(hiddenBlockMoveIDs = it.settings.hiddenBlockMoveIDs + id)) }
    } else {
        if (id !in settings.hiddenBlockMoveIDs) return
        update { it.copy(settings = it.settings.copy(hiddenBlockMoveIDs = it.settings.hiddenBlockMoveIDs - id)) }
    }
}
