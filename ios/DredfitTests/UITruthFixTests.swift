//
//  Pins for the UI-truth audit fixes (27.08.2026). Each test here failed
//  against the code as it stood before its fix — the flat-load comparisons
//  that showed a plan as a fact and hid a recorded shortfall, the milestone
//  label one point short of its own tick, and the snapshot that dropped the
//  sparse coordinates the row's number includes.
//

import XCTest
import DredfitCore
@testable import Dredfit

// The app target runs under default MainActor isolation, and the types this
// touches (AppStore, RecordedPosition) inherit it — so the tests hop on.
@MainActor
final class UITruthFixTests: XCTestCase {

    /// The uneven plan every flat-load defect hid behind: 9-8-8 — base 8,
    /// one carried set.
    private func unevenExercise() -> SessionExercise {
        SessionExercise(pattern: .squat, name: "Squat", variation: 1, unit: .reps,
                        load: 8, perSide: false, sets: 3, restSetSec: 60,
                        restExerciseSec: 60, loads: [9, 8, 8], probe: nil)
    }

    // MARK: - The work screen's "actual N" (WorkoutFlowView.setActual)

    func testOffPlanIsSilentOnTheUntouchedTopSetOfAnUnevenPlan() {
        let ex = unevenExercise()
        XCTAssertNil(SetFacts.offPlan([:], ex, set: 0),
                     "nothing was entered — the planned 9 is not an actual")
        XCTAssertNil(SetFacts.offPlan([:], ex, set: 1))
    }

    func testOffPlanShowsABelowPlanEntryEqualToTheBase() {
        let ex = unevenExercise()
        let facts = SetFacts.recording(8, in: [:], ex, set: 0)
        XCTAssertEqual(SetFacts.offPlan(facts, ex, set: 0), 8,
                       "8 on a set planned at 9 is a real shortfall to accent")
    }

    // MARK: - History's guard (HistorySheet.setFacts)

    func testDiffersSeesAShortfallThatMatchesTheBaseDose() {
        let ex = unevenExercise()
        XCTAssertTrue(SetFacts.differs([8, 8, 8], from: ex),
                      "8-8-8 against a plan of 9-8-8 is not \"ran to plan\"")
        XCTAssertFalse(SetFacts.differs([9, 8, 8], from: ex))
    }

    // MARK: - The probe caption's knowable gate (§40.4)

    func testFoldBelowThePlanMeansTheProbeWillNotCount() {
        let ex = unevenExercise()
        var short = SetFacts.PerSet()
        for set in 0..<3 { short = SetFacts.recording(8, in: short, ex, set: set) }
        XCTAssertTrue(SetFacts.foldFallsShort(short, of: ex))
        // 9-8-8 done as written collapses to nothing said at all — the
        // caption may promise, and the engine will keep the promise.
        let onPlan = SetFacts.recording(9, in: [:], ex, set: 0)
        XCTAssertFalse(SetFacts.foldFallsShort(onPlan, of: ex))
    }

    // MARK: - The next-milestone label counts the crossing, not the ceiling

    func testMilestoneDistanceEqualsTheOrdinalGapToTheNextVariation() {
        for (pattern, cut) in [(Pattern.squat, 0), (.squat, 1), (.coreAntiExt, 0)] {
            var state = EngineState.initial
            let unit = Library.unit(pattern, 1)
            state.doses[pattern] = Dose.grid(unit).max - Dose.grid(unit).step
            if cut > 0 { state = Engine.setCut(state: state, pattern: pattern, cut: cut) }
            let position = state.position(pattern)
            let labelled = Engine.stepsToVariationCeiling(state, pattern) + position.cut + 1
            let entry = Engine.progress(pattern, variation: 2, sets: EngineConfig.setsBase,
                                        dose: Dose.grid(Library.unit(pattern, 2)).min)
            XCTAssertEqual(entry - Engine.progress(state, pattern), labelled,
                           "\(pattern) cut \(cut): the label must land on the next variation's own tick")
        }
    }

    // MARK: - Both sides of a per-side hold carry the same load

