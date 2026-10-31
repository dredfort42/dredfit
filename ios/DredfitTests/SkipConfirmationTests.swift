//
//  The question a skip asks. Pinned here rather than only in the UI suite
//  because the two rules worth breaking are both about STRINGS, and a walk
//  that taps by label would report either break as "the control did nothing".
//

import XCTest
@testable import Dredfit

@MainActor
final class SkipConfirmationTests: XCTestCase {

    private let all: [SkipConfirmation.Kind] = [.probeSet, .workingSet, .restOfSets, .exercise,
                                                .warmup, .cooldown]

    private func make(_ kind: SkipConfirmation.Kind) -> SkipConfirmation {
        SkipConfirmation(kind: kind) { }
    }

    /// Every question says something, and nothing says its own key back.
    func testEveryKindCarriesATitleAMessageAndAConfirmLabel() {
        for kind in all {
            let skip = make(kind)
            XCTAssertFalse(skip.title.isEmpty, "\(kind) asks nothing")
            XCTAssertFalse(skip.message.isEmpty, "\(kind) says nothing about what is lost")
            XCTAssertFalse(skip.confirmTitle.isEmpty, "\(kind) offers no way to say yes")
        }
    }

    /// The confirm label must not be the label of the control that raised the
    /// question. Two buttons reading the same words are one button to a test
    /// query and to VoiceOver's rotor — and the one that matters is the one
    /// inside the alert.
    func testTheConfirmLabelIsNeverTheLabelOfTheControlThatRaisedIt() {
        let controls = [String(localized: "Skip this set"),
                        String(localized: "Skip remaining sets"),
                        String(localized: "Skip exercise"),
                        GuidedBlock.warmup.skipTitle,
                        GuidedBlock.cooldown.skipTitle]
        for kind in all {
            XCTAssertFalse(controls.contains(make(kind).confirmTitle),
                           "\(kind) answers itself with the words already on screen")
        }
    }

    /// ONE label for all six, because `UIAlertController` picks its layout
    /// from the button widths: per-kind labels would make two controls that
    /// sit at equal weight in the same row stack differently — in Russian
    /// "Пропустить этот подход" fits beside the cancel and "Пропустить это
    /// упражнение", three characters longer, does not.
    ///
    /// Identical strings cannot diverge in any language or at any text size,
    /// which is what makes this the fix rather than a shorter wording. Which
    /// question is up is read off the TITLE, and the titles are all different.
    func testAllSixAnswerToTheSameButton() {
        XCTAssertEqual(Set(all.map { make($0).confirmTitle }).count, 1,
                       "a per-kind confirm label lets the alert's layout differ")
        XCTAssertEqual(Set(all.map { make($0).title }).count, 5,
                       "the two set-level skips share a question; the other four do not")
    }

    /// All six questions have the SAME shape, with no red `.destructive`
    /// button on any of them: red says "danger", and this app's position on a
    /// skip is that a skipped movement stays exactly where it was, no penalty
    /// and no rollback. What is destroyed is the numbers, and the message says
    /// so; a red button would argue with the sentence above it.
    ///
    /// Asserted through the strings rather than through a role, because there
    /// is no role to read — what a test can hold is that no question is told
    /// apart from the others by anything but its words.
    func testTheFourQuestionsDifferOnlyInWhatTheySay() {
        let shapes = all.map { make($0) }
        for skip in shapes {
            XCTAssertTrue(skip.title.hasSuffix("?"),
                          "\(skip.kind) does not read as a question")
            XCTAssertFalse(skip.confirmTitle.isEmpty,
                           "\(skip.kind) offers nothing to confirm with")
        }
        // …and no two of them are the same question.
        XCTAssertEqual(Set(shapes.map(\.message)).count, shapes.count,
                       "two skips promise the same thing about different acts")
    }

    /// The set-level questions say exactly what the controls' accessibility
    /// hints say, because they are the same promise about the same rule. A
    /// second wording is a second promise, and only one of them gets updated.
    func testTheSetLevelMessagesAreTheHintsThemselves() {
        XCTAssertEqual(make(.workingSet).message,
                       String(localized: """
                           The plan keeps this set off next time. \
                           Nothing else about the movement changes.
                           """))
        XCTAssertEqual(make(.probeSet).message,
                       String(localized: """
                           The probe just comes back next time. \
                           The working sets lose nothing.
                           """))
    }

    /// The probe takes no volume off anything, so its question must
    /// not borrow the working set's sentence — which promises a set kept off
    /// the next plan.
    func testTheProbeIsNotToldTheWorkingSetsPromise() {
        XCTAssertNotEqual(make(.probeSet).message, make(.workingSet).message)
    }

    /// The action is held by the question, not resolved by the alert: the tap
    /// that raised it is the tap that runs.
    func testConfirmingRunsTheActionTheQuestionWasRaisedWith() {
        var ran = 0
        let skip = SkipConfirmation(kind: .exercise) { ran += 1 }
        XCTAssertEqual(ran, 0, "building the question must not perform it")
        skip.perform()
        XCTAssertEqual(ran, 1)
    }

    /// A block's question freezes the block, so saying no has to hand the
    /// clock back — and only saying no: the answer that skips must not also
    /// resume a block it is ending, and building the question runs neither.
    func testKeepGoingRunsTheCancelAndOnlyIt() {
        var performed = 0
        var cancelled = 0
        let skip = SkipConfirmation(kind: .cooldown,
                                    perform: { performed += 1 },
                                    cancel: { cancelled += 1 })
        XCTAssertEqual(cancelled, 0, "building the question must not answer it")
        skip.cancel()
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(performed, 0, "saying no must not skip")
    }

    /// The cool-down's question says the one thing the button cannot: there
    /// is no way back into the block from the rating.
    func testTheCooldownQuestionSaysItCannotBeStartedAgain() {
        XCTAssertEqual(make(.cooldown).message,
                       String(localized: """
                           The workout goes straight to the rating, and the cool-down \
                           cannot be started again. The plan does not change.
                           """))
        XCTAssertNotEqual(make(.warmup).message, make(.cooldown).message)
    }
}
