//
//  DiffTests.swift
//  DredfitCoreTests
//
//  The JS ↔ Swift differential. `golden.json` pins 331 steps chosen by hand
//  around known forks and explains every one of them; this does the other
//  half of the job — ten thousand random trajectories from a fixed seed,
//  folded into a single fingerprint. The reference computes it in
//  `reference/difftest.js`, the port recomputes it here with the same
//  pseudo-random generator, and the two numbers are compared.
//
//  A divergence in one set, one second of rest or one field of state moves the
//  fingerprint. What it will not do is tell you WHERE — that is golden's job,
//  and the division of labour is deliberate: golden answers "why", the
//  differential answers "and nowhere else?".
//
//  The fold is FNV-1a 64 over a stream of INTEGERS. Integers mean the same
//  thing in both languages with no caveats; the single fractional field
//  (`weekAgeDays`) goes in as the bit pattern of its double, because both
//  sides are IEEE 754 running the same sequence of operations.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

/// The fingerprint the reference wrote, with the run's shape alongside it —
/// so a mismatch says whether the two sides even ran the same experiment.
private struct DiffFixture: Decodable {
    let generator: String
    let seed: UInt32
    let trajectories: Int
    let steps: Int
    let values: Int
    let digest: String
}

/// xorshift32 — literally the same three shifts as the reference, on the same
/// seed. The trajectories have to be identical before the fingerprints can
/// mean anything.
private struct XorShift32 {
    private var state: UInt32
    init(seed: UInt32) { state = seed }

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    mutating func pick<T>(_ options: [T]) -> T {
        options[Int(next() % UInt32(options.count))]
    }
}

/// FNV-1a 64.
private struct Fold {
    private(set) var hash: UInt64 = 14_695_981_039_346_656_037
    private(set) var values = 0
    private static let prime: UInt64 = 1_099_511_628_211

    mutating func feed(_ n: Int) {
        var v = UInt64(bitPattern: Int64(n))
        for _ in 0..<8 {
            hash = (hash ^ (v & 0xff)) &* Self.prime
            v >>= 8
        }
        values += 1
    }

    mutating func feed(_ x: Double) { feed(Int(bitPattern: UInt(x.bitPattern))) }
    mutating func feed(_ flag: Bool) { feed(flag ? 1 : 0) }
}

final class DiffTests: XCTestCase {

