//
//  WorkoutFlowView.swift
//  Dredfit
//
//  warm-up > work > rest > … > cool-down > feedback. Every countdown is
//  wall-clock based (an end Date, not a tick count) so locking the phone
//  loses nothing; the screen stays awake for the whole session.
//

import Combine
import SwiftUI
import StoreKit
import UIKit
import DredfitCore

struct WorkoutFlowView: View {
    let session: Session
    var resume: WorkoutSnapshot?
    /// nil is the full session. The session object is the same either way —
    /// only the exercises the flow walks differ, and everything left out is
    /// recorded as an honest skip when the workout ends.
    var shortPlan: Set<Pattern>?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.requestReview) private var requestReview

    private enum Phase: Equatable {
        case warmup
        case work
        case rest(seconds: Int)
        case cooldown                 // between the last exercise and the rating
        case feedback
        case milestone([Milestone])   // only when the workout earned one
    }

    @State private var exIndex = 0
    @State private var setIndex = 0          // 0-based
    @State private var phase: Phase = .warmup
    @State private var warmupIndex = 0
    @State private var warmupRemaining = 0
    @State private var warmupEndDate: Date?
    // Shares the block's countdown state — one timer, two stages — so
    // nothing new has to survive backgrounding.
    @State private var warmupStage: Warmup.Stage = .getReady
    // Computed once on entry: the composition depends on what was performed.
    @State private var cooldownPositions: [CooldownPosition] = []
    @State private var cooldownIndex = 0
    @State private var cooldownRemaining = 0
    @State private var cooldownEndDate: Date?
    @State private var cooldownStage: Cooldown.Stage = Cooldown.openingStage
    // The pause of the guided blocks (issue #61). One for both, like the
    // stage/remaining pairs above: the two blocks never run at once. Held, the
    // frozen seconds sit in warmupRemaining / cooldownRemaining and no end
    // date exists anywhere; re-entering, only this moves.
    @State private var blockPause = BlockPause.State()
    @State private var restRemaining = 0
    @State private var restEndDate: Date?
    /// What this transition planned, kept because the phase carries the
    /// current total and the extension cap is twice the PLANNED one.
    @State private var restPlanned = 0
    // Captured at tap time (not a bool): the rest countdown keeps ticking
    // while the sheet is open and may flip the phase underneath.
    @State private var techniqueExercise: SessionExercise?
    // Unlike techniqueExercise, presenting this freezes the countdown.
    @State private var positionTechnique: PositionTechnique?
    @State private var actuals: [Pattern: Int] = [:]
    @State private var skippedPatterns: Set<Pattern> = []
    /// Kept apart from `skippedPatterns`: the engine treats both as skips for
    /// the session, but the rating and the history say different things.
    @State private var discomfortPatterns: Set<Pattern> = []
    /// Hold-this-level requests (#78): not a skip set — the movement is
    /// performed. A toggle until the workout ends; then it is engine state.
    @State private var pinnedPatterns: Set<Pattern> = []
    @State private var adjusting = false
    @State private var adjustValue = 0
    @State private var workoutStart: Date?   // actual duration for Health
    @State private var lastResult: FeedbackResult?   // gates the review ask
    @State private var liveActivity = WorkoutActivityController()
    @State private var exitConfirmShown = false
    /// Labelled "not finished" on the rating screen; to the engine it is a
    /// skip like any other.
    @State private var interruptedPattern: Pattern?
    /// One-shot guard: sheets presented over the flow can make onAppear fire
    /// more than once.
    @State private var didStart = false

    // Per-side holds run the countdown twice; the actual is the smaller of
    // the two — the honest bottleneck.
    @State private var holdEndDate: Date?
    @State private var holdRemaining = 0
    @State private var holdTotal = 0
    @State private var holdSecondSide = false
    @State private var firstSideHeld: Int?
    // The second side starts itself — no tap, with hands busy in a plank.
    @State private var holdPauseEndDate: Date?
    @State private var holdPauseRemaining = 0

    @ScaledMetric(relativeTo: .largeTitle) private var restRingSize: CGFloat = 240

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Every position in the flow (indices, "N / M", the capsules, restore
    /// clamping) counts in these, not in session.exercises.
    private var exercises: [SessionExercise] {
        guard let shortPlan else { return session.exercises }
        return session.exercises.filter { shortPlan.contains($0.pattern) }
    }
    private var omitted: Set<Pattern> {
        guard shortPlan != nil else { return [] }
        return Set(session.exercises.map(\.pattern)).subtracting(exercises.map(\.pattern))
    }
    private var exercise: SessionExercise { exercises[exIndex] }
    private var isLastSet: Bool { setIndex == exercise.sets - 1 }
    private var isLastExercise: Bool { exIndex == exercises.count - 1 }
    private var holding: Bool { holdEndDate != nil }
    private var holdSwitchPausing: Bool { holdPauseEndDate != nil }
    private var isMilestone: Bool { if case .milestone = phase { return true }; return false }

    /// The stamp is written whether or not iOS shows the prompt — Apple
    /// rate-limits invisibly, and an unseen request still counts against our
    /// own floor. The delay waits out the cover's dismissal: StoreKit
    /// silently drops a prompt asked for mid-transition.
    private func askForReviewIfEarned() {
        guard store.shouldRequestReview(lastResult: lastResult) else { return }
        let store = self.store
        let requestReview = self.requestReview
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            store.recordReviewRequest()
            requestReview()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            switch phase {
            case .warmup:
                warmupView
            case .work:
                workView
            case .rest:
                restView
            case .cooldown:
                cooldownView
            case .feedback:
                FeedbackView(session: session, actuals: actuals,
                             skipped: skippedPatterns.union(omitted),
                             discomfort: discomfortPatterns,
                             pinned: pinnedPatterns,
                             interrupted: interruptedPattern) { result, overrides in
                    let earned = store.completeWorkout(
                        session: session, result: result,
                        overrides: overrides,
                        // Skips like any other: levels frozen, counter and
                        // rotation still advance. The engine has no idea the
                        // workout was short, and that is the point.
                        skipped: skippedPatterns.union(omitted),
                        discomfort: discomfortPatterns,
                        pinned: pinnedPatterns,
                        durationSec: workoutStart.map {
                            // max: the wall clock can move backwards mid-workout
                            max(0, Int(Date.now.timeIntervalSince($0)))
                        })
                    if earned.isEmpty {
                        dismiss()
                    } else {
                        lastResult = result
                        phase = .milestone(earned)
                    }
                }
            case .milestone(let earned):
                MilestoneView(milestones: earned,
                              levels: store.levelCurve(through: store.lastRecord?.date),
                              retrospective: Retrospective.make(
                                  records: store.records,
                                  currentLevels: store.engineState.levels)) {
                    askForReviewIfEarned()
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 24)
        .background(Color.white)
        .onReceive(timer) { _ in
            switch phase {
            case .warmup:
                if blockPause.isPaused { tickBlockPause() } else { tickWarmup() }
            case .rest:
                tickRest()
            case .cooldown:
                if blockPause.isPaused { tickBlockPause() } else { tickCooldown() }
            case .work where holdSwitchPausing:
                tickHoldSwitchPause()
            case .work where holding:
                tickHold()
            default:
                break
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            guard !didStart else { return }
            didStart = true
            // Pay the audio-session setup here, not on the first tick.
            if store.settings.soundsEnabled { CountdownSounds.shared.prime() }
            if let resume { restore(from: resume) }
            if workoutStart == nil { workoutStart = .now }
            // Nothing for the lock screen to describe on the rating.
            if phase != .feedback {
                liveActivity.start(sessionNumber: session.sessionNumber,
                                   state: currentActivityState())
            }
            if phase == .warmup { startWarmupPosition(0) }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            liveActivity.end()
        }
        // A held block is the one state where the app knows nobody is
        // training, so it stops holding the screen open. One place rather
        // than one per path: every way in and out of a pause runs through it.
        .onChange(of: blockPause.isHeld) { _, held in
            UIApplication.shared.isIdleTimerDisabled = !held
        }
        .sheet(item: $techniqueExercise) { ex in
            TechniqueSheet(exercise: ex)
        }
        .sheet(item: $positionTechnique, onDismiss: resumePositionCountdown) { technique in
            PositionTechniqueSheet(technique: technique)
        }
        .confirmationDialog(String(localized: "Leave the workout?"),
                            isPresented: $exitConfirmShown,
                            titleVisibility: .visible) {
            Button(String(localized: "Finish now")) { finishNow() }
            Button(String(localized: "Discard workout"), role: .destructive) {
                discardWorkout()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("“Finish now” keeps what you've done and goes to the rating — the remaining exercises are marked as skipped.")
        }
    }

    // MARK: - Header with progress segments

    @ViewBuilder
    private var header: some View {
        if phase != .feedback, !isMilestone {
            FlowHeader(title: headerTitle,
                       steps: phase == .warmup ? 0 : exercises.count,
                       doneIndex: exIndex) {
                if hasProgress {
                    exitConfirmShown = true
                } else {
                    discardWorkout()
                }
            }
        }
    }

    private var headerTitle: String {
        switch phase {
        case .work:     return String(localized: "\(exIndex + 1) / \(exercises.count)")
        case .warmup:   return String(localized: "WARM-UP")
        case .cooldown: return String(localized: "COOL-DOWN")
        default:        return String(localized: "REST")
        }
    }

    // MARK: - Warm-up

    /// The way back in from a pause wears the transition's screen, because it
    /// is the same beat: the name of the position, the 3-2-1, then the
    /// position. Only the seconds it counts and what "I'm ready" cuts short
    /// differ.
    @ViewBuilder
    private var warmupView: some View {
        if reentering || warmupStage == .getReady {
            GetReadyScreen(name: Warmup.moves[warmupIndex].name,
                           remaining: reentering ? blockPause.reentryRemaining : warmupRemaining,
                           index: warmupIndex, count: Warmup.moves.count,
                           countdownIdentifier: countdownIdentifier(reentering: reentering),
                           blockSkipTitle: String(localized: "Skip warm-up"),
                           paused: blockPause.isHeld,
                           onTechnique: { openWarmupTechnique() },
                           onStart: { reentering ? endBlockReentry() : startWarmupMoveNow() },
                           onPauseToggle: { toggleBlockPause() },
                           onSkipPosition: { skipWarmupPosition() },
                           onSkipBlock: { finishWarmup() })
        } else {
            warmupMoveView
        }
    }

    private var warmupMoveView: some View {
        WarmupMoveScreen(name: Warmup.moves[warmupIndex].name,
                         remaining: warmupRemaining,
                         index: warmupIndex, count: Warmup.moves.count,
                         paused: blockPause.isHeld,
                         onTechnique: { openWarmupTechnique() },
                         onPauseToggle: { toggleBlockPause() },
                         onSkipPosition: { skipWarmupPosition() },
                         onSkipBlock: { finishWarmup() })
    }

    private func openWarmupTechnique() {
        openPositionTechnique(PositionTechnique(warmup: Warmup.moves[warmupIndex]))
    }

    /// Skipping from the transition skips the move it was announcing.
    private func skipWarmupPosition() {
        if warmupIndex + 1 < Warmup.moves.count {
            startWarmupPosition(warmupIndex + 1)
        } else {
            finishWarmup()
        }
    }

    private func startWarmupPosition(_ index: Int) {
        enterWarmupStage(index: index, stage: .getReady,
                         remaining: Warmup.stageSeconds(.getReady))
    }

    /// The transition is a floor on the pause between positions, never a wait.
    private func startWarmupMoveNow() {
        enterWarmupStage(index: warmupIndex, stage: .move,
                         remaining: Warmup.stageSeconds(.move))
    }

    private func enterWarmupStage(index: Int, stage: Warmup.Stage, remaining: Int) {
        clearBlockPause()   // a new stage is never entered still frozen
        warmupIndex = index
        warmupStage = stage
        warmupRemaining = remaining
        warmupEndDate = Date.now.addingTimeInterval(TimeInterval(remaining))
    }

    private func tickWarmup() {
        guard let end = warmupEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != warmupRemaining else { return }
        if newRemaining > 0 {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < warmupRemaining {
                playTick()
            }
            // Animated so contentTransition(.numericText) rolls the digits —
            // a bare mutation swaps them with no transaction.
            withAnimation(.linear(duration: 0.3)) { warmupRemaining = newRemaining }
            return
        }
        // Warmup.advance absorbs whatever a long absence already covered.
        guard let next = Warmup.advance(from: (warmupIndex, warmupStage),
                                        overshoot: Int(max(0, -end.timeIntervalSinceNow))) else {
            playGo()            // the block is over: the first exercise is up
            finishWarmup()
            return
        }
        // The go marks the moment a movement starts — the end of the
        // transition, not the end of the move before it. `entered` names the
        // first boundary crossed and `stage` where the overshoot landed; a
        // long absence crosses several, so a landing on a transition stays
        // silent whichever boundary opened the run.
        if next.entered != .getReady, next.stage != .getReady { playGo() }
        enterWarmupStage(index: next.index, stage: next.stage, remaining: next.remaining)
    }

    /// Freezes the running countdown: the end date comes off (the tick
    /// guards go quiet) while the remaining seconds stay put and rebuild it.
    /// The way back in from a pause freezes with it — reading is not getting
    /// back into position either.
    private func openPositionTechnique(_ technique: PositionTechnique) {
        positionTechnique = technique
        warmupEndDate = nil
        cooldownEndDate = nil
        blockPause.freezeForSheet()
    }

    private func resumePositionCountdown() {
        // Whatever the sheet froze is what it hands back. A way back in
        // outlives it; a pause outranks it — closing the sheet must never
        // restart a block the user stopped (issue #34 vs #61).
        blockPause.thawAfterSheet(now: .now)
        guard !blockPause.isPaused else { return }
        switch phase {
        case .warmup:
            warmupEndDate = Date.now.addingTimeInterval(TimeInterval(warmupRemaining))
        case .cooldown:
            cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
        default:
            break
        }
    }

    private func finishWarmup() {
        clearBlockPause()
        warmupEndDate = nil
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }

    // MARK: - Live Activity

    /// Strings leave the app pre-localized — the extension renders verbatim.
    private func activityWorkState() -> RestActivityAttributes.ContentState {
        if phase == .warmup {
            return .init(phase: .work, title: String(localized: "WARM-UP"),
                         detail: "", restEndDate: nil)
        }
        return .init(phase: .work, title: exercise.name,
                     detail: String(localized: "set \(setIndex + 1) of \(exercise.sets)"),
                     restEndDate: nil)
    }

    // MARK: - Work

    private var workView: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(exercise.name)
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                // The held state travels with the name, never colour alone
                .accessibilityLabel(pinnedPatterns.contains(exercise.pattern)
                    ? Text("\(exercise.name), level held") : Text(verbatim: exercise.name))

            TechniqueButton { techniqueExercise = exercise }
                .padding(.top, 10)

            VStack(spacing: 4) {
                Text("\(workNumber)")
                    .dredfitFont(112, weight: .heavy, cap: 150)
                    .tracking(-4)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(loadCaption)
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 20)

            HStack(spacing: 10) {
                ForEach(0..<exercise.sets, id: \.self) { i in
                    Circle()
                        .fill(i < setIndex ? Theme.ink : (i == setIndex ? Theme.accent : Theme.hairline))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 30)

            WorkStatusCaption(switchingSides: holdSwitchPausing,
                              secondSide: holdSecondSide,
                              actual: actuals[exercise.pattern] == exercise.load
                                  ? nil : actuals[exercise.pattern],
                              held: pinnedPatterns.contains(exercise.pattern),
                              setIndex: setIndex, sets: exercise.sets)
                .padding(.top, 10)

            Spacer()

            if adjusting {
                AdjustPanel(value: $adjustValue, unit: exercise.unit) {
                    actuals[exercise.pattern] = adjustValue
                    if adjustValue == exercise.load {
                        actuals.removeValue(forKey: exercise.pattern) // back to the plan
                    }
                    adjusting = false
                    persistProgress()   // an entered actual is worth keeping
                }
                .padding(.bottom, 8)
            }

            if exercise.unit == .hold {
                if holding {
                    PrimaryButton(title: String(localized: "Stop")) { stopHoldEarly() }
                } else if holdSwitchPausing {
                    // hidden, not opacity: the button must leave the
                    // accessibility tree while keeping its reserved space.
                    PrimaryButton(title: String(localized: "Start hold")) { }.hidden()
                } else {
                    PrimaryButton(title: String(localized: "Start hold")) { startHold() }
                }
            } else {
                PrimaryButton(title: String(localized: "Done")) { completeSet() }
            }

            ExerciseActionsRow(pinned: pinnedPatterns.contains(exercise.pattern),
                               onAdjust: { startAdjusting() },
                               onSkip: { leaveExercise() },
                               onPin: { togglePin() },
                               onDiscomfort: { leaveExercise(hurt: true) })
            .padding(.vertical, 14)
            // no adjusting/skipping mid-hold or mid-pause
            .opacity(holding || holdSwitchPausing ? 0 : 1)
            .disabled(holding || holdSwitchPausing)

            // Opacity, not `if`: the reserved height keeps the layout still
            // when the hint's job is done mid-exercise.
            if store.records.isEmpty {
                Text("Did far more than planned? Tap “Went differently” and enter what you actually did — the system will land on your level right away.")
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .opacity(holding || holdSwitchPausing || adjusting
                             || actuals[exercise.pattern] != nil ? 0 : 1)
            }
        }
    }

    /// In order of precedence.
    private var workNumber: Int {
        if holdSwitchPausing { return holdPauseRemaining }
        if holding { return holdRemaining }
        return actuals[exercise.pattern] ?? exercise.load
    }

    // MARK: - Inline actual adjuster (the panel itself is AdjustPanel.swift)

    private func startAdjusting() {
        adjustValue = actuals[exercise.pattern] ?? exercise.load
        adjusting = true
    }

    private var loadCaption: String {
        // During the switch pause the big number is the pause countdown.
        if holdSwitchPausing { return String(localized: "sec") }
        // The unit only: the 112 pt number above already says how many, and
        // printing it twice is the kind of noise that makes a screen feel
        // busy. Because the caption no longer agrees with a number, these
        // keys need no ICU plurals — one form per language.
        switch (exercise.unit, exercise.perSide) {
        case (.reps, false): return String(localized: "reps")
        case (.reps, true):  return String(localized: "reps per side")
        case (.hold, false): return String(localized: "seconds")
        case (.hold, true):  return String(localized: "seconds per side")
        }
    }

    // MARK: - Rest

    private var restView: some View {
        RestRing(remaining: restRemaining,
                 fraction: progressFraction,
                 ringSize: restRingSize,
                 nextLabel: nextLabel,
                 extensionSeconds: Self.restExtensionSeconds,
                 canExtend: canExtendRest,
                 onTechnique: { techniqueExercise = restTargetExercise },
                 onExtend: extendRest,
                 onSkip: {
                     restEndDate = nil
                     restRemaining = 0
                     advanceAfterRest()
                 })
    }

    /// The cap is twice the rest this transition planned, so the dial cannot
    /// turn a workout into an evening.
    private var canExtendRest: Bool {
        guard case .rest(let total) = phase, restPlanned > 0 else { return false }
        return total + Self.restExtensionSeconds <= restPlanned * 2
    }

    /// Moves the end date, not a counter: restRemaining keeps deriving from
    /// the date, so a backgrounded phone comes back to the right number. The
    /// new total goes into the phase because the ring divides by it —
    /// otherwise the arc would run past 100%.
    ///
    /// The last-seconds signal needs no "already played" flag to reset: it
    /// fires on `newRemaining < restRemaining`, and an extension raises
    /// restRemaining, so the new countdown signals again on its own way down.
    private func extendRest() {
        guard case .rest(let total) = phase, let end = restEndDate, canExtendRest else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(Self.restExtensionSeconds))
        restEndDate = newEnd
        restRemaining = max(0, Int(newEnd.timeIntervalSinceNow.rounded()))
        phase = .rest(seconds: total + Self.restExtensionSeconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: String(localized: "Next up"),
                                  restEndDate: newEnd))
        persistProgress()
    }

    private var progressFraction: CGFloat {
        guard case .rest(let total) = phase, total > 0 else { return 0 }
        return CGFloat(restRemaining) / CGFloat(total)
    }

    private var nextLabel: String {
        if isLastSet {
            if isLastExercise { return String(localized: "Workout rating") }
            let next = exercises[exIndex + 1]
            return "\(next.name) · \(next.display)"
        }
        return String(localized: "\(exercise.name) · set \(setIndex + 2) of \(exercise.sets)")
    }

    /// Rest is never entered on the final set of the last exercise (that goes
    /// straight to the cool-down), so the index is always in range.
    private var restTargetExercise: SessionExercise {
        if isLastSet && !isLastExercise {
            return exercises[exIndex + 1]
        }
        return exercise
    }

    // MARK: - State machine transitions

    private func completeSet() {
        adjusting = false
        if isLastSet && isLastExercise {
            // "Finish now" deliberately does not run the cool-down.
            startCooldown()
        } else if isLastSet {
            startRest(exercise.restExerciseSec)
        } else {
            startRest(exercise.restSetSec)
        }
    }

    /// One exit for both ways of ending an exercise early: a skip says "not
    /// today", a report says the joint complained (issue #66). The engine
    /// leaves the level alone either way — only the rest afterwards differs.
    private func leaveExercise(hurt: Bool = false) {
        adjusting = false
        holdSecondSide = false
        firstSideHeld = nil
        holdPauseEndDate = nil
        actuals.removeValue(forKey: exercise.pattern)   // either wins over an actual
        if hurt {
            discomfortPatterns.insert(exercise.pattern)
        } else {
            skippedPatterns.insert(exercise.pattern)
        }
        if isLastExercise {
            // startCooldown degrades to the rating when nothing was performed.
            startCooldown()
        } else {
            exIndex += 1
            setIndex = 0
            phase = .work
            liveActivity.update(activityWorkState())
            persistProgress()
        }
    }

    private func startRest(_ seconds: Int) {
        #if DEBUG
        // --uitest-fast: the full-flow driver must never depend on the runner
        // tapping Skip in time. Production untouched; DEBUG builds only.
        let seconds = CommandLine.arguments.contains("--uitest-fast") ? 1 : seconds
        #endif
        restRemaining = seconds
        restEndDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        restPlanned = seconds
        phase = .rest(seconds: seconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: String(localized: "Next up"),
                                  restEndDate: restEndDate))
        persistProgress()
    }

    private func tickRest() {
        guard let end = restEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != restRemaining else { return }
        if newRemaining == 0 {
            restEndDate = nil
            restRemaining = 0
            playGo()
            advanceAfterRest()
        } else {
            // no tick spam after backgrounding
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < restRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { restRemaining = newRemaining }
        }
    }
}

