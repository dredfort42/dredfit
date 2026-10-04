//
//  A set the cross-credit gives back, announced on the row of a movement
//  that did not train. An extension rather than more of `SetsNoticeTests`:
//  one more test would take the class's file past the linter's 600-line
//  warning.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
extension SetsNoticeTests {

    /// The pull slot's two branches share their gains, so a set can come back
    /// on a movement that did not train: the credit hands the bar a set and
    /// arms its hold, as the bar's own return would. The card the person last
    /// saw for the bar carried one set fewer, so its row has to say so.
    func testASetTheCreditGivesBackIsAnnouncedOnItsRow() throws {
        var seed = EngineState.initial
        seed.hasBar = true
        seed.counter = 1
        seed.vars[.pull] = 4
        seed.doses[.pull] = 8
        seed.shown[.pull] = [4: 8]
        seed.vars[.pullBar] = 7
        seed.sets[.pullBar] = 5
        seed.doses[.pullBar] = 9
        seed.cut[.pullBar] = 3
        seed.setsHold[.pullBar] = 1
        seed.shown[.pullBar] = [6: 15, 7: 15]
        try JSONEncoder().encode(AppData(engineState: seed, records: [], settings: AppSettings()))
            .write(to: tempURL)
        let store = makeStore()
        XCTAssertEqual(store.engineState, seed,
                       "the seed did not load — everything below would be about a clean start")

        train(store)
        let card = try XCTUnwrap(store.records.last?.exercises?.first { $0.pattern == .pullBar },
                                 "an odd counter puts the bar in this workout — its card is what the row is read against")
        XCTAssertEqual(card.sets, 2, "the bar's card must be journalled with the set still off")
        XCTAssertNil(store.engineState.setsHold[.pullBar],
                     "the bar's own appearance must spend the hold without giving the set back — "
                        + "otherwise the line would be that appearance's, not the credit's")

        let crediting = train(store)
        XCTAssertEqual(crediting.exercises.map(\.pattern).filter { Pattern.pullSide.contains($0) }, [.pull],
                       "the workout that credits the bar must train the row — the bar sits it out")
        XCTAssertEqual(store.engineState.cutOf(.pullBar), 2,
                       "the credit must give the bar its set back — that return is what the row announces")
        XCTAssertEqual(store.engineState.setsHold[.pullBar], EngineConfig.setsBackHold,
                       "the credit's set return must arm the bar's hold — the hold is what the row reads")

        let row = try XCTUnwrap(store.nextSession.exercises.first { $0.pattern == .pullBar },
                                "the next workout's pull slot is the bar again")
        XCTAssertEqual(row.sets, 3,
                       "the row must show the set the credit gave back — a line about a set it does not show is false")
        XCTAssertTrue(store.aSetJustCameBack(in: row),
                      "a set the credit gave back reached the row without a word")
    }
}
