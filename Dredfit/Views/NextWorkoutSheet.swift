//
//  NextWorkoutSheet.swift
//  Dredfit
//
//  Preview of the next workout, shown with its honest date
//  ("tomorrow", "on Monday") and deliberately WITHOUT a Start button —
//  one workout per day.
//

import SwiftUI
import DredfitCore

struct NextWorkoutSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var techniqueFor: SessionExercise?

    var body: some View {
        let session = store.nextSession

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: String(localized: "Next · \(store.nextTrainingDateLabel)"))
                Text("Workout \(session.sessionNumber)")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-0.5)
                Text("≈ \(Int(session.estimatedTotalMin.rounded())) min · \(session.exercises.count) exercises")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)

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

            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(exercise: ex)
        }
    }
}
