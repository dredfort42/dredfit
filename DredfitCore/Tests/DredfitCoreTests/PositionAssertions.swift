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

    /// The position a session delta lands a pattern on, by the §33 rule: up in
    /// sub-steps under the growth cell, down in whole levels with the sub-step
    /// zeroed, and standing still on a zero delta.
    func expectedPosition(_ state: EngineState, _ p: DredfitCore.Pattern, delta: Int) -> Position {
        let entry = state.position(p)
        let cap = EngineConfig.maxUp(pattern: p, tier: Level.decode(entry.level).tier)
        if delta > 0 {
            return Level.rise(level: entry.level, sub: entry.sub, by: min(delta, cap))
        }
        if delta < 0 {
            return Position(level: min(max(entry.level + delta, 0), EngineConfig.levelMax), sub: 0)
        }
        return entry
    }
}
