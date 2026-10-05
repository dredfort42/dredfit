//
//  What the person reads about the pull cap's two newer rules. A push whose
//  next set band waits for the pulls says so on its Progress row instead of
//  counting steps to a set the pulls decide; it lost nothing, and nothing on
//  Today says it did. A push the cap releases gets the line the cap's return
//  already had: "A set is back." — over a card that carries the stamp of the
//  hold, and only over such a card.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class PushGateSignalsTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-push-gate" }

    /// The pull slot and both pushes on their top variations, where sets come
    /// in bands. The pull stands at its dose floor, so it crosses no band of
    /// its own while a test reads it; the pushes stand on their dose ceiling,
    /// where their next growth is the band above.
    private func seed(pullSets: Int, pushSets: Int, barSets: Int? = nil) -> EngineState {
        var seed = EngineState.initial
        func put(_ p: Pattern, sets: Int, ceiling: Bool) {
            let top = Library.count(p)
            let grid = Dose.grid(Library.unit(p, top))
            seed.vars[p] = top
            seed.sets[p] = sets == EngineConfig.setsBase ? nil : sets
            seed.doses[p] = ceiling ? grid.max : grid.min
            seed.shown[p] = [top: seed.doses[p] ?? grid.min]
        }
        put(.pull, sets: pullSets, ceiling: false)
        if let barSets {
            seed.hasBar = true
            put(.pullBar, sets: barSets, ceiling: false)
        }
        put(.pushH, sets: pushSets, ceiling: true)
        put(.pushV, sets: pushSets, ceiling: true)
        return seed
    }

    private func launch(_ state: EngineState, records: [WorkoutRecord] = []) throws -> AppStore {
        try JSONEncoder().encode(AppData(engineState: state, records: records, settings: AppSettings()))
            .write(to: tempURL)
        let store = makeStore()
        XCTAssertEqual(store.engineState, state,
                       "the seed did not load — everything below would be about a clean start")
        return store
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    /// One workout on plan every two days, the plan as Today shows it.
    private func train(_ store: AppStore, setsSkipped: SetFacts.Skips = [:]) {
        let session = store.nextSession
        store.recordPlanShown(session)
        store.completeWorkout(session: session, result: .plan, setsSkipped: setsSkipped,
                              date: day(-300 + 2 * store.records.count))
    }

    private func row(_ p: Pattern, _ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == p },
                      "this workout must carry \(p) — the rotation moved")
    }

    // MARK: - The Progress row

    func testAPushOnItsCeilingBehindThePullsWaitsForThem() throws {
        let store = try launch(seed(pullSets: 3, pushSets: 3))
        XCTAssertTrue(store.nextSetWaitsForThePulls(.pushH),
                      "band 4 needs a pull on four sets: no count of steps says when that comes")
        XCTAssertTrue(store.nextSetWaitsForThePulls(.pushV))
        XCTAssertFalse(store.nextSetWaitsForThePulls(.pull), "nothing caps the pull itself")
    }

    func testAPullOnTheBandsSetsBringsTheCountdownBack() throws {
        let store = try launch(seed(pullSets: 4, pushSets: 3))
        XCTAssertFalse(store.nextSetWaitsForThePulls(.pushH),
                       "the pull already shows four: the push's set is a matter of its own steps")
    }

    /// With the bar on, the cap is the weaker branch, and that is the one that
    /// decides whether the band waits.
    func testWithTheBarTheWeakerBranchKeepsThePushWaiting() throws {
        let store = try launch(seed(pullSets: 4, pushSets: 3, barSets: 3))
        XCTAssertTrue(store.nextSetWaitsForThePulls(.pushH),
                      "the bar stands on three, and the push enters band 4 behind the weaker branch")
    }

    /// The band is what waits, not the sets on screen: a push on band 4 with
    /// a set taken off shows three, and its next set is band 5.
    func testTheBandWaitsNotTheSetsOnScreen() throws {
        var state = seed(pullSets: 4, pushSets: 4)
        state.cut[.pushH] = 1
        let store = try launch(state)
        XCTAssertTrue(store.nextSetWaitsForThePulls(.pushH),
                      "band 5 needs a pull on five, whatever the push shows today")
    }

    func testOnlyAPushBelowTheTopBandOfItsTopVariationWaits() throws {
        var below = seed(pullSets: 3, pushSets: 3)
        below.vars[.pushH] = Library.count(.pushH) - 1
        below.doses[.pushH] = Dose.grid(Library.unit(.pushH, Library.count(.pushH) - 1)).max
        let store = try launch(below)
        XCTAssertFalse(store.nextSetWaitsForThePulls(.pushH),
                       "below the top variation the next milestone is a probe, which nothing caps")

        let full = try launch(seed(pullSets: 3, pushSets: 5))
        XCTAssertFalse(full.nextSetWaitsForThePulls(.pushV), "at five sets there is no next set to wait for")
    }

    // MARK: - Today, through the pull cap's lines

    /// The push on its ceiling meets a pull on three and parks: it shows the
    /// three sets it showed last time. Nothing was taken off, so no line says
    /// the pulls held it back — the Progress row is where the wait is named.
    func testAParkedPushSaysNothingAboutFewerSets() throws {
        let store = try launch(seed(pullSets: 3, pushSets: 3))
        train(store)
        let vertical = try row(.pushV, store.nextSession)
        XCTAssertEqual(store.engineState.position(.pushV).sets, 3, "the push parked on band 3")
        XCTAssertEqual(vertical.sets, 3, "and shows the three sets it showed last time")
        XCTAssertFalse(store.setsJustHeldBackByThePulls(in: vertical), "nothing was taken off")
        XCTAssertFalse(store.aSetJustCameBack(in: vertical))
        XCTAssertTrue(store.nextSetWaitsForThePulls(.pushV), "its next set still waits for the pulls")
    }

    /// Both pushes on 5×15 and a pull set skipped: the vertical push shows four
    /// while the pull does, and the card that showed four carries the stamp.
    /// Once the pull has its set back, the push stands where it stood — and it
    /// gets the fifth set back, with the line the cap's return has.
    func testAFrozenPushTheCapReleasesSaysASetIsBack() throws {
        let store = try launch(seed(pullSets: 5, pushSets: 5))
        var shown: [Int] = []
        var cameBack: [Bool] = []
        for k in 0..<4 {
            let session = store.nextSession
            if let vertical = session.exercises.first(where: { $0.pattern == .pushV }) {
                shown.append(vertical.sets)
                cameBack.append(store.aSetJustCameBack(in: vertical))
            }
            train(store, setsSkipped: k == 0 ? [.pull: 1] : [:])
        }
        XCTAssertEqual(shown, [5, 4, 5], "capped once while the pull showed four, then released")
        XCTAssertEqual(cameBack, [false, false, true], "the released set is announced, once")
    }

    /// The first plan after the update releases a push the build before had
    /// frozen. Whether the person reads "A set is back." depends on the card
    /// the push last showed: a card from a build that stamped the hold says
    /// it, and a card from before the stamp claims nothing.
    func testTheReleaseAfterTheUpdateIsAnnouncedOnlyOverAStampedCard() throws {
        let before = try launch(seed(pullSets: 4, pushSets: 5))
        train(before)
        let record = try XCTUnwrap(before.records.last)
        XCTAssertEqual(try XCTUnwrap(record.exercises?.first { $0.pattern == .pushV }).sets, 4,
                       "the pull on four held the push at four")
        XCTAssertEqual(record.heldBack, [.pushH, .pushV], "and the card carries the stamp")

        // The state a build without the cap memory left: the pull has its
        // fifth set since, and nothing says what the pushes were capped at.
        var legacy = before.engineState
        legacy.sets[.pull] = 5
        legacy.shownCap = [:]
        legacy.shownOwn = [:]
        legacy.shownSkip = []

        let stamped = try launch(legacy, records: [record])
        let released = try row(.pushV, stamped.nextSession)
        XCTAssertEqual(released.sets, 5, "the update hands the frozen push its fifth set back")
        XCTAssertTrue(stamped.aSetJustCameBack(in: released), "over a stamped card the release is announced")

        var unstamped = record
        unstamped.heldBack = nil
        let older = try launch(legacy, records: [unstamped])
        XCTAssertEqual(try row(.pushV, older.nextSession).sets, 5)
        XCTAssertFalse(older.aSetJustCameBack(in: try row(.pushV, older.nextSession)),
                       "a card from before the stamp claims nothing, so the set returns without a word")
    }
}
