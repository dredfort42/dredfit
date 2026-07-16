//
//  WorkoutFlowView.swift
//  Dredfit
//
//  The workout flow: exercise (big number, set dots) and rest (ring timer).
//  State machine: work > rest > … > feedback.
//

import Combine
import SwiftUI
import AudioToolbox
import UIKit
import DredfitCore

struct WorkoutFlowView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    private enum Phase: Equatable {
        case work
        case rest(seconds: Int)
        case feedback
    }

    @State private var exIndex = 0
    @State private var setIndex = 0          // 0-based
    @State private var phase: Phase = .work
    @State private var restRemaining = 0
    @State private var restEndDate: Date?
    @State private var techniqueShown = false
    @State private var actuals: [Pattern: Int] = [:]
    @State private var adjusting = false
    @State private var exitConfirmShown = false
    @State private var adjustValue = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var exercise: SessionExercise { session.exercises[exIndex] }
    private var isLastSet: Bool { setIndex == exercise.sets - 1 }
    private var isLastExercise: Bool { exIndex == session.exercises.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header

            switch phase {
            case .work:
                workView
            case .rest:
                restView
            case .feedback:
                FeedbackView(session: session, actuals: actuals) { result, overrides in
                    store.completeWorkout(session: session, result: result, overrides: overrides)
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 24)
        .background(Color.white)
        .onReceive(timer) { _ in
            guard case .rest = phase, let end = restEndDate else { return }
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
        .sheet(isPresented: $techniqueShown) {
            TechniqueSheet(exercise: exercise)
        }
        .confirmationDialog(String(localized: "End the workout?"),
                            isPresented: $exitConfirmShown,
                            titleVisibility: .visible) {
            Button(String(localized: "End workout"), role: .destructive) { dismiss() }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Progress of this session won't be saved.")
        }
    }

    // MARK: - Header with progress segments

    @ViewBuilder
    private var header: some View {
        if phase != .feedback {
            VStack(spacing: 10) {
                ZStack {
                    HStack {
                        Button(String(localized: "Exit")) { exitConfirmShown = true }
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink3)
                        Spacer()
                    }
                    Group {
                        if phase == .work {
                            Text("\(exIndex + 1) / \(session.exercises.count)")
                        } else {
                            Text("REST")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.ink3)
                }
                HStack(spacing: 5) {
                    ForEach(0..<session.exercises.count, id: \.self) { i in
                        Capsule()
                            .fill(i <= exIndex ? Theme.ink : Theme.hairline)
                            .frame(height: 4)
                    }
                }
                .frame(width: 200)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Work

    private var workView: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(exercise.name)
                .font(.system(size: 23, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                techniqueShown = true
            } label: {
                Label(String(localized: "technique"), systemImage: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 10)

            VStack(spacing: 4) {
                Text("\(actuals[exercise.pattern] ?? exercise.load)")
                    .font(.system(size: 112, weight: .heavy))
                    .tracking(-4)
                    .monospacedDigit()
                Text(loadCaption)
                    .font(.system(size: 17, weight: .medium))
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
                if let actual = actuals[exercise.pattern], actual != exercise.load {
                    Text("actual \(actual)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("set \(setIndex + 1) of \(exercise.sets)")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.top, 10)

            Spacer()

            if adjusting {
                adjustPanel
                    .padding(.bottom, 8)
            }

            PrimaryButton(title: String(localized: "Done")) { completeSet() }

            HStack(spacing: 26) {
                Button(String(localized: "Went differently")) { startAdjusting() }
                Button(String(localized: "Skip exercise")) { skipExercise() }
            }
            .font(.system(size: 14.5))
            .foregroundStyle(Theme.ink2)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Inline actual adjuster (UPDATE-5)

    private var adjustPanel: some View {
        HStack(spacing: 18) {
            stepButton("minus") { bumpAdjust(-1) }
            Text(exercise.unit == .hold ? "\(adjustValue) s" : "\(adjustValue)")
                .font(.system(size: 26, weight: .heavy))
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
                    .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().stroke(Theme.hairline, lineWidth: 1.5))
        }
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
                        .font(.system(size: 72, weight: .heavy))
                        .tracking(-2)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("sec")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .frame(width: 240, height: 240)

            VStack(spacing: 6) {
                Kicker(text: String(localized: "Next up"))
                Text(nextLabel)
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.top, 44)

            Spacer()

            Button {
                restEndDate = nil
                restRemaining = 0
                advanceAfterRest()
            } label: {
                Text("Skip rest")
                    .font(.system(size: 17, weight: .medium))
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

    // MARK: - State machine transitions

    private func completeSet() {
        adjusting = false
        if isLastSet && isLastExercise {
            phase = .feedback
        } else if isLastSet {
            startRest(exercise.restExerciseSec)
        } else {
            startRest(exercise.restSetSec)
        }
    }

    private func skipExercise() {
        adjusting = false
        if isLastExercise {
            phase = .feedback
        } else {
            exIndex += 1
            setIndex = 0
            phase = .work
        }
    }

    private func startRest(_ seconds: Int) {
        restRemaining = seconds
        restEndDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        phase = .rest(seconds: seconds)
    }

    // MARK: - Audible countdown of the last rest seconds

    /// How many seconds before the end of rest to start "ticking".
    private static let countdownSignalSeconds = 3

    /// A short tick on 3-2-1. The system sound respects silent mode,
    /// a light vibration duplicates the signal for silent mode.
    private func playTick() {
        AudioServicesPlaySystemSound(1103) // Tink
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The "set start" signal at zero — lower in tone and with a haptic accent.
    private func playGo() {
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
    }
}
