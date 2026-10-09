//
//  What the app coming to the foreground runs, in order. Every step makes
//  its own change through the store; this file only sequences them.
//  Port of ios/Dredfit/AppStore+Activation.swift. The iOS sequence also
//  reschedules reminders and asks Health for the weight; each joins this list
//  with the module that owns it (reminders/, health/).
//

package com.dredfit.store

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
}