// MARK: - Holds, signals and session persistence

/// Same file, so the private state stays private.
private extension WorkoutFlowView {

    // MARK: - Hold countdown

    func startHold() {
        adjusting = false
        holdTotal = actuals[exercise.pattern] ?? exercise.load
        holdRemaining = holdTotal
        holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
    }

    func tickHold() {
        guard let end = holdEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdRemaining else { return }
        if newRemaining == 0 {
            // The switch pause announces itself; a go here would say "done"
            // a side too early.
            if !(exercise.perSide && !holdSecondSide) { playGo() }
            finishHold(heldSeconds: holdTotal)
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < holdRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { holdRemaining = newRemaining }
        }
    }

    static let holdMistapSeconds = 3.0

    /// "Stop" sits exactly where "Start hold" was, so a stop within the first
    /// seconds is an accidental double-tap: the set stays available.
    /// Otherwise one mis-tap consumes the set and records a bogus actual —
    /// which on the first workout also feeds the zero-level calibration.
    func stopHoldEarly() {
        guard let end = holdEndDate else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        let held = Double(holdTotal) - remaining
        if held < Self.holdMistapSeconds {
            holdEndDate = nil
            holdRemaining = holdTotal
            return
        }
        finishHold(heldSeconds: Int(held.rounded()))
    }

