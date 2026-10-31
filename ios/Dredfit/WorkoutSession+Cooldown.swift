//
//  The cool-down block (issue #28): offered once the work is behind, composed
//  zone by zone for the session, and run on the guided blocks' engine
//  (+Blocks).
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// Rounded up: the block is an offer, and a promise it overruns is worse
    /// than one it beats.
    var cooldownIntroMinutes: Int { Self.cooldownMinutes(of: cooldownPositions[...]) }

    /// What is LEFT of the block, for the header that answers "how much
    /// longer" everywhere else in the flow — the work screen reserves the
    /// cool-down's minutes in its own number, so the one screen where the
    /// person is actually waiting them out must not say nothing.
    ///
    /// The position on screen counts WHOLE, like the set the rest screen is
    /// standing on: the header's number is an "≈", and rounding a running
    /// position down would make it drop by a minute at a boundary and stand
    /// still in between.
    var cooldownMinutesLeft: Int? {
        guard phase == .cooldown, cooldownPositions.indices.contains(cooldown.index) else {
            return nil
        }
        return Self.cooldownMinutes(of: cooldownPositions[cooldown.index...])
    }

    /// One arithmetic for the offer and for what is left of it: two copies
    /// would let the block promise five minutes and then count down from four.
    static func cooldownMinutes(of positions: ArraySlice<CooldownPosition>) -> Int {
        let seconds = positions.reduce(0) { total, position in
            total + GetReady.stageSeconds(needsSetup: position.needsSetup)
                + Cooldown.slotSeconds(of: position)
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    /// The athlete set the position on screen aside, or brought an earlier one
    /// back.
    ///
    /// Unlike the warm-up, this composition is state — drawn in
    /// `startCooldown` — so nothing moves on its own and the block would
    /// simply go on showing what was just refused. The two blocks answer the
    /// same control, so they answer it the same way: recompose from the same
    /// input the block started with, and restart the slot on its transition.
    /// A position nobody announced must not begin under the thumb.
    ///
    /// WHICH slot is `cooldownLanding`'s rule: the warm-up's `rebaseLanding`
    /// with a floor at the level reached. A clamp of the ordinal would reopen
    /// a stretch already done: a zone emptied by the position on screen is
    /// refilled on the refill's own level, which can sort in above the slot,
    /// and "Bring back" puts a position back on its level — above the athlete,
    /// as often as not, in place of a stand-in they already did. The sheet
    /// does not close on that tap, so nobody would see the block move under
    /// them.
    func rebaseCooldownOnComposition() {
        guard phase == .cooldown else { return }
        let recomposed = Cooldown.positions(sessionNumber: session.sessionNumber,
                                            hiding: store.settings.hiddenBlockMoveIDs)
        // Nothing to say when the block is unchanged — bringing back a
        // position the composition never drew is the ordinary case. And never
        // to an empty block: `Cooldown.honoured` will not compose one, and
        // every read below indexes.
        guard !recomposed.isEmpty, recomposed != cooldownPositions else { return }
        // Read BEFORE the new list is stored: the prefix of the composition
        // that was running is what the block has already been through.
        let passed = Set(cooldownPositions.prefix(max(0, cooldown.index)).map(\.id))
        // The level of the position on screen: where the athlete is, or is
        // getting to. The index is state, hence the check.
        let reached = cooldownPositions.indices.contains(cooldown.index)
            ? cooldownPositions[cooldown.index].level : .standing
        guard let index = Self.cooldownLanding(in: recomposed, after: passed, reached: reached) else {
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

    /// `rebaseLanding` with the cool-down's floor: the first slot on the level
    /// the athlete has reached. The block only goes down, so a position
    /// brought back above it — the kneeling lunge while they kneel in the rest
    /// pose, whose standing twin is already behind them — waits for the next
    /// workout rather than getting them up, and the zone is not stretched
    /// twice.
    static func cooldownLanding(in positions: [CooldownPosition], after passed: Set<String>,
                                reached: CooldownPosition.Level) -> Int? {
        let floor = positions.firstIndex { $0.level >= reached } ?? positions.count
        return rebaseLanding(in: positions.map(\.id), after: passed, notBefore: floor)
    }

    /// The movements the workout actually performed — whether there is
    /// anything to cool down from at all.
    var performedPatterns: [Pattern] {
        exercises.map(\.pattern).filter { !skippedPatterns.contains($0) }
    }

    /// A workout of pure skips has nothing to stretch — straight to the
    /// rating instead.
    func startCooldown() {
        cooldownPositions = performedPatterns.isEmpty ? [] :
            Cooldown.positions(sessionNumber: session.sessionNumber,
                               hiding: store.settings.hiddenBlockMoveIDs)
        guard !cooldownPositions.isEmpty else {
            // Never offered, so never begun: zero, for the reason `finishNow`
            // gives.
            cooldownSec = 0
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

    /// …or no. The same ending a fully skipped cool-down has: straight to the
    /// rating, with the work counted exactly as it was done.
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
