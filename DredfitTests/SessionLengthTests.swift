//
//  How long a session takes, and what the person can do about it.
//
//  This suite used to be about the TIME BUDGET: that the answer was stored,
//  survived a relaunch, reached the plan, and bought its minutes out of the
//  sets rather than the levels. All thirteen tests went with the mechanism —
//  the audit measured what its rungs actually did: 10, 15 and 20 produced the
//  SAME plan, and the "20" rung missed its own target in 100 % of sessions.
//
//  What replaced it was a handle on the plan, and that has now been removed
//  too: nobody is asked before the workout how much of it they have in them.
//  The plan announces its length; the person shortens the session from inside
//  it (SetSkipTests), and the movement's own VARIATION is the one thing still
//  worth choosing in advance — which is what is left here.
//
//  The hard-coded minute rows this file used to carry went with the level
//  scale (§40.7): they were keyed by `L`, and there is no `L`. Every number
//  below is DERIVED from the engine, which is the only place duration
//  arithmetic has ever lived.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SessionLengthTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-length" }

    /// A trainee `variation` rungs up every ladder, at the dose ceiling —
    /// where a full session runs long, which is the case the range exists for.
    ///
    /// Seeded in the v3 shape: a v2 state does not decode at all now (§40.8),
    /// and a seed the store quietly replaced with a clean start would make
    /// every assertion here true for the wrong reason. `lastHard` keeps a
    /// probe out of the plan, so the numbers are about working sets.
    private func advancedStore(counter: Int = 0, variation: Int) throws -> AppStore {
        func at(_ p: Pattern) -> Int { min(variation, Library.count(p)) }
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(at($0))" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(Dose.grid(Library.unit($0, at($0))).max)" }
            .joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let journal = Pattern.allCases.map { p in
            let rows = (1...at(p)).map { "\"\($0)\":\(Dose.grid(Library.unit(p, $0)).max)" }
                .joined(separator: ",")
            return "\"\(p.rawValue)\",{\(rows)}"
        }.joined(separator: ",")
        let hard = Pattern.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),"vars":[\(vars)],"doses":[\(doses)],
                        "shown":[\(journal)],"lastHard":[\(hard)],
                        "failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.engineState.vars[.squat], at(.squat), "the seed must load")
        return store
    }

    /// The widest position any ladder reaches — the sweeps below walk to it.
    private var deepestVariation: Int { Pattern.allCases.map(Library.count).max() ?? 1 }

    // MARK: - The range on Today

    /// A range is a promise about which end is which, and both ends are the
    /// ENGINE's own `estimatedTotalMin` — the app owns no duration arithmetic.
    func testTheRangeIsOrderedAndComesFromTheEngine() throws {
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            let length = store.sessionLengthRange()
            XCTAssertLessThanOrEqual(length.floor, length.full,
                                     "variation \(variation): the range is inverted")
            XCTAssertEqual(length.full, Int(store.nextSession.estimatedTotalMin.rounded()),
                           "variation \(variation): the full end is not the announced plan")
            XCTAssertGreaterThan(length.floor, 0)
        }
    }

    /// The claim is about the WHOLE scale: nothing anywhere on it can be
    /// squeezed below what a clean start costs on its sets floor. The floor of
    /// the shortest possible session IS the clean start's — the least work the
    /// app is willing to call a workout (§37.1).
    func testNoPositionIsShorterThanACleanStartOnItsFloor() throws {
        let cleanFloor = try advancedStore(variation: 1).sessionLengthRange().floor
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            XCTAssertGreaterThanOrEqual(
                store.sessionLengthRange().floor, cleanFloor,
                "variation \(variation) can be squeezed under the shortest session there is")
        }
    }

    /// And a session grows as the ladder does — otherwise the range would be
    /// saying nothing at all.
    func testTheFullSessionGrowsAlongTheLadder() throws {
        let low = try advancedStore(variation: 1).sessionLengthRange().full
        let high = try advancedStore(variation: deepestVariation).sessionLengthRange().full
        XCTAssertGreaterThan(high, low,
                             "a session at the top of the ladders must cost more than one at the bottom")
    }

    // MARK: - The handle that is left

    /// "Easier version" is inactive on the first variation, and says so rather
    /// than disappearing.
    func testTheEasierHandleIsInactiveOnTheFirstVariation() throws {
        let store = try advancedStore(variation: 1)
        for ex in store.nextSession.exercises {
            XCTAssertEqual(ex.variation, 1)
            XCTAssertFalse(store.canMakeEasier(ex.pattern),
                           "\(ex.pattern): there is nothing below the first variation")
            XCTAssertNil(store.easierPreview(ex.pattern))
        }
    }

    /// And where it IS active it carries its RESULT: the preview names the
    /// variation the person would get, and the tap delivers that one.
    func testTheEasierHandlePreviewIsWhatTheTapDelivers() throws {
        let store = try advancedStore(variation: 3)
        let target = try XCTUnwrap(store.nextSession.exercises.first).pattern
        let preview = try XCTUnwrap(store.easierPreview(target))

        store.makeEasier(target)

        let now = try XCTUnwrap(store.nextSession.exercises.first { $0.pattern == target })
        XCTAssertEqual("\(now.name) · \(now.display)", preview,
                       "the preview promised a variation the tap did not deliver")
    }

    /// The handle goes through the ENGINE, so its landing is §40.6's and
    /// nothing else: one variation down, at the dose the JOURNAL remembers for
    /// it, on the base set count. There are no tier floors to land on any
    /// more, and no arithmetic of its own to get wrong.
    func testTheEasierHandleLandsInTheJournal() throws {
        for variation in 2...deepestVariation {
            let store = try advancedStore(variation: variation)
            for ex in store.nextSession.exercises where store.canMakeEasier(ex.pattern) {
                let p = ex.pattern
                let target = ex.variation - 1
                let journal = store.engineState.shownDose(p, variation: target)
                    ?? Dose.grid(Library.unit(p, target)).min

                let easier = Engine.easierVariation(state: store.engineState, pattern: p)

                XCTAssertEqual(easier.vars[p], target,
                               "variation \(variation) \(p): the variation must drop")
                XCTAssertEqual(easier.doses[p], journal,
                               "variation \(variation) \(p): the landing is the journal")
                XCTAssertEqual(easier.sets[p] ?? EngineConfig.setsBase, EngineConfig.setsBase,
                               "variation \(variation) \(p): the landing is on the base band")
                XCTAssertEqual(easier.sub[p] ?? 0, 0)
                XCTAssertEqual(easier.cutOf(p), 0)
            }
        }
    }
}
