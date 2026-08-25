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
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Cool-down")
                .dredfitFont(32, weight: .heavy)
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
            Text("The work is done. A few minutes of stretching helps it settle.")
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text("\(cooldownPositions.count) positions · about \(cooldownIntroMinutes) min")
                .dredfitFont(13.5)
                .foregroundStyle(Theme.ink3)
                .padding(.top, 6)
                .accessibilityIdentifier("cooldown-intro-length")
            Spacer()
            PrimaryButton(title: String(localized: "Start the cool-down")) { beginCooldown() }
                .accessibilityIdentifier("cooldown-start")
            Button(String(localized: "Skip the cool-down")) { declineCooldown() }
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)
                .accessibilityIdentifier("cooldown-intro-skip")
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Rounded up: the block is an offer, and a promise it overruns is worse
    /// than one it beats.
    var cooldownIntroMinutes: Int {
        let seconds = cooldownPositions.reduce(0) { total, position in
            let hold = position.perSide
                ? Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
                : Cooldown.positionSeconds
            return total + GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    /// The way back in borrows the transition's screen here too — see
    /// `warmupView`.
    @ViewBuilder
    var cooldownView: some View {
        if reentering || cooldownStage == .getReady {
            GetReadyScreen(name: cooldownPositions[cooldownIndex].name,
                           remaining: reentering ? blockPause.reentryRemaining : cooldownRemaining,
                           index: cooldownIndex, count: cooldownPositions.count,
                           countdownIdentifier: countdownIdentifier(reentering: reentering),
                           blockSkipTitle: String(localized: "cooldown.skip",
                                                  defaultValue: "Skip cool-down"),
                           blockSkipIdentifier: "skip-cooldown",
                           paused: blockPause.isHeld,
                           onTechnique: { openCooldownTechnique() },
                           onStart: { reentering ? endBlockReentry() : startCooldownPositionNow() },
                           onPauseToggle: { toggleBlockPause() },
                           onSkipPosition: { skipCooldownPosition() },
                           onSkipBlock: { finishCooldown() })
        } else {
            cooldownPositionView
        }
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
        let performed = exercises.map(\.pattern).filter { !skippedPatterns.contains($0) }
        cooldownPositions = Cooldown.positions(performed: performed)
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
        startCooldownPosition(0)
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

    func startCooldownPositionNow() {
        guard let next = Cooldown.step(after: (cooldownIndex, .getReady),
                                       positions: cooldownPositions) else { return }
        enterCooldownStage(index: next.index, stage: next.stage)
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
            withAnimation(.linear(duration: 0.3)) { cooldownRemaining = newRemaining }
            return
        }
        guard let next = Cooldown.advance(from: (cooldownIndex, cooldownStage),
                                          overshoot: Int(max(0, -end.timeIntervalSinceNow)),
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
        switch (next.entered, next.stage) {
        case (.getReady, .getReady):         playDone()
        case (.getReady, _), (_, .getReady): break
        case (.switchPause, _):              playSwitch()
        default:                             playGo()
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
        cooldownEndDate = nil
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }
}
