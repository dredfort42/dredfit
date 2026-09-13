//
//  The cool-down block of the workout flow (issue #28), split out of
//  WorkoutFlowView when that file grew past the lint's ceiling. The code
//  moved unchanged; what was added to it is the intro screen — the block no
//  longer starts itself.
//

import SwiftUI
import DredfitCore

// MARK: - Cool-down (issue #28)
//
// A same-file extension so the view struct stays within the linter's size
// for a type body. @State storage stays in the struct; only behaviour here.
extension WorkoutFlowView {
    /// The cool-down is OFFERED, not started.
    ///
    /// The tone is the wave's own: it is proposed, never required, and the
    /// screen carries no consequence for saying no. The warm-up keeps its
    /// footer skip and gains no confirmation of its own — the owner asked for
    /// this one only, and symmetry here would be a decision nobody made.
    var cooldownIntroView: some View {
        // Wrapped for the reason its warm-up twin states (UX review
        // 05.09.2026): these two were the only screens of the flow with no
        // scroll under them, and at the accessibility text sizes the decline
        // button goes off the bottom of a bare VStack.
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Cool-down")
                        .dredfitFont(32, weight: .heavy)
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    // The third sentence says what the block already IS and
                    // never admitted (UX review 05.09.2026): three of the six
                    // positions are drawn from the movements actually
                    // performed today, so the person saying no knows what
                    // they are turning down. "Some", deliberately — two
                    // positions and the rest pose are fixed, and a short
                    // session tops the middle three up from a fixed pool.
                    Text("""
                        The work is done. A few minutes of stretching helps it settle. \
                        Some of the positions follow the movements you did today.
                        """)
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    // ink2, for the reason the warm-up offer states: ink3 is
                    // 2.35:1 in the light theme and does not carry small text
                    // (owner, UX review 05.09.2026).
                    Text("\(cooldownPositions.count) positions · about \(cooldownIntroMinutes) min")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    PrimaryButton(title: String(localized: "Start the cool-down")) { beginCooldown() }
                        .accessibilityIdentifier("cooldown-start")
                    // No question here, unlike the escape inside the block:
                    // the offer's own "no" is the answer it asked for.
                    Button(GuidedBlock.cooldown.skipTitle) { declineCooldown() }
                        .dredfitFont(14.5)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 4)
                        .accessibilityIdentifier("cooldown-intro-skip")
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height,
                       alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

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
    private func cooldownMinutes(of positions: ArraySlice<CooldownPosition>) -> Int {
        let seconds = positions.reduce(0) { total, position in
            let hold = position.perSide
                ? Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
                : Cooldown.positionSeconds
            return total + GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    /// The way back in borrows the transition's screen here too — see
    /// `warmupView`.
    var cooldownView: some View {
        // Grouped for the reason `warmupView` states: the observer belongs to
        // the block, not to whichever of the two screens is up.
        Group {
            if reentering || cooldownStage == .getReady {
                GetReadyScreen(name: cooldownPositions[cooldownIndex].name,
                               remaining: reentering ? blockPause.reentryRemaining : cooldownRemaining,
                               index: cooldownIndex, count: cooldownPositions.count,
                               countdownIdentifier: countdownIdentifier(reentering: reentering),
                               block: .cooldown,
                               paused: blockPause.isHeld,
                               countingIn: !reentering
                                   && cooldownRemaining <= GetReady.countInSeconds,
                               onTechnique: { openCooldownTechnique() },
                               onStart: { reentering ? endBlockReentry() : countInCooldownPosition() },
                               onPauseToggle: { toggleBlockPause() },
                               onSkipPosition: { skipCooldownPosition() },
                               onSkipBlock: { finishCooldown() })
            } else {
                cooldownPositionView
            }
        }
        .onChange(of: store.settings.hiddenBlockMoveIDs) { _, _ in
            rebaseCooldownOnComposition()
        }
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
        cooldownRemaining = Cooldown.stageSeconds(Cooldown.openingStage, of: recomposed[index])
        // Not through `enterCooldownStage`, and the date only if one was
        // running — `rebaseWarmupOnComposition` carries the reasoning.
        if cooldownEndDate != nil {
            cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
        }
        persistProgress()
    }

    /// What the cool-down is composed FROM: the movements the workout actually
    /// performed. One spelling, because `startCooldown` and the recompose above
    /// have to agree — two would let a set-aside position come back as soon as
    /// another one was hidden.
    private var performedPatterns: [Pattern] {
        exercises.map(\.pattern).filter { !skippedPatterns.contains($0) }
    }

    var cooldownPositionView: some View {
        CooldownPositionScreen(position: cooldownPositions[cooldownIndex],
                               stage: cooldownStage,
                               remaining: cooldownRemaining,
                               index: cooldownIndex, count: cooldownPositions.count,
                               paused: blockPause.isHeld,
                               onTechnique: { openCooldownTechnique() },
                               onPauseToggle: { toggleBlockPause() },
                               onSkipPosition: { skipCooldownPosition() },
                               onSkipBlock: { finishCooldown() })
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
        cooldownBeganAt = .now
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

    func openCooldownTechnique() {
        openPositionTechnique(PositionTechnique(cooldown: cooldownPositions[cooldownIndex]))
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
        cooldownRemaining = min(cooldownRemaining, GetReady.countInSeconds)
        cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
    }

    func enterCooldownStage(index: Int, stage: Cooldown.Stage) {
        clearBlockPause()   // a new stage is never entered still frozen
        cooldownIndex = index
        cooldownStage = stage
        cooldownRemaining = Cooldown.stageSeconds(stage, of: cooldownPositions[index])
        cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
    }

    func tickCooldown() {
        guard let end = cooldownEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != cooldownRemaining else { return }
        if newRemaining > 0 {
            // No 3-2-1 inside the switch pause: ticks would bury the tone it
            // opened with. The transition is the opposite — the 3-2-1 IS its
            // signal.
            if cooldownStage != .switchPause,
               newRemaining <= Self.countdownSignalSeconds && newRemaining < cooldownRemaining {
                playTick()
            }
            withAnimation(countdownAnimation) { cooldownRemaining = newRemaining }
            return
        }
        let overshoot = Int(max(0, -end.timeIntervalSinceNow))
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
        cooldownRemaining = next.remaining
        cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(next.remaining))
        // Re-stamp so a long cool-down keeps the session resumable — it
        // restores onto the rating, never into a stretch.
        if next.entered == .getReady { persistProgress() }
    }

    func finishCooldown() {
        clearBlockPause()
        // Written once, for the reason `finishWarmup` states.
        if cooldownSec == nil {
            // Minus what the block stood still for — see `finishWarmup`.
            cooldownSec = max(0, BlockRun.seconds(began: cooldownBeganAt, ended: .now)
                              - blockPausedSec)
        }
        cooldownEndDate = nil
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }
}
