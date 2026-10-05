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
    /// when it carried `culprit` and "on plan" otherwise — the naive persona,
    /// a shoulder that keeps failing, seeded UP THE SCALE on purpose.
    ///
    /// The prompt routes into the easier-variation handle, and it stays silent
    /// when that handle could do nothing — so a persona on the first variation
    /// is not the case this suite is about: at the declared bottom of the app
    /// there is nothing left to offer, and
    /// `testAMovementWithNoHandleLeftIsNotSuggested` pins exactly that.
    /// Someone whose shoulder keeps failing is somewhere up the scale, with
    /// the handle still live, and that is who is seeded here.
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
        // The journal of what was shown: the handle lands under it, and a
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
        let store = makeStore()
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
        let store = makeStore()
        for _ in 0..<12 {
            _ = store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertNil(store.unnamedLessSuspect(), "nothing is failing — nothing to ask about")
        XCTAssertFalse(store.shouldAskAboutSuspect())
    }

    func testATraineeWhoAlreadyNamesTheMovementIsNeverAsked() {
        // The way to name a movement is an exact number below the plan, and
        // that is the answer the prompt is trying to reach.
        let store = makeStore()
        for _ in 0..<12 {
            let session = store.nextSession
            let carried = session.exercises.first { $0.pattern == .pushV }
            var overrides: [Pattern: Double] = [:]
            if let carried { overrides[.pushV] = Double(max(0, carried.load - 2)) }
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

    /// Dismissing the question must change no plan: the dismissal touches no
    /// engine state, and the movement's next appearance takes no set off.
    func testDismissingTheQuestionChangesNothingAboutThePlan() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        let before = store.engineState
        store.dismissSuspectPrompt()
        XCTAssertFalse(store.shouldAskAboutSuspect(), "asked once per session")
        XCTAssertEqual(store.engineState, before, "a dismissal touches no engine state")

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

    // MARK: - The answer is a handle, not a diagnosis

    /// "Make it easier" acts AT ONCE and on the movement named: it changes the
    /// variation now, with no queue for the next appearance, and keeps the
    /// movement in the rotation from here on.
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

    /// And the movement stays IN the plan: an easier variation of it, never
    /// weeks without it.
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
    /// on the first variation the question would route into a dead control.
    ///
    /// This is the accepted bottom, stated from the app's side — at the
    /// first variation the app has run out of things to offer, and going quiet
    /// is the honest answer rather than showing a button that cannot fire.
    /// Volume is answered inside the workout, and a prompt on the plan cannot
    /// offer it.
    func testAMovementWithNoHandleLeftIsNotSuggested() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        while store.canMakeEasier(suspect) { store.makeEasier(suspect) }
        XCTAssertFalse(store.canMakeEasier(suspect), "seeding: the easier handle is spent")
        XCTAssertNil(store.unnamedLessSuspect(),
                     "with the handle spent there is nothing left to offer")
    }
}
