//
//  И4 (§40.9) swept the way the reference sweeps it: every position of every
//  ladder, through every path a descent can take.
//
//  WHY THIS FILE EXISTS. `EngineTests` carried a sweep that called itself
//  exhaustive — "every variation and every rung of every ladder" — while
//  building its starting position exactly one way: base band, `cut 0`,
//  `sub 0`. Everything §40.5 (bands 4 and 5), §36 (the cut) and §33 (the
//  sub-step) add to a position was outside it, and so were three of the four
//  ways down. Block 13 of `verify2.js` does sweep all of them; this file is
//  that block ported, and the sweep is deliberately driven by an enumeration
//  of positions rather than by one hand-written start.
//
//  The four paths: `fallBy` (a rated descent), `fallDoses` (whole rungs — the
//  deload, the decay, the comeback), `easierPosition` (the handle), and the
//  direct write in the comeback's landing ceiling (`Breaks.swift`).
//
//  TWO MEASURES, ON PURPOSE. Every "no heavier" below is asserted twice: once
//  through `Engine.noHarder`, and once through `Work` — a measure this file
//  computes itself out of the position and the catalog. The second is not a
//  belt-and-braces duplicate of the first: on a landing it is the ONLY one of
//  the two that can fail. `Work` carries the mutation that proved it.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

/// §41.6 item 1: the closed list of boundaries where "no heavier" is
/// structurally unreachable — the variation below is trained per side, or in
/// other units, and even its lightest plan outweighs two sets of the one
/// above. Keyed by the UPPER variation of the crossing, exactly as
/// `IMPOSSIBLE_LANDINGS` in `verify2.js` is.
///
/// The list is closed and named by number. Widening it silently is not
/// allowed: every line of it is an accepted gap of the spec, not a threshold.
private enum AcceptedGap {

    ///   hinge 4→3     sliding leg curl (two legs) → one-leg glute bridge   ×2.00
    ///   hinge 7→6     assisted nordic curl        → one-leg sliding curl   ×2.00
    ///   pull_bar 3→2  negatives (reps)            → scapular hang (s)      ×1.50
    static let landings: [DredfitCore.Pattern: Set<Int>] = [.hinge: [4, 7], .pullBar: [3]]

    /// How much heavier an accepted gap may land when the independent measure
    /// CAN see it — measured over all four paths and every position of every
    /// ladder on 26.08.2026, and reached exactly: 3×4 on two legs (12) → 3×4
    /// per side (24) on both hinge gaps. Flat, not per boundary: a descent
    /// that crosses both hinge gaps at once (7 → 1) only reaches ×1.50.
    ///
    /// An accepted gap is therefore BOUNDED here rather than skipped. §41.6 is
    /// a list of accepted numbers, not a licence, and a `continue` on those
    /// cells would turn a closed list of three into a hole.
    static let factor = 2

    static func closes(_ p: DredfitCore.Pattern, leaving v: Int) -> Bool {
        landings[p]?.contains(v) ?? false
    }

    /// True when a descent from `from` to `to` steps over any of them.
    static func crossed(_ p: DredfitCore.Pattern, from: Int, to: Int) -> Bool {
        let lo = Swift.min(from, to) + 1, hi = Swift.max(from, to)
        guard lo <= hi else { return false }             // no boundary was crossed at all
        return (lo...hi).contains { closes(p, leaving: $0) }
    }
}

/// The one thing the independent measure below is NOT allowed to look at: the
/// single boundary in the library where a ladder changes units — pull_bar v3
/// (negatives, in reps) → v2 (scapular hang, in seconds). Reps and seconds are
/// not commensurable, the spec defines no conversion between them (§40.1,
/// §40.10 п. 3), and the ×3.75 the raw numbers give across that step is an
/// artefact of the two grids rather than a measure of work.
///
/// Listed by number and pinned against the catalog by
/// `test_theUnitCrossings_areTheOneBoundaryTheCatalogHas`, because an
/// exclusion that widens on its own is how a sweep goes quiet. Keyed by the
/// UPPER variation, as `AcceptedGap` is.
private enum UnitCrossing {

