//
//  What a failed write or an unread journal changes: the way back from a
//  failed write and whether a workout may start at all.
//  Port of ios/Dredfit/AppStore+SaveFailure.swift.
//

package com.dredfit.store

/** Off while the journal is frozen: a workout done then is kept in memory only. */
val AppStore.canStartWorkout: Boolean get() = !journalFrozen

/** An empty change through `update`, not a second path to the file. Not while
 *  frozen: even this empty change would count as work and pin the freeze. */
fun AppStore.retryPersist() {
    if (journalFrozen) return
    update { it }
}
