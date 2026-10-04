//
//  The warm-up block: offered, never required, composed live from the pool,
//  and run on the guided blocks' engine (+Blocks).
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// The six moves of THIS session (nine in the pool, six on screen). A
    /// pure function of the session number and of what the athlete has set
    /// aside, so a restored snapshot recomputes the same list rather than
    /// carrying it.
    ///
    /// The hidden set is read LIVE, which the cool-down's twin is not — its
    /// composition is state, drawn into `cooldownPositions`. That difference
    /// is why `rebaseWarmupOnComposition` exists below: hiding the move on
    /// screen changes this list under a countdown that is still standing on
    /// the old one.
    var warmupMoves: [WarmupMove] {
        Warmup.moves(for: session, hiding: store.settings.hiddenBlockMoveIDs)
    }

    /// What the offer screen promises for THIS session's composition.
    var warmupIntroMinutes: Int { Warmup.introMinutes(warmupMoves) }

    /// Both warm-up screens are the same beat as far as the rest of the view
    /// is concerned: not a step of the work, and WARM-UP on the lock screen.
    var isWarmingUp: Bool { phase == .warmup || phase == .warmupIntro }

    /// The person said yes. Nothing is persisted: there is no progress yet to
    /// survive anything.
    func beginWarmup() {
        guard phase == .warmupIntro else { return }
        phase = .warmup
        warmupBeganAt = now()
        // The pair is per BLOCK, and this block starts here.
        blockPausedSec = 0
        blockFrozenAt = nil
        startPosition(0, of: .warmup)
        // "Start the warm-up" is a start tap like "I'm ready", so the block
        // opens on the count-in, not on the full travel time between two
        // positions: the person is standing at their mat with a thumb on the
        // glass, not walking to the next one. Only the AUTOMATIC transitions
        // — the ones no tap opened — keep their full length
        // (`GetReady.stageSeconds`).
        countIn(.warmup)
    }

    /// …or no. The same ending the footer's "Skip warm-up" has, and the same
    /// one taking every move in turn arrives at: straight to the work. A
    /// declined block records a length of zero (`finishWarmup`).
    func declineWarmup() {
        guard phase == .warmupIntro else { return }
        finishWarmup()
    }

    /// The composition changed while the block was running it.
    ///
    /// There is exactly one way that happens: the technique sheet setting the
    /// move on screen aside, or bringing an earlier one back. The list is a
    /// pure function of the session number and the hidden set, so the write
    /// lands instantly and `warmup.index` suddenly names a different move —
    /// the name on screen would change under the seconds of the move it
    /// replaced, and a split move would inherit the `.whole` stage of one
    /// that has no halves.
    ///
    /// So the slot restarts on its own transition instead. A move nobody
    /// announced must not begin under the thumb, and the transition is the one
    /// screen that can open it honestly — the same ending `skipPosition` gives
    /// the next move.
    ///
    /// WHICH slot is `rebaseLanding`'s rule, and `was` is the composition the
    /// block was running: an ordinal is not a stable name for a slot across a
    /// recomposition.
    func rebaseWarmupOnComposition(was previous: [String]) {
        guard phase == .warmup else { return }
        let moves = warmupMoves
        // `Warmup.honoured` guarantees six, so this is the belt to its braces:
        // an empty list would index out of bounds on the very next read.
        guard !moves.isEmpty else { finishWarmup(); return }
        // The prefix of the OLD list is what the block has already been
        // through, run or skipped. `max(0,)` because the index is state.
        let passed = Set(previous.prefix(max(0, warmup.index)))
        guard let index = Self.rebaseLanding(in: moves.map(\.id), after: passed) else {
            // Everything the new composition holds is behind the athlete —
            // ending the block is the honest answer, not reopening one of them.
            finishWarmup()
            return
        }
        warmup.index = index
        warmup.stage = .getReady
        // NOT through `enterStage`: that clears the pause and closes the
        // freeze, and the sheet that got us here is still open with both held.
        // The clock runs on only if it was running — `resumePositionCountdown`
        // puts it back from these seconds when the sheet closes, and a paused
        // block waits for Resume. Either order of the two is safe.
        warmup.clock.reset(to: GuidedBlock.warmup.stageSeconds(.getReady, of: moves[index]),
                           now: now())
    }

    /// Where a recomposed block picks up — the rule for BOTH of them.
    ///
    /// Land AFTER the last slot the athlete has already left behind, never on
    /// one of them. `warmup.index` and `cooldown.index` are ordinals, and a
    /// recomposition is not a deletion: `Warmup.moves(sessionNumber:hiding:)`
    /// re-derives its rotation window from what is LEFT and
    /// `Cooldown.positions` re-grows its middle, so slot i after the write can
    /// name the move that stood at i-1 before it. Clamping the ordinal would
    /// reopen a move finished a minute earlier.
    ///
    /// Landing on the FIRST move not yet run would be the other error. What
    /// advances from here is an ordinal machine (`skipPosition`,
    /// `GuidedBlock.advance`), one slot at a time, so a landing behind the athlete
    /// replays everything between it and where they were. Forward-only is also
    /// what survives a second and a third change of the composition without
    /// carrying a set of ids through the block: whatever the recomposition put
    /// before the landing is left behind with the rest of the prefix, and stays
    /// left behind next time.
    ///
    /// The cost is that a move brought back mid-block may not appear until the
    /// next workout. That is the honest half of the trade: the block keeps the
    /// length it promised and never runs a position twice.
    ///
    /// nil when nothing is left — the block is over.
    static func rebaseLanding(in ids: [String], after passed: Set<String>) -> Int? {
        let index = (ids.lastIndex { passed.contains($0) }).map { $0 + 1 } ?? 0
        return index < ids.count ? index : nil
    }

    /// The move on screen. Clamped: the index is state, and a composition
    /// that changed under a restored snapshot must not index out of bounds.
    var warmupMove: WarmupMove {
        warmupMoves[min(max(warmup.index, 0), warmupMoves.count - 1)]
    }

    func finishWarmup() {
        guard phase == .warmup || phase == .warmupIntro else { return }
        clearBlockPause()
        // Resolved here because every ending arrives here: declined, skipped
        // from the footer, or every move taken in turn. Written once — this
        // runs again on a re-entry and a second span would be the whole
        // detour, not the block.
        if warmupSec == nil {
            // Minus what the block stood still for. Wall clock alone would
            // bill a pause, an open technique sheet and an absence to the
            // stretching, and what reads it is the energy Health is told about.
            warmupSec = max(0, BlockRun.seconds(began: warmupBeganAt, ended: now())
                            - blockPausedSec)
        }
        warmup.clock.freeze()
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }
}
