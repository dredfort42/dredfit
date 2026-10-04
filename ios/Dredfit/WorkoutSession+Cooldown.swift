//
//  The cool-down block (issue #28): offered once the work is behind, composed
//  from the movements actually performed.
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
        guard phase == .cooldown, cooldownPositions.indices.contains(cooldownIndex) else {
            return nil
        }
        return cooldownMinutes(of: cooldownPositions[cooldownIndex...])
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
        let passed = Set(cooldownPositions.prefix(max(0, cooldownIndex)).map(\.id))
        guard let index = Self.rebaseLanding(in: recomposed.map(\.id), after: passed) else {
            // Nothing left that is not already behind the athlete. The old
            // composition stays put on the way out — `finishCooldown` is the
            // ending, and no screen reads the list again.
            finishCooldown()
            return
        }
        cooldownPositions = recomposed
        cooldownIndex = index
        cooldownStage = Cooldown.openingStage
        // Not through `enterCooldownStage`, and the clock runs on only if it
        // was running — `rebaseWarmupOnComposition` carries the reasoning.
        cooldownClock.reset(to: Cooldown.stageSeconds(Cooldown.openingStage, of: recomposed[index]),
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
        phase = .cooldown
        cooldownBeganAt = now()
        // The pair is per BLOCK — the warm-up's own standing still is behind.
        blockPausedSec = 0
        blockFrozenAt = nil
        startCooldownPosition(0)
        countInCooldownPosition()   // a start tap opens the count-in — see `beginWarmup`
        persistProgress()
    }

    /// …or no. The same ending a fully skipped cool-down already had: straight
    /// to the rating, with the work counted exactly as it was done.
    func declineCooldown() {
        finishCooldown()
    }

    func skipCooldownPosition() {
        if cooldownIndex + 1 < cooldownPositions.count {
            startCooldownPosition(cooldownIndex + 1)
        } else {
            finishCooldown()
        }
    }

    func startCooldownPosition(_ index: Int) {
        enterCooldownStage(index: index, stage: Cooldown.openingStage)
    }

    /// The warm-up's rule over stretches — see `countInWarmupMove`: the tap
    /// cuts the transition to a count-in instead of starting the position
    /// under the thumb. Written out rather than routed through
    /// `enterCooldownStage`, which owns a stage's FULL length and would hand
    /// the transition its ten seconds straight back.
    func countInCooldownPosition() {
        clearBlockPause()
        cooldownClock.start(min(cooldownClock.remaining, GetReady.countInSeconds), now: now())
    }

    func enterCooldownStage(index: Int, stage: Cooldown.Stage) {
        clearBlockPause()   // a new stage is never entered still frozen
        cooldownIndex = index
        cooldownStage = stage
        cooldownClock.start(Cooldown.stageSeconds(stage, of: cooldownPositions[index]), now: now())
    }

    func tickCooldown() {
        let overshoot: Int
        switch cooldownClock.read(now: now()) {
        case .unchanged:
            return
        case .second(let second):
            // No 3-2-1 inside the switch pause: ticks would bury the tone it
            // opened with. The transition is the opposite — the 3-2-1 IS its
            // signal.
            if cooldownStage != .switchPause,
               cooldownClock.signals(second, within: Self.countdownSignalSeconds) {
                playTick()
            }
            animate(.countdown) { cooldownClock.show(second) }
            return
        case .ended(let late):
            overshoot = Int(max(0, late))
        }
        // The warm-up's rule, mirrored (UX review 05.09.2026): a boundary
        // crossed while the phone was elsewhere is not one the person was at,
        // so the block freezes on the stage that was running instead of
        // swallowing the stretches that followed it. `tickWarmup` carries the
        // reasoning; a rule living in one of two identical block machines is
        // the "applied to one branch of two" defect written out by hand.
        if overshoot > BlockPause.absenceSeconds {
            // The absence goes with it, exactly as in `tickWarmup`.
            pauseBlock(absence: overshoot)
            return
        }
        guard let next = Cooldown.advance(from: (cooldownIndex, cooldownStage),
                                          overshoot: overshoot,
                                          positions: cooldownPositions) else {
            // The whole workout is assembled — the finale, not another start
            // (#84). Skipping the cool-down stays silent: a tap is a tap.
            playWorkoutDone()
            finishCooldown()
            return
        }
        // (boundary crossed, where the overshoot landed). A transition that
        // is the boundary just crossed means the position before it ended —
        // done, and for a unilateral position only at its far end, never at
        // the switch. Landing anywhere else after a long absence stays
        // silent: the signal belongs to what is on screen (see tickWarmup).
        //
        // Spoken as well as sounded, for the reason `tickWarmup` states: the
        // subtree VoiceOver was in has just been replaced, so without this the
        // change of screen reaches nobody who cannot see it.
        let position = cooldownPositions[next.index]
        switch (next.entered, next.stage) {
        case (.getReady, .getReady):
            playDone()
            announce(String(localized: "Get ready: \(position.name)"))
        case (.getReady, _), (_, .getReady):
            break
        case (.switchPause, _):
            playSwitch()
            announce(SplitStageWords(halves: .sides).switching)
        default:
            playGo()
            if next.stage == .secondSide {
                announce(SplitStageWords(halves: .sides).secondHalf)
            } else {
                announce(position.name)
            }
        }
        cooldownIndex = next.index
        cooldownStage = next.stage
        cooldownClock.start(next.remaining, now: now())
        // Re-stamp so a long cool-down keeps the session resumable — it
        // restores onto the rating, never into a stretch.
        if next.entered == .getReady { persistProgress() }
    }

    func finishCooldown() {
        clearBlockPause()
        // Written once, for the reason `finishWarmup` states.
        if cooldownSec == nil {
            // Minus what the block stood still for — see `finishWarmup`.
            cooldownSec = max(0, BlockRun.seconds(began: cooldownBeganAt, ended: now())
                              - blockPausedSec)
        }
        cooldownClock.freeze()
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }
}
