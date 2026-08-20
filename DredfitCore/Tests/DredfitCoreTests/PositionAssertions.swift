//
//  PositionAssertions.swift
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
    func assertPosition(_ state: EngineState, _ p: DredfitCore.Pattern, _ want: Position,
                        _ message: String = "",
                        file: StaticString = #filePath, line: UInt = #line) {
        let got = state.position(p)
        XCTAssertEqual(got.level, want.level,
                       "\(message) — level (got \(got.level).\(got.sub), want \(want.level).\(want.sub))",
                       file: file, line: line)
        XCTAssertEqual(got.sub, want.sub,
                       "\(message) — sub-step (got \(got.level).\(got.sub), want \(want.level).\(want.sub))",
                       file: file, line: line)
    }

    /// Assert the pattern rose by exactly `count` sub-steps from `entry`.
    func assertRose(_ state: EngineState, _ p: DredfitCore.Pattern, from entry: EngineState,
                    by count: Int, _ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
        let want = Level.rise(level: entry.position(p).level,
                              sub: entry.position(p).sub, by: count)
        assertPosition(state, p, want, message, file: file, line: line)
    }

    /// The position a session delta lands a pattern on: up in sub-steps under
    /// the growth cell (§33), and standing still on a zero delta.
    /// v2.23 (spec §34.1): DOWN in sub-steps too — one position back along the
    /// growth path, never past the floor of its own block. The old line
    /// (`level + delta, sub: 0`) encoded the level-wise descent that was the
    /// subject of the wave: it crossed the tier boundary and landed in the
    /// middle of the tier below, where the dose is higher.
    func expectedPosition(_ state: EngineState, _ p: DredfitCore.Pattern, delta: Int) -> Position {
        let entry = state.position(p)
        let cap = EngineConfig.maxUp(pattern: p, tier: Level.decode(entry.level).tier)
        if delta > 0 {
            return Level.rise(level: entry.level, sub: entry.sub, by: min(delta, cap))
        }
        if delta < 0 {
            return Level.descend(level: entry.level, sub: entry.sub, by: -delta)
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
    func expectedDeload(_ p: DredfitCore.Pattern, from: Position, base: Int? = nil) -> Position {
        let target = min(max((base ?? from.level) - EngineConfig.deloadDrop, 0),
                         EngineConfig.levelMax)
        return Position(level: Level.descendNoHarder(pattern: p, from: from.level,
                                                     factLevel: target, fromSub: from.sub),
                        sub: 0)
    }

    /// Assert the pattern stepped exactly `count` sub-steps back from `entry`,
    /// and that the landing does not ask for more work than it came from.
    func assertDescended(_ state: EngineState, _ p: DredfitCore.Pattern, from entry: Position,
                         by count: Int, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
        assertPosition(state, p, Level.descend(level: entry.level, sub: entry.sub, by: count),
                       message, file: file, line: line)
        let got = state.position(p)
        XCTAssertTrue(Level.noHarder(pattern: p, from: entry.level, to: got.level,
                                     fromSub: entry.sub, toSub: got.sub),
                      "\(message) — an evaluative descent may not make the plan heavier",
                      file: file, line: line)
    }
}
