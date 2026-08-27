//
//  §40.4 — the probe channel, seen from above the engine.
//
//  The probe is the only door into a new variation, and until this suite it
//  had no guard anywhere above `DredfitCore`. The engine's own fixtures cover
//  `probeAllowed` and `resolveProbe`; what nothing reached was the SEAM the
//  app owns — a plan that carries a probe, the number the flow hands back for
//  it, and what the persisted state does with that number. The audit of
//  26.08.2026 measured what a break in that seam costs: EIGHT LADDERS OUT OF
//  TEN frozen for anyone who only taps.
//
//  Everything here is driven through `AppStore`, because the app layer is the
//  unguarded one. The two rules that stay out of reach — the probe caption's
//  own wording and the technique offered during the rest before a probe —
//  live inside a SwiftUI view as `private` members and cannot be reached from
//  a unit test at all; see the note at the bottom of this file.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ProbeChannelTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-probe" }

    // MARK: - Fixtures

    /// A store seeded through the storage file — the same door the real app
    /// loads through, and the only one that catches a seed the store silently
    /// replaced with a clean start.
    ///
    /// Every pattern stands ONE RUNG BELOW its grid's ceiling, which is the
    /// position §40.4 offers no probe from, so a probe anywhere in these
    /// sessions was asked for by name. `maxed` lifts the named patterns onto
    /// the ceiling; `journal` pins what the trainee actually SHOWED there when
    /// that has to differ from the dose the plan climbed to (§41.4).
    private func seededStore(variation: [Pattern: Int] = [:],
                             maxed: Set<Pattern> = [],
                             journal: [Pattern: Int] = [:],
                             lastHard: Set<Pattern> = [],
                             hasBar: Bool = false,
                             counter: Int = 0) throws -> AppStore {
        func rung(_ p: Pattern) -> Int { min(variation[p] ?? 1, Library.count(p)) }
        func dose(_ p: Pattern) -> Int {
            let grid = Dose.grid(Library.unit(p, rung(p)))
            return maxed.contains(p) ? grid.max : grid.max - grid.step
        }
        func shownHere(_ p: Pattern) -> Int { journal[p] ?? dose(p) }
        func pairs(_ value: (Pattern) -> Int) -> String {
            Pattern.allCases.map { "\"\($0.rawValue)\",\(value($0))" }.joined(separator: ",")
        }
        // Every rung below the current one is journalled at its own ceiling: a
        // descent lands IN the journal (§40.6), and a state without one would
        // send a movement to the floor of its ladder instead of to where it
        // has actually been.
        let rows = Pattern.allCases.map { p -> String in
            let cells = (1...rung(p)).map { v -> String in
                let value = v == rung(p) ? shownHere(p) : Dose.grid(Library.unit(p, v)).max
                return "\"\(v)\":\(value)"
            }
            return "\"\(p.rawValue)\",{\(cells.joined(separator: ","))}"
        }.joined(separator: ",")
        let varsJSON = pairs(rung)
        let dosesJSON = pairs(dose)
        let zerosJSON = pairs { _ in 0 }
        let hardJSON = lastHard.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),"hasBar":\(hasBar),
                        "vars":[\(varsJSON)],"doses":[\(dosesJSON)],
                        "shown":[\(rows)],"failStreak":[\(zerosJSON)],
                        "lastHard":[\(hardJSON)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        // A state that fails to decode starts clean, and every assertion below
        // would then be true of a state nobody wrote. Position AND journal AND
        // lastHard: a clean start carries no journal at all, so checking the
        // position alone would pass whenever the seed sits on variation 1.
        XCTAssertEqual(store.engineState.position(.pull).dose, dose(.pull),
                       "the seed did not load: the pull slot is not on the dose it was written at")
        XCTAssertEqual(store.engineState.shownDose(.pull, variation: rung(.pull)), shownHere(.pull),
                       "the seed did not load: the journal of what was shown is not there")
        XCTAssertEqual(store.engineState.lastHard, lastHard,
                       "the seed did not load: \"the last answer was hard\" is not the set that was written")
        return store
    }

    private func exercise(_ pattern: Pattern, in session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == pattern },
                      "\(pattern.rawValue) must be in session \(session.sessionNumber), "
                      + "or this test is asserting about a plan that does not contain it")
    }

    // MARK: - When the plan offers a probe

    func test_session_whenBothTheDoseAndTheJournalAreOnTheCeiling_swapsTheLastSetForAProbe() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession
        let pulling = try exercise(.pull, in: session)
        let probe = try XCTUnwrap(pulling.probe,
                                  "a maxed variation with the journal to match IS the probe condition of §40.4")

        XCTAssertEqual(probe.variation, pulling.variation + 1,
                       "the probe offers the NEXT rung of the ladder, never one further up")
        XCTAssertEqual(probe.load, Dose.grid(Library.unit(.pull, probe.variation)).min,
                       "and asks for the floor of the new grid — 4 reps, or 15 s")
        XCTAssertEqual(pulling.sets, EngineConfig.setsBase - 1,
                       "the probe REPLACES a working set: the volume of the session must not grow")

        let control = try exercise(.hinge, in: session)
        XCTAssertNil(control.probe, "a movement one rung below its ceiling is offered nothing")
        XCTAssertEqual(control.sets, EngineConfig.setsBase, "and keeps every working set it had")
    }

    func test_session_whenTheJournalStopsShortOfTheCeiling_offersNoProbe() throws {
        let grid = Dose.grid(Library.unit(.pull, 1))
        let store = try seededStore(maxed: [.pull], journal: [.pull: grid.max - grid.step])
        let pulling = try exercise(.pull, in: store.nextSession)

        XCTAssertEqual(store.engineState.position(.pull).dose, grid.max,
                       "the PLAN did climb to the ceiling — the half of the old gate that still holds")
        XCTAssertNil(pulling.probe,
                     "§41.4: the gate reads the journal of what was SHOWN, and 14 against a ceiling of 15 "
                     + "is not a maxed variation — eleven probes in 75 appearances were thrown away this way")
        XCTAssertEqual(pulling.sets, EngineConfig.setsBase, "so the last set stays a working one")
    }

    func test_session_whenTheLastAnswerForThePatternWasHard_offersNoProbe() throws {
        let store = try seededStore(maxed: [.pull], lastHard: [.pull])

        XCTAssertNil(try exercise(.pull, in: store.nextSession).probe,
                     "a movement just called hard is not offered a harder one — and this cannot be read off "
                     + "failStreak, which a deload zeroes while \"hard\" does not stop having been said")
    }

    func test_session_onTheTopVariationOfTheLadder_offersNoProbe() throws {
        let store = try seededStore(variation: [.pull: Library.count(.pull)], maxed: [.pull])

        XCTAssertNil(try exercise(.pull, in: store.nextSession).probe,
                     "there is no next variation to try: growth continues in the set bands instead (§40.5)")
    }

    // MARK: - What the reported number does

    func test_probe_whenTheReportedNumberMeetsItsTarget_entersTheNextVariationAtThreeByTheFloor() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession
        let probe = try XCTUnwrap(try exercise(.pull, in: session).probe, "the fixture must carry a probe")
        let leftBehind = try XCTUnwrap(store.engineState.shownDose(.pull, variation: 1),
                                       "the seed journals the rung the probe is offered from")

        store.completeWorkout(session: session, result: .plan, probes: [.pull: probe.load])

        let after = store.engineState.position(.pull)
        XCTAssertEqual(after.variation, probe.variation,
                       "a passed probe is the door into the new variation, and the only one there is")
        XCTAssertEqual(after.dose, Dose.grid(Library.unit(.pull, probe.variation)).min,
                       "entry is always the grid floor — 3×4 (3×15 s), never the dose of the rung left behind")
        XCTAssertEqual(after.sets, EngineConfig.setsBase, "at the base set count")
        XCTAssertEqual(after.sub, 0, "with no sub-step already owed")
        XCTAssertEqual(after.cut, 0, "and nothing already cut")
        XCTAssertEqual(store.engineState.shownDose(.pull, variation: probe.variation), probe.load,
                       "what the probe showed is what the new rung's journal says")
        XCTAssertEqual(store.engineState.shownDose(.pull, variation: 1), leftBehind,
                       "and the rung left behind keeps its own number — that is where a descent lands (§40.6)")
    }

    func test_probe_whenTheReportedNumberFallsShortOfItsTarget_movesNothingButTheJournal() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession
        let probe = try XCTUnwrap(try exercise(.pull, in: session).probe, "the fixture must carry a probe")
        let before = store.engineState.position(.pull)
        // One RUNG below the target, not one unit: the number is snapped to
        // the grid on the way in, and on a hold's grid of five "one less"
        // would land back on the floor and read as a pass.
        let short = probe.load - Dose.grid(probe.unit).step

        store.completeWorkout(session: session, result: .plan, probes: [.pull: short])

        XCTAssertEqual(store.engineState.position(.pull), before,
                       "И3: a failed probe changes no coordinate. Staying on a movement you can already do "
                       + "is not a failure and is never charged for")
        XCTAssertEqual(store.engineState.shownDose(.pull, variation: probe.variation), short,
                       "what was honestly shown on the new rung is still recorded — it is a fact either way")
        XCTAssertFalse(store.engineState.lastHard.contains(.pull),
                       "and a short probe is not a \"hard\", or the gate would withhold the next probe too")
    }

    func test_probe_whenNoNumberComesBackAtAll_leavesTheOfferStandingForNextTime() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession
        let probe = try XCTUnwrap(try exercise(.pull, in: session).probe, "the fixture must carry a probe")
        let before = store.engineState.position(.pull)

        store.completeWorkout(session: session, result: .plan, probes: [:])

        XCTAssertEqual(store.engineState.position(.pull), before,
                       "a probe nobody resolved moves nothing — it is not a failed one")
        XCTAssertNil(store.engineState.shownDose(.pull, variation: probe.variation),
                     "and writes nothing down: nobody showed anything on the new rung")
        // The pull slot appears in EVERY session, which is why the assertion
        // below can ask the very next plan whether the offer still stands.
        XCTAssertNotNil(try exercise(.pull, in: store.nextSession).probe,
                        "the probe comes round again at the next appearance")
    }

    func test_probeSet_finishedByATapWithNoNumberTyped_countsAsItsTargetAndMovesTheLadder() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession
        let pulling = try exercise(.pull, in: session)
        let probe = try XCTUnwrap(pulling.probe, "the fixture must carry a probe")
        // Exactly what the flow's completeSet() hands over when the probe set
        // ends on a Done tap and nothing was typed into the adjuster (§41.2).
        let reported = SetFacts.recordingProbe([:], pulling.pattern,
                                               isProbe: true, target: probe.load)

        store.completeWorkout(session: session, result: .plan, probes: reported)

        XCTAssertEqual(store.engineState.position(.pull).variation, probe.variation,
                       "a tapped probe is a done probe: while it was not, eight ladders out of ten were "
                       + "frozen forever for anyone who only taps")
    }

    // MARK: - What a probing exercise must NOT remember

    func test_probingExercise_whenThePlanIsShown_leavesNoMemoryOfShowingForTheRungItLeaves() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession

        store.recordPlanShown(session)

        XCTAssertNil(store.engineState.shownWork[.pull],
                     "an exercise carrying a probe is one working set short of its own plan — remembering "
                     + "that as the work shown would make the next ordinary plan read as a rise and be trimmed")
        XCTAssertNil(store.engineState.shownOrd[.pull],
                     "and for the same reason no position is remembered for it either")
        XCTAssertNotNil(store.engineState.shownWork[.hinge],
                        "while an ordinary exercise in the very same plan is remembered as before")
    }

    func test_probingExercise_whenTheSessionIsRated_leavesNoMemoryOfShowingForTheRungItLeaves() throws {
        let store = try seededStore(maxed: [.pull])
        let session = store.nextSession

        store.completeWorkout(session: session, result: .plan, probes: [:])

        XCTAssertNil(store.engineState.shownWork[.pull],
                     "the rating writes the same memory as the showing does, and skips a probing exercise "
                     + "for the same reason")
        XCTAssertNotNil(store.engineState.shownWork[.hinge],
                        "while its ordinary neighbours in the session are written down")
    }

    // MARK: - What the probe puts on screen

    func test_techniqueTarget_forAProbe_pointsAtTheOfferedMovementInItsOwnUnit() throws {
        // pull_bar 2 → 3 is the one boundary in the whole library where the
        // unit changes (§40.1): seconds below it, reps above. A target that
        // took its unit from the planned exercise would read "seconds" over a
        // set of negatives, and no other rung in the library would show it.
        let store = try seededStore(variation: [.pullBar: 2], maxed: [.pullBar],
                                    hasBar: true, counter: 1)
        let barring = try exercise(.pullBar, in: store.nextSession)
        let probe = try XCTUnwrap(barring.probe, "the fixture must carry a probe")
        XCTAssertNotEqual(barring.unit, probe.unit,
                          "the fixture must straddle the unit boundary, or it proves nothing")

        let target = TechniqueTarget(probe: probe, of: barring.pattern)

        XCTAssertEqual(target.pattern, barring.pattern, "the sheet stays inside the same movement pattern")
        XCTAssertEqual(target.variation, probe.variation, "but shows the movement being OFFERED")
        XCTAssertEqual(target.unit, probe.unit, "in the unit that movement is actually trained in")
        XCTAssertNotEqual(target.id, TechniqueTarget(barring).id,
                          "and it must be a different item, or .sheet(item:) would leave the planned "
                          + "movement's sheet open when the probe's is asked for")
    }

    func test_probeDisplay_readsAsOneSetAndNeverAsAMultiplier() {
        let reps = SessionProbe(variation: 2, name: "any", unit: .reps, load: 4, perSide: false)
        let perSide = SessionProbe(variation: 2, name: "any", unit: .reps, load: 4, perSide: true)
        let hold = SessionProbe(variation: 2, name: "any", unit: .hold, load: 15, perSide: false)

        XCTAssertEqual(reps.display, "4",
                       "one set of four reps reads as the bare number — the probe is never \"N×\"")
        XCTAssertTrue(perSide.display.hasPrefix("4 "), "the per-side probe still leads with its number")
        XCTAssertNotEqual(perSide.display, reps.display,
                          "and has to say which side, or two very different sets read identically")
        XCTAssertTrue(hold.display.hasPrefix("15 "),
                      "a hold leads with its seconds and then names the unit")
        for probe in [reps, perSide, hold] {
            XCTAssertFalse(probe.display.contains("×"),
                           "\(probe.display): a probe is ONE set, so it never carries a multiplier")
        }
    }
}

// NOT COVERED HERE, and not coverable from a unit test as the code stands:
//
//  * `WorkoutFlowView.probeCaption` — the three things the probe set says
//    under its number ("one set to try it", "next time: X", "we'll stay").
//  * `WorkoutFlowView.restTechniqueTarget` — that the technique offered
//    during the rest BEFORE a probe is the probe's movement.
//
// Both are `private` members of a SwiftUI view, so `@testable import` does
// not reach them, and neither has a value-returning form. Making
// `probeCaption` an internal `var probeCaptionText: String` and
// `restTechniqueTarget` internal — the shape `headline`/`subline` were given
// in the widget after I-8 — would put both under test with no other change.
