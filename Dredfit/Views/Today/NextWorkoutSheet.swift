//
//  Deliberately WITHOUT a Start button — one workout per day.
//

import SwiftUI
import DredfitCore

struct NextWorkoutSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var techniqueFor: TechniqueTarget?

    var body: some View {
        let session = store.nextSession
        let length = store.sessionLengthRange()
        let debuts = store.debutPatterns

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: String(localized: "Next · \(store.nextTrainingDateLabel)"))
                Text("Workout \(session.sessionNumber)")
                    .dredfitFont(28, weight: .heavy)
                    .tracking(-0.5)
                    // The palette, not the inherited `.primary` (#FFFFFF
                    // against ink's #F2F2F4 in the dark scheme) — the same
                    // heading as Today's, and it must not read differently
                    // from the screen it is opened over (UX review
                    // 05.09.2026, finding 15).
                    .foregroundStyle(Theme.ink)
                PlanLength(floor: length.floor, full: length.full,
                           count: session.exercises.count)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                PlanEndsNote(warmupMin: session.warmupMin,
                             cooldownMin: session.cooldownMin)
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)

            List(session.exercises) { ex in
                let notes = ExerciseRow.notes(
                    ex,
                    setCameBack: store.aSetJustCameBack(in: ex),
                    easedByHand: store.easedByHandAhead.contains(ex.pattern),
                    variationDropped: store.aVariationJustDropped(in: ex))
                Button {
                    techniqueFor = TechniqueTarget(ex)
                } label: {
                    // The same card as Today's, so it carries the same one
                    // line about why the set count is what it is — and the
                    // same pill. The badge was simply not passed here, and a
                    // preview that hides which movement is NEW is missing one
                    // of the two facts it is opened for; `debutPatterns` is
                    // computed over this very session (UX review 05.09.2026).
                    ExerciseRow(exercise: ex,
                                badge: debuts.contains(ex.pattern)
                                    ? String(localized: "new variation") : nil,
                                notes: notes)
                }
                .listRowSeparatorTint(Theme.hairline)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // Its own name — see TechniqueSheet: four sheets close on the same
            // two words.
            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .accessibilityIdentifier("next-workout-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        // Without `planned:` — this preview looks at a session rather than
        // deciding about one, so the step below stays off it (owner, R30). One
        // boolean if that is ever reconsidered.
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(target: ex)
        }
    }
}
