//
//  The question a skip asks before it happens.
//
//  The two escapes are 44 pt targets sitting 18 pt under the button that logs
//  the set. A workout has no undo: one stray thumb would take a set, or a
//  whole movement together with every number already entered for it, and
//  nothing anywhere could put it back. The guard therefore has to stand in
//  FRONT of the state change rather than behind it.
//
//  The same holds for the escape that ends a guided block. It is a 56 pt
//  full-width button under "I'm ready", it fires on contact, and a block
//  left by accident cannot be picked up again: one bump of the phone — a
//  child's hand on the screen — took a cool-down straight to the rating.
//

import SwiftUI

/// One of the six skips, holding the action it will run if confirmed.
struct SkipConfirmation: Identifiable {
    enum Kind: String {
        case probeSet, workingSet, restOfSets, exercise
        /// The escape that ends a whole guided block.
        case warmup, cooldown
    }

    let kind: Kind
    /// Held here rather than resolved by the alert, so a question raised about
    /// one skip cannot be answered by another: the tap that opened this is the
    /// tap that runs.
    let perform: () -> Void
    /// What saying no hands back. A block's question freezes the block while
    /// it stands — a position must not run on, or end, behind an alert nobody
    /// has answered yet — so "Keep going" has to give the clock back.
    var cancel: () -> Void = {}

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .probeSet, .workingSet: return String(localized: "Skip this set?")
        case .restOfSets:            return String(localized: "Skip the remaining sets?")
        case .exercise:              return String(localized: "Skip this exercise?")
        case .warmup:                return String(localized: "Skip the warm-up?")
        case .cooldown:              return String(localized: "Skip the cool-down?")
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
            // ONE NOUN, and it is the title's: the question above says
            // "exercise" — the word the control that raised it uses too — so
            // the answer says "it" rather than hand the reader a second noun
            // to sew to the first under a running clock.
            return String(localized: """
                It counts as not trained, and any number you entered for it \
                is not kept. Its plan stays exactly as it is.
                """)
        // What a block's escape loses is the block itself, and the cool-down's
        // sentence says the one thing nobody can see from the button: there
        // is no way back into it from the rating.
        case .warmup:
            return String(localized: """
                The workout goes straight to the first exercise. \
                The plan does not change.
                """)
        case .cooldown:
            return String(localized: """
                The workout goes straight to the rating, and the cool-down \
                cannot be started again. The plan does not change.
                """)
        }
    }

    /// ONE SHORT VERB FOR ALL SIX, and the length is the point.
    /// `UIAlertController` lays two actions side by side only while both
    /// titles fit on one line and stacks them otherwise, so per-kind labels
    /// would make the layout itself differ between two controls that sit at
    /// equal weight in the same row — in Russian "Пропустить это упражнение"
    /// is three characters longer than "Пропустить этот подход". Identical
    /// labels cannot diverge, in any language or at any text size.
    ///
    /// Not "OK" either, and nothing longer is needed: the question stands
    /// directly above the two buttons and names the thing being skipped.
    ///
    /// The key is the onboarding cards' own "Skip": a different screen, never
    /// up at the same time, and no control in the workout reads exactly this.
    var confirmTitle: String { String(localized: "Skip") }

    // NO `.destructive` ROLE ON ANY OF THE SIX — not even the exercise-level
    // one, though `leaveExercise` really does discard the facts entered for
    // the pattern. Red says "danger", and this app's position on a skip is
    // the opposite: a skipped movement stays exactly where it was, no penalty
    // and no rollback, which is what the sentence above the button says in so
    // many words. A button shouting at a message that reassures is one screen
    // arguing with itself.
    //
    // What is destroyed is the numbers, not the movement, and the message
    // names them: the warning belongs in the sentence. The two escapes also
    // stand at equal weight in the row that raises them, so their questions
    // do too.
}

extension View {
    /// One alert for all six, driven by the pending question.
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
            Button(String(localized: "Keep going"), role: .cancel) { skip.cancel() }
            Button(skip.confirmTitle) { skip.perform() }
        } message: { skip in
            Text(verbatim: skip.message)
        }
    }
}
