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

/// What the number above is made of at both ends. Ten of those minutes are the
/// warm-up and the cool-down, and they are 10–41 % of the announced length —
/// the share is largest on exactly the shortest sessions, where the person
/// deciding "will this fit" is reading the highest number they will ever be
/// asked to fit (UX review 05.09.2026).
///
/// It states the fact and stops there: whether to skip a block is a question
/// the flow asks with the block in front of the person, and answering it here,
/// before they have seen one, would be an invitation rather than a disclosure.
///
/// Beside `PlanLength` rather than inside it: the range carries an
/// accessibility label of its own ("about 24 to 32 minutes · 6 exercises"), and
/// a second line under the same identifier would rewrite what a query reads.
struct PlanEndsNote: View {
    let warmupMin: Int
    let cooldownMin: Int

    var body: some View {
        Text("Includes about \(warmupMin + cooldownMin) min of warm-up and cool-down.")
            .dredfitFont(13.5)
            // ink2, not ink3: ink3 is 2.35:1 on the light ground and fails the
            // 4.5:1 small-text floor (owner, 05.09.2026 — the low contrast was
            // an oversight, not a choice).
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
