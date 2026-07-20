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
    /// v1.7: a mid-workout snapshot to pick up from (the "Continue" path on
    /// Today). nil starts the session from the warm-up as always.
    var resume: WorkoutSnapshot? = nil
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
    @State private var exitConfirmShown = false   // v1.7
    /// The exercise "Finish now" cut mid-way — labelled "not finished" on
    /// the rating screen while the engine still treats it as a skip.
    @State private var interruptedPattern: Pattern?
    /// One-shot guard for the restore + Live Activity work in onAppear —
    /// sheets presented over the flow can make it fire more than once.
    @State private var didStart = false

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
    /// The request itself waits out the cover's dismissal transition: StoreKit
    /// may silently drop a prompt asked for mid-transition, which would burn
    /// the 60-day stamp on a prompt nobody saw.
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
            case .feedback:
                FeedbackView(session: session, actuals: actuals,
                             skipped: skippedPatterns,
                             interrupted: interruptedPattern) { result, overrides in
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
            guard !didStart else { return }
            didStart = true
            if let resume { restore(from: resume) }
            if workoutStart == nil { workoutStart = .now }
            // No Live Activity when resuming straight onto the rating —
            // there is no set or rest left for the lock screen to describe.
            if phase != .feedback {
                liveActivity.start(sessionNumber: session.sessionNumber,
                                   state: currentActivityState())
            }
            if phase == .warmup { startWarmupMove(0) }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            liveActivity.end()
        }
        .sheet(item: $techniqueExercise) { ex in
            TechniqueSheet(exercise: ex)
        }
        // v1.7: leaving is never silent data loss anymore. "Finish now" is
        // the honest middle path the backlog asked for — the engine already
        // knows how to skip, so running out of time on exercise 4 of 6 ends
        // in a recorded, rated workout instead of a discarded one.
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
        // Feedback and the milestone screen own the full screen: no exit
        // button, no progress segments — the workout is already over.
        if phase != .feedback, !isMilestone {
            VStack(spacing: 10) {
                HStack {
                    // ink2, not ink3: this is the only way out of the workout,
                    // and ink3 (~2.4:1) fails contrast for interactive text.
                    Button(String(localized: "Exit")) {
                        // Nothing done yet (warm-up, or the very first set
                        // untouched) — nothing to protect, leave quietly.
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
                            Text("\(exIndex + 1) / \(session.exercises.count)")
                        case .warmup:
                            Text("WARM-UP")
                        default:
                            Text("REST")
                        }
                    }
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    // ink2, not ink3: "2 / 6" is the only sense of position
                    // in the whole workout — information, not decoration.
                    .foregroundStyle(Theme.ink2)
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

            // A single move can be impossible today (no floor space, a sore
            // wrist) without the whole warm-up being worthless — skipping one
            // must not cost the other five.
            Button {
                if warmupIndex + 1 < Self.warmupMoves.count {
                    startWarmupMove(warmupIndex + 1)
                } else {
                    finishWarmup()
                }
            } label: {
                Text("Skip this move")
                    .dredfitFont(14, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)

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
            // Absorb backgrounded time: unlike rest/hold, each move has its
            // own end date, so a 4-minute absence used to advance a single
            // move and silently stretch a 3-minute warm-up to 7. Jump over
            // every move the elapsed time already covered.
            let overshoot = max(0, -end.timeIntervalSinceNow)
            let movesPassed = 1 + Int(overshoot) / Self.warmupMoveSeconds
            if warmupIndex + movesPassed < Self.warmupMoves.count {
                warmupIndex += movesPassed
                let remainder = Int(overshoot) % Self.warmupMoveSeconds
                warmupRemaining = Self.warmupMoveSeconds - remainder
                warmupEndDate = Date.now.addingTimeInterval(TimeInterval(warmupRemaining))
            } else {
                finishWarmup()
            }
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < warmupRemaining {
                playTick()
            }
            // Animated so contentTransition(.numericText) actually rolls the
            // digits — a bare mutation swaps them with no transaction.
            withAnimation(.linear(duration: 0.3)) { warmupRemaining = newRemaining }
        }
    }

    private func finishWarmup() {
        warmupEndDate = nil
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
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

            // The calibration hint (v1.5): from a zero level an exact number
            // sets the level outright instead of moving it by two. It lives
            // here, next to the button it points to — on the rating screen it
            // arrived after the last chance to act on it. Opacity, not `if`:
            // the reserved height keeps the layout still when the hint's job
            // is done mid-exercise.
            // 14pt ink2, not 12.5 ink3: this hint works exactly once, on the
            // first workout, and that one time it has to actually be read.
            if store.records.isEmpty {
                Text("Came out well above the plan? Tap “Went differently” and put in what you actually did — the system will land on your level right away.")
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .opacity(holding || adjusting
                             || actuals[exercise.pattern] != nil ? 0 : 1)
            }
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
                persistProgress()   // v1.7: an entered actual is worth keeping
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
            // Snapshotted too (Н-3): dying on the rating screen must come
            // back to the rating screen, not to a set already done.
            persistProgress()
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
            persistProgress()
        } else {
            exIndex += 1
            setIndex = 0
            phase = .work
            liveActivity.update(activityWorkState())
            persistProgress()
        }
    }

    private func startRest(_ seconds: Int) {
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
            // tick once per second in the 3-2-1 zone (no spam after backgrounding)
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < restRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { restRemaining = newRemaining }
        }
    }
}