    static let boundaries: [DredfitCore.Pattern: Set<Int>] = [.pullBar: [3]]

    static func crossed(_ p: DredfitCore.Pattern, from: Int, to: Int) -> Bool {
        let lo = Swift.min(from, to) + 1, hi = Swift.max(from, to)
        guard lo <= hi else { return false }
        return (lo...hi).contains { boundaries[p]?.contains($0) ?? false }
    }
}

/// THE INDEPENDENT MEASURE — the work a plan costs, computed here instead of
/// asked of the engine.
///
/// WHY THE DUPLICATED ARITHMETIC IS DELIBERATE. `Engine.landInVar` searches
/// for its landing under `planLoad(...).total <= budget`, starts that search
/// at the journal's ceiling and only ever walks DOWN, and writes
/// `sets: setsBase` into every landing it returns. `Engine.noHarder` then
/// checks those same three facts — `b.total <= a.total`, `b.load <= journal`,
/// `b.sets <= setsBase` — with the same `Engine.planLoad`. On any landing that
/// came out of `landInVar` the postcondition is therefore true BY
/// CONSTRUCTION, whatever `planLoad` and `landInVar` actually compute.
///
/// Established by mutation on 26.08.2026: halving `total` in `Engine.planLoad`
/// for one pattern and one variation (`.squat`, variation 2) left all 13 tests
/// of this file GREEN, while `GoldenTests` went to 110 failures and
/// `EngineV3Tests.testFactBelowTheFloorLandsNoHeavier` to one. The engine's
/// behaviour had changed on 110 recorded cells and the sweep that calls itself
/// exhaustive said nothing at all.
///
/// So this must NOT be "simplified" back into `Engine.planLoad`: routing both
/// sides of the comparison through the function under test is exactly the
/// tautology. What the measure deliberately does not do is second-guess the
/// MODEL — it is the same quantity §41.1 names (sets × dose × sides), taken
/// from the other side of the boundary between the test and the code.
private enum Work {

    /// Sets, doses and sides straight off the position and the catalog: the
    /// plan as the athlete performs it, set by set.
    ///
    /// Deliberately does not `fit` its argument — a landing is measured
    /// exactly as it was written, not as the sanitizer would rewrite it.
    static func of(_ p: DredfitCore.Pattern, _ q: Position) -> Int {
        let sets = Swift.max(EngineConfig.setsFloor, q.sets - Swift.max(0, q.cut))
        let grid = Dose.grid(Library.unit(p, q.variation))
        // The sub-step is off on the top rung of a grid (§33) and never asks
        // for more sets than the cut left standing (v2.25, Ф5).
        let carrying = q.dose >= grid.max ? 0 : Swift.min(Swift.max(q.sub, 0), Swift.max(0, sets - 1))
        return (0..<sets).map { $0 < carrying ? q.dose + grid.step : q.dose }
            .reduce(0, +) * Library.sides(p, q.variation)
    }
}

final class DescentSweepTests: XCTestCase {

    // MARK: - The domain of the sweep

    /// Every position of a pattern that `fit` accepts as its own — the input
    /// of the reference's `allPositions`. Doses BELOW a band's entry are in on
    /// purpose: a descent lands there, and that is where the A3-1 defects of
    /// v2 lived. The round-trip filter keeps a position `fit` would rewrite (a
    /// band on a non-top variation, a sub-step wider than the sets left
    /// standing) out of the sweep, so a failure means "wrong", never "illegal".
    private func allPositions(_ p: Pattern) -> [Position] {
        var out: [Position] = []
        for v in 1...Library.count(p) {
            let unit = Library.unit(p, v)
            let bands = Library.isTop(p, v)
                ? Array(EngineConfig.setsBase...EngineConfig.setsMax)
                : [EngineConfig.setsBase]
            for sets in bands {
                for rung in 0..<Dose.rungCount(unit) {
                    for sub in 0..<sets {
                        for cut in 0...Engine.cutMax(sets: sets) {
                            let raw = Position(variation: v, sets: sets,
                                               dose: Dose.dose(unit, atRung: rung),
                                               sub: sub, cut: cut)
                            let q = Engine.fit(p, raw)
                            if q.sub == sub, q.cut == cut { out.append(q) }
                        }
                    }
                }
            }
        }
        return out
    }

