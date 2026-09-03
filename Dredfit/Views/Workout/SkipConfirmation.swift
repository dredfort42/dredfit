//
//  The question a skip asks before it happens.
//
//  The two escapes are 44 pt targets sitting 18 pt under the button that logs
//  the set, and until this file they fired on contact. A workout has no undo:
//  one stray thumb took a set, or a whole movement together with every number
//  already entered for it, and nothing anywhere could put it back. The guard
//  therefore has to stand in FRONT of the state change rather than behind it.
//

import SwiftUI

/// One of the four skips, holding the action it will run if confirmed.
struct SkipConfirmation: Identifiable {
    enum Kind: String {
        case probeSet, workingSet, restOfSets, exercise
    }

    let kind: Kind
    /// Held here rather than resolved by the alert, so a question raised about
    /// one skip cannot be answered by another: the tap that opened this is the
    /// tap that runs.
    let perform: () -> Void

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .probeSet, .workingSet: return String(localized: "Skip this set?")
        case .restOfSets:            return String(localized: "Skip the remaining sets?")
        case .exercise:              return String(localized: "Skip this exercise?")
        }
    }

    /// What is actually lost. The two set-level sentences are THE SAME KEYS the
    /// controls' accessibility hints already use — one wording per rule, so the
    /// spoken promise and the written one cannot drift apart.
    var message: String {
        switch kind {
        case .probeSet:
            return String(localized: """
                The probe just comes back next time. \
                The working sets lose nothing.
                """)
        case .workingSet:
            return String(localized: """
                The plan keeps this set off next time. \
                Nothing else about the movement changes.
                """)
        case .restOfSets:
            return String(localized: """
                The movement still counts as trained — the plan keeps those \
                sets off next time.
                """)
        case .exercise:
            return String(localized: """
                The movement counts as not trained, and any number you \
                entered for it is not kept. Its plan stays exactly as it is.
                """)
        }
    }

    /// ONE SHORT VERB FOR ALL FOUR, and the length is the point (owner,
    /// 31.08.2026). `UIAlertController` lays two actions side by side only
    /// while both titles fit on one line and stacks them otherwise, so
    /// per-kind labels made the layout itself differ between two controls that
    /// sit at equal weight in the same row: in Russian "Пропустить этот
    /// подход" fit beside the cancel and "Пропустить это упражнение", three
    /// characters longer, did not. Nobody chose that; the width did. Identical
    /// labels cannot diverge, in any language or at any text size.
    ///
    /// It does not answer the question with "OK" either. The rule the exit
    /// alert set is that a button must not answer "cancel WHAT?" — and there
    /// four buttons made the referent genuinely ambiguous. Here the question
    /// stands directly above two, and it names the thing being skipped.
    ///
    /// The key is the onboarding cards' own "Skip": a different screen, never
    /// up at the same time, and no control in the workout reads exactly this.
    var confirmTitle: String { String(localized: "Skip") }

    // NO `.destructive` ROLE ON ANY OF THE FOUR, and the exercise-level one is
    // where that was decided (owner, 31.08.2026). It carried red for a while
    // because `leaveExercise` really does discard the facts entered for the
    // pattern — but red says "danger", and this app's position on a skip is
    // the opposite: a skipped movement stays exactly where it was, no penalty
    // and no rollback, which is what the sentence above the button says in so
    // many words. A button shouting at a message that reassures is one screen
    // arguing with itself.
    //
    // What is destroyed is the numbers, not the movement, and the message
    // names them. The warning belongs in the sentence; the colour only
    // duplicated it, and duplicated it wrong. The two escapes also stand at
    // equal weight in the row that raises them — diverging here is the
    // arbitrariness that gave this away.
}

extension View {
    /// One alert for all four, driven by the pending question.
    ///
    /// An ALERT and not a `confirmationDialog`, for the reason written out at
    /// the workout's exit alert: iOS 26 draws the latter as an anchored
    /// popover, and a popover suppresses its own cancel because tapping
    /// outside IS the cancel. A question about losing work must be answered by
    /// a button — and an alert also swallows the stray tap that this whole
    /// file exists to catch, instead of treating it as an answer.
    func skipConfirmation(_ pending: Binding<SkipConfirmation?>) -> some View {
        let shown = Binding(get: { pending.wrappedValue != nil },
                            set: { if !$0 { pending.wrappedValue = nil } })
        return alert(pending.wrappedValue?.title ?? "",
                     isPresented: shown,
                     presenting: pending.wrappedValue) { skip in
            Button(String(localized: "Keep going"), role: .cancel) { }
            Button(skip.confirmTitle) { skip.perform() }
        } message: { skip in
            Text(verbatim: skip.message)
        }
    }
}