    /// Per-side holds run the pause and the second side by themselves; the
    /// recorded actual is the smaller of the two sides.
    func finishHold(heldSeconds: Int) {
        holdEndDate = nil
        if exercise.perSide && !holdSecondSide {
            firstSideHeld = heldSeconds
            holdSecondSide = true
            startHoldSwitchPause()
            return
        }
        let held = min(heldSeconds, firstSideHeld ?? heldSeconds)
        holdSecondSide = false
        firstSideHeld = nil
        recordHoldActual(heldSeconds: held)
        completeSet()
    }

    // MARK: - The side-switch pause (issue #35)

    func startHoldSwitchPause() {
        playSwitch()
        holdPauseRemaining = Cooldown.stageSeconds(.switchPause)
        holdPauseEndDate = Date.now.addingTimeInterval(TimeInterval(holdPauseRemaining))
    }

    /// No 3-2-1 inside the pause: ticks would bury the switch tone.
    func tickHoldSwitchPause() {
        guard let end = holdPauseEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdPauseRemaining else { return }
        if newRemaining == 0 {
            holdPauseEndDate = nil
            playGo()
            holdRemaining = holdTotal
            holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
        } else {
            withAnimation(.linear(duration: 0.3)) { holdPauseRemaining = newRemaining }
        }
    }