    /// "The ceiling was shown in every variation" — the most generous journal
    /// there is, and therefore the worst case for every "no heavier" check:
    /// the landing has the largest possible ceiling to walk down from.
    private func fullJournal(_ p: Pattern) -> [Pattern: [Int: Int]] {
        var row: [Int: Int] = [:]
        for v in 1...Library.count(p) { row[v] = Dose.grid(Library.unit(p, v)).max }
        return [p: row]
    }

    private func describe(_ p: Pattern, _ q: Position) -> String {
        "\(p.rawValue) v\(q.variation) \(q.sets)×\(q.dose) sub \(q.sub) cut \(q.cut)"
    }

    /// One pattern moved to `q`, everything else fresh, journal at the ceiling.
    private func seeded(_ p: Pattern, _ q: Position) -> EngineState {
        var s = EngineState.initial
        s.vars[p] = q.variation
        s.doses[p] = q.dose
        if q.sets != EngineConfig.setsBase { s.sets[p] = q.sets }
        if q.sub > 0 { s.sub[p] = q.sub }
        if q.cut > 0 { s.cut[p] = q.cut }
        s.shown = fullJournal(p)
        return s
    }

    // MARK: - И4 on one transition, by both measures

    /// The independent measure first, then the engine's own postcondition.
    ///
    /// The two are asserted on different domains, and that asymmetry is the
    /// whole point (see `Work`):
    ///
    ///   • `Work` runs everywhere the quantities are commensurable, accepted
    ///     gaps included — bounded there by `AcceptedGap.factor` instead of
    ///     waved through — and steps aside only at the unit boundary, where
    ///     the model itself declines to define a measure;
    ///   • `Engine.noHarder` keeps the domain §41.6 item 1 leaves it, and adds
    ///     the one thing `Work` cannot see: that the landing is inside the
    ///     JOURNAL of what was shown.
    ///
    /// Returns whether the independent measure actually ran on this cell, so a
    /// sweep can assert that its own exclusions did not quietly eat it.
    private func assertDescent(_ p: Pattern, from: Position, to: Position,
                               shown: [Pattern: [Int: Int]],
                               _ what: @autoclosure () -> String,
                               file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let gap = AcceptedGap.crossed(p, from: from.variation, to: to.variation)
        let measurable = !UnitCrossing.crossed(p, from: from.variation, to: to.variation)
        if measurable {
            let before = Work.of(p, from), after = Work.of(p, to)
            XCTAssertLessThanOrEqual(after, gap ? AcceptedGap.factor * before : before,
                                     "\(what()): work \(before) → \(after)"
                                     + (gap ? ", past the ×\(AcceptedGap.factor) §41.6 item 1 accepts" : ""),
                                     file: file, line: line)
        }
        if !gap {
            XCTAssertTrue(Engine.noHarder(p, from: from, to: to, shown: shown),
                          "\(what()): the engine's own postcondition rejects it",
                          file: file, line: line)
        }
        return measurable
    }

    // MARK: - The sweep's own guard

