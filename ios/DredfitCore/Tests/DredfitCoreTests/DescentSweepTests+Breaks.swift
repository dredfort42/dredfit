//
//  The fourth path of the descent sweep: what a break writes — the silent
//  decay and the comeback's landing ceiling. Kept apart from the rated and
//  handle paths only for file length; it reuses the same enumeration and
//  the same two-measure `assertDescent`.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

extension DescentSweepTests {
    // MARK: - Path 4 · what a break writes

    /// The silent decay is a descent too, and it walks `fallDoses` from
    /// whatever the person was standing on — bands and cut included.
    func test_silentDecay_fromEveryPosition_neverMakesThePlanHeavier() {
        var measured = 0
        for p in Pattern.allCases {
            let journal = fullJournal(p)
            for q in allPositions(p) {
                let after = Engine.applySilentDecay(state: seeded(p, q), gapDays: 10).position(p)
                if assertDescent(p, from: q, to: after, shown: journal,
                                 "\(describe(p, q)) decayed to \(describe(p, after))") { measured += 1 }
            }
        }
        XCTAssertGreaterThan(measured, 5000,
                             "only \(measured) cells reached the independent measure")
    }

    /// The fourth path down: on a gap that hits a row of the landing-ceiling
    /// table the comeback walks rungs and then holds the landing to the
    /// ceiling (`Breaks.swift`). A walk that ends above it is replaced by the
    /// ceiling's floor on the base band, with nothing cut; one that ends on it
    /// keeps its band and cut and drops to the floor dose. Swept from every position with a
    /// cut or a band: what the write does to somebody training on two sets,
    /// or on a band of four or five, is asserted for each of them.
    ///
    /// What `applyComeback` promises here is the CEILING, absolutely: the
    /// landing is never above `ceilVar`, and landing on `ceilVar` is always the
    /// floor of its grid, whatever the position was.
    func test_comebackLandingCeiling_fromEveryCutAndBandPosition_landsOnTheFloorOfItsVariation() {
        for p in Pattern.allCases {
            let positions = allPositions(p).filter { $0.cut > 0 || $0.sets > EngineConfig.setsBase }
            for (minGap, floorIndex) in EngineConfig.comebackLandingCeil {
                let ceiling = Engine.ceilVar(pattern: p, floorIndex: floorIndex)
                for q in positions {
                    let after = Engine.applyComeback(state: seeded(p, q), gapDays: minGap).position(p)
                    XCTAssertLessThanOrEqual(after.variation, ceiling,
                                             "\(describe(p, q)) after \(minGap) days landed above the ceiling")
                    guard after.variation == ceiling else { continue }
                    XCTAssertEqual(after.dose, Dose.grid(Library.unit(p, ceiling)).min,
                                   "\(describe(p, q)) after \(minGap) days: the ceiling must be a grid floor")
                    XCTAssertEqual(after.sub, 0, "\(describe(p, q)): a return takes the sub-step everywhere")
                }
            }
        }
    }

