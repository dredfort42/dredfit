//
//  The rating after the fact: the one sentence about what it moved, and the
//  way to give a different one.
//
//  An extension in a file of its own, for the reason `TodayView+PlanRow`
//  states — the type stands at the linter's body bound and an extension
//  weighs nothing against it wherever it sits. Together here rather than
//  apart because they are one thought: the sentence is what a person reads
//  before deciding the answer was wrong.
//

import SwiftUI
import DredfitCore

extension TodayView {

    /// The one sentence about what the tap did.
    ///
    /// After a "tough" it NAMES the movements the descent landed on. The
    /// rating card promised "the next one eases off where it's hardest", and
    /// until now nothing anywhere said WHERE that was — an unnamed "less"
    /// moves one movement, not the workout, so the person reading this line
    /// the next morning could not check the promise against the plan
    /// (UX review 05.09.2026, finding 27).
    ///
    /// The attribution exists for the LAST workout only and is stamped at the
    /// moment the rating is applied (`PlanMoves`); an empty list means "nothing
    /// to say", never "nothing happened", which is why the unnamed sentence
    /// stays as the honest fallback instead of being turned into a claim about
    /// zero movements.
    var resultCaption: String {
        guard let record = store.lastRecord else { return "" }
        switch record.result {
        case .less:
            let eased = store.easedByRating(in: record)
            guard !eased.isEmpty else {
                return String(localized: "Rating: tough — the next one will be easier")
            }
            // The system's own list, so the conjunction and the commas are
            // the locale's rather than ours.
            let names = eased.map(\.displayName).formatted(.list(type: .and))
            return String(localized: "today.ratingLessNamed",
                          defaultValue: "Rating: tough — the next one eases off on \(names)")
        case .plan:
            return String(localized: "Rating: on plan — the next one adds a step to the movements that have room for one")
        case .more:
            return String(localized: "Rating: easy — progressing as fast as each movement allows")
        }
    }

    // MARK: - Giving a different answer

    /// The way back from a rating, and it is not a nicety: owner decision 1
    /// (05.09.2026) settles a workout nobody rated as "on plan" while the app
    /// is not even running, so the first rating a person ever meets may be one
    /// they never gave (UX review 05.09.2026, finding 25).
    ///
    /// Quiet, and last on the screen: it is the rarest control here, and the
    /// door beside it — "What you did today" — is the common one. Every guard
    /// is the store's (`canChangeLastRating`), which closes this door the
    /// moment anything else has moved the state the record left behind.
    ///
    /// The alert hangs on the button, which survives its own action: the
    /// re-application stamps a fresh `RatingUndo` for the new answer, so the
    /// door stays open and nothing is dismissed out from under a presentation
    /// (the trap WorkoutFlowView.swift:439-443 is written against).
    @ViewBuilder
    var changeRatingButton: some View {
        if store.canChangeLastRating, let record = store.lastRecord {
            Button {
                ratingChangeShown = true
            } label: {
                // accentText, not accent: 3.58:1 does not carry small text
                // (owner, 05.09.2026). 44 pt, because a bare 14 pt word is
                // about 17 pt of hit area (#193's floor).
                Text(verbatim: String(localized: "today.changeRating",
                                      defaultValue: "Change the rating"))
                    .dredfitFont(14)
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("change-rating")
            .alert(String(localized: "today.changeRating.title",
                          defaultValue: "How did it actually go?"),
                   isPresented: $ratingChangeShown) {
                ratingChoices(for: record)
            } message: {
                Text(verbatim: String(localized: "today.changeRating.body", defaultValue: """
                    The workout itself does not change — the sets, the numbers \
                    and the date all stay. Only the next plan is built again, \
                    from the new answer.
                    """))
            }
        }
    }

    /// The other two answers, spelled out rather than looped: an alert's
    /// actions are a fixed short list, and the three words are the FeedbackView
    /// ones on purpose — the same question must not be asked twice in two
    /// vocabularies.
    ///
    /// The current answer is absent because re-applying it is a no-op
    /// (`changeLastRating` refuses it), and a button that does nothing is the
    /// ghost control this wave has been taking out everywhere else.
    ///
    /// The milestones the new answer earns are dropped on purpose. That screen
    /// is a moment INSIDE a workout — it is how the flow tells someone
    /// something changed while they are still training — and raising it over
    /// Today would announce a milestone for a correction made days later. The
    /// plan states its own numbers on the next screen either way.
    @ViewBuilder
    private func ratingChoices(for record: WorkoutRecord) -> some View {
        if record.result != .less {
            Button(String(localized: "Tough, did less")) { store.changeLastRating(to: .less) }
        }
        if record.result != .plan {
            Button(String(localized: "On plan")) { store.changeLastRating(to: .plan) }
        }
        // The same gate the rating screen puts on "easy", so a correction
        // cannot become the way around it.
        if record.result != .more, didFullPlan(record) {
            Button(String(localized: "Easy, could do more")) { store.changeLastRating(to: .more) }
        }
        // Names what it keeps, like the other three questions on this screen:
        // "Cancel" answers "cancel what?" and this one does not.
        Button(String(localized: "today.changeRating.keep",
                      defaultValue: "Keep this rating"), role: .cancel) { }
    }

    /// `SetFacts.didFullPlan`, over the journal entry instead of over the live
    /// session — the same rule, the same arguments.
    ///
    /// A record that does not carry its own exercises answers NO rather than
    /// vacuously yes: `allSatisfy` over an empty plan is true, which would
    /// hand "easy" to exactly the sessions nothing is known about. Nothing
    /// reachable is in that state today — the undo this door needs is written
    /// by the same call that writes the exercises — and the guard is here so
    /// that stays a fact rather than a coincidence.
    private func didFullPlan(_ record: WorkoutRecord) -> Bool {
        guard let exercises = record.exercises, !exercises.isEmpty else { return false }
        return SetFacts.didFullPlan(record.setActuals ?? [:],
                                    skips: record.setsSkipped ?? [:],
                                    skipped: record.skipped ?? [],
                                    in: exercises)
    }
}
