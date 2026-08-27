//
//  Technique sheet: name, variation tag, 3 steps, 2 common mistakes.
//
//  It is addressed by (pattern, variation) rather than by a planned exercise,
//  because §40.4 gave it a second caller: the PROBE offers one set of the NEXT
//  variation, and the person has to be able to read how that movement is done
//  before doing it. An exercise-shaped sheet could not show a movement that is
//  not in the plan.
//

import SwiftUI
import DredfitCore

/// What a technique sheet is about. Identifiable so it can drive `.sheet(item:)`.
struct TechniqueTarget: Identifiable, Equatable {
    let pattern: Pattern
    let variation: Int
    let unit: LoadUnit

    var id: String { "\(pattern.rawValue)-\(variation)" }

    init(pattern: Pattern, variation: Int, unit: LoadUnit) {
        self.pattern = pattern
        self.variation = variation
        self.unit = unit
    }

    init(_ exercise: SessionExercise) {
        self.init(pattern: exercise.pattern, variation: exercise.variation, unit: exercise.unit)
    }

    /// The movement a probe offers — a different variation of the same
    /// pattern, and possibly in a different unit (§40.1, `pull_bar` 2→3).
    init(probe: SessionProbe, of pattern: Pattern) {
        self.init(pattern: pattern, variation: probe.variation, unit: probe.unit)
    }
}

struct TechniqueSheet: View {
    let target: TechniqueTarget
    @Environment(\.dismiss) private var dismiss

    private var variation: ExerciseVariation {
        Library.at(target.pattern, target.variation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(variation.name)
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 30)

                    Text(variationTag)
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .padding(.top, 10)

                    Kicker(text: String(localized: "Technique"))
                        .padding(.top, 28)
                    ForEach(Array(variation.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .dredfitFont(13, weight: .semibold)
                                .foregroundStyle(Theme.bg)
                                .frame(width: 26, height: 26)
                                .background(Theme.ink, in: Circle())
                            Text(step)
                                .dredfitFont(16.5)
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 13)
                    }

                    Kicker(text: String(localized: "Common mistakes"))
                        .padding(.top, 18)
                    ForEach(Array(variation.mistakes.enumerated()), id: \.offset) { _, mistake in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "xmark")
                                .dredfitFont(11, weight: .bold)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26, height: 26)
                                .background(Theme.accentSoft, in: Circle())
                                .accessibilityHidden(true)   // a bullet, not content
                            Text(mistake)
                                .dredfitFont(16.5)
                                .lineSpacing(4)
                                .foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 13)
                    }

                    Kicker(text: String(localized: "life.kicker", defaultValue: "In life"))
                        .padding(.top, 18)
                    Text(LifeBenefit.text(for: target.pattern, variation: target.variation))
                        .dredfitFont(16.5)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink2)
                        .padding(.vertical, 11)
                        .accessibilityIdentifier("technique-life")
                }
                .padding(.horizontal, 24)
            }

            // Four sheets in this app close on a button reading "Got it", and
            // a workout can have two of them stacked. Each names its own, the
            // way `how-it-works-done` and `milestone-done` already do.
            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .accessibilityIdentifier("technique-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }

    /// "variation 3 of 7 · pull · 4–15 reps". The total comes from the library
    /// — the ladders are four to seven rungs long now (§40.1) — and the range
    /// is the grid the whole library shares (§40.2), not a per-tier one.
    private var variationTag: String {
        let range = target.unit == .reps
            ? String(localized: "4–15 reps")
            : String(localized: "15–45 sec")
        let total = Library.count(target.pattern)
        let movement = target.pattern.displayName.lowercased()
        return String(localized: "variation \(target.variation) of \(total) · \(movement) · \(range)")
    }
}