    /// The 5-second step of the manual adjuster, within 5...90. The planned
    /// value removes the override — that is "on plan".
    func recordHoldActual(heldSeconds: Int) {
        let rounded = min(max(Int((Double(heldSeconds) / 5).rounded()) * 5, 5), 90)
        if rounded == exercise.load {
            actuals.removeValue(forKey: exercise.pattern)
        } else {
            actuals[exercise.pattern] = rounded
        }
    }

    // MARK: - Audible countdown of the last rest seconds

    static let countdownSignalSeconds = 3
    /// One tap of extra rest. The cap on repeats is twice the planned rest.
    static let restExtensionSeconds = 15

    /// The tone respects silent mode; the haptic is the signal's silent-mode
    /// channel.
    func playTick() {
        guard store.settings.soundsEnabled else { return }
        CountdownSounds.shared.playTick()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func playGo() {
        guard store.settings.soundsEnabled else { return }
        CountdownSounds.shared.playGo()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Its own haptic weight, so silent mode can tell it from a tick.
    func playSwitch() {
        guard store.settings.soundsEnabled else { return }
        CountdownSounds.shared.playSwitch()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A toggle, not an exit: the exercise is still being done, so this must
    /// not run through leaveExercise. Flow state only — the undo is free.
    func togglePin() {
        pinnedPatterns.formSymmetricDifference([exercise.pattern])
        persistProgress()   // a lone pin is progress worth resuming
    }

    func advanceAfterRest() {
        if isLastSet {
            exIndex += 1
            setIndex = 0
        } else {
            setIndex += 1
        }
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }

    // MARK: - Surviving process death

    /// Called on every phase transition and whenever an actual changes.
    func persistProgress() {
        var restEnd: Date?
        var restTotal: Int?
        var restPlan: Int?
        if case .rest(let total) = phase {
            restEnd = restEndDate
            restTotal = total
            restPlan = restPlanned
        }
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: session.sessionNumber,
            exIndex: exIndex, setIndex: setIndex,
            restEndDate: restEnd, restTotalSec: restTotal, restPlannedSec: restPlan,
            actuals: actuals, skipped: skippedPatterns,
            discomfort: discomfortPatterns.isEmpty ? nil : discomfortPatterns,
            pinned: pinnedPatterns.isEmpty ? nil : pinnedPatterns,
            workoutStart: workoutStart ?? .now, savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: session),
            // Process death during the cool-down restores to the rating
            // (spec §4): the work is fully behind.
            atFeedback: phase == .feedback || phase == .cooldown ? true : nil,
            interrupted: interruptedPattern,
            // Without it a short-workout snapshot resumes into the full six
            // with indices pointing into a list nobody agreed to.
            shortPlan: shortPlan.map { Array($0) }))
    }

