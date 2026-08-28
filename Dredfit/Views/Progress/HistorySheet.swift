//
//  A completed workout viewed from the calendar.
//

import SwiftUI
import DredfitCore

struct HistorySheet: View {
    let record: WorkoutRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: record.date.screenDateText)
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
                            // Only a record written before the wave can carry
                            // this. History says what happened, and what
                            // happened is that the person reported it.
                            if record.discomfort?.contains(ex.pattern) == true {
                                Text("hurt")
                                    .dredfitFont(12.5)
                                    .foregroundStyle(Theme.accentText)
                            } else if record.skipped?.contains(ex.pattern) == true {
                                Text("skipped")
                                    .dredfitFont(12.5)
                                    .foregroundStyle(Theme.ink2)
                            } else if let fact = setFacts(ex) {
                                SetFactsLabel(values: fact.values,
                                              reported: fact.reported, size: 12.5)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .listRowSeparatorTint(Theme.hairline)
                .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                // Not every record carries an exercise snapshot.
                Spacer()
                Text("No details saved for this workout.")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            // A record written before v3 carries a number on a scale that no
            // longer exists, so the line is simply absent for it rather than
            // stated in the wrong unit.
            if let steps = record.totalProgressAfter {
                HStack {
                    Text("Total steps after: \(steps)")
                        .dredfitFont(13.5)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            // Its own name — see TechniqueSheet: four sheets close on the same
            // two words.
            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .accessibilityIdentifier("history-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }

    /// The facts worth printing for one exercise, or nil when it simply ran
    /// to plan. The sets lead: a near miss that stood down rather than claim
    /// the plan hands the engine no number at all, and the record of what was
    /// actually done must survive that. A record written before a fact
    /// belonged to its own set keeps one number for the whole exercise —
    /// that number was in force for every set of it, which is what a single
    /// value says.
    private func setFacts(_ ex: SessionExercise) -> (values: [Int], reported: Int)? {
        let reported = record.actuals?[ex.pattern]
        let values: [Int]
        if let facts = record.setActuals, facts[ex.pattern] != nil {
            values = SetFacts.allSets(facts, ex)
        } else if let reported {
            values = [reported]
        } else {
            return nil
        }
        guard let first = values.first,
              SetFacts.differs(values, from: ex) else { return nil }
        return (values, reported ?? first)
    }

    /// The snapshot froze `name` in the language active when the session was
    /// generated; resolve it again so history follows a language switch.
    ///
    /// The stored name stays the fallback for a variation the library no
    /// longer has — and, above all, for a record written before v3, which
    /// decodes with `variation == 0`: the old tier numbers point at different
    /// movements now, so those lines keep the names they were written with.
    private func currentName(_ ex: SessionExercise) -> String {
        guard (1...Library.count(ex.pattern)).contains(ex.variation) else { return ex.name }
        return Library.name(ex.pattern, ex.variation)
    }

    private var resultCaption: String {
        switch record.result {
        case .less: return String(localized: "Rating: tough — the next one will be easier")
        case .plan: return String(localized: "Rating: on plan — the next adds a step to the movements that have room for one")
        case .more: return String(localized: "Rating: easy — progressing as fast as each movement allows")
        }
    }
}
