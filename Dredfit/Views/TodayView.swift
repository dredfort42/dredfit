//
//  TodayView.swift
//  Dredfit
//
//  Two states: the plan for today + Start, or the "completed" state with
//  a preview of the next workout under its honest date.
//

import SwiftUI
import DredfitCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var workoutPresented = false
    @State private var techniqueFor: SessionExercise?
    @State private var nextPreviewShown = false

    var body: some View {
        Group {
            if store.doneToday {
                doneView
            } else {
                planView
            }
        }
        .padding(.horizontal, 24)
        .fullScreenCover(isPresented: $workoutPresented) {
            WorkoutFlowView(session: store.nextSession)
        }
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(exercise: ex)
        }
        .sheet(isPresented: $nextPreviewShown) {
            NextWorkoutSheet()
        }
    }

    // MARK: - Plan state

    private var planView: some View {
        let session = store.nextSession
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    .capitalized)
                Text("Workout \(session.sessionNumber)")
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(-0.5)
                Text("≈ \(Int(session.estimatedTotalMin.rounded())) min · \(session.exercises.count) exercises")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 18)

            List(session.exercises) { ex in
                Button {
                    techniqueFor = ex
                } label: {
                    ExerciseRow(exercise: ex)
                }
                .listRowSeparatorTint(Theme.hairline)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            PrimaryButton(title: String(localized: "Start")) { workoutPresented = true }
                .padding(.top, 10)
                .padding(.bottom, 14)   // breathing room above the tab bar
        }
    }

    // MARK: - Completed state

    private var doneView: some View {
        VStack(spacing: 0) {
            HStack {
                Kicker(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    .capitalized)
                Spacer()
            }
            .padding(.top, 18)

            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.cardBG)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            Text("Workout \(store.lastRecord?.sessionNumber ?? 0) completed")
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.4)
                .padding(.top, 24)

            Text(resultCaption)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 6)

            Spacer()

            // The next workout — a preview with an honest date, not "for today"
            Button {
                nextPreviewShown = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker(text: String(localized: "Next"))
                        Text("Workout \(store.nextSession.sessionNumber) · \(store.nextTrainingDateLabel)")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.bottom, 24)
        }
    }

    private var resultCaption: String {
        switch store.lastRecord?.result {
        case .less: return String(localized: "Rating: tough — the next one will be easier")
        case .plan: return String(localized: "Rating: on plan — next: +1 rep")
        case .more: return String(localized: "Rating: easy — next: +2 reps")
        case nil:   return ""
        }
    }
}

// MARK: - Exercise row (shared with NextWorkoutSheet)

struct ExerciseRow: View {
    let exercise: SessionExercise

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(exercise.name)
                .font(.system(size: 16.5, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(shortLoad)
                .font(.system(size: 15.5))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .padding(.vertical, 4)
    }

    private var shortLoad: String {
        let side = exercise.perSide ? String(localized: " /side") : ""
        switch exercise.unit {
        case .reps: return String(localized: "\(exercise.sets) × \(exercise.load)\(side)")
        case .hold: return String(localized: "\(exercise.sets) × \(exercise.load) s\(side)")
        }
    }
}