    /// A rest still running resumes inside it; one that ran out lands on the
    /// set it was leading into (the advance the timer would have made). Holds
    /// never restore mid-count — the set starts over. Indices are clamped
    /// defensively even though the snapshot was validated.
    func restore(from snap: WorkoutSnapshot) {
        exIndex = min(max(snap.exIndex, 0), exercises.count - 1)
        setIndex = min(max(snap.setIndex, 0), exercises[exIndex].sets - 1)
        actuals = snap.actuals
        skippedPatterns = snap.skipped
        discomfortPatterns = snap.discomfort ?? []
        pinnedPatterns = snap.pinned ?? []
        workoutStart = snap.workoutStart
        interruptedPattern = snap.interrupted
        if snap.atFeedback == true {
            phase = .feedback
            return
        }
        if let end = snap.restEndDate, let total = snap.restTotalSec, end > .now {
            restEndDate = end
            restRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
            // An older snapshot has no planned value; the total it carries is
            // the closest honest stand-in, and it keeps the button live.
            restPlanned = snap.restPlannedSec ?? total
            phase = .rest(seconds: total)
        } else {
            if snap.restEndDate != nil, !(isLastSet && isLastExercise) {
                if isLastSet {
                    exIndex += 1
                    setIndex = 0
                } else {
                    setIndex += 1
                }
            }
            phase = .work
        }
    }

