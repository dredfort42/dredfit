//
//  DredfitCoreTests
//
//  Engine v2.11 (spec §21) — RE-MARKED for v2.26 (§37.0).
//
//  The suite was about the pain report: it took the load off, armed a freeze,
//  opened an episode, and the 3 → 6 → 12 ladder deepened the rest on every
//  repeat. None of that exists any more — `applyFeedback` has no `discomfort`
//  argument and the state has no `sore`, `soreLeft`, `frozen` or `painSeen`.
//  Ten of the eleven tests here stood on that and are gone with it.
//
//  ONE claim survives untouched and stays here: §21.1's encoding, "an unload
//  lands at the bottom of the PREVIOUS tier". `Level.unload` is still part of
//  the contract and still exported — the reference keeps it for the port and
//  the verifier even though nothing inside the model calls it since §36.5 —
//  so dropping the test with the mechanism would have left an exported
//  function with no coverage at all.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV211Tests: XCTestCase {

    /// §21.1: the landing of an unload, over the whole scale. The bands of
    /// four and five sets are tier 4 by the encoding, so they land in tier 3
    /// exactly as tier 4 does.
    func testUnloadLandsAtTheBottomOfThePreviousTier() {
        XCTAssertEqual(Level.unload(5), 0)     // tier 1 → the floor
        XCTAssertEqual(Level.unload(12), 0)    // tier 2 → the floor
        XCTAssertEqual(Level.unload(20), 8)    // tier 3 → bottom of tier 2
        XCTAssertEqual(Level.unload(28), 16)   // tier 4 → bottom of tier 3
        XCTAssertEqual(Level.unload(35), 16)   // band 4 is tier 4 by encoding
        XCTAssertEqual(Level.unload(47), 16)   // and so is band 5
    }

    /// And the landing is always the floor of a tier, never its middle — the
    /// property the whole §30 wave was about. Swept rather than sampled: the
    /// six literals above pin the rungs a reader checks by eye, this pins the
    /// rule they are instances of.
    func testEveryUnloadLandsOnATierFloor() {
        for level in 0...EngineConfig.levelMax {
            let landed = Level.unload(level)
            XCTAssertEqual(landed % EngineConfig.stepsPerTier, 0,
                           "L\(level) unloaded into the middle of a tier (L\(landed))")
            XCTAssertLessThan(landed, max(1, level),
                              "L\(level) unloaded upwards (L\(landed))")
        }
    }
}
