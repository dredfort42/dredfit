//
//  What a failed write or an unread journal changes: the way back from a
//  failed write (the banner's "Try again" and the `activate()` retry) and
//  whether a workout may start at all.
//

import Foundation

extension AppStore {
    /// Off while the journal is frozen: a workout done then is kept in memory
    /// only, and Today offers a retry of the read instead of a Start.
    var canStartWorkout: Bool { !journalFrozen }

    /// An empty change through `update`, not a second path to the file: the
    /// write, the frozen-journal guard and the widget refresh stay the ones a
    /// real change gets, and the in-memory state is already what to save.
    ///
    /// Not while frozen: persist() would count even this empty change as work
    /// done on a launch that never read its journal, and pin the freeze.
    func retryPersist() {
        guard !journalFrozen else { return }
        update { _ in }
    }
}
