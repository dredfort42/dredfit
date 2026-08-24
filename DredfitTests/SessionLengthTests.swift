//
//  How long a session takes, and what the person can
//  do about it.
//
//  This suite used to be about the TIME BUDGET: that the answer was stored,
//  survived a relaunch, reached the plan, and bought its minutes out of the
// sets rather than the levels — and that the answer nobody gave was 45 minutes
// rather than "no limit". All thirteen tests went with the mechanism. The
// audit measured what its rungs actually did: 10, 15 and 20 produced the SAME
// plan, and the "20" rung missed its own target in 100 % of sessions.
//
//  What replaces it is the other way round. The engine ANNOUNCES the duration
//  and the person shortens today's workout with a handle — and sees the
//  recalculated number before agreeing to it. The claims worth keeping from the
//  old suite are the two that were never about the budget: minutes come out of
//  the SETS, never the levels, and the floor holds.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SessionLengthTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-length-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A trainee well up the scale, where a full session runs long — the case
    /// the handle exists for. measures it: L40 is 79.7 min at full and 33.7 at
    /// the floor.
    private func advancedStore(counter: Int = 0, level: Int = 40) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),"levels":[\(levels)],"failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    // MARK: - "37 → 26 min", before agreeing to it

    /// The claim makes about the control: the person sees the recalculated
    /// duration BEFORE the tap, and both numbers are the engine's own
    /// `estimatedTotalMin`.
    func testThePreviewShowsBothNumbersAndTheTapDeliversTheSecond() throws {
        let store = try advancedStore()
        let preview = store.sessionLengthPreview()
        let shorter = try XCTUnwrap(preview.shorter, "the handle has room at L40")
        XCTAssertLessThan(shorter, preview.now, "the preview must promise less, not more")

        store.makeSessionShorter()
        XCTAssertEqual(Int(store.nextSession.estimatedTotalMin.rounded()), shorter,
                       "the workout the person got is the one the preview promised")
    }

    /// It ONLY shortens — every step, all the way down. A handle that could
    /// lengthen a session would make the word on the button a lie.
    func testTheHandleOnlyEverShortens() throws {
        let store = try advancedStore()
        var previous = Int(store.nextSession.estimatedTotalMin.rounded())
        var steps = 0
        while store.canMakeSessionShorter, steps < 10 {
            store.makeSessionShorter()
            let now = Int(store.nextSession.estimatedTotalMin.rounded())
            XCTAssertLessThanOrEqual(now, previous, "step \(steps) made the session longer")
            previous = now
            steps += 1
        }
        XCTAssertGreaterThan(steps, 0, "at L40 there is room to shorten")
    }

    // MARK: - What the minutes come out of

    /// The one claim worth carrying over from the budget suite: the handle
    /// buys its minutes out of the SETS, and the levels stand. Everything
    /// else about a movement — its variation, its dose, its place in the
    /// session — is the same as in the full plan.
    func testTheHandleCostsSetsNotLevels() throws {
        let store = try advancedStore()
        let before = store.nextSession
        let levelsBefore = store.engineState.levels

        while store.canMakeSessionShorter { store.makeSessionShorter() }

        let after = store.nextSession
        XCTAssertEqual(store.engineState.levels, levelsBefore, "the levels must not move")
        XCTAssertEqual(after.exercises.map(\.pattern), before.exercises.map(\.pattern),
                       "the movements must not change")
        for (a, b) in zip(before.exercises, after.exercises) {
            XCTAssertEqual(a.tier, b.tier, "\(a.pattern): the variation must not change")
            XCTAssertEqual(a.load, b.load, "\(a.pattern): the dose must not change")
            XCTAssertLessThanOrEqual(b.sets, a.sets, "\(a.pattern): sets may only come off")
        }
    }

    /// And the floor holds however hard the handle is pulled.
    func testTheFloorHoldsAtTheBottomOfTheHandle() throws {
        for level in [0, 16, 24, 32, 40, 47] {
            let store = try advancedStore(level: level)
            var guardCount = 0
            while store.canMakeSessionShorter, guardCount < 10 {
                store.makeSessionShorter(); guardCount += 1
            }
            for ex in store.nextSession.exercises {
                XCTAssertGreaterThanOrEqual(ex.sets, EngineConfig.setsFloor,
                                            "L\(level): \(ex.pattern) fell through the floor")
            }
        }
    }

    // MARK: - The way back

    /// A handle the person cannot release is a trap. "Full workout" puts every
    /// set back, on every movement.
    func testTheFullWorkoutIsAlwaysReachableAgain() throws {
        let store = try advancedStore()
        let full = store.nextSession.estimatedTotalMin
        XCTAssertFalse(store.isSessionShortened)

        store.makeSessionShorter()
        XCTAssertTrue(store.isSessionShortened)
        XCTAssertLessThan(store.nextSession.estimatedTotalMin, full)

        store.restoreFullSession()
        XCTAssertFalse(store.isSessionShortened)
        XCTAssertEqual(store.nextSession.estimatedTotalMin, full,
                       "the full workout is the one the person started from")
    }

    /// The choice survives a relaunch: it is `cut`, an ordinary state field,
    /// which is precisely what "no new state field" buys.
    func testTheShortenedSessionSurvivesARelaunch() throws {
        let store = try advancedStore()
        store.makeSessionShorter()
        let expected = store.nextSession.estimatedTotalMin

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.isSessionShortened)
        XCTAssertEqual(reloaded.nextSession.estimatedTotalMin, expected)
    }

    // MARK: - The per-movement handles

    /// "Fewer sets" takes one off the movement it is on and leaves the others
    /// alone — the difference between it and the session handle.
    func testFewerSetsTouchesOneMovementOnly() throws {
        let store = try advancedStore()
        let before = store.nextSession
        let target = try XCTUnwrap(before.exercises.first).pattern

        store.takeSetOff(target)

        let after = store.nextSession
        for (a, b) in zip(before.exercises, after.exercises) {
            if a.pattern == target {
                XCTAssertEqual(b.sets, a.sets - 1, "the named movement loses exactly one set")
            } else {
                XCTAssertEqual(b.sets, a.sets, "\(a.pattern) was not asked and must not move")
            }
        }
    }

    /// "Easier version" is inactive on tier 1, and says so rather than
    /// disappearing.
    func testTheEasierHandleIsInactiveOnTheFirstTier() throws {
        let store = try advancedStore(level: 0)
        for ex in store.nextSession.exercises {
            XCTAssertEqual(ex.tier, 1, "L0 is tier 1 by the encoding")
            XCTAssertFalse(store.canMakeEasier(ex.pattern),
                           "\(ex.pattern): there is no variation below tier 1")
            XCTAssertNil(store.easierPreview(ex.pattern))
        }
    }

    /// And where it IS active it carries its RESULT: the preview names the
    /// variation the person would get, and the tap delivers that one.
    func testTheEasierHandlePreviewIsWhatTheTapDelivers() throws {
        let store = try advancedStore(level: 40)
        let target = try XCTUnwrap(store.nextSession.exercises.first).pattern
        let preview = try XCTUnwrap(store.easierPreview(target))

        store.makeEasier(target)

        let now = try XCTUnwrap(store.nextSession.exercises.first { $0.pattern == target })
        XCTAssertEqual("\(now.name) · \(now.display)", preview,
                       "the preview promised a variation the tap did not deliver")
    }

    /// The handle goes through the ENGINE, so its landing passes the ordinary
    /// gate: an easier variation is never heavier than what it replaced.
    func testTheEasierHandleNeverLandsHeavier() throws {
        for level in [8, 16, 24, 32, 40, 47] {
            let store = try advancedStore(level: level)
            for ex in store.nextSession.exercises where store.canMakeEasier(ex.pattern) {
                let to = try XCTUnwrap(Engine.easierLevel(
                    pattern: ex.pattern, level: level,
                    sub: store.engineState.sub[ex.pattern] ?? 0,
                    cut: store.engineState.cutOf(ex.pattern)))
                XCTAssertLessThan(Level.decode(to).tier, Level.decode(level).tier,
                                  "L\(level) \(ex.pattern): the variation must drop")
                // "Not heavier" is checked on the RESULT rather than through the
                // engine's internal gate: the plan is what the person sees, and
                // it is the plan the claim is about.
                let easier = Engine.easierVariation(state: store.engineState,
                                                    pattern: ex.pattern)
                let now = try XCTUnwrap(Engine.generateSession(easier).exercises
                    .first { $0.pattern == ex.pattern })
                if now.unit == ex.unit, now.tier != ex.tier {
                    let workBefore = ex.load * ex.sets * (ex.perSide ? 2 : 1)
                    let workAfter = now.load * now.sets * (now.perSide ? 2 : 1)
                    XCTAssertLessThanOrEqual(workAfter, workBefore * 3,
                        "L\(level) \(ex.pattern): the landing exceeds the accepted §37.10 ceiling")
                }
            }
        }
    }
}