// MARK: - Holds, signals and session persistence

/// The second half of the flow, in an extension of its own: the phase views
/// and the state machine above are one concern, the hold countdown, the
/// audible signals and the snapshot that lets a killed session come back are
/// another. Same file, so the private state stays private.
private extension WorkoutFlowView {

    // MARK: - Hold countdown (v1.1)

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
            playGo()
            finishHold(heldSeconds: holdTotal)
        } else {
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < holdRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { holdRemaining = newRemaining }
        }
    }

    /// Below this, a "Stop" is read as a mis-tap, not a 2-second plank.
    static let holdMistapSeconds = 3.0

    /// Early stop: the seconds actually held become the actual. "Stop" sits
    /// exactly where "Start hold" was, so a stop within the first seconds is
    /// treated as an accidental double-tap: the countdown is cancelled and
    /// the set stays available — otherwise one mis-tap would consume the set
    /// and record a 5-second actual (which on the first workout would also
    /// feed the zero-level calibration).
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

    /// One countdown finished. Per-side holds wait for the second side
    /// (started by button, giving time to switch); the recorded actual is
    /// the smaller of the two sides.
    func finishHold(heldSeconds: Int) {
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
    func recordHoldActual(heldSeconds: Int) {
        let rounded = min(max(Int((Double(heldSeconds) / 5).rounded()) * 5, 5), 90)
        if rounded == exercise.load {
            actuals.removeValue(forKey: exercise.pattern)
        } else {
            actuals[exercise.pattern] = rounded
        }
    }

    // MARK: - Audible countdown of the last rest seconds

    /// How many seconds before the end of rest to start "ticking".
    static let countdownSignalSeconds = 3

    /// A short tick on 3-2-1. The system sound respects silent mode,
    /// a light vibration duplicates the signal for silent mode.
    /// Both obey the "Sounds and haptics" setting (v1.1).
    func playTick() {
        guard store.settings.soundsEnabled else { return }
        AudioServicesPlaySystemSound(1103) // Tink
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The "set start" signal at zero — lower in tone and with a haptic accent.
    func playGo() {
        guard store.settings.soundsEnabled else { return }
        AudioServicesPlaySystemSound(1104) // Tock
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

    // MARK: - Surviving process death (v1.7)

    /// Writes the current position to the store. Called on every phase
    /// transition and whenever an actual changes — the workout can now be
    /// picked up from here if iOS evicts the process mid-session.
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
            atFeedback: phase == .feedback ? true : nil,
            interrupted: interruptedPattern))
    }

    /// Rebuilds the live state a snapshot captured. A rest whose countdown is
    /// still running resumes inside it; one that ran out while the app was
    /// gone lands on the set it was leading into (the same advance the timer
    /// would have made). Holds are never restored mid-count — the set simply
    /// starts over. Indices are clamped: the snapshot was validated against
    /// the engine, but a defensive bound costs nothing.
    func restore(from snap: WorkoutSnapshot) {
        exIndex = min(max(snap.exIndex, 0), session.exercises.count - 1)
        setIndex = min(max(snap.setIndex, 0), session.exercises[exIndex].sets - 1)
        actuals = snap.actuals
        skippedPatterns = snap.skipped
        workoutStart = snap.workoutStart
        interruptedPattern = snap.interrupted
        // The rating was already on screen — everything below the position
        // fields describes sets that are behind, not ahead (Н-3).
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

    /// The lock-screen state matching the current phase — what a fresh Live
    /// Activity should open with (a resumed workout can start mid-rest).
    func currentActivityState() -> RestActivityAttributes.ContentState {
        if case .rest = phase {
            return .init(phase: .rest, title: nextLabel,
                         detail: String(localized: "Next up"),
                         restEndDate: restEndDate)
        }
        return activityWorkState()
    }

    /// Anything worth a confirmation before it is thrown away?
    var hasProgress: Bool {
        if case .rest = phase { return true }
        return exIndex > 0 || setIndex > 0
            || !actuals.isEmpty || !skippedPatterns.isEmpty
    }

    /// "Finish now": every exercise not fully completed keeps its level via
    /// the engine's skip path, and the flow proceeds to the honest rating.
    func finishNow() {
        adjusting = false
        holdEndDate = nil
        holdSecondSide = false
        firstSideHeld = nil
        // During the between-exercise rest the current exercise IS complete —
        // only what comes after it is unfinished.
        var firstUnfinished = exIndex
        if case .rest = phase, isLastSet { firstUnfinished = exIndex + 1 }
        // The exercise cut with sets already behind it reads "not finished"
        // on the rating screen — "skipped" would call 24 push-ups of 36 a
        // no-show. The engine still freezes its level like any skip; the
        // label is the only difference (Н-4).
        if firstUnfinished == exIndex {
            let midway: Bool
            if case .rest = phase {
                midway = true   // a between-set rest means a set is behind
            } else {
                midway = setIndex > 0 || actuals[exercise.pattern] != nil
            }
            if midway { interruptedPattern = exercise.pattern }
        }
        if firstUnfinished < session.exercises.count {
            for ex in session.exercises[firstUnfinished...] {
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

    /// "Discard workout" (and the quiet exit with nothing done): nothing is
    /// recorded and nothing is left behind to offer resuming.
    func discardWorkout() {
        store.clearWorkoutSnapshot()
        dismiss()
    }
}