    /// Every check below is only as complete as this enumeration, and an
    /// enumeration that quietly loses an axis reads as "greener than before" —
    /// which is exactly how the one-shaped sweep it replaces could claim to
    /// cover "every rung of every ladder" while covering one band, one cut and
    /// one sub-step.
    func test_positionDomain_overEveryLadder_reachesBothBandsTheCutAndTheSubStep() {
        var bands: Set<Int> = []
        var withCut = 0, withSub = 0, belowBandEntry = 0, total = 0
        for p in Pattern.allCases {
            for q in allPositions(p) {
                total += 1
                bands.insert(q.sets)
                if q.cut > 0 { withCut += 1 }
                if q.sub > 0 { withSub += 1 }
                let entry = Engine.bandStartDose(Library.unit(p, q.variation), sets: q.sets)
                if q.sets > EngineConfig.setsBase, q.dose < entry { belowBandEntry += 1 }
                XCTAssertGreaterThanOrEqual(Engine.setsAfterCut(sets: q.sets, cut: q.cut),
                                            EngineConfig.setsFloor,
                                            "\(describe(p, q)) is below the shared floor of sets")
            }
        }
        XCTAssertEqual(bands, Set(EngineConfig.setsBase...EngineConfig.setsMax),
                       "§40.5: bands 4 and 5 must be in the domain, on the top variation")
        XCTAssertGreaterThan(withCut, 0, "§36: the cut axis must be in the domain")
        XCTAssertGreaterThan(withSub, 0, "§33: the sub-step must be in the domain")
        XCTAssertGreaterThan(belowBandEntry, 0,
                             "doses below a band's entry must be in the domain — a descent lands there")
        XCTAssertGreaterThan(total, 1000, "the domain must be the ladders, not a handful of cells")
    }

    /// The independent measure has exactly one blind spot, and it is pinned to
    /// the catalog rather than trusted: the library changes units ONCE, at
    /// pull_bar v3 → v2. A ladder that grew a second unit boundary would
    /// silently widen the skip in `assertDescent` and take a slice of И4 out of
    /// the sweep with it — so a new one has to be a decision here, in writing.
    func test_theUnitCrossings_areTheOneBoundaryTheCatalogHas() {
        var found: [Pattern: Set<Int>] = [:]
        for p in Pattern.allCases {
            for v in 2...Library.count(p) where Library.unit(p, v) != Library.unit(p, v - 1) {
                found[p, default: []].insert(v)
            }
        }
        XCTAssertEqual(found, UnitCrossing.boundaries,
                       "a unit boundary needs a measure before it needs a skip")
        XCTAssertEqual(Library.unit(.pullBar, 3), .reps, "pull_bar v3 is counted in reps")
        XCTAssertEqual(Library.unit(.pullBar, 2), .hold, "pull_bar v2 is counted in seconds")
    }

    /// Bands are a property of the TOP variation and of nothing else (§40.5).
    /// Asserted on the domain rather than on `setsCeil`, because a sweep that
    /// silently enumerated a band on a mid-ladder variation would spend its
    /// whole run on positions the engine can never hold.
    func test_setBands_onEveryVariationBelowTheTop_collapseToTheBase() {
        for p in Pattern.allCases {
            for v in 1...Library.count(p) where !Library.isTop(p, v) {
                let raw = Position(variation: v, sets: EngineConfig.setsMax,
                                   dose: Dose.grid(Library.unit(p, v)).min, sub: 0, cut: 0)
                XCTAssertEqual(Engine.fit(p, raw).sets, EngineConfig.setsBase,
                               "\(p.rawValue) v\(v): a band may only stand on the top variation")
            }
            XCTAssertEqual(Engine.setsCeil(p, Library.count(p)), EngineConfig.setsMax,
                           "\(p.rawValue): the top variation carries the bands")
        }
    }

    // MARK: - Path 1 · `fallBy`, the rated descent

    /// И4 over the WHOLE domain. A single step is the unit of the invariant;
    /// several in a row are swept too, because a landing composes with the
    /// steps that follow it and the composition is where a band boundary can
    /// hide (class A3-1, §36.8).
    func test_fallBy_fromEveryPositionOfEveryLadder_neverMakesThePlanHeavier() {
        var measured = 0
        for p in Pattern.allCases {
            let journal = fullJournal(p)
            for q in allPositions(p) {
                for steps in 1...4 {
                    let to = Engine.fallBy(p, q, steps, shown: journal)
                    if assertDescent(p, from: q, to: to, shown: journal,
                                     "\(describe(p, q)) − \(steps) → \(describe(p, to))") { measured += 1 }
                }
            }
        }
        // 21 631 cells on 26.08.2026. The floor is loose on purpose: it guards
        // against an exclusion eating the sweep, not against a ladder growing.
        XCTAssertGreaterThan(measured, 20_000,
                             "only \(measured) cells reached the independent measure")
    }

