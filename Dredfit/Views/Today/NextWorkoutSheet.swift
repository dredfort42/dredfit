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

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: String(localized: "Next · \(store.nextTrainingDateLabel)"))
                Text("Workout \(session.sessionNumber)")
                    .dredfitFont(28, weight: .heavy)
                    .tracking(-0.5)
                PlanLength(floor: length.floor, full: length.full,
                           count: session.exercises.count)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)

            List(session.exercises) { ex in
                Button {
                    techniqueFor = TechniqueTarget(ex)
                } label: {
                    // The same card as Today's, so it carries the same one
                    // line about why the set count is what it is.
                    ExerciseRow(exercise: ex,
                                note: ExerciseRow.note(setCameBack: store.aSetJustCameBack(in: ex)))
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
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(target: ex)
        }
    }
}
