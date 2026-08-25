//
//  The one line that says how long a session takes: the full plan, and the
//  shortest it can be made from inside it. Shared by Today and the
//  next-workout preview because the same plan must not read two ways — the
//  preview showed the full number alone, which overstates what the person is
//  agreeing to, and the range is the whole point: "will this fit today" gets
//  an answer without asking anyone to decide anything first.
//
//  The identifier stays with the caller. Both screens can be in the hierarchy
//  at once — the preview is a sheet over Today — and one identifier on two
//  live elements is ambiguous to a UI test.
//

import SwiftUI

struct PlanLength: View {
    let floor: Int
    let full: Int
    let count: Int

    var body: some View {
        // One number only when the plan is already on the floor and the two
        // ends have met.
        if floor < full {
            Text("≈ \(floor)–\(full) min · \(count) exercises")
                .accessibilityLabel(
                    Text("about \(floor) to \(full) minutes · \(count) exercises"))
        } else {
            Text("≈ \(full) min · \(count) exercises")
        }
    }
}