    /// A descent may not cross a band DOWNWARD: (4,11) → (3,15) carries one
    /// less set and a HIGHER dose per set, which is the defect the gate was
    /// written for. Volume inside a band comes off through the cut instead.
    func test_fallBy_insideABand_takesVolumeThroughTheCutAndNeverRaisesTheDose() {
        for p in Pattern.allCases {
            let journal = fullJournal(p)
            for q in allPositions(p) where q.sets > EngineConfig.setsBase {
                let to = Engine.fallBy(p, q, 1, shown: journal)
                guard to.variation == q.variation else { continue }
                XCTAssertLessThanOrEqual(to.sets, q.sets,
                                         "\(describe(p, q)): a descent may not add a band")
                XCTAssertLessThanOrEqual(to.dose, q.dose,
                                         "\(describe(p, q)) → \(describe(p, to)): dose per set rose")
            }
        }
    }

    // MARK: - Path 2 · `fallDoses`, whole rungs

    /// The path the deload, the silent decay and the comeback all walk. It
    /// zeroes the sub-step and therefore reaches cells `fallBy` never sees
    /// from the same start.
    func test_fallDoses_fromEveryPositionOfEveryLadder_neverMakesThePlanHeavier() {
        var measured = 0
        for p in Pattern.allCases {
            let journal = fullJournal(p)
            for q in allPositions(p) {
                for steps in 1...4 {
                    let to = Engine.fallDoses(p, q, steps, shown: journal)
                    if assertDescent(p, from: q, to: to, shown: journal,
                                     "\(describe(p, q)) − \(steps) rungs → \(describe(p, to))") { measured += 1 }
                }
            }
        }
        XCTAssertGreaterThan(measured, 20_000,             // 21 479 on 26.08.2026
                             "only \(measured) cells reached the independent measure")
    }

    // MARK: - Path 3 · the handle "give me something easier"

    /// §40.6 and §41.1 through the handle, from every position and not only
    /// from the floor of a variation: the handle carries the CUT across the
    /// boundary, so a person on two sets is the case that has to be swept.
    func test_easierPosition_fromEveryPositionAboveTheFirst_landsInsideTheJournalAndNoHeavier() throws {
        var measured = 0
        for p in Pattern.allCases {
            let journal = fullJournal(p)
            for q in allPositions(p) where q.variation > 1 {
                let to = try XCTUnwrap(Engine.easierPosition(pattern: p, position: q, shown: journal),
                                       "\(describe(p, q)): the handle must act above the first variation")
                let grid = Dose.grid(Library.unit(p, to.variation))
                XCTAssertEqual(to.variation, q.variation - 1,
                               "\(describe(p, q)): the handle steps exactly one variation down")
                XCTAssertLessThanOrEqual(to.dose, Engine.landingDose(p, to.variation, shown: journal),
                                         "\(describe(p, q)) → \(describe(p, to)): above what was shown there")
                XCTAssertGreaterThanOrEqual(to.dose, grid.min,
                                            "\(describe(p, q)) → \(describe(p, to)): below the grid floor")
                XCTAssertEqual(to.sets, EngineConfig.setsBase,
                               "\(describe(p, q)) → \(describe(p, to)): a landing is in the base band")
                if assertDescent(p, from: q, to: to, shown: journal,
                                 "\(describe(p, q)) → \(describe(p, to)), a handle labelled easier") {
                    measured += 1
                }
            }
        }
        XCTAssertGreaterThan(measured, 4000,               // 4507 on 26.08.2026
                             "only \(measured) cells reached the independent measure")
    }

