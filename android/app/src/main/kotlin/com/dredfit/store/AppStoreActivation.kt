//
//  What the app coming to the foreground runs, in order. Every step makes
//  its own change through the store; this file only sequences them.
//  Port of ios/Dredfit/AppStore+Activation.swift. The iOS sequence also
//  settles a forgotten workout (before the day is re-anchored — the order
//  matters), reschedules reminders and asks Health for the weight; each joins
//  this list with the module that owns it (the workout flow, reminders/,
//  health/).
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
    reloadIfNeeded()
    // The disk may have recovered while the app was away; without this a
    // failed write waits for the next unrelated change.
    if (lastPersistError != null) retryPersist()
    refreshDay(now)
}
