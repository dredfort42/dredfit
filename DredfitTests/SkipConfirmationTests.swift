//
//  The question a skip asks. Pinned here rather than only in the UI suite
//  because the two rules worth breaking are both about STRINGS, and a walk
//  that taps by label would report either break as "the control did nothing".
//

import XCTest
@testable import Dredfit

@MainActor
final class SkipConfirmationTests: XCTestCase {

    private let all: [SkipConfirmation.Kind] = [.probeSet, .workingSet, .restOfSets, .exercise]

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
                        String(localized: "Skip exercise")]
        for kind in all {
            XCTAssertFalse(controls.contains(make(kind).confirmTitle),
                           "\(kind) answers itself with the words already on screen")
        }
    }

    /// All four questions have the SAME shape — the movement-level one carried
    /// a red `.destructive` button for a while and lost it (owner,
    /// 31.08.2026): red says "danger", and this app's position on a skip is
    /// that a skipped movement stays exactly where it was, no penalty and no
    /// rollback. What is destroyed is the numbers, and the message says so;
    /// the colour argued with the sentence above it.
    ///
    /// Asserted through the strings rather than through a role, because the
    /// role is gone — what a test can still hold is that no question is told
    /// apart from the others by anything but its words.
    func testTheFourQuestionsDifferOnlyInWhatTheySay() {
        let shapes = all.map { make($0) }
        for skip in shapes {
            XCTAssertTrue(skip.title.hasSuffix("?"),
                          "\(skip.kind) does not read as a question")
            XCTAssertTrue(skip.confirmTitle.hasPrefix("Skip"),
                          "\(skip.kind) does not name the act it confirms")
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

    /// The probe takes no volume off anything (§40.4), so its question must
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
}