    func testTheFirstSideAloneDecidesHowLongTheSecondRuns() {
        // No first side yet: the plan stands.
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 30, firstSideHeld: nil), 30)
        // A first side cut short takes the second down with it.
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 30, firstSideHeld: 20), 20)
        // A first side that ran the plan changes nothing — the case every
        // completed set takes, so the rule must be invisible there.
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 30, firstSideHeld: 30), 30)
    }

    func testTheSecondSideIsNeverLongerThanThePlan() {
        // The only way a first side could report more is a plan raised between
        // the sides; equal load means the second follows the FIRST.
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 20, firstSideHeld: 45), 20)
    }

    func testAVeryShortFirstSideStillLeavesAStoppableSecond() {
        // The mis-tap grace lets a first side end at three seconds. A second
        // side of three could not be stored (the corridor floor is five) and
        // could not be stopped (every tap inside three seconds is a mis-tap),
        // so the floor is load-bearing, not decoration.
        let floor = SetFacts.corridor(for: .hold).lowerBound
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 30, firstSideHeld: 3), floor)
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 30, firstSideHeld: 4), floor)
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 30, firstSideHeld: floor), floor)
        // …and the floor never overrides a plan shorter than itself.
        XCTAssertEqual(SetFacts.holdSideSeconds(planned: 3, firstSideHeld: 3), 3)
    }

    // MARK: - The maximum-out-of-order note (owner, 27.08.2026)

    func testTheMaximumNoteFiresOnlyAboveThisSetsOwnPlan() {
        let ex = unevenExercise()                    // 9-8-8, three sets
        // Above the plan of a set that is not the last one — the case.
        XCTAssertTrue(SetFacts.maximumOutOfOrder(12, ex, set: 0))
        XCTAssertTrue(SetFacts.maximumOutOfOrder(9, ex, set: 1))
        // At or below THIS set's own plan: nothing to say. Against the flat
        // base dose the untouched top set of an uneven plan would have fired
        // it at 9, which is exactly the plan.
        XCTAssertFalse(SetFacts.maximumOutOfOrder(9, ex, set: 0))
        XCTAssertFalse(SetFacts.maximumOutOfOrder(8, ex, set: 1))
        // The last set is what the note is FOR — never flagged.
        XCTAssertFalse(SetFacts.maximumOutOfOrder(99, ex, set: 2))
    }

    /// The claim the note must NOT make. The fold is the mean, so the order of
    /// the sets does not reach the engine: a maximum first and a maximum last
    /// land the same next plan. Measured, because the note's old copy advised
    /// exactly this and the advice was not what the model does.
    func testTheOrderOfAMaximumDoesNotReachTheEngine() throws {
        var state = EngineState.initial
        state.doses[.pull] = 8
        state.shown[.pull] = [1: 8]
        let session = Engine.generateSession(state)
        let ex = try XCTUnwrap(session.exercises.first { $0.pattern == .pull })

        func nextPlan(_ sets: [Int]) throws -> String {
            var facts = SetFacts.PerSet()
            for (i, v) in sets.enumerated() { facts = SetFacts.recording(v, in: facts, ex, set: i) }
            let fold = SetFacts.override(facts, for: ex)
            let next = Engine.applyFeedback(state: state, session: session, result: .plan,
                                            overrides: fold.map { [.pull: $0] } ?? [:])
            return try XCTUnwrap(Engine.generateSession(next).exercises
                .first { $0.pattern == .pull }).display
        }
        XCTAssertEqual(try nextPlan([12, 6, 6]), try nextPlan([6, 6, 12]),
                       "same total, different order — the engine cannot tell them apart")
        XCTAssertEqual(try nextPlan([12, 8, 8]), try nextPlan([8, 8, 12]),
                       "and the same holds when the plan is held on the other sets")
        XCTAssertNotEqual(try nextPlan([12, 6, 6]), try nextPlan([8, 8, 12]),
                          "what DOES move the plan is the total, which is what the note now says")
    }

    // MARK: - §41.10/§41.11: what a descent off a probing appearance may do

    /// The state the comeback card was caught on: every pattern at the ceiling
    /// of its variation with the journal to prove it, so every one is probing.
    private func toppedOutOnEveryVariation() -> EngineState {
        var state = EngineState.initial
        state.counter = 11
        for p in Pattern.allCases {
            let target = min(3, Library.count(p))
            state.vars[p] = target
            state.doses[p] = Dose.grid(Library.unit(p, target)).max
            var journal: [Int: Int] = [:]
            for v in 1...target { journal[v] = Dose.grid(Library.unit(p, v)).max }
            state.shown[p] = journal
        }
        return state
    }

    private func work(_ ex: SessionExercise) -> Int {
        ex.plannedVolume * (ex.perSide ? 2 : 1)
    }

    /// The bound is the plan the POSITION holds, not the working sets that
    /// happened to be on screen while the probe borrowed one of them (§41.11).
    /// Against the working sets this asserted that a descent must come back as
    /// TWO sets, which is exactly how the borrowed slot was being kept.
    func testADescentNeverAsksMoreThanThePlanThePositionHolds() throws {
        let state = toppedOutOnEveryVariation()
        // What Today records the moment it draws the plan.
        let shown = Engine.recordShown(state: state, session: Engine.generateSession(state))
        var held: [Pattern: Int] = [:]
        for ex in Engine.generateSession(shown).exercises where ex.probe != nil {
            held[ex.pattern] = (ex.plannedVolume + ex.load) * (ex.perSide ? 2 : 1)
        }
        XCTAssertFalse(held.isEmpty, "the seed must actually be probing")

        var descents: [(String, EngineState)] = [
            ("silent decay", Engine.applySilentDecay(state: shown, gapDays: 10)),
        ]
        for gap in [14, 35, 56, 77, 119] {
            descents.append(("comeback gap \(gap)", Engine.applyComeback(state: shown, gapDays: gap)))
        }
        for (label, after) in descents {
            for ex in Engine.generateSession(after).exercises {
                guard let before = held[ex.pattern] else { continue }
                XCTAssertLessThanOrEqual(
                    work(ex), before,
                    "\(label): \(ex.pattern) asks \(work(ex)) against the \(before) the position holds")
            }
        }
    }

    /// And the promise the comeback card makes in words: the longer the break,
    /// the lower the plan meets you. It broke on exactly this state — 84 days
    /// met a person higher than 56 — because the trim stopped firing once the
    /// dose had fallen far enough for three sets to fit under the depressed
    /// base again.
    func testAComebackNeverRisesWithTheLengthOfTheBreak() throws {
        let shown = Engine.recordShown(state: toppedOutOnEveryVariation(),
                                       session: Engine.generateSession(toppedOutOnEveryVariation()))
        XCTAssertTrue(Engine.generateSession(shown).exercises.contains { $0.probe != nil },
                      "the seed must actually be probing")
        for p in Pattern.allCases {
            var previous = Int.max
            for gap in [14, 20, 28, 35, 42, 56, 70, 77, 84, 95, 110, 119] {
                let after = Engine.applyComeback(state: shown, gapDays: gap)
                guard let ex = Engine.generateSession(after).exercises
                    .first(where: { $0.pattern == p }) else { continue }
                XCTAssertLessThanOrEqual(
                    work(ex), previous,
                    "\(p.rawValue): \(gap) days lands on \(work(ex)), a shorter break on \(previous)")
                previous = work(ex)
            }
        }
    }

    /// The memory itself — the root the sweeps above stand on.
    func testAProbingAppearanceRecordsThePlanWithoutItsProbe() throws {
        let state = toppedOutOnEveryVariation()
        let session = Engine.generateSession(state)
        let probing = try XCTUnwrap(session.exercises.first { $0.probe != nil })
        let shown = Engine.recordShown(state: state, session: session)
        XCTAssertEqual(shown.shownWork[probing.pattern],
                       (probing.plannedVolume + probing.load) * (probing.perSide ? 2 : 1),
                       "the borrowed set is counted back in, not written off")
        XCTAssertGreaterThan(try XCTUnwrap(shown.shownWork[probing.pattern]), work(probing),
                             "which is strictly more than the working sets alone")
    }

    // MARK: - The snapshot carries the sparse coordinates into the chart

    func testProgressOverloadReadsSubAndCut() {
        XCTAssertEqual(Engine.progress(.squat, variation: 1, sets: 3, dose: 8, sub: 2, cut: 0),
                       Engine.progress(.squat, variation: 1, sets: 3, dose: 8) + 2)
        XCTAssertEqual(Engine.progress(.squat, variation: 1, sets: 3, dose: 8, sub: 0, cut: 1),
                       Engine.progress(.squat, variation: 1, sets: 3, dose: 8) - 1)
    }

    func testRecordedPositionKeepsTheSparseCoordinatesSparse() throws {
        var state = EngineState.initial
        state.doses[.squat] = 8
        state.sub[.squat] = 1
        let recorded = try XCTUnwrap(AppStore.positions(of: state)[.squat])
        XCTAssertEqual(recorded.sub, 1)
        XCTAssertNil(recorded.cut, "a zero coordinate stays sparse, like the state")

        // A record written before the fields existed decodes without them —
        // and one written with nils re-encodes to the same shape.
        let legacy = Data(#"{"variation":3,"sets":3,"dose":11}"#.utf8)
        let decoded = try JSONDecoder().decode(RecordedPosition.self, from: legacy)
        XCTAssertNil(decoded.sub)
        XCTAssertNil(decoded.cut)
        let reencoded = try JSONDecoder().decode(
            RecordedPosition.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reencoded, decoded)
    }
}