    /// On the first variation the handle is inert for EVERY pattern: there is
    /// nothing below it in the library (§37.1).
    func test_easierPosition_onTheFirstVariationOfEveryLadder_isInert() {
        for p in Pattern.allCases {
            for q in allPositions(p) where q.variation == 1 {
                XCTAssertNil(Engine.easierPosition(pattern: p, position: q, shown: fullJournal(p)),
                             "\(describe(p, q)): there is nothing below the first variation")
            }
        }
    }

    // MARK: - The boundary itself, against every shape of journal

    /// The one point from which a descent MUST cross: the floor of a variation
    /// on the floor of the sets. Swept against four journals — none, the grid
    /// floor, one rung up, the ceiling — because the landing reads the journal
    /// and every earlier check pinned only the richest of the four.
    func test_landing_fromTheBottomOfEveryVariation_staysInsideTheJournalAndTheBaseBand() {
        var crossings = 0, measured = 0
        for p in Pattern.allCases {
            for v in 2...Library.count(p) {
                let below = Dose.grid(Library.unit(p, v - 1))
                for remembered in [nil, below.min, below.min + below.step, below.max] as [Int?] {
                    var shown: [Pattern: [Int: Int]] = [p: [:]]
                    if let remembered { shown[p] = [v - 1: remembered] }
                    let grid = Dose.grid(Library.unit(p, v))
                    let bottom = Engine.fit(p, Position(variation: v, sets: EngineConfig.setsBase,
                                                        dose: grid.min, sub: 0,
                                                        cut: Engine.cutMax(sets: EngineConfig.setsBase)))
                    let to = Engine.fallBy(p, bottom, 1, shown: shown)
                    crossings += 1
                    let ctx = "\(p.rawValue) v\(v) → \(describe(p, to)), journal \(remembered.map(String.init) ?? "—")"
                    XCTAssertEqual(to.variation, v - 1, "\(ctx): a descent off the floor must change variation")
                    XCTAssertLessThanOrEqual(to.dose, Engine.landingDose(p, v - 1, shown: shown),
                                             "\(ctx): the landing is above the journal")
                    XCTAssertGreaterThanOrEqual(to.dose, below.min, "\(ctx): the landing is below the grid floor")
                    XCTAssertEqual(to.sets, EngineConfig.setsBase, "\(ctx): a landing is in the base band")
                    XCTAssertEqual(to.sub, 0, "\(ctx): a descent takes the sub-step")
                    XCTAssertGreaterThanOrEqual(Engine.setsAfterCut(sets: to.sets, cut: to.cut),
                                                EngineConfig.setsFloor, "\(ctx): the floor of sets was broken")
                    if AcceptedGap.closes(p, leaving: v) {
                        // §41.6 item 1: there is nothing below the grid floor to
                        // land on, and that is the only thing assertable here
                        // ABOUT THE DOSE. The work such a landing costs is
                        // bounded all the same, in `assertDescent`.
                        XCTAssertEqual(to.dose, below.min, "\(ctx): an accepted gap must lie on the grid floor")
                    }
                    if assertDescent(p, from: bottom, to: to, shown: shown, ctx) { measured += 1 }
                }
            }
        }
        XCTAssertGreaterThan(crossings, 0, "no boundary was swept at all")
        XCTAssertGreaterThan(measured, 150,                // 192 of the 196 on 26.08.2026
                             "only \(measured) crossings reached the independent measure")
    }

