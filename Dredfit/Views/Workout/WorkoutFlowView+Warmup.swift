//
//  The warm-up block of the workout flow, split out of WorkoutFlowView the
//  way the cool-down already was — one file per guided block, and this one
//  stays clear of the lint's ceiling. The code moved unchanged.
//

import SwiftUI
import DredfitCore

// MARK: - Warm-up
//
// A same-file extension so the view struct stays within the linter's size for
// a type body. @State storage stays in the struct; only behaviour here.
extension WorkoutFlowView {
    /// The warm-up is OFFERED, not started.
    ///
    /// Same two answers as the cool-down and the same tone: no consequence
    /// attaches to saying no. The one difference is the reason on offer —
    /// arriving already warm is ordinary, and the screen says so rather than
    /// making the person justify a skip by walking out of a countdown.
    var warmupIntroView: some View {
        // The scroll of `BlockLayout`, for the reason stated there and one
        // more of its own (UX review 05.09.2026): this screen and its
        // cool-down twin were the only ones of the flow NOT wrapped, and they
        // now carry two lines more. At the accessibility text sizes a bare
        // VStack overflows both ends and takes the decline button off the
        // bottom with it. Below that size nothing scrolls and nothing moved.
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Warm-up")
                        .dredfitFont(32, weight: .heavy)
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("A few easy minutes to get the body ready. Skip it if you are already warm.")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    // ink3 → ink2: this is small TEXT, and ink3 is 2.35:1 on
                    // the light background — under the 4.5:1 small text needs.
                    // Owner's call, UX review 05.09.2026: the low-contrast ink3
                    // text across the app was an oversight, and ink3 is a
                    // graphics tone from here on.
                    Text("\(warmupMoves.count) positions · about \(warmupIntroMinutes) min")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 6)
                    warmupCompositionLines
                    Spacer(minLength: 0)
                    PrimaryButton(title: String(localized: "Start the warm-up")) { beginWarmup() }
                        .accessibilityIdentifier("warmup-start")
                    // No question on THIS one, unlike the escape inside the
                    // block: the offer's own "no" is the answer it asked for.
                    Button(GuidedBlock.warmup.skipTitle) { declineWarmup() }
                        .dredfitFont(14.5)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 4)
                        .accessibilityIdentifier("warmup-intro-skip")
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height,
                       alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// What the offer is actually offering.
    ///
    /// UX review 05.09.2026: the only screen where "do it or not" is decided
    /// named no movement at all, while the composition changes from session to
    /// session (six compositions of six out of a pool of nine) and could be
    /// read only one name at a time INSIDE the block being decided about. The
    /// names are already localized — they are the same strings the running
    /// screen shows — and the list needs no separator of its own: the locale's
    /// own list format has one.
    ///
    /// The second line is the mechanic that has existed since 1.7 and lived
    /// behind the very decision it should be changing: someone with twenty
    /// minutes instead of thirty cut the whole block because the screen
    /// offered nothing smaller.
    ///
    /// ink2, like every other word on the screen: at 2.35:1 in the light
    /// theme ink3 does not carry small text (owner, 05.09.2026 — the
    /// low-contrast ink3 text was an oversight, not a decision).
    @ViewBuilder
    private var warmupCompositionLines: some View {
        Text(warmupMoves.map(\.name).formatted(.list(type: .and)))
            .dredfitFont(13.5)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        Text("Any position can be skipped as you go.")
            .dredfitFont(13.5)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    /// The six moves of THIS session (§40.1: nine in the pool, six on
    /// screen). A pure function of the session number and of what the athlete
    /// has set aside, so a restored snapshot recomputes the same list rather
    /// than carrying it.
    ///
    /// The hidden set is read LIVE, which the cool-down's twin is not — its
    /// composition is drawn once into `cooldownPositions`. That difference is
    /// why `rebaseWarmupOnComposition` exists below: hiding the move on screen
    /// changes this list under a countdown that is still standing on the old
    /// one (UX review 05.09.2026, finding 49).
    var warmupMoves: [WarmupMove] {
        Warmup.moves(for: session, hiding: store.settings.hiddenBlockMoveIDs)
    }

    /// What the offer screen promises for THIS session's composition.
    var warmupIntroMinutes: Int { Warmup.introMinutes(warmupMoves) }

    /// Both warm-up screens are the same beat as far as the rest of the view
    /// is concerned: not a step of the work, and WARM-UP on the lock screen.
    var isWarmingUp: Bool { phase == .warmup || phase == .warmupIntro }

    /// The person said yes. This is the start the view used to make for them
    /// on appear — nothing is persisted, exactly as before: there is no
    /// progress yet to survive anything.
    func beginWarmup() {
        phase = .warmup
        warmupBeganAt = .now
        // The pair is per BLOCK, and this block starts here.
        blockPausedSec = 0
        blockFrozenAt = nil
        startWarmupPosition(0)
        // "Start the warm-up" is a start tap like "I'm ready", so the block
        // opens on the count-in, not on the full travel time between two
        // positions: the person is standing at their mat with a thumb on the
        // glass, not walking to the next one. Only the AUTOMATIC transitions
        // — the ones no tap opened — keep `GetReady.seconds`.
        countInWarmupMove()
    }

    /// …or no. The same ending the footer's "Skip warm-up" already had, and
    /// the same one taking every move in turn arrives at: straight to the
    /// work, with nothing recorded about the block either way.
    func declineWarmup() {
        finishWarmup()
    }

    /// The way back in from a pause wears the transition's screen, because it
    /// is the same beat: the name of the position, the 3-2-1, then the
    /// position. Only the seconds it counts and what "I'm ready" cuts short
    /// differ.
    var warmupView: some View {
        // The Group is what carries the observer below: the two branches are
        // different screens and swap as the stage does, and a modifier applied
        // inside either of them would be torn down with it.
        Group {
            if reentering || warmupStage == .getReady {
                GetReadyScreen(name: warmupMove.name,
                               remaining: reentering ? blockPause.reentryRemaining : warmupRemaining,
                               index: warmupIndex, count: warmupMoves.count,
                               countdownIdentifier: countdownIdentifier(reentering: reentering),
                               block: .warmup,
                               paused: blockPause.isHeld,
                               // The way back in is not a transition to cut: its
                               // "I'm ready" ends it outright, so it keeps one.
                               countingIn: !reentering
                                   && warmupRemaining <= GetReady.countInSeconds,
                               onTechnique: { openWarmupTechnique() },
                               onStart: { reentering ? endBlockReentry() : countInWarmupMove() },
                               onPauseToggle: { toggleBlockPause() },
                               onSkipPosition: { skipWarmupPosition() },
                               onSkipBlock: { finishWarmup() })
            } else {
                warmupMoveView
            }
        }
        // The OLD list is what the rebase needs and the only place it still
        // exists: `warmupMoves` is computed, so by the time this runs it
        // already answers with the new composition (review 06.09.2026).
        .onChange(of: warmupMoves.map(\.id)) { previous, _ in
            rebaseWarmupOnComposition(was: previous)
        }
    }

    /// The composition changed while the block was running it.
    ///
    /// There is exactly one way that happens (UX review 05.09.2026, finding
    /// 49): the technique sheet setting the move on screen aside, or bringing
    /// an earlier one back. The list is a pure function of the session number
    /// and the hidden set, so the write lands instantly and `warmupIndex`
    /// suddenly names a different move — the name on screen would change under
    /// the seconds of the move it replaced, and a split move would inherit the
    /// `.move` stage of one that has no halves.
    ///
    /// So the slot restarts on its own transition instead. A move nobody
    /// announced must not begin under the thumb, and the transition is the one
    /// screen that can open it honestly — the same ending `skipWarmupPosition`
    /// gives the next move.
    ///
    /// WHICH slot is `rebaseLanding`'s rule, and `was` is the composition the
    /// block was running: the clamp this replaced kept the ordinal, and an
    /// ordinal is not a stable name for a slot across a recomposition.
    func rebaseWarmupOnComposition(was previous: [String]) {
        guard phase == .warmup else { return }
        let moves = warmupMoves
        // `Warmup.honoured` guarantees six, so this is the belt to its braces:
        // an empty list would index out of bounds on the very next read.
        guard !moves.isEmpty else { finishWarmup(); return }
        // The prefix of the OLD list is what the block has already been
        // through, run or skipped. `max(0,)` because the index is state.
        let passed = Set(previous.prefix(max(0, warmupIndex)))
        guard let index = Self.rebaseLanding(in: moves.map(\.id), after: passed) else {
            // Everything the new composition holds is behind the athlete —
            // ending the block is the honest answer, not reopening one of them.
            finishWarmup()
            return
        }
        warmupIndex = index
        warmupStage = .getReady
        warmupRemaining = Warmup.stageSeconds(.getReady, of: moves[index])
        // NOT through `enterWarmupStage`: that clears the pause and closes the
        // freeze, and the sheet that got us here is still open with both held.
        // The date is rebuilt only if one was running — `resumePositionCountdown`
        // puts it back from these seconds when the sheet closes, and a paused
        // block waits for Resume. Either order of the two is safe.
        if warmupEndDate != nil {
            warmupEndDate = Date.now.addingTimeInterval(TimeInterval(warmupRemaining))
        }
    }

    /// Where a recomposed block picks up — the rule for BOTH of them.
    ///
    /// Land AFTER the last slot the athlete has already left behind, never on
    /// one of them. `warmupIndex` and `cooldownIndex` are ordinals, and a
    /// recomposition is not a deletion: `Warmup.moves(sessionNumber:hiding:)`
    /// re-derives its rotation window from what is LEFT and
    /// `Cooldown.positions` re-grows its middle, so slot i after the write can
    /// name the move that stood at i-1 before it. Both blocks used to clamp the
    /// ordinal, which reopened a move finished a minute earlier — session 4 did
    /// it at three of its six slots, and the cool-down's "Bring back" did it at
    /// every slot past the one it restores (review 06.09.2026).
    ///
    /// Landing on the FIRST move not yet run would be the other error. What
    /// advances from here is an ordinal machine (`skipWarmupPosition`,
    /// `Warmup.advance`), one slot at a time, so a landing behind the athlete
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

    var warmupMoveView: some View {
        WarmupMoveScreen(move: warmupMove,
                         stage: warmupStage,
                         remaining: warmupRemaining,
                         index: warmupIndex, count: warmupMoves.count,
                         paused: blockPause.isHeld,
                         onTechnique: { openWarmupTechnique() },
                         onPauseToggle: { toggleBlockPause() },
                         onSkipPosition: { skipWarmupPosition() },
                         onSkipBlock: { finishWarmup() })
    }

    /// The move on screen. Clamped: the index is state, and a composition
    /// that changed under a restored snapshot must not index out of bounds.
    var warmupMove: WarmupMove {
        warmupMoves[min(max(warmupIndex, 0), warmupMoves.count - 1)]
    }

    func openWarmupTechnique() {
        openPositionTechnique(PositionTechnique(warmup: warmupMove))
    }

    /// Skipping from the transition skips the move it was announcing.
    func skipWarmupPosition() {
        if warmupIndex + 1 < warmupMoves.count {
            startWarmupPosition(warmupIndex + 1)
        } else {
            finishWarmup()
        }
    }

    func startWarmupPosition(_ index: Int) {
        enterWarmupStage(index: index, stage: .getReady,
                         remaining: Warmup.stageSeconds(.getReady, of: warmupMoves[index]))
    }

    /// The transition is a floor on the pause between positions, never a wait.
    ///
    /// "I'm ready" no longer drops the move under the thumb, though: it cuts
    /// the transition down to a count-in and lets the SAME screen run that
    /// out, so the 3-2-1 and the go still arrive. The tap means "I'm in
    /// position", not "start the clock this instant".
    ///
    /// `min`, never a plain five: the reserve the two blocks are budgeted
    /// against is spent to the second (`GetReady.setupSupplementSec`), so a
    /// tap may only shorten what is already running. Tapped with less than
    /// the count-in left, it changes nothing — there was no jump to soften.
    func countInWarmupMove() {
        enterWarmupStage(index: warmupIndex, stage: .getReady,
                         remaining: min(warmupRemaining, GetReady.countInSeconds))
    }

    func enterWarmupStage(index: Int, stage: Warmup.Stage, remaining: Int) {
        clearBlockPause()   // a new stage is never entered still frozen
        warmupIndex = index
        warmupStage = stage
        warmupRemaining = remaining
        warmupEndDate = Date.now.addingTimeInterval(TimeInterval(remaining))
    }

    func tickWarmup() {
        guard let end = warmupEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != warmupRemaining else { return }
        if newRemaining > 0 {
            // No 3-2-1 inside the switch pause, for the reason `tickCooldown`
            // gives: the ticks would bury the tone the pause opened with.
            if warmupStage != .switchPause,
               newRemaining <= Self.countdownSignalSeconds && newRemaining < warmupRemaining {
                playTick()
            }
            // Animated so contentTransition(.numericText) rolls the digits —
            // a bare mutation swaps them with no transaction.
            withAnimation(countdownAnimation) { warmupRemaining = newRemaining }
            return
        }
        let overshoot = Int(max(0, -end.timeIntervalSinceNow))
        // A boundary crossed while the phone was elsewhere is not a boundary
        // the person was at (UX review 05.09.2026). The block used to swallow
        // whole stages here, and an absence long enough to cover the rest of
        // it played `done` and put someone into the first working set cold,
        // announced by a signal nobody could hear. The rest already refuses
        // that — `SetFacts.restHandsOverWithCountIn` hands the next set a
        // count-in when its go went nowhere — and the warm-up needs no new
        // screen to do the same: freeze on the stage that was running, and
        // the way back in is Resume with the 3-2-1 it already has.
        if overshoot > BlockPause.absenceSeconds {
            // The absence itself is handed over: it is time the block stood
            // still, and `warmupSec` is wall clock (see `blockPausedSec`).
            pauseBlock(absence: overshoot)
            return
        }
        // Warmup.advance absorbs whatever a short overrun already covered.
        guard let next = Warmup.advance(from: (warmupIndex, warmupStage),
                                        overshoot: overshoot,
                                        moves: warmupMoves) else {
            // The block is over: done, not go — a tap starts the first exercise (#186).
            playDone()
            finishWarmup()
            return
        }
        // A transition opening is the done of the move before it; the go marks
        // where a movement starts, the end of the transition. `entered` names
        // the first boundary crossed and `stage` where the overshoot landed: a
        // long absence crosses several, so anything but a landing on the
        // boundary that opened the run stays silent — the signal belongs to
        // what is on screen.
        //
        // The switch of §41.12 is its own tone, and it is chosen the way the
        // cool-down chooses it (`tickCooldown`): a done only where a whole
        // move ended, never at the halfway point of a unilateral one.
        //
        // Each audible boundary is SPOKEN as well (UX review 05.09.2026).
        // VoiceOver stays where it was and the subtree it was in has just been
        // replaced, so nothing is read: the tone was the only channel, and it
        // is behind the same switch as the haptic. The words are the ones the
        // new screen already shows — no string of their own to drift.
        let move = warmupMoves[next.index]
        switch (next.entered, next.stage) {
        case (.getReady, .getReady):
            playDone()
            announce(String(localized: "Get ready: \(move.name)"))
        case (.getReady, _), (_, .getReady):
            break
        case (.switchPause, _):
            playSwitch()
            // Only a split move has this stage, so `halves` is there — and
            // nothing is invented if it somehow is not.
            if let halves = move.halves { announce(SplitStageWords(halves: halves).switching) }
        default:
            playGo()
            if next.stage == .secondHalf, let halves = move.halves {
                announce(SplitStageWords(halves: halves).secondHalf)
            } else {
                announce(move.name)
            }
        }
        enterWarmupStage(index: next.index, stage: next.stage, remaining: next.remaining)
    }

    func finishWarmup() {
        clearBlockPause()
        // Resolved here because every ending arrives here: declined, skipped
        // from the footer, or every move taken in turn. Written once — this
        // runs again on a re-entry and a second span would be the whole
        // detour, not the block.
        if warmupSec == nil {
            // Minus what the block stood still for. Wall clock alone billed a
            // pause, an open technique sheet and an absence to the stretching,
            // and what reads it is the energy Health is told about
            // (UX review 05.09.2026).
            warmupSec = max(0, BlockRun.seconds(began: warmupBeganAt, ended: .now)
                            - blockPausedSec)
        }
        warmupEndDate = nil
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }
}
