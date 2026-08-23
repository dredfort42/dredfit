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

// v2.26: the type is split across files — one per guided block, in
// WorkoutFlowView+Warmup.swift and WorkoutFlowView+Cooldown.swift, because
// this file crossed the lint's hard ceiling of 1200 lines and a CI error is
// not a style opinion. Swift's
// `private` is FILE-scoped, so the state and helpers that block reaches for
// are declared without it. They are internal to the module and to this type,
// not API: nothing outside the two files touches them.
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

    enum Phase: Equatable {
        /// v2.26 (spec §37.7a, owner's call): the warm-up no longer starts
        /// itself either. Being dropped straight into a countdown nobody
        /// agreed to is how a block gets skipped by walking away rather than
        /// by saying so — and the answer "I am already warm" is a real one.
        /// Offered, never required; the same two answers as the cool-down.
        case warmupIntro
        case warmup
        case work
        case rest(seconds: Int)
        /// v2.26 (spec §37.7a): the cool-down no longer starts itself. The
        /// work is behind, and being dropped straight into a stretch nobody
        /// asked for is how a block gets skipped by walking away instead of by
        /// saying so. One screen, two answers, and both are fine.
        case cooldownIntro
        case cooldown                 // between the last exercise and the rating
        case feedback
        case milestone([Milestone])   // only when the workout earned one
    }

    @State private var exIndex = 0
    @State private var setIndex = 0          // 0-based
    @State var phase: Phase = .warmupIntro
    @State var warmupIndex = 0
    @State var warmupRemaining = 0
    @State var warmupEndDate: Date?
    // Shares the block's countdown state — one timer, two stages — so
    // nothing new has to survive backgrounding.
    @State var warmupStage: Warmup.Stage = .getReady
    // Computed once on entry: the composition depends on what was performed.
    @State var cooldownPositions: [CooldownPosition] = []
    @State var cooldownIndex = 0
    @State var cooldownRemaining = 0
    @State var cooldownEndDate: Date?
    @State var cooldownStage: Cooldown.Stage = Cooldown.openingStage
    // The pause of the guided blocks (issue #61). One for both, like the
    // stage/remaining pairs above: the two blocks never run at once. Held, the
    // frozen seconds sit in warmupRemaining / cooldownRemaining and no end
    // date exists anywhere; re-entering, only this moves.
    @State var blockPause = BlockPause.State()
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
    /// A fact belongs to the set it happened on — see SetFacts for the shape
    /// and for what a set of them collapses to.
    @State private var actuals: SetFacts.PerSet = [:]
    @State var skippedPatterns: Set<Pattern> = []
    /// Kept apart from `skippedPatterns`: the engine treats both as skips for
    /// the session, but the rating and the history say different things.
    @State private var adjusting = false
    /// v2.26 (spec §37.8 p. 2): movements this session has already been warned
    /// about. Once per exercise — a second copy of the same advice is nagging.
    @State private var maximumNoted: Set<Pattern> = []
    @State private var maximumWarning: String?
    @State private var adjustValue = 0
    @State private var workoutStart: Date?   // actual duration for Health
    @State private var lastResult: FeedbackResult?   // gates the review ask
    @State var liveActivity = WorkoutActivityController()
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
    var exercises: [SessionExercise] {
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
            case .warmupIntro:
                warmupIntroView
            case .warmup:
                warmupView
            case .work:
                workView
            case .rest:
                restView
            case .cooldownIntro:
                cooldownIntroView
            case .cooldown:
                cooldownView
            case .feedback:
                FeedbackView(session: session, facts: actuals,
                             skipped: skippedPatterns.union(omitted),
                             interrupted: interruptedPattern) { result, overrides in
                    let earned = store.completeWorkout(
                        session: session, result: result,
                        overrides: overrides,
                        setActuals: actuals,
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
                        // At the transition, not in MilestoneView.onAppear:
                        // onAppear can refire behind sheets, and a restore
                        // lands on the rating — so this cannot double-play.
                        playMilestone()
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
        .background(Theme.bg.ignoresSafeArea())
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
                       steps: isWarmingUp ? 0 : exercises.count,
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
        case .warmup, .warmupIntro: return String(localized: "WARM-UP")
        case .cooldownIntro, .cooldown: return String(localized: "COOL-DOWN")
        default:        return String(localized: "REST")
        }
    }

    // MARK: - The technique sheet (shared by both guided blocks)

    /// Freezes the running countdown: the end date comes off (the tick
    /// guards go quiet) while the remaining seconds stay put and rebuild it.
    /// The way back in from a pause freezes with it — reading is not getting
    /// back into position either.
    func openPositionTechnique(_ technique: PositionTechnique) {
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

    // MARK: - Live Activity

    /// Strings leave the app pre-localized — the extension renders verbatim.
    func activityWorkState() -> RestActivityAttributes.ContentState {
        if isWarmingUp {
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
                .accessibilityLabel(Text(verbatim: exercise.name))

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
                              actual: setActual,
                              setIndex: setIndex, sets: exercise.sets,
                              planned: exercise.plannedLoad(set: setIndex),
                              uneven: exercise.loads != nil)
                .padding(.top, 10)

            Spacer()

            if adjusting {
                AdjustPanel(value: $adjustValue, unit: exercise.unit) {
                    // This set only — the ones behind keep what they ran at.
                    actuals = SetFacts.recording(adjustValue, in: actuals,
                                                 exercise, set: setIndex)
                    noteMaximumOutOfOrder()
                    adjusting = false
                    persistProgress()   // an entered actual is worth keeping
                }
                .padding(.bottom, 8)
            }

            // v2.26 (spec §37.8 p. 2): soft, once per exercise per session,
            // and it never blocks the entry.
            if let warning = maximumWarning {
                Text(warning)
                    .dredfitFont(13)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("maximum-order-note")
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

            ExerciseActionsRow(onAdjust: { startAdjusting() },
                               onSkip: { leaveExercise() })
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
        return SetFacts.inForce(actuals, exercise, set: setIndex)
    }

    /// The caption's: this set's own number, nothing when it is the plan.
    private var setActual: Int? {
        let value = SetFacts.inForce(actuals, exercise, set: setIndex)
        return value == exercise.load ? nil : value
    }

    // MARK: - Inline actual adjuster (the panel itself is AdjustPanel.swift)

    private func startAdjusting() {
        adjustValue = SetFacts.inForce(actuals, exercise, set: setIndex)
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
        // All three ways a set ends meet here (#186): the Done tap, the hold
        // reaching zero, an early stop past the mis-tap window. A per-side
        // hold's first side goes to the switch pause instead, not here.
        playDone()
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

    /// Leaving an exercise early. v2.26 (spec §37.0): there used to be two
    /// ways — a skip and a pain report — and the report is gone. A person who
    /// finds the movement too hard now reaches for a handle instead, which
    /// keeps the movement in the plan rather than taking it out for weeks.
    /// v2.26 (spec §37.8 p. 2): a soft note when the person enters MORE than
    /// the plan on a set that is not the last one. Once per exercise per
    /// session, and the entry stands either way — it is advice about the
    /// workout, never a correction of the number.
    ///
    /// What it must NOT say is that the system measures the last set more
    /// accurately. Under a mean the ORDER OF SETS DOES NOT REACH THE ENGINE at
    /// all: 12, 8, 8 and 8, 8, 12 both collapse to 9 (§37.8 p. 3). The advice
    /// is about training — a maximum attempt fatigues what follows it — and
    /// the wording says exactly that and nothing more.
    private func noteMaximumOutOfOrder() {
        let pattern = exercise.pattern
        guard !maximumNoted.contains(pattern) else { return }
        guard setIndex < exercise.sets - 1 else { return }          // the last set is fine
        guard adjustValue > exercise.plannedLoad(set: setIndex) else { return }
        maximumNoted.insert(pattern)
        maximumWarning = String(localized: "Do the plan, and leave your maximum for the last set.")
    }

    private func leaveExercise() {
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
            maximumWarning = nil   // the note belongs to the exercise it was about
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
// Declared without `private` for the same reason as the state above: Swift's
// `private` is file-scoped, and the cool-down block was moved to its own file
// when this one crossed the lint's hard ceiling.
extension WorkoutFlowView {

    // MARK: - Hold countdown

    func startHold() {
        adjusting = false
        holdTotal = SetFacts.inForce(actuals, exercise, set: setIndex)
        holdRemaining = holdTotal
        holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
    }

    func tickHold() {
        guard let end = holdEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdRemaining else { return }
        if newRemaining == 0 {
            // Silent: completeSet() owns the end-of-set signal now, whatever
            // ended it (#186). Sounding a done here would double it.
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
        holdPauseRemaining = Cooldown.switchPauseSeconds
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

    /// Onto the grid the manual adjuster steps on, and onto the set actually
    /// held: stopping at 40 s of 55 in the third set is the third set's fact.
    func recordHoldActual(heldSeconds: Int) {
        actuals = SetFacts.recording(SetFacts.snap(Double(heldSeconds), unit: .hold),
                                     in: actuals, exercise, set: setIndex)
    }

    // MARK: - Audible countdown of the last rest seconds

    static let countdownSignalSeconds = 3
    /// One tap of extra rest. The cap on repeats is twice the planned rest.
    static let restExtensionSeconds = 15

    /// Thin wrappers: each signal's tone + haptic pair lives in
    /// WorkoutSignals, gated here by the one sounds toggle.
    func playTick() { WorkoutSignals.tick(store.settings.soundsEnabled) }
    func playGo() { WorkoutSignals.go(store.settings.soundsEnabled) }
    func playSwitch() { WorkoutSignals.switchSides(store.settings.soundsEnabled) }
    func playDone() { WorkoutSignals.done(store.settings.soundsEnabled) }
    func playWorkoutDone() { WorkoutSignals.workoutDone(store.settings.soundsEnabled) }
    func playMilestone() { WorkoutSignals.milestone(store.settings.soundsEnabled) }

    func advanceAfterRest() {
        if isLastSet {
            exIndex += 1
            maximumWarning = nil   // the note belongs to the exercise it was about
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
            setActuals: actuals, skipped: skippedPatterns,
            workoutStart: workoutStart ?? .now, savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: session),
            // Process death during the cool-down restores to the rating
            // (spec §4): the work is fully behind.
            // v2.26: the intro screen counts as "the work is behind" too —
            // process death there must not resume into the last exercise.
            atFeedback: phase == .feedback || phase == .cooldown
                || phase == .cooldownIntro ? true : nil,
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
        actuals = snap.facts
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
            // An older snapshot has no planned value; the total it carries is
            // the closest honest stand-in, and it keeps the button live.
            restPlanned = snap.restPlannedSec ?? total
            phase = .rest(seconds: total)
        } else {
            if snap.restEndDate != nil, !(isLastSet && isLastExercise) {
                if isLastSet {
                    exIndex += 1
            maximumWarning = nil   // the note belongs to the exercise it was about
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
        // v2.26: the cool-down QUESTION is behind the work too — leaving from
        // it must end the same way leaving from the block does.
        if phase == .cooldown || phase == .cooldownIntro {
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

// MARK: - The pause of the guided blocks (issue #61)
//
// The state machine is BlockPause.State; this is the flow's half — the block's
// own end dates, the tones, and the screen. The snapshot is untouched: the
// warm-up writes none by design, the cool-down keeps writing at position
// boundaries, and process death while paused restores by the rules it had.
extension WorkoutFlowView {

    var reentering: Bool { blockPause.isReentering }

    func countdownIdentifier(reentering: Bool) -> String {
        reentering ? "reentry-countdown" : "getready-countdown"
    }

    /// Held, the only way on is Resume; counting back in, the tap holds again.
    func toggleBlockPause() {
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
    func endBlockReentry() {
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
    func clearBlockPause() { blockPause.clear() }

    /// VoiceOver stays on the control it has just used, so the state change
    /// has to be spoken; everyone else reads it under the countdown.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