    /// What a fresh Live Activity opens with — a resumed workout can start
    /// mid-rest.
    func currentActivityState() -> RestActivityAttributes.ContentState {
        if case .rest = phase {
            return .init(phase: .rest, title: nextLabel,
                         detail: String(localized: "Next up"),
                         restEndDate: restEndDate)
        }
        return activityWorkState()
    }

    var hasProgress: Bool {
        if case .rest = phase { return true }
        return exIndex > 0 || setIndex > 0
            || !actuals.isEmpty || !skippedPatterns.isEmpty
            || !discomfortPatterns.isEmpty || !pinnedPatterns.isEmpty
    }

    /// Every exercise not fully completed keeps its level via the engine's
    /// skip path, and the flow proceeds to the rating.
    func finishNow() {
        // Every exercise is already behind. Without this the generic path
        // would call the completed last exercise "not finished".
        if phase == .cooldown {
            finishCooldown()
            return
        }
        adjusting = false
        clearBlockPause()
        holdEndDate = nil
        holdSecondSide = false
        firstSideHeld = nil
        holdPauseEndDate = nil
        var firstUnfinished = exIndex
        if case .rest = phase, isLastSet { firstUnfinished = exIndex + 1 }
        // "not finished", not "skipped": the engine still freezes the level
        // like any skip, the label is the only difference.
        if firstUnfinished == exIndex {
            let midway: Bool
            if case .rest = phase {
                midway = true   // a between-set rest means a set is behind
            } else {
                midway = setIndex > 0 || actuals[exercise.pattern] != nil
            }
            if midway { interruptedPattern = exercise.pattern }
        }
        if firstUnfinished < exercises.count {
            for ex in exercises[firstUnfinished...]
            where !discomfortPatterns.contains(ex.pattern) {
                actuals.removeValue(forKey: ex.pattern)   // a skip wins over an actual
                skippedPatterns.insert(ex.pattern)
            }
        }
        restEndDate = nil
        restRemaining = 0
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }

