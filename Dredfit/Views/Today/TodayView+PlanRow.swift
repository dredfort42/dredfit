//
//  The plan row and the look of its one handle are one subject, and they live
//  in an extension rather than in TodayView's struct body because the type is
//  at the linter's size bound without them. The separate FILE is only a
//  consequence of that — an extension weighs nothing against the type's body
//  wherever it sits.
//
//  What used to live beside this was `handleRow` — the two session handles,
//  "fewer sets in every movement" and "fewer movements". Both asked the person
//  to predict, before the workout, how much of it they had in them; that
//  answer moved to the work screen, where it is known.
//

import SwiftUI
import DredfitCore

extension TodayView {

    /// `.plain`, and the handle below `.borderless`, because a List row with
    /// several default-styled buttons in it is one button as far as the row is
    /// concerned: measured, a single tap on the empty strip beside a handle
    /// pulled it — the announced duration went 35 min to 33 and the control
    /// vanished under the finger. Neither style changes how anything looks.
    ///
    /// `contentShape` is the other half of that fix, not decoration: a
    /// `.plain` button answers only where it DRAWS, and this row draws a name
    /// on the left and a load on the right with a wide gap between. Without
    /// the shape a tap into the gap reached nothing — a different bug, no
    /// better. The card is the target; the handle under it is its own.
    func planRow(_ ex: SessionExercise, debuts: Set<Pattern>) -> some View {
        Button {
            techniqueFor = ex
        } label: {
            ExerciseRow(exercise: ex,
                        badge: debuts.contains(ex.pattern)
                            ? String(localized: "new variation") : nil,
                        note: ExerciseRow.note(store.setsNote(for: ex)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