    /// And the return is a DESCENT, so "no heavier" binds it as well —
    /// including the gaps where the ceiling replaces the walk's landing, and
    /// including the cut and the bands.
    ///
    /// The reference's verifier runs this sweep over every position for the
    /// silent decay only; for the comeback it checks narrower things, such as
    /// a longer break never landing higher. This sweep goes further on purpose,
    /// and is no stricter rule: the engine already passes it, so it pins what
    /// the model does rather than raising a bar past it.
    func test_comeback_fromEveryCutAndBandPosition_neverMakesThePlanHeavier() {
        // Both sides of the return table: gaps before its first row walk rungs
        // only, gaps on a row also take the landing ceiling.
        let gaps = [EngineConfig.comebackMinGapDays, 30]
            + EngineConfig.comebackLandingCeil.map(\.0)
        var measured = 0
        for p in Pattern.allCases {
            let journal = fullJournal(p)
            let positions = allPositions(p).filter { $0.cut > 0 || $0.sets > EngineConfig.setsBase }
            for gap in gaps {
                for q in positions {
                    let after = Engine.applyComeback(state: seeded(p, q), gapDays: gap).position(p)
                    if assertDescent(p, from: q, to: after, shown: journal,
                                     "\(describe(p, q)) returned after \(gap) days to \(describe(p, after))") {
                        measured += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(measured, 15_000,
                             "only \(measured) cells reached the independent measure")
    }

    /// The depth of a comeback does not RISE with the length of the break.
    /// The sweep above is about two points — this plan against the last one —
    /// and a curve that dips and comes back up satisfies it at every step
    /// while breaking the card's own sentence, "the longer the break, the
    /// lower the plan meets you".
    ///
    /// A probing appearance is where it would break: with the memory written
    /// by the working sets alone, one set below the position, a descent would
    /// take the set the probe only borrowed until the dose fell far enough for
    /// three sets to fit under that base again, and the plan would jump back UP —
    /// 84 days would meet a person higher than 56. `Engine.shownWorkOf` counts
    /// the borrowed set for that reason.
    func test_comeback_afterAProbingAppearance_neverRisesWithTheLengthOfTheBreak() throws {
        let gaps = [14, 16, 18, 20, 24, 28, 35, 42, 49, 56, 63, 70, 77, 84, 95, 110, 120]
        // Every dose at the ceiling of its variation with the journal to prove
        // it — the one state that offers a probe (`probeAllowed`).
        var state = EngineState.initial
        state.counter = 11
        for p in Pattern.allCases {
            let grid = Dose.grid(Library.unit(p, 1))
            state.doses[p] = grid.max
            state.shown[p] = [1: grid.max]
        }
        let shown = Engine.generateSession(state.sanitized())
        let probing = Set(shown.exercises.filter { $0.probe != nil }.map(\.pattern))
        // Without this the sweep measures an ordinary descent and goes green
        // on a state that never exercised the rule.
        XCTAssertFalse(probing.isEmpty, "the seed produced no probing appearance")

        let played = Engine.applyFeedback(state: state.sanitized(), session: shown,
                                          result: .plan, overrides: [:], skipped: [],
                                          setsSkipped: [:], gapDays: 7.0 / 3, probes: [:])
        for p in Pattern.allCases {
            var previous = Int.max
            for gap in gaps {
                let after = Engine.applyComeback(state: played, gapDays: gap)
                guard let ex = Engine.generateSession(after).exercises
                    .first(where: { $0.pattern == p }) else { continue }
                let work = Engine.exerciseWork(ex)
                XCTAssertLessThanOrEqual(
                    work, previous,
                    "\(p.rawValue): a \(gap)-day break lands on \(work), a shorter one on \(previous)")
                previous = work
            }
        }
    }

    /// The other half of the same rule, stated on the axis the repair acts on:
    /// a descent out of a probing appearance keeps the sets the POSITION holds.
    /// The probe borrowed a set for one session; nothing about coming back
    /// says it may be kept.
    func test_comeback_afterAProbingAppearance_keepsTheSetsThePositionHolds() throws {
        var state = EngineState.initial
        state.counter = 11
        for p in Pattern.allCases {
            let grid = Dose.grid(Library.unit(p, 1))
            state.doses[p] = grid.max
            state.shown[p] = [1: grid.max]
        }
        let shown = Engine.generateSession(state.sanitized())
        XCTAssertTrue(shown.exercises.contains { $0.probe != nil },
                      "the seed produced no probing appearance")
        let played = Engine.applyFeedback(state: state.sanitized(), session: shown,
                                          result: .plan, overrides: [:], skipped: [],
                                          setsSkipped: [:], gapDays: 7.0 / 3, probes: [:])
        for gap in [14, 20, 35, 56, 84, 120] {
            let after = Engine.applyComeback(state: played, gapDays: gap).sanitized()
            for ex in Engine.generateSession(after).exercises where ex.probe == nil {
                let q = after.position(ex.pattern)
                XCTAssertEqual(ex.sets, Engine.setsAfterCut(sets: q.sets, cut: q.cut),
                               "\(ex.pattern.rawValue): \(gap) days gave \(ex.sets) sets "
                               + "against a position of \(Engine.setsAfterCut(sets: q.sets, cut: q.cut))")
            }
        }
    }

    /// The two ends of the ceiling table are fixed points: the deepest return
    /// lands on the first variation, the shallowest may stay on the top one.
    /// Without this the linear stretch in `ceilVar` could drift by one and
    /// every check above would still pass.
    func test_comebackCeilingTable_atBothEnds_spansTheWholeLadder() {
        for p in Pattern.allCases {
            XCTAssertEqual(Engine.ceilVar(pattern: p, floorIndex: 1), 1,
                           "\(p.rawValue): the deepest return lands on the first variation")
            XCTAssertEqual(Engine.ceilVar(pattern: p, floorIndex: EngineConfig.comebackCeilFloors),
                           Library.count(p),
                           "\(p.rawValue): the shallowest return may stay on the top variation")
        }
    }
}