    func discardWorkout() {
        store.clearWorkoutSnapshot()
        dismiss()
    }
}

// MARK: - Cool-down (issue #28)
//
// A same-file extension so the view struct stays within the linter's size
// for a type body. @State storage stays in the struct; only behaviour here.
extension WorkoutFlowView {
    /// The way back in borrows the transition's screen here too — see
    /// `warmupView`.
    @ViewBuilder
    private var cooldownView: some View {
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

    private var cooldownPositionView: some View {
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
    private func startCooldown() {
        let notPerformed = skippedPatterns.union(discomfortPatterns)
        let performed = exercises.map(\.pattern).filter { !notPerformed.contains($0) }
        cooldownPositions = Cooldown.positions(performed: performed)
        guard !cooldownPositions.isEmpty else {
            phase = .feedback
            liveActivity.end()
            persistProgress()
            return
        }
        phase = .cooldown
        liveActivity.update(.init(phase: .work, title: String(localized: "COOL-DOWN"),
                                  detail: "", restEndDate: nil))
        startCooldownPosition(0)
        persistProgress()
    }

    private func openCooldownTechnique() {
        openPositionTechnique(PositionTechnique(cooldown: cooldownPositions[cooldownIndex]))
    }

    private func skipCooldownPosition() {
        if cooldownIndex + 1 < cooldownPositions.count {
            startCooldownPosition(cooldownIndex + 1)
        } else {
            finishCooldown()
        }
    }

    private func startCooldownPosition(_ index: Int) {
        enterCooldownStage(index: index, stage: Cooldown.openingStage)
    }

    private func startCooldownPositionNow() {
        guard let next = Cooldown.step(after: (cooldownIndex, .getReady),
                                       positions: cooldownPositions) else { return }
        enterCooldownStage(index: next.index, stage: next.stage)
    }

    private func enterCooldownStage(index: Int, stage: Cooldown.Stage) {
        clearBlockPause()   // a new stage is never entered still frozen
        cooldownIndex = index
        cooldownStage = stage
        cooldownRemaining = Cooldown.stageSeconds(stage)
        cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
    }

    private func tickCooldown() {
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
            playGo()
            finishCooldown()
            return
        }
        // The signal belongs to what is on screen now: a landing on a
        // transition is silent whichever boundary opened the run (see
        // tickWarmup).
        if next.stage != .getReady {
            switch next.entered {
            case .switchPause: playSwitch()
            case .getReady:    break
            default:           playGo()
            }
        }
        cooldownIndex = next.index
        cooldownStage = next.stage
        cooldownRemaining = next.remaining
        cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(next.remaining))
        // Re-stamp so a long cool-down keeps the session resumable — it
        // restores onto the rating (spec §4), never into a stretch.
        if next.entered == .getReady { persistProgress() }
    }

