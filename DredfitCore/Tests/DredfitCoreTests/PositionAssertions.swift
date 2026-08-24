//
//  DredfitCoreTests
//
//  v2.22 (spec §33): growth moves by SUB-STEPS, so "grew by one" is a claim
//  about a POSITION — the pair (level, sub) — not about a level. These helpers
//  let the suites state the expectation the way the engine computes it, instead
//  of re-deriving levels by hand: a re-marked assertion stays derived from the
//  rule rather than pinned to a number that happened to come out.
//

import XCTest
@testable import DredfitCore

extension XCTestCase {

    /// The pattern's place on the progression.
    func position(_ state: EngineState, _ p: DredfitCore.Pattern) -> Position {
        state.position(p)
    }

    /// Where the pattern sits on the sub-step scale — the one number that
    /// orders two positions.
    func ordinal(_ state: EngineState, _ p: DredfitCore.Pattern) -> Int {
        Level.ordinal(state.position(p))
    }

    /// Assert a pattern landed exactly on the expected position.
    /// v2.25 (spec §36.3): a position is a TRIPLE, so the third coordinate is
    /// compared too. Every pre-v2.25 call site keeps reading as it did — a
    /// `Position` built without a cut carries zero — and now says so.
    func assertPosition(_ state: EngineState, _ p: DredfitCore.Pattern, _ want: Position,
                        _ message: String = "",
                        file: StaticString = #filePath, line: UInt = #line) {
        let got = state.position(p)
        let shown = "(got \(got.level).\(got.sub)/\(got.cut), want \(want.level).\(want.sub)/\(want.cut))"
        XCTAssertEqual(got.level, want.level, "\(message) — level \(shown)", file: file, line: line)
        XCTAssertEqual(got.sub, want.sub, "\(message) — sub-step \(shown)", file: file, line: line)
        XCTAssertEqual(got.cut, want.cut, "\(message) — cut \(shown)", file: file, line: line)
    }

    /// The position a session delta lands a pattern on: up in sub-steps under
    /// the growth cell (§33), and standing still on a zero delta.
    /// v2.23 (spec §34.1): DOWN in sub-steps too — one position back along the
    /// growth path, never past the floor of its own block. The old line
    /// (`level + delta, sub: 0`) encoded the level-wise descent that was the
    /// subject of the wave: it crossed the tier boundary and landed in the
    /// middle of the tier below, where the dose is higher.
    /// v2.25 (spec §36.3): both directions walk the shared scale — growth
    /// gives sets back first, a descent spends the dose before the sets — and
    /// the descent's floor is the pain one under a live episode (§36.9).
    func expectedPosition(_ state: EngineState, _ p: DredfitCore.Pattern, delta: Int) -> Position {
        let entry = state.position(p)
        let cap = EngineConfig.maxUp(pattern: p, tier: Level.decode(entry.level).tier)
        if delta > 0 {
            return Level.riseBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                                by: min(delta, cap),
                                allowSetsBack: (state.setsHold[p] ?? 0) == 0)
        }
        if delta < 0 {
            // v2.26 (§37.3): ONE floor. The episode-aware exception went with
            // the episode — and it was the only reader of the pain floor here.
            return Level.fallBy(level: entry.level, sub: entry.sub, cut: entry.cut, by: -delta,
                                floor: EngineConfig.setsFloor)
        }
        return entry
    }

    /// v2.23 (spec §34.3): where a deload lands — `deloadDrop` levels below
    /// its base, pulled down by the "no harder" gate. The gate is the point:
    /// until v2.23 the deload was a descent with no gate at all.
    ///
    /// The base differs by path (§34.3). On the rating path it is the entry
    /// level, which the rating never moved; on the exact-fact path it is the
    /// honest landing, which a deload may not climb back above — pass it as
    /// `base`. The gate always measures against the plan the session was done
    /// on, so `from` stays the entry position either way.
    /// v2.25 (spec §36.3): the deload reads the ACCUMULATED cut — it stands
    /// after the rating's own step, so the gate has to compare a trimmed plan
    /// with a trimmed one — and the cut it keeps has to fit the NEW band, at
    /// the pain floor: a deload is a descent and may give nothing back.
    func expectedDeload(_ p: DredfitCore.Pattern, from: Position, base: Int? = nil,
                        stepped: Position? = nil) -> Position {
        let target = min(max((base ?? from.level) - EngineConfig.deloadDrop, 0),
                         EngineConfig.levelMax)
        let landed = Level.descendNoHarder(pattern: p, from: from.level, factLevel: target,
                                           fromSub: from.sub, fromCut: from.cut)
        let carried = stepped?.cut ?? from.cut
        return Position(level: landed, sub: 0,
                        cut: min(carried, Level.cutMax(level: landed,
                                                       floor: EngineConfig.setsFloor)))
    }

    /// Assert the pattern stepped exactly `count` sub-steps back from `entry`,
    /// and that the landing does not ask for more work than it came from.
    /// v2.25 (spec §36.3): a step of the descent walks `fallBy` — the dose
    /// first, and a set on a block floor — and the gate reads the whole triple.
    func assertDescended(_ state: EngineState, _ p: DredfitCore.Pattern, from entry: Position,
                         by count: Int, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
        assertPosition(state, p,
                       Level.fallBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                                    by: count, floor: EngineConfig.setsFloor),
                       message, file: file, line: line)
        let got = state.position(p)
        XCTAssertTrue(Level.noHarder(pattern: p, from: entry.level, to: got.level,
                                     fromSub: entry.sub, toSub: got.sub,
                                     fromCut: entry.cut, toCut: got.cut),
                      "\(message) — an evaluative descent may not make the plan heavier",
                      file: file, line: line)
    }
}
