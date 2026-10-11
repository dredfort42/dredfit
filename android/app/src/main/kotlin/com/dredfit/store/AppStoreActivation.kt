//
//  What the app coming to the foreground runs, in order. Every step makes
//  its own change through the store; this file only sequences them.
//  Port of ios/Dredfit/AppStore+Activation.swift.
//

package com.dredfit.store

import kotlinx.coroutines.launch
import java.time.Instant

/** Re-anchors only when the day actually rolled over, and runs the
 *  blind-zone decay on the same pulse, so the plan is corrected before Today
 *  renders. */
fun AppStore.refreshDay(now: Instant = clock.instant()) {
    reanchorToday(now)
    applySilentDecayIfNeeded(now)
}

/** One seam for a cold launch and a return alike. Order matters: the decay
 *  can only correct a journal that has loaded. */
fun AppStore.activate(now: Instant = clock.instant()) {
    // In the app the second read of a frozen journal runs on the disk thread
    // and the rest waits for it; inline it is the same sequence as on iOS.
    reloadIfNeeded { activateLoaded(now) }
}

private fun AppStore.activateLoaded(now: Instant) {
    // The disk may have recovered while the app was away; without this a
    // failed write waits for the next unrelated change.
    if (lastPersistError != null) retryPersist()
    // BEFORE the day is re-anchored, never after: the settlement writes a
    // journal entry dated to the day it happened, and the silent decay and
    // the comeback both measure their gap from the last record.
    settleAbandonedWorkout(now)
    refreshDay(now)
    // The window rebuilt on every return, so it never runs dry while the
    // app is in use.
    rescheduleReminders(now)
    // Off the sequence: a Health Connect call must not hold the plan's
    // re-anchoring behind it. A workout write taken back since the last
    // return turns the switch off first — this is also the re-check after
    // Android's own restore onto a new phone, which needs no device mark:
    // it runs on every return. Then the weight, the owner's, who may have
    // weighed themselves since. Cancelled, not just replaced: two returns in
    // a row leave two reads in flight, and Health Connect decides which
    // answers first — the older reading must not land last and stick.
    bodyMassJob?.cancel()
    bodyMassJob = healthScope.launch {
        reconcileHealthAuthorization()
        refreshBodyMassFromHealth()
    }
}