    private func loadFixture() throws -> DiffFixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "difftest", withExtension: "json"),
            "difftest.json not found in test resources")
        return try JSONDecoder().decode(DiffFixture.self, from: Data(contentsOf: url))
    }

    /// The fixture must come from the pinned reference version, for the same
    /// reason golden's generator string is checked: a fingerprint regenerated
    /// from the wrong engine would re-baseline everything instead of catching
    /// a port bug.
    func testTheDifferentialFixtureComesFromThePinnedReference() throws {
        let f = try loadFixture()
        XCTAssertEqual(f.generator, "adaptive_engine.js v2.25.0")
        XCTAssertGreaterThanOrEqual(f.trajectories, 10_000,
                                    "the differential is meant to be a wide sweep")
    }

    private func feedSession(_ fold: inout Fold, _ w: Session) {
        fold.feed(w.sessionNumber)
        // The duration in tenths of a minute, exactly as the engine prints it.
        fold.feed(Int((w.estimatedTotalMin * 10).rounded()))
        fold.feed(w.warmupMin)
        fold.feed(w.cooldownMin)
        fold.feed(w.exercises.count)
        for ex in w.exercises {
            fold.feed(Pattern.allCases.firstIndex(of: ex.pattern) ?? -1)
            fold.feed(ex.tier)
            fold.feed(ex.unit == .reps ? 0 : 1)
            fold.feed(ex.load)
            fold.feed(ex.perSide)
            fold.feed(ex.sets)
            fold.feed(ex.restSetSec)
            fold.feed(ex.restExerciseSec)
            fold.feed(ex.loads?.count ?? 0)
            for v in ex.loads ?? [] { fold.feed(v) }
        }
    }

    private func feedState(_ fold: inout Fold, _ s: EngineState) {
        fold.feed(s.counter)
        fold.feed(s.hasBar)
        for p in Pattern.allCases {
            fold.feed(s.levels[p] ?? 0)
            fold.feed(s.sub[p] ?? 0)
            fold.feed(s.cut[p] ?? 0)
            fold.feed(s.painSeen[p] ?? 0)
            fold.feed(s.setsHold[p] ?? 0)
            // Sparseness is part of the contract: "no entry" and "zero" have
            // to differ, or the postcondition repair reads them alike.
            fold.feed(s.shownWork[p] != nil)
            fold.feed(s.shownWork[p] ?? 0)
            fold.feed(s.shownOrd[p] != nil)
            fold.feed(s.shownOrd[p] ?? 0)
            fold.feed(s.failStreak[p] ?? 0)
            fold.feed(s.frozen[p] ?? 0)
            fold.feed(s.sore[p] ?? 0)
            fold.feed(s.soreLeft[p] ?? 0)
            fold.feed(s.lessHist[p] ?? 0)
            fold.feed(s.weekGain[p] ?? 0)
            fold.feed(s.creditPaused.contains(p))
        }
        fold.feed(s.shownBudget)
        fold.feed(s.lessRun)
        fold.feed(s.returnRun)
        fold.feed(s.illness)
        fold.feed(s.rampWindow)
        fold.feed(s.timeBudgetMin)
        fold.feed(s.weekAgeDays)
    }

    /// Ten thousand trajectories, twenty-four steps each, from the reference's
    /// seed — and one number at the end.
    ///
    /// The branching is the reference's, step for step: the pain channel down
    /// to a single set and back, the silent decay, the comeback, the lens,
    /// budgets 0/30/45/90, skips, exact facts, `recordShown`, a moved time
    /// handle, and a gap that is sometimes absent — the calendar-blind path of
    /// §7 is a contract too and has to agree bit for bit like everything else.
    func testTenThousandRandomTrajectoriesAgreeWithTheReference() throws {
        let fixture = try loadFixture()
        let budgets = [0, 30, 45, 90]
        var rng = XorShift32(seed: fixture.seed)
        var fold = Fold()

        for _ in 0..<fixture.trajectories {
            var s = EngineState.initial
            s.hasBar = rng.next() % 2 == 0
            s.timeBudgetMin = rng.pick(budgets)
            // Some trajectories start from a level already climbed: without it
            // bands 4-5 and the `pullBar` unit change would show up in a
            // handful of runs out of ten thousand.
            let seedLevel = Int(rng.next() % 48)
            for p in Pattern.allCases { s.levels[p] = (seedLevel + Int(rng.next() % 8)) % 48 }
            feedState(&fold, s)

            for _ in 0..<fixture.steps {
                let w = Engine.generateSession(s)
                feedSession(&fold, w)
                let r = rng.next() % 100
                if r < 5 {
                    s = Engine.applySilentDecay(state: s, gapDays: 7 + Int(rng.next() % 6))
                } else if r < 9 {
                    s = Engine.applyComeback(state: s, gapDays: 14 + Int(rng.next() % 200),
                                             alreadyDecayed: false)
                } else if r < 12 {
                    s = Engine.applyIllness(state: s)
                } else if r < 14 {
                    s = Engine.recordShown(state: s, session: w)
                } else if r < 16 {
                    s.timeBudgetMin = rng.pick(budgets)
                } else {
                    var overrides: [Pattern: Int] = [:]
                    if rng.next() % 4 == 0 {
                        for ex in w.exercises where rng.next() % 3 == 0 {
                            overrides[ex.pattern] = max(0, ex.load + Int(rng.next() % 9) - 4)
                        }
                    }
                    var skipped: Set<Pattern> = []
                    if rng.next() % 12 == 0 {
                        skipped = [w.exercises[Int(rng.next() % UInt32(w.exercises.count))].pattern]
                    }
                    var discomfort: Set<Pattern> = []
                    if rng.next() % 8 == 0 {
                        discomfort = [w.exercises[Int(rng.next() % UInt32(w.exercises.count))].pattern]
                    }
                    let result = rng.pick([FeedbackResult.less, .plan, .plan, .more])
                    let gap: Double? = rng.next() % 5 == 0
                        ? nil : Double(rng.next() % 400) / 100
                    s = Engine.applyFeedback(state: s, session: w, result: result,
                                             overrides: overrides, skipped: skipped,
                                             discomfort: discomfort, gapDays: gap)
                }
                feedState(&fold, s)
            }
        }

        XCTAssertEqual(fold.values, fixture.values,
                       "the two sides folded a different number of values — "
                       + "the trajectories themselves diverged, not just the results")
        XCTAssertEqual(String(format: "%016lx", fold.hash), fixture.digest,
                       "the port diverged from the reference somewhere in "
                       + "\(fixture.trajectories) trajectories")
    }
}
