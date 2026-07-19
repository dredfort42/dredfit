//
//  HistorySheet.swift
//  Dredfit
//
//  UPDATE-3 (new): a completed workout viewed from the calendar.
//  Shows the plan that was performed; exercises adjusted via
//  "Adjust by exercise" additionally show the actual value.
//

import SwiftUI
import DredfitCore

struct HistorySheet: View {
    let record: WorkoutRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: record.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    .capitalized)
                Text("Workout \(record.sessionNumber)")
                    .dredfitFont(28, weight: .heavy)
                    .tracking(-0.5)
                Text(resultCaption)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)

            if let exercises = record.exercises, !exercises.isEmpty {
                List(exercises) { ex in
                    HStack(alignment: .firstTextBaseline) {
                        Text(currentName(ex))
                            .dredfitFont(16, weight: .medium)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ex.display)
                                .dredfitFont(15)
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink2)
                            if record.skipped?.contains(ex.pattern) == true {
                                Text("skipped")
                                    .dredfitFont(12.5)
                                    .foregroundStyle(Theme.ink3)
                            } else if let actual = record.actuals?[ex.pattern], actual != ex.load {
                                Text("actual \(actual)")
                                    .dredfitFont(12.5)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .listRowSeparatorTint(Theme.hairline)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                // records created before UPDATE-3 have no snapshot
                Spacer()
                Text("No details saved for this workout.")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            HStack {
                Text("Total level after: \(record.totalLevelAfter)")
                    .dredfitFont(13.5)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    /// The persisted snapshot froze `name` in the language active when the
    /// session was generated; resolve it again so history follows the UI
    /// language after a switch. The stored name stays the fallback for any
    /// tier the current library no longer has.
    private func currentName(_ ex: SessionExercise) -> String {
        let variations = ExerciseLibrary.entry(for: ex.pattern).variations
        guard (1...variations.count).contains(ex.tier) else { return ex.name }
        return variations[ex.tier - 1].name
    }

    private var resultCaption: String {
        switch record.result {
        case .less: return String(localized: "Rating: tough — the next one will be easier")
        case .plan: return String(localized: "Rating: on plan — next: +1 rep")
        case .more: return String(localized: "Rating: easy — next: +2 reps")
        }
    }
}
