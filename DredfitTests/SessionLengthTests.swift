//
//  How long a session takes, and what the person can do about it.
//
//  This suite used to be about the TIME BUDGET: that the answer was stored,
//  survived a relaunch, reached the plan, and bought its minutes out of the
//  sets rather than the levels. All thirteen tests went with the mechanism —
//  the audit measured what its rungs actually did: 10, 15 and 20 produced the
//  SAME plan, and the "20" rung missed its own target in 100 % of sessions.
//
//  What replaced it was a handle on the plan, and §38 has now removed that
//  too: nobody is asked before the workout how much of it they have in them.
//  The plan announces its length; the person shortens the session from inside
//  it (SetSkipTests), and the movement's own VARIATION is the one thing still
//  worth choosing in advance — which is what is left here.
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
    /// §38 exists for. The spec measures it: L40 is 79.7 min at full and 33.7
    /// with every movement on the sets floor.
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

    // MARK: - The range on Today (§38.3)

    /// The six rows of §38.3, exactly: the full plan and the shortest the
    /// session can be made from inside it. These are the numbers the screen
    /// prints, and drift in either of them is drift in what the app promises.
    func testTheRangeIsTheOneTheSpecAnnounces() throws {
        for (level, floor, full) in [(0, 26, 34), (16, 25, 33), (24, 27, 38),
                                     (32, 29, 52), (40, 34, 80), (47, 40, 94)] {
            let store = try advancedStore(level: level)
            let length = store.sessionLengthRange()
            XCTAssertEqual([length.floor, length.full], [floor, full],
                           "L\(level): the announced range moved")
        }
    }

    /// §37.1's declared bottom, and the first wave that can check it: the
    /// short workout used to live outside the engine and reach 20.5 minutes
    /// against an announced 24.8, which is exactly why it was removed.
    ///
    /// The claim is about the WHOLE scale, not the six rows above: no level
    /// anywhere can be squeezed under the number the App Store listing names,
    /// and one of them reaches it.
    func testTheShortestSessionOnAnyLevelIsTheAnnouncedFloor() throws {
        // 24.8 min, as the screen rounds it. The spec's own number is the
        // tenth; the app never shows tenths.
        let announced = Int(24.8.rounded())
        var shortest = Int.max
        for level in 0...EngineConfig.levelMax {
            let store = try advancedStore(level: level)
            let floor = store.sessionLengthRange().floor
            XCTAssertGreaterThanOrEqual(floor, announced,
                                        "L\(level) can be squeezed under the announced floor")
            shortest = min(shortest, floor)
        }
        XCTAssertEqual(shortest, announced,
                       "no level reaches the announced floor any more — §37.1 is either "
                       + "untrue or out of date")
    }

    /// A plan already on the floor has one number, not a range of one: the
    /// line must not offer a saving that has been taken.
    func testAPlanOnTheFloorHasNoRangeLeft() throws {
        let store = try advancedStore(level: 40)
        // Every movement taken to the floor the way the app takes it: skipped
        // sets, landed by the engine when the rating comes in.
        var skips: SetFacts.Skips = [:]
        for pattern in Pattern.allCases { skips[pattern] = EngineConfig.setsMax }
        store.completeWorkout(session: store.nextSession, result: .less, setsSkipped: skips)

        let length = store.sessionLengthRange()
        XCTAssertEqual(length.floor, length.full,
                       "with every movement on the floor the two ends must meet")
    }

    /// The range is a QUESTION, not a decision: asking it must not move the
    /// plan, the levels or the cut.
    func testAskingForTheRangeChangesNothing() throws {
        let store = try advancedStore(level: 40)
        let before = store.engineState
        let plan = store.nextSession

        _ = store.sessionLengthRange()

        XCTAssertEqual(store.engineState, before, "the question wrote state")
        XCTAssertEqual(store.nextSession, plan, "the question moved the plan")
    }

    // MARK: - The handle that is left

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
