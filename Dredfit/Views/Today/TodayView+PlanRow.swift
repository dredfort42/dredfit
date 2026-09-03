//
//  The plan row, in an extension rather than in TodayView's struct body because
//  the type is at the linter's size bound without it. The separate FILE is only
//  a consequence of that — an extension weighs nothing against the type's body
//  wherever it sits.
//
//  Three controls have stood beside this row and none of them is left.
//  `handleRow` — "fewer sets in every movement" and "fewer movements" — asked
//  the person to predict, before the workout, how much of it they had in them;
//  that answer moved to the work screen, where it is known. `exerciseHandles`
//  offered the variation one step below; it moved into the sheet this row
//  opens (R30), for the same reason and one more: after the v2 → v3 carry-over
//  every movement sat above the first variation, so the offer stood under all
//  six rows at once.
//

import SwiftUI
import DredfitCore

extension TodayView {

    /// `.plain` because a List row with several default-styled buttons in it is
    /// one button as far as the row is concerned: measured, a single tap on the
    /// empty strip beside the handle that used to sit here pulled it — the
    /// announced duration went 35 min to 33 and the control vanished under the
    /// finger. The handle is gone (R30), so the row is the only control on
    /// itself and the trap is closed by construction; the style stays because
    /// it is also what keeps a List row from tinting the card. It changes how
    /// nothing looks.
    ///
    /// `contentShape` is the other half of that fix and is still load-bearing:
    /// a `.plain` button answers only where it DRAWS, and this row draws a name
    /// on the left and a load on the right with a wide gap between. Without the
    /// shape a tap into the gap reaches nothing — which now costs the whole
    /// handle, not just a sheet, because the sheet is where the handle lives.
    func planRow(_ ex: SessionExercise, debuts: Set<Pattern>) -> some View {
        Button {
            techniqueFor = TechniqueTarget(ex)
        } label: {
            ExerciseRow(exercise: ex,
                        badge: debuts.contains(ex.pattern)
                            ? String(localized: "new variation") : nil,
                        notes: ExerciseRow.notes(ex, setCameBack: store.aSetJustCameBack(in: ex)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Per pattern, so a row is addressable without reading its rendered
        // load ("3 ×" is a format and a locale, not an identity) and without
        // `element(boundBy: 0)`, which also matches the settings overlay
        // sitting above the tab content.
        .accessibilityIdentifier("plan-row-\(ex.pattern.rawValue)")
    }
}
