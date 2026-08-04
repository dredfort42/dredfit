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
    @State private var restRemaining = 0
    @State private var restEndDate: Date?
    // Captured at tap time (not a bool): the rest countdown keeps ticking
    // while the sheet is open and may flip the phase underneath.
    @State private var techniqueExercise: SessionExercise?
    // Unlike techniqueExercise, presenting this freezes the countdown.
    @State private var positionTechnique: PositionTechnique?
    @State private var actuals: [Pattern: Int] = [:]
    @State private var skippedPatterns: Set<Pattern> = []
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
                             interrupted: interruptedPattern,
                             lastResult: store.lastRecord?.result) { result, overrides in
                    let earned = store.completeWorkout(
                        session: session, result: result,
                        overrides: overrides,
                        // Skips like any other: levels frozen, counter and
                        // rotation still advance. The engine has no idea the
                        // workout was short, and that is the point.
                        skipped: skippedPatterns.union(omitted),
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
                tickWarmup()
            case .rest:
                tickRest()
            case .cooldown:
                tickCooldown()
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
            VStack(spacing: 10) {
                HStack {
                    // ink2, not ink3: ink3 (~2.4:1) fails contrast for
                    // interactive text.
                    Button(String(localized: "Exit")) {
                        if hasProgress {
                            exitConfirmShown = true
                        } else {
                            discardWorkout()
                        }
                    }
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Group {
                        switch phase {
                        case .work:
                            Text("\(exIndex + 1) / \(exercises.count)")
                        case .warmup:
                            Text("WARM-UP")
                        case .cooldown:
                            Text("COOL-DOWN")
                        default:
                            Text("REST")
                        }
                    }
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    // ink2, not ink3: this is information, not decoration.
                    .foregroundStyle(Theme.ink2)
                    Spacer()
                    Button(String(localized: "Exit")) { }.dredfitFont(14).hidden() // symmetry
                }
                if phase != .warmup {
                    HStack(spacing: 5) {
                        ForEach(0..<exercises.count, id: \.self) { i in
                            Capsule()
                                .fill(i <= exIndex ? Theme.ink : Theme.hairline)
                                .frame(height: 4)
                        }
                    }
                    .frame(width: 200)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Warm-up


    @ViewBuilder
    private var warmupView: some View {
        if warmupStage == .getReady {
            GetReadyScreen(name: Warmup.moves[warmupIndex].name,
                           remaining: warmupRemaining,
                           index: warmupIndex, count: Warmup.moves.count,
                           blockSkipTitle: String(localized: "Skip warm-up"),
                           onTechnique: { openWarmupTechnique() },
                           onStart: { startWarmupMoveNow() },
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
                         onTechnique: { openWarmupTechnique() },
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
    private func openPositionTechnique(_ technique: PositionTechnique) {
        positionTechnique = technique
        warmupEndDate = nil
        cooldownEndDate = nil
    }

    private func resumePositionCountdown() {
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

            Group {
                if holdSwitchPausing {
                    Text("Switch sides")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.accentText)
                } else if holdSecondSide {
                    Text("second side")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.accentText)
                } else if let actual = actuals[exercise.pattern], actual != exercise.load {
                    Text("actual \(actual)")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.accentText)
                } else {
                    Text("set \(setIndex + 1) of \(exercise.sets)")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                }
            }
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

            HStack(spacing: 26) {
                Button(String(localized: "Went differently")) { startAdjusting() }
                Button(String(localized: "Skip exercise")) { skipExercise() }
            }
            .dredfitFont(14.5)
            .foregroundStyle(Theme.ink2)
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
        // Must agree with the number above it (ru: 1 повтор / 3 повтора).
        let base: String
        switch exercise.unit {
        case .reps: base = String(localized: "\(workNumber) reps")
        case .hold: base = String(localized: "\(workNumber) seconds")
        }
        return exercise.perSide ? String(localized: "\(base) per side") : base
    }

    // MARK: - Rest

    private var restView: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: restRemaining)
                VStack(spacing: 2) {
                    Text("\(restRemaining)")
                        .dredfitFont(72, weight: .heavy, cap: 104)
                        .tracking(-2)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("sec")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                }
            }
            // Capped to still fit the narrowest screen with its 24pt margins.
            .frame(width: min(restRingSize, 330), height: min(restRingSize, 330))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(restRemaining) seconds of rest left"))

            VStack(spacing: 6) {
                Kicker(text: String(localized: "Next up"))
                Text(nextLabel)
                    .dredfitFont(17, weight: .semibold)
            }
            .padding(.top, 44)

            TechniqueButton { techniqueExercise = restTargetExercise }
                .padding(.top, 16)

            Spacer()

            BlockSkipButton(title: String(localized: "Skip rest")) {
                restEndDate = nil
                restRemaining = 0
                advanceAfterRest()
            }
            .padding(.bottom, 20)
        }
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

    private func skipExercise() {
        adjusting = false
        holdSecondSide = false
        firstSideHeld = nil
        holdPauseEndDate = nil
        actuals.removeValue(forKey: exercise.pattern)   // a skip wins over an actual
        skippedPatterns.insert(exercise.pattern)
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
        if case .rest(let total) = phase {
            restEnd = restEndDate
            restTotal = total
        }
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: session.sessionNumber,
            exIndex: exIndex, setIndex: setIndex,
            restEndDate: restEnd, restTotalSec: restTotal,
            actuals: actuals, skipped: skippedPatterns,
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
        workoutStart = snap.workoutStart
        interruptedPattern = snap.interrupted
        if snap.atFeedback == true {
            phase = .feedback
            return
        }
        if let end = snap.restEndDate, let total = snap.restTotalSec, end > .now {
            restEndDate = end
            restRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
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
            for ex in exercises[firstUnfinished...] {
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
    @ViewBuilder
    private var cooldownView: some View {
        if cooldownStage == .getReady {
            GetReadyScreen(name: cooldownPositions[cooldownIndex].name,
                           remaining: cooldownRemaining,
                           index: cooldownIndex, count: cooldownPositions.count,
                           blockSkipTitle: String(localized: "cooldown.skip",
                                                  defaultValue: "Skip cool-down"),
                           blockSkipIdentifier: "skip-cooldown",
                           onTechnique: { openCooldownTechnique() },
                           onStart: { startCooldownPositionNow() },
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
                               onTechnique: { openCooldownTechnique() },
                               onSkipPosition: { skipCooldownPosition() },
                               onSkipBlock: { finishCooldown() })
    }

    /// A workout of pure skips has nothing to stretch — straight to the
    /// rating instead.
    private func startCooldown() {
        let performed = exercises.map(\.pattern).filter { !skippedPatterns.contains($0) }
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
        cooldownEndDate = nil
        phase = .feedback
        liveActivity.end()
        persistProgress()
    }
}