    /// THE NEGATIVE CONTROL of §41.1, and the reason the third clause of
    /// `noHarder` cannot be deleted in silence.
    ///
    /// Every other check in this file measures what `landInVar` DOES, and the
    /// behaviour of `landInVar` does not depend on the predicate: the mutation
    /// of 26.08.2026 removed `b.total <= a.total` and both the reference's
    /// verifier and its acceptance stayed at zero failures. The predicate must
    /// also REJECT the pre-§41.1 landing — the journal's ceiling on the full
    /// band — wherever that landing weighs more than the position left behind.
    func test_noHarder_againstTheLandingItReplaced_rejectsIt() {
        var rejections = 0
        for p in Pattern.allCases {
            for v in 2...Library.count(p) {
                let below = Dose.grid(Library.unit(p, v - 1))
                for remembered in [below.min, below.min + below.step, below.max] {
                    let shown: [Pattern: [Int: Int]] = [p: [v - 1: remembered]]
                    let grid = Dose.grid(Library.unit(p, v))
                    let bottom = Engine.fit(p, Position(variation: v, sets: EngineConfig.setsBase,
                                                        dose: grid.min, sub: 0,
                                                        cut: Engine.cutMax(sets: EngineConfig.setsBase)))
                    let old = Engine.fit(p, Position(variation: v - 1, sets: EngineConfig.setsBase,
                                                     dose: Engine.landingDose(p, v - 1, shown: shown),
                                                     sub: 0, cut: 0))
                    guard Engine.planLoad(p, old).total > Engine.planLoad(p, bottom).total else { continue }
                    rejections += 1
                    XCTAssertFalse(Engine.noHarder(p, from: bottom, to: old, shown: shown),
                                   "\(p.rawValue) v\(v): the predicate ACCEPTED the old landing "
                                   + "\(old.dose)×\(old.sets), work "
                                   + "\(Engine.planLoad(p, bottom).total) → \(Engine.planLoad(p, old).total)")
                }
            }
        }
        XCTAssertGreaterThan(rejections, 0,
                             "the negative control never ran — the predicate is unbound again")
    }

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
        XCTAssertGreaterThan(measured, 5000,               // 5423 on 26.08.2026
                             "only \(measured) cells reached the independent measure")
    }

    /// The fourth path down is the one no golden scenario reaches: past the
    /// end of the return table the comeback WRITES a position instead of
    /// walking rungs (`Breaks.swift`), and that write hands the sets back to
    /// the base. Every break scenario in the fixture starts from `cut == 0` on
    /// the base band, so what the write does to somebody who was training on
    /// two sets, or on a band of four or five, was asserted nowhere.
    ///
    /// What the spec promises here is the CEILING, absolutely: the landing is
    /// never above `ceilVar`, and landing on `ceilVar` is always the floor of
    /// its grid, whatever the position was.
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

    /// And the return is a DESCENT, so И4 binds it as well — including the
    /// gaps where the ceiling writes a position instead of walking rungs, and
    /// including the cut and the bands the fixture never starts from.
    ///
    /// The reference's verifier binds the silent decay this way and stops
    /// there; the comeback's own block only checks the shape of the ceiling.
    /// Measured before it was asserted: over 8264 (position × gap) cells the
    /// work grows in none outside the boundaries §41.6 item 1 already names —
    /// so this is a check the model passes, not a bar raised past it.
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
        XCTAssertGreaterThan(measured, 15_000,             // 19 999 on 26.08.2026
                             "only \(measured) cells reached the independent measure")
    }

    /// §41.11: the depth of a comeback does not RISE with the length of the
    /// break. The sweep above is about two points — this plan against the last
    /// one — and a curve that dips and comes back up satisfies it at every
    /// step while breaking the card's own sentence, "the longer the break, the
    /// lower the plan meets you".
    ///
    /// It broke exactly here: on a probing appearance the memory was written
    /// by the working sets, one set below the position, so a descent lost the
    /// set the probe had borrowed — until the dose fell far enough that three
    /// sets fitted under the base again, and the plan jumped back UP. Measured
    /// on the reference before the fix: 84 days met a person higher than 56.
    func test_comeback_afterAProbingAppearance_neverRisesWithTheLengthOfTheBreak() throws {
        let gaps = [14, 16, 18, 20, 24, 28, 35, 42, 49, 56, 63, 70, 77, 84, 95, 110, 120]
        // Every dose at the ceiling of its variation with the journal to prove
        // it (§41.4) — the one state that offers a probe.
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