    private func finishCooldown() {
        clearBlockPause()
        cooldownEndDate = nil
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }
}

// MARK: - The pause of the guided blocks (issue #61)
//
// The state machine is BlockPause.State; this is the flow's half — the block's
// own end dates, the tones, and the screen. The snapshot is untouched: the
// warm-up writes none by design, the cool-down keeps writing at position
// boundaries, and process death while paused restores by the rules it had.
extension WorkoutFlowView {

    private var reentering: Bool { blockPause.isReentering }

    private func countdownIdentifier(reentering: Bool) -> String {
        reentering ? "reentry-countdown" : "getready-countdown"
    }

    /// Held, the only way on is Resume; counting back in, the tap holds again.
    private func toggleBlockPause() {
        if blockPause.isHeld { resumeBlock() } else { pauseBlock() }
    }

    /// Freezes the stage where it stands: the end date comes off, so every
    /// tick guard goes quiet and no tone can be reached, while the seconds on
    /// screen stay put and rebuild it later.
    private func pauseBlock() {
        blockPause.hold()
        warmupEndDate = nil
        cooldownEndDate = nil
        announce(String(localized: "Paused"))
    }

    private func resumeBlock() {
        announce(String(localized: "Resumed"))
        guard needsReentry else {
            // A frozen transition is its own way back in: its 3-2-1 and its
            // go are still ahead of it, and a lead-in here would count one
            // position down twice.
            blockPause.clear()
            restartFrozenStage()
            return
        }
        blockPause.beginReentry(seconds: BlockPause.reentrySeconds, now: .now)
    }

    private var needsReentry: Bool {
        switch phase {
        case .warmup:   return BlockPause.needsReentry(warmupStage)
        case .cooldown: return BlockPause.needsReentry(cooldownStage)
        default:        return false
        }
    }

    /// Held there is no end date at all, so nothing moves — the whole point.
    private func tickBlockPause() {
        var result = BlockPause.Tick.nothing
        withAnimation(.linear(duration: 0.3)) {
            result = blockPause.tick(now: .now, signalSeconds: Self.countdownSignalSeconds)
        }
        switch result {
        case .signal:            playTick()
        case .over:              endBlockReentry()
        case .nothing, .redraw:  break
        }
    }

    /// The go marks the moment the position starts again — the signal a "Get
    /// ready" ends on, for the same reason.
    private func endBlockReentry() {
        playGo()
        blockPause.clear()
        restartFrozenStage()
    }

    /// The stage picks up the seconds it froze with, never its whole length:
    /// a pause must not quietly make the user hold a position twice.
    private func restartFrozenStage() {
        switch phase {
        case .warmup:
            warmupEndDate = Date.now.addingTimeInterval(TimeInterval(warmupRemaining))
        case .cooldown:
            cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
        default:
            break
        }
    }

    /// Entering a stage, skipping a position and leaving a block all end the
    /// pause with it: one state serves both blocks and must never outlive the
    /// screen that froze.
    private func clearBlockPause() { blockPause.clear() }

    /// VoiceOver stays on the control it has just used, so the state change
    /// has to be spoken; everyone else reads it under the countdown.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
