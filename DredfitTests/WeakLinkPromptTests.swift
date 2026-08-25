//
//  The movement the trainee never names. Someone who
//  only knows the one-tap gesture rates "tough" whenever the pushes come up;
//  because the pushes are in most sessions, the model reads that as "the whole
//  programme is too hard" and nine weeks later the programme is gone — while
//  the movement that actually hurts is still in every plan. The journal has
//  seen the correlation all along; this asks one question about it.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class WeakLinkPromptTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-weaklink" }

    /// A store whose journal is `count` sessions, each one an unnamed "tough"
    /// when it carried `culprit` and "on plan" otherwise — the naive persona.
    /// The audit's shoulder persona, and it is seeded UP THE SCALE on purpose.
    ///
    /// The prompt now routes into the handles, and it stays silent when
    /// neither of them could do anything — so a persona sitting at L0 on the
    /// sets floor is not the case this suite is about. It is the case accepts:
    /// at the declared bottom of the app there is nothing left to offer, and
    /// `testAMovementWithNoHandleLeftIsNotSuggested` pins exactly that.
    /// Someone whose shoulder keeps failing is somewhere up the scale, with
    /// both handles still live, and that is who is seeded here.
    private func naiveStore(sessions count: Int, culprit: Pattern = .pushV,
                            variation: Int = 3) -> AppStore {
        func at(_ p: Pattern) -> Int { min(variation, Library.count(p)) }
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(at($0))" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(Dose.grid(Library.unit($0, at($0))).min + 2)" }
            .joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        // The journal of what was shown: the handle lands IN it (§40.6), and a
        // persona without one would find an easier variation that offers 3×4.
        let shown = Pattern.allCases.map { p in
            let rows = (1...at(p)).map { "\"\($0)\":\(Dose.grid(Library.unit(p, $0)).max)" }
                .joined(separator: ",")
            return "\"\(p.rawValue)\",{\(rows)}"
        }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"vars":[\(vars)],"doses":[\(doses)],
                        "shown":[\(shown)],"failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try? Data(json.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<count {
            let session = store.nextSession
            let carries = session.exercises.contains { $0.pattern == culprit }
            _ = store.completeWorkout(session: session, result: carries ? .less : .plan)
        }
        return store
    }

    func testThePromptNamesTheMovementThatKeepsLandingUnderTough() {
        let store = naiveStore(sessions: 12)
        XCTAssertEqual(store.unnamedLessSuspect(), .pushV)
        XCTAssertTrue(store.shouldAskAboutSuspect())
    }

    func testAnHonestTraineeIsNeverAsked() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<12 {
            _ = store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertNil(store.unnamedLessSuspect(), "nothing is failing — nothing to ask about")
        XCTAssertFalse(store.shouldAskAboutSuspect())
    }

    func testATraineeWhoAlreadyNamesTheMovementIsNeverAsked() {
        // Naming the movement used to mean reporting pain on it; the surviving
        // way to name one is an exact number below the plan, and that is the
        // answer the prompt is trying to reach.
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<12 {
            let session = store.nextSession
            let carried = session.exercises.first { $0.pattern == .pushV }
            var overrides: [Pattern: Int] = [:]
            if let carried { overrides[.pushV] = max(0, carried.load - 2) }
            _ = store.completeWorkout(session: session,
                                      result: carried != nil ? .less : .plan,
                                      overrides: overrides)
        }
        XCTAssertNil(store.unnamedLessSuspect())
    }

    func testTheQuestionIsAskedOncePerSession() {
        let store = naiveStore(sessions: 12)
        XCTAssertTrue(store.shouldAskAboutSuspect())
        store.dismissSuspectPrompt()
        XCTAssertFalse(store.shouldAskAboutSuspect(), "a question, not a campaign")

        // The next workout is a new session, so the question may return.
        _ = store.completeWorkout(session: store.nextSession, result: .less)
        XCTAssertTrue(store.shouldAskAboutSuspect())
    }

    /// Re-marked from
    /// `testTheSofterAnswerHoldsTheLevelInsteadOfTakingTheLoadOff`. The softer
    /// answer — "just hard" — armed a hold, and the hold is cancelled: the case
    /// it served (the plan ran ahead of what the trainee can do) is what the
    /// sub-step fixes without asking. The prompt is down to the diagnosis and a
    /// dismissal, and THAT is what gets pinned: dismissing must change no plan.
    func testDismissingTheQuestionChangesNothingAboutThePlan() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        let before = store.engineState
        store.dismissSuspectPrompt()
        XCTAssertFalse(store.shouldAskAboutSuspect(), "asked once per session")
        XCTAssertEqual(store.engineState, before, "a dismissal touches no state")

        var applied = false
        for _ in 0..<8 where !applied {
            let session = store.nextSession
            let carries = session.exercises.contains { $0.pattern == suspect }
            _ = store.completeWorkout(session: session, result: .plan)
            if carries {
                applied = true
                XCTAssertEqual(store.engineState.cutOf(suspect), 0,
                               "nothing was pulled, so no set came off")
            }
        }
        XCTAssertTrue(applied)
    }

    // Three tests moved rather than vanished — see the two below. The prompt
    // used to answer "it hurts" by QUEUEING a pain report for the movement's
    // next appearance: the answer was sticky, it had to survive a relaunch,
    // and it took effect an appearance later. The handle takes effect at once
    // and needs no queue, so "the answer survives a relaunch" has nothing left
    // to survive.

    // MARK: - The answer is a handle, not a diagnosis

    /// "Make it easier" acts AT ONCE and on the movement named. The old answer
    /// queued a pain report for the next appearance; this one changes the
    /// variation now and keeps the movement in every plan from here on.
    func testMakingItEasierActsAtOnceOnTheNamedMovement() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        let before = store.engineState.position(suspect)
        let stepsBefore = Engine.progress(store.engineState, suspect)
        let othersBefore = Pattern.allCases.reduce(into: [Pattern: Position]()) {
            $0[$1] = store.engineState.position($1)
        }

        store.makeSuspectEasier(suspect)

        let after = store.engineState.position(suspect)
        XCTAssertLessThan(Engine.progress(store.engineState, suspect), stepsBefore,
                          "the named movement drops to an easier variation")
        XCTAssertLessThan(after.variation, before.variation,
                          "and it is the VARIATION that dropped, not just the rung")
        for (pattern, position) in othersBefore where pattern != suspect {
            XCTAssertEqual(store.engineState.position(pattern), position,
                           "\(pattern) was not named and must not move")
        }
        XCTAssertFalse(store.shouldAskAboutSuspect(),
                       "the question is answered for this session")
    }

    /// And the movement stays IN the plan — the difference from the mechanism
    /// this replaces, which took it out for weeks.
    func testTheMovementStaysInThePlanAfterTheHandle() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        store.makeSuspectEasier(suspect)

        var seen = false
        for _ in 0..<8 where !seen {
            let session = store.nextSession
            if session.exercises.contains(where: { $0.pattern == suspect }) { seen = true }
            _ = store.completeWorkout(session: session, result: .plan)
        }
        XCTAssertTrue(seen, "the movement is still in the rotation")
    }

    /// Nothing to suggest when the handle the prompt offers would do nothing:
    /// on tier 1 the question would route into a dead control.
    ///
    /// This is the accepted bottom, stated from the app's side — at the
    /// first variation the app has run out of things to offer, and going quiet
    /// is the honest answer rather than showing a button that cannot fire. The
    /// sets half of the old guard went with the sets handle: volume is
    /// answered inside the workout now, and a prompt on the plan cannot offer
    /// it.
    func testAMovementWithNoHandleLeftIsNotSuggested() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        while store.canMakeEasier(suspect) { store.makeEasier(suspect) }
        XCTAssertFalse(store.canMakeEasier(suspect), "seeding: the easier handle is spent")
        XCTAssertNil(store.unnamedLessSuspect(),
                     "with the handle spent there is nothing left to offer")
    }
}
