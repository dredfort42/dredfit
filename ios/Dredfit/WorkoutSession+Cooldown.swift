//
//  The cool-down block (issue #28): offered once the work is behind, composed
//  once from the movements actually performed, and run on the guided blocks'
//  engine (+Blocks).
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// Rounded up: the block is an offer, and a promise it overruns is worse
    /// than one it beats.
    var cooldownIntroMinutes: Int { cooldownMinutes(of: cooldownPositions[...]) }

    /// What is LEFT of the block, for the header that answers "how much
    /// longer" everywhere else in the flow and went silent here — the work
    /// screen reserves the cool-down's minutes in its own number, and then the
    /// one screen where the person is actually waiting them out said nothing
    /// (UX review 05.09.2026).
    ///
    /// The position on screen counts WHOLE, like the set the rest screen is
    /// standing on: the header's number is an "≈", and rounding a running
    /// position down would make it drop by a minute at a boundary and stand
    /// still in between.
    var cooldownMinutesLeft: Int? {
        guard phase == .cooldown, cooldownPositions.indices.contains(cooldown.index) else {
            return nil
        }
        return cooldownMinutes(of: cooldownPositions[cooldown.index...])
    }

    /// One arithmetic for the offer and for what is left of it: two copies
    /// would let the block promise five minutes and then count down from four.
    func cooldownMinutes(of positions: ArraySlice<CooldownPosition>) -> Int {
        let seconds = positions.reduce(0) { total, position in
            let hold = position.perSide
                ? Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
                : Cooldown.positionSeconds
            return total + GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    /// The athlete set the position on screen aside, or brought an earlier one
    /// back (UX review 05.09.2026, finding 49).
    ///
    /// Unlike the warm-up, this composition is state — drawn once in
    /// `startCooldown` — so nothing moves on its own and the block would
    /// simply go on showing what was just refused. The two blocks answer the
    /// same control, so they answer it the same way: recompose from the same
    /// input the block started with, and restart the slot on its transition.
    /// A position nobody announced must not begin under the thumb.
    ///
    /// WHICH slot is `rebaseLanding`'s rule, shared with the warm-up. Hiding
    /// the position on screen was safe here by luck of the arithmetic — the
    /// middle only ever tops up at its tail — but "Bring back" re-inserts into
    /// `opening` and pushes everything after it one slot right, and the clamp
    /// this replaced then reopened a stretch already done while dropping the
    /// one that was running. The sheet does not close on that tap, so nobody
    /// saw the block move under them (review 06.09.2026).
    func rebaseCooldownOnComposition() {
        guard phase == .cooldown else { return }
        let recomposed = Cooldown.positions(performed: performedPatterns,
                                            hiding: store.settings.hiddenBlockMoveIDs)
        // Nothing to say when the block is unchanged — bringing back a
        // position the composition never drew is the ordinary case. And never
        // to an empty block: `Cooldown.honoured` will not compose one, and
        // every read below indexes.
        guard !recomposed.isEmpty, recomposed != cooldownPositions else { return }
        // Read BEFORE the new list is stored: the prefix of the composition
        // that was running is what the block has already been through.
        let passed = Set(cooldownPositions.prefix(max(0, cooldown.index)).map(\.id))
        guard let index = Self.rebaseLanding(in: recomposed.map(\.id), after: passed) else {
            // Nothing left that is not already behind the athlete. The old
            // composition stays put on the way out — `finishCooldown` is the
            // ending, and no screen reads the list again.
            finishCooldown()
            return
        }
        cooldownPositions = recomposed
        cooldown.index = index
        cooldown.stage = .getReady
        // Not through `enterStage`, and the clock runs on only if it was
        // running — `rebaseWarmupOnComposition` carries the reasoning.
        cooldown.clock.reset(to: GuidedBlock.cooldown.stageSeconds(.getReady, of: recomposed[index]),
                             now: now())
        persistProgress()
    }

    /// What the cool-down is composed FROM: the movements the workout actually
    /// performed. One spelling, because `startCooldown` and the recompose above
    /// have to agree — two would let a set-aside position come back as soon as
    /// another one was hidden.
    var performedPatterns: [Pattern] {
        exercises.map(\.pattern).filter { !skippedPatterns.contains($0) }
    }

    /// A workout of pure skips has nothing to stretch — straight to the
    /// rating instead.
    func startCooldown() {
        cooldownPositions = Cooldown.positions(performed: performedPatterns,
                                               hiding: store.settings.hiddenBlockMoveIDs)
        guard !cooldownPositions.isEmpty else {
            phase = .feedback
            liveActivity.end()
            persistProgress()
            return
        }
        // Ask first. The positions are already drawn, so the screen can say
        // how many and how long.
        phase = .cooldownIntro
        liveActivity.update(.init(phase: .work, title: String(localized: "COOL-DOWN"),
                                  detail: "", restEndDate: nil))
        persistProgress()
    }

    /// The person said yes on the intro screen.
    func beginCooldown() {
        guard phase == .cooldownIntro else { return }
        phase = .cooldown
        cooldownBeganAt = now()
        // The pair is per BLOCK — the warm-up's own standing still is behind.
        blockPausedSec = 0
        blockFrozenAt = nil
        startPosition(0, of: .cooldown)
        countIn(.cooldown)   // a start tap opens the count-in — see `beginWarmup`
        persistProgress()
    }

    /// …or no. The same ending a fully skipped cool-down already had: straight
    /// to the rating, with the work counted exactly as it was done.
    func declineCooldown() {
        guard phase == .cooldownIntro else { return }
        finishCooldown()
    }

    func finishCooldown() {
        guard phase == .cooldown || phase == .cooldownIntro else { return }
        clearBlockPause()
        // Written once, for the reason `finishWarmup` states.
        if cooldownSec == nil {
            // Minus what the block stood still for — see `finishWarmup`.
            cooldownSec = max(0, BlockRun.seconds(began: cooldownBeganAt, ended: now())
                              - blockPausedSec)
        }
        cooldown.clock.freeze()
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }
}
