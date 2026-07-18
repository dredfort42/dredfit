//
//  WorkoutFlowView.swift
//  Dredfit
//
//  The workout flow: exercise (big number, set dots) and rest (ring timer).
//  State machine: work > rest > … > feedback.
//
//  v1.1: hold exercises run a countdown (start by button, 3-2-1 signals,
//  auto-advance at zero; an early stop records the held seconds as the
//  actual). Skipped exercises are collected and passed to the engine so
//  their patterns honestly keep their level. The screen stays awake.
//

import Combine
import SwiftUI
import AudioToolbox
import StoreKit
import UIKit
import DredfitCore

struct WorkoutFlowView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.requestReview) private var requestReview

    private enum Phase: Equatable {
        case warmup
        case work
        case rest(seconds: Int)
        case feedback
        case milestone([Milestone])   // v1.4 — only when the workout earned one
    }

    @State private var exIndex = 0
    @State private var setIndex = 0          // 0-based
    @State private var phase: Phase = .warmup
    @State private var warmupIndex = 0
    @State private var warmupRemaining = 0
    @State private var warmupEndDate: Date?
    @State private var restRemaining = 0
    @State private var restEndDate: Date?
    // Captured at tap time (not a bool): the rest countdown keeps ticking while
    // the sheet is open, so it may flip the phase underneath — the item binding
    // keeps whatever exercise was tapped, immune to that transition.
    @State private var techniqueExercise: SessionExercise?
    @State private var actuals: [Pattern: Int] = [:]
    @State private var skippedPatterns: Set<Pattern> = []
    @State private var adjusting = false
    @State private var adjustValue = 0
    @State private var workoutStart: Date?   // v1.3: actual duration for Health
    @State private var lastResult: FeedbackResult?   // v1.4: gates the review ask
    @State private var liveActivity = WorkoutActivityController()   // v1.3

    // Hold-exercise countdown (v1.1): date-based so it survives backgrounding.
    // Per-side holds run the countdown twice (left/right); the actual is the
    // smaller of the two — the honest bottleneck.
    @State private var holdEndDate: Date?
    @State private var holdRemaining = 0
    @State private var holdTotal = 0
    @State private var holdSecondSide = false
    @State private var firstSideHeld: Int?

    /// The rest ring scales with the countdown it frames (v1.4).
    @ScaledMetric(relativeTo: .largeTitle) private var restRingSize: CGFloat = 240

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var exercise: SessionExercise { session.exercises[exIndex] }
    private var isLastSet: Bool { setIndex == exercise.sets - 1 }
    private var isLastExercise: Bool { exIndex == session.exercises.count - 1 }
    private var holding: Bool { holdEndDate != nil }
    private var isMilestone: Bool { if case .milestone = phase { return true }; return false }

    /// The only place the app ever asks for a review (v1.4): closing a
    /// milestone screen, and only when every condition in the store's gate
    /// holds. The stamp is written whether or not iOS decides to show the
    /// prompt — Apple rate-limits it invisibly, and a request we cannot see
    /// the outcome of still counts against our own 60-day floor.
    private func askForReviewIfEarned() {
        guard store.shouldRequestReview(lastResult: lastResult) else { return }
        store.recordReviewRequest()
        requestReview()
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
            case .feedback:
                FeedbackView(session: session, actuals: actuals,
                             skipped: skippedPatterns) { result, overrides in
                    let earned = store.completeWorkout(
                        session: session, result: result,
                        overrides: overrides, skipped: skippedPatterns,
                        durationSec: workoutStart.map {
                            Int(Date.now.timeIntervalSince($0))
                        })
                    // The workout is already recorded either way — the
                    // milestone screen is a coda, never a gate.
                    if earned.isEmpty {
                        dismiss()
                    } else {
                        lastResult = result
                        phase = .milestone(earned)
                    }
                }
            case .milestone(let earned):
                MilestoneView(milestones: earned) {
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
            case .work where holding:
                tickHold()
            default:
                break
            }
        }
        .onAppear {
            // Keep the screen awake for the whole workout (timers, holds).
            UIApplication.shared.isIdleTimerDisabled = true
            if workoutStart == nil {
                workoutStart = .now
                liveActivity.start(sessionNumber: session.sessionNumber,
                                   state: activityWorkState())
            }
            if phase == .warmup && warmupEndDate == nil { startWarmupMove(0) }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            liveActivity.end()
        }
        .sheet(item: $techniqueExercise) { ex in
            TechniqueSheet(exercise: ex)
        }
    }

    // MARK: - Header with progress segments

    @ViewBuilder
    private var header: some View {
        // Feedback and the milestone screen own the full screen: no exit
        // button, no progress segments — the workout is already over.
        if phase != .feedback, !isMilestone {
            VStack(spacing: 10) {
                HStack {
                    Button(String(localized: "Exit")) { dismiss() }
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Group {
                        switch phase {
                        case .work:
                            Text("\(exIndex + 1) / \(session.exercises.count)")
                        case .warmup:
                            Text("WARM-UP")
                        default:
                            Text("REST")
                        }
                    }
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    .foregroundStyle(Theme.ink3)
                    Spacer()
                    Button(String(localized: "Exit")) { }.dredfitFont(14).hidden() // symmetry
                }
                if phase != .warmup {
                    HStack(spacing: 5) {
                        ForEach(0..<session.exercises.count, id: \.self) { i in
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

    // MARK: - Warm-up (v1.1)

    /// Six universal mobility moves, 30 s each — ~3 minutes before the first
    /// exercise. No levels involved; the whole block can be skipped.
    private static let warmupMoves: [String.LocalizationValue] = [
        "Marching in place", "Arm circles", "Torso rotations",
        "Hip circles", "Half squats", "Cat-cow",
    ]
    private static let warmupMoveSeconds = 30

    private var warmupView: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(String(localized: Self.warmupMoves[warmupIndex]))
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            VStack(spacing: 4) {
                Text("\(warmupRemaining)")
                    .dredfitFont(112, weight: .heavy, cap: 150)
                    .tracking(-4)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("sec")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 20)

            HStack(spacing: 10) {
                ForEach(0..<Self.warmupMoves.count, id: \.self) { i in
                    Circle()
                        .fill(i < warmupIndex ? Theme.ink
                              : (i == warmupIndex ? Theme.accent : Theme.hairline))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 30)

            Spacer()

            Button {
                finishWarmup()
            } label: {
                Text("Skip warm-up")
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1.5))
            }
            .padding(.bottom, 20)
        }
    }

    private func startWarmupMove(_ index: Int) {
        warmupIndex = index
        warmupRemaining = Self.warmupMoveSeconds
        warmupEndDate = Date.now.addingTimeInterval(TimeInterval(Self.warmupMoveSeconds))
    }

    private func tickWarmup() {
        guard let end = warmupEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != warmupRemaining else { return }
        if newRemaining == 0 {
            playGo()
            if warmupIndex + 1 < Self.warmupMoves.count {
                startWarmupMove(warmupIndex + 1)
            } else {
                finishWarmup()
            }
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < warmupRemaining {
                playTick()
            }
            warmupRemaining = newRemaining
        }
    }

    private func finishWarmup() {
        warmupEndDate = nil
        phase = .work
        liveActivity.update(activityWorkState())
    }

    // MARK: - Live Activity (v1.3)

    /// The lock-screen state for the current work phase. Strings leave the
    /// app pre-localized — the extension renders them verbatim.
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

            Button {
                techniqueExercise = exercise
            } label: {
                Label(String(localized: "technique"), systemImage: "info.circle")
                    .dredfitFont(14, weight: .medium)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 10)

            VStack(spacing: 4) {
                Text("\(holding ? holdRemaining : (actuals[exercise.pattern] ?? exercise.load))")
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
                if holdSecondSide {
                    Text("second side")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                } else if let actual = actuals[exercise.pattern], actual != exercise.load {
                    Text("actual \(actual)")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("set \(setIndex + 1) of \(exercise.sets)")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.top, 10)

            Spacer()

            if adjusting {
                adjustPanel
                    .padding(.bottom, 8)
            }

            if exercise.unit == .hold {
                if holding {
                    PrimaryButton(title: String(localized: "Stop")) { stopHoldEarly() }
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
            .opacity(holding ? 0 : 1)      // no adjusting/skipping mid-hold
            .disabled(holding)
        }
    }

    // MARK: - Inline actual adjuster (UPDATE-5)

    private var adjustPanel: some View {
        HStack(spacing: 18) {
            stepButton("minus") { bumpAdjust(-1) }
            Text(exercise.unit == .hold ? "\(adjustValue) s" : "\(adjustValue)")
                .dredfitFont(26, weight: .heavy)
                .monospacedDigit()
                .frame(minWidth: 76)
            stepButton("plus") { bumpAdjust(+1) }

            Button {
                actuals[exercise.pattern] = adjustValue
                if adjustValue == exercise.load {
                    actuals.removeValue(forKey: exercise.pattern) // back to the plan
                }
                adjusting = false
            } label: {
                Text("OK")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .dredfitFont(15, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().stroke(Theme.hairline, lineWidth: 1.5))
        }
        // "minus"/"plus" alone is what VoiceOver would otherwise announce.
        .accessibilityLabel(Text(icon == "minus"
                                 ? String(localized: "Fewer")
                                 : String(localized: "More")))
        // Pinned so the label change does not move the symbol-derived id.
        .accessibilityIdentifier(icon)
    }

    private func startAdjusting() {
        adjustValue = actuals[exercise.pattern] ?? exercise.load
        adjusting = true
    }

    private func bumpAdjust(_ dir: Int) {
        let step = exercise.unit == .hold ? 5 : 1
        let range = exercise.unit == .hold ? 5...90 : 0...30
        adjustValue = min(max(adjustValue + dir * step, range.lowerBound), range.upperBound)
    }

    private var loadCaption: String {
        let base: String
        switch exercise.unit {
        case .reps: base = String(localized: "reps")
        case .hold: base = String(localized: "seconds")
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
            // The ring grows with the countdown inside it, up to a diameter
            // that still fits the narrowest screen with its 24pt margins.
            .frame(width: min(restRingSize, 330), height: min(restRingSize, 330))
            // Read as one thing: "42 seconds of rest", not "42" then "sec".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(restRemaining) seconds of rest left"))

            VStack(spacing: 6) {
                Kicker(text: String(localized: "Next up"))
                Text(nextLabel)
                    .dredfitFont(17, weight: .semibold)
            }
            .padding(.top, 44)

            // v1.3: review the technique of what's coming up while you rest —
            // the same sheet the work screen offers, aimed at the next move.
            Button {
                techniqueExercise = restTargetExercise
            } label: {
                Label(String(localized: "technique"), systemImage: "info.circle")
                    .dredfitFont(14, weight: .medium)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 16)

            Spacer()

            Button {
                restEndDate = nil
                restRemaining = 0
                advanceAfterRest()
            } label: {
                Text("Skip rest")
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1.5))
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
            let next = session.exercises[exIndex + 1]
            return "\(next.name) · \(next.display)"
        }
        return String(localized: "\(exercise.name) · set \(setIndex + 2) of \(exercise.sets)")
    }

    /// The exercise this rest leads into — the one under "Next up". Between
    /// sets it's the current exercise; after the last set it's the next one.
    /// Rest is never entered on the final set of the last exercise (that goes
    /// straight to feedback), so the index is always in range.
    private var restTargetExercise: SessionExercise {
        if isLastSet && !isLastExercise {
            return session.exercises[exIndex + 1]
        }
        return exercise
    }

    // MARK: - State machine transitions

    private func completeSet() {
        adjusting = false
        if isLastSet && isLastExercise {
            phase = .feedback
            liveActivity.end()
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
        actuals.removeValue(forKey: exercise.pattern)   // a skip wins over an actual
        skippedPatterns.insert(exercise.pattern)
        if isLastExercise {
            phase = .feedback
            liveActivity.end()
        } else {
            exIndex += 1
            setIndex = 0
            phase = .work
            liveActivity.update(activityWorkState())
        }
    }

    private func startRest(_ seconds: Int) {
        restRemaining = seconds
        restEndDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        phase = .rest(seconds: seconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: String(localized: "Next up"),
                                  restEndDate: restEndDate))
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
            // tick once per second in the 3-2-1 zone (no spam after backgrounding)
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < restRemaining {
                playTick()
            }
            restRemaining = newRemaining
        }
    }

    // MARK: - Hold countdown (v1.1)

    private func startHold() {
        adjusting = false
        holdTotal = actuals[exercise.pattern] ?? exercise.load
        holdRemaining = holdTotal
        holdEndDate = Date.now.addingTimeInterval(TimeInterval(holdTotal))
    }

    private func tickHold() {
        guard let end = holdEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != holdRemaining else { return }
        if newRemaining == 0 {
            playGo()
            finishHold(heldSeconds: holdTotal)
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < holdRemaining {
                playTick()
            }
            holdRemaining = newRemaining
        }
    }

    /// Early stop: the seconds actually held become the actual.
    private func stopHoldEarly() {
        guard let end = holdEndDate else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        finishHold(heldSeconds: Int((Double(holdTotal) - remaining).rounded()))
    }

    /// One countdown finished. Per-side holds wait for the second side
    /// (started by button, giving time to switch); the recorded actual is
    /// the smaller of the two sides.
    private func finishHold(heldSeconds: Int) {
        holdEndDate = nil
        if exercise.perSide && !holdSecondSide {
            firstSideHeld = heldSeconds
            holdSecondSide = true
            return
        }
        let held = min(heldSeconds, firstSideHeld ?? heldSeconds)
        holdSecondSide = false
        firstSideHeld = nil
        recordHoldActual(heldSeconds: held)
        completeSet()
    }

    /// Rounds to the 5-second step (same as the manual adjuster), within 5...90.
    /// Holding exactly the planned value removes the override — that is "on plan".
    private func recordHoldActual(heldSeconds: Int) {
        let rounded = min(max(Int((Double(heldSeconds) / 5).rounded()) * 5, 5), 90)
        if rounded == exercise.load {
            actuals.removeValue(forKey: exercise.pattern)
        } else {
            actuals[exercise.pattern] = rounded
        }
    }

    // MARK: - Audible countdown of the last rest seconds

    /// How many seconds before the end of rest to start "ticking".
    private static let countdownSignalSeconds = 3

    /// A short tick on 3-2-1. The system sound respects silent mode,
    /// a light vibration duplicates the signal for silent mode.
    /// Both obey the "Sounds and haptics" setting (v1.1).
    private func playTick() {
        guard store.settings.soundsEnabled else { return }
        AudioServicesPlaySystemSound(1103) // Tink
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The "set start" signal at zero — lower in tone and with a haptic accent.
    private func playGo() {
        guard store.settings.soundsEnabled else { return }
        AudioServicesPlaySystemSound(1104) // Tock
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func advanceAfterRest() {
        if isLastSet {
            exIndex += 1
            setIndex = 0
        } else {
            setIndex += 1
        }
        phase = .work
        liveActivity.update(activityWorkState())
    }
}
