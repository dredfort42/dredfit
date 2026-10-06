//
//  What a scene becoming active runs, in order. Every step it calls makes its
//  own change through the store; this file only sequences them.
//

import Foundation
import DredfitCore

extension AppStore {

    /// Re-anchors only when the day actually rolled over — mutating `today`
    /// on every activation would re-render for nothing.
    func refreshDay(now: Date = .now) {
        reanchorToday(now: now)
        // The blind-zone decay rides the same pulse, so by the time Today
        // renders the plan is already corrected.
        applySilentDecayIfNeeded(now: now)
    }

    /// Everything a scene becoming `.active` must run, in one seam — a cold
    /// launch renders already active without a phase transition, so `onAppear`
    /// has to run the same sequence or the blind-zone decay never fires.
    /// Order matters: the decay can only correct a journal that has loaded.
    func activate(now: Date = .now) {
        reloadIfNeeded()
        // The disk may have recovered while the app was away (storage freed,
        // protection lifted); without this a failed write waits for the next
        // unrelated change, and a quiet session never gets one.
        if lastPersistError != nil { retryPersist() }
        // BEFORE the day is re-anchored, never after: the settlement writes a
        // journal entry dated to the day it happened, and the silent decay and
        // the comeback both measure their gap from the last record. Settling
        // afterwards would decay a state that had just been trained.
        settleAbandonedWorkout(now: now)
        refreshDay(now: now)
        rescheduleReminders(now: now)
        // Off the sequence, because it is the only step that leaves the
        // device: a HealthKit query must not hold the plan's re-anchoring
        // behind it. The weight is the owner's, and the owner may have
        // weighed themselves since the last foreground.
        // A share taken back since the last foreground turns the switch off
        // here, before the read below would query Health for nothing.
        reconcileHealthAuthorization()
        if settings.healthEnabled {
            // Cancelled, not just replaced: two foregrounds in a row leave two
            // queries in flight, and HealthKit decides which returns first —
            // without this the older reading could land last and stick.
            bodyMassTask?.cancel()
            bodyMassTask = Task { await self.refreshBodyMassFromHealth() }
        }
    }
}
