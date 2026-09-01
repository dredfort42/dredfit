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
                    row(ex)
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

    /// The movement, what it cost, and — under both, at full width — what its
    /// last set was when that set was not a working one.
    ///
    /// The probe line goes UNDER rather than into the column on the right: the
    /// sentence is longer than that column, and the load has to keep its place.
    /// The same shape the plan gives its own probe line.
    private func row(_ ex: SessionExercise) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
                    // Only a record written before the wave can carry this.
                    // History says what happened, and what happened is that
                    // the person reported it.
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
            if let probe = Self.probeLine(ex, in: record) {
                Text(probe)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-probe-\(ex.pattern.rawValue)")
            }
        }
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

    /// What the last set of this exercise was, when it was not a working set.
    ///
    /// The plan carried the probe all along — `SessionExercise.probe` is in the
    /// record's own CodingKeys — and this screen printed nothing about it, so a
    /// session of "2 × 15 plus a probe" read in history exactly like a session
    /// of two sets. What it could not say until now is the OUTCOME, and half of
    /// that is still an inference rather than a fact: the number comes from
    /// `record.probes`, which only exists from this wave on.
    ///
    /// The verdict does not re-implement §40.4. It is read off what actually
    /// happened — the position the session ended on, against the variation the
    /// probe offered — because a second copy of the pass rule in the app is a
    /// copy that can disagree with the engine.
    ///
    /// A missing number is deliberately NOT read as "skipped". A record written
    /// before this wave has no numbers either, and the two are indistinguishable
    /// from the file; "not this time" is true of both, and it is the sentence
    /// the work screen already gives an unresolved probe.
    /// Static, and taking the record rather than reading `self`, for the one
    /// reason the two rules named at the bottom of `ProbeChannelTests` are NOT
    /// covered: a policy written as a `private` member of a SwiftUI view is a
    /// policy no unit test can reach. This one is a pure function of a record
    /// and an exercise, so it is written as one.
    static func probeLine(_ ex: SessionExercise, in record: WorkoutRecord) -> String? {
        guard let probe = ex.probe,
              let after = record.positionsAfter?[ex.pattern] else { return nil }
        let name = (1...Library.count(ex.pattern)).contains(probe.variation)
            ? Library.name(ex.pattern, probe.variation)
            : probe.name
        let landed = after.variation >= probe.variation
        guard let shown = record.probes?[ex.pattern] else {
            return landed
                ? String(localized: "history.probePassedPlain",
                         defaultValue: "Probe: \(name) — passed")
                : String(localized: "history.probeUnresolved",
                         defaultValue: "Probe: \(name) — not this time")
        }
        // The probe's own unit, which is not always the exercise's (§40.1).
        let did = SessionProbe(variation: probe.variation, name: name, unit: probe.unit,
                               load: shown, perSide: probe.perSide).display
        return landed
            ? String(localized: "history.probePassed",
                     defaultValue: "Probe: \(name) · \(did) — passed")
            : String(localized: "history.probeShort",
                     defaultValue: "Probe: \(name) · \(did) — not this time")
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
