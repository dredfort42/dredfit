//
//  TechniqueSheet.swift
//  Dredfit
//
//  Technique sheet: name, tier tag, 3 steps, 2 common mistakes.
//

import SwiftUI
import DredfitCore

struct TechniqueSheet: View {
    let exercise: SessionExercise
    @Environment(\.dismiss) private var dismiss

    private var variation: ExerciseVariation {
        ExerciseLibrary.entry(for: exercise.pattern).variations[exercise.tier - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(variation.name)
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.5)
                        .padding(.top, 30)

                    Text(tierTag)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .padding(.top, 10)

                    Kicker(text: String(localized: "Technique")).padding(.top, 28)
                    ForEach(Array(variation.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Theme.ink, in: Circle())
                            Text(step)
                                .font(.system(size: 16.5))
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 13)
                    }

                    Kicker(text: String(localized: "Common mistakes")).padding(.top, 18)
                    ForEach(variation.mistakes, id: \.self) { mistake in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26, height: 26)
                                .background(Theme.accentSoft, in: Circle())
                            Text(mistake)
                                .font(.system(size: 16.5))
                                .lineSpacing(4)
                                .foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 11)
                    }
                }
                .padding(.horizontal, 24)
            }

            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var tierTag: String {
        let range = exercise.unit == .reps
            ? String(localized: "8–15 reps")
            : String(localized: "20–55 sec")
        return String(localized: "tier \(exercise.tier) · \(exercise.pattern.displayName.lowercased()) · \(range)")
    }
}
