//
//  One movement of a workout as the history sheet reads it back.
//

import SwiftUI
import DredfitCore

struct HistoryRow: View {
    let ex: SessionExercise
    /// The record being read: the walk can leave it on a neighbour of the one
    /// the sheet was opened with.
    let shown: WorkoutRecord
    /// Handed down by the sheet: the answer is about the record, not the row.
    let easedByHand: [Pattern]

    /// The movement, what it cost, and — under both, at full width — what its
    /// last set was when that set was not a working one.
    ///
    /// The probe line goes UNDER rather than into the column on the right: the
    /// sentence is longer than that column, and the load has to keep its place.
    /// The same shape the plan gives its own probe line.
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(currentName(ex))
                    .dredfitFont(16, weight: .medium)
                    .foregroundStyle(Theme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    // NAMED. Three rows of numbers can stand under one
                    // movement — the plan, what was done, what it became —
                    // and each carries a word. With the fact in accent
                    // directly under a bare plan and "After:" directly below,
                    // the reader has to guess which of the three is which,
                    // and takes the accent for the future.
                    Text("plan \(ex.display)")
                        .dredfitFont(15)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    // Only a record written by a build that had the pain
                    // report can carry this. History says what happened, and
                    // what happened is that the person reported it.
                    if shown.discomfort?.contains(ex.pattern) == true {
                        Text("hurt")
                            .dredfitFont(12.5)
                            .foregroundStyle(Theme.accentText)
                    } else if shown.skipped?.contains(ex.pattern) == true {
                        Text(HistorySheet.skipWord(ex, in: shown))
                            .dredfitFont(12.5)
                            .foregroundStyle(Theme.ink2)
                            // Named, like the lines under the row: without it
                            // a test could only count anonymous labels, and
                            // counting them measures what fits on screen
                            // rather than what happened.
                            .accessibilityIdentifier(
                                "history-skipword-\(ex.pattern.rawValue)")
                    }
                }
            }
            factRow
            if let probe = HistorySheet.probeLine(ex, in: shown) {
                Text(probe)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-probe-\(ex.pattern.rawValue)")
            }
            if let dropped = HistorySheet.setsSkippedLine(ex, in: shown) {
                Text(dropped)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-setsskipped-\(ex.pattern.rawValue)")
            }
            // The one cause of a drop that lands on a session's point without
            // being that session's doing and without a break to explain it:
            // the athlete moved the movement down themselves, and two weeks
            // later the chart shows a step they no longer remember taking.
            if easedByHand.contains(ex.pattern) {
                Text(String(localized: "history.easedByHand",
                            defaultValue: "You chose an easier variation before this workout"))
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-easedbyhand-\(ex.pattern.rawValue)")
            }
            if let after = HistorySheet.afterLine(ex, in: shown) {
                Text(after)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-after-\(ex.pattern.rawValue)")
            }
        }
    }

    /// The fact, under the row at full width and in the PLAN'S OWN SPELLING
    /// — "30-30-25 sec per side", not "30 · 30 · 25" — so the two lines can
    /// be read against each other digit for digit. Accented, because it is
    /// the one line that says the session went differently from the plan;
    /// the word in front of it is what stops the accent being read as "next
    /// time".
    @ViewBuilder
    private var factRow: some View {
        if shown.skipped?.contains(ex.pattern) != true,
           shown.discomfort?.contains(ex.pattern) != true,
           let fact = HistorySheet.factLine(ex, in: shown) {
            Text(fact)
                .dredfitFont(12.5, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(Theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("history-actual-\(ex.pattern.rawValue)")
        }
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
}
