//
//  The cap on set-aside block moves when the set holds ids no pool has —
//  moves this build does not carry, such as cat-cow, the bird dog and Y-T-W.
//

import XCTest
import DredfitCore
@testable import Dredfit

extension AppStoreTests {

    /// An id no pool knows stays in the set — an imported backup or a
    /// downgrade must not lose it — but it takes no slot from the three. The
    /// sheet can neither name it nor bring it back, so a slot it held could
    /// never be freed: three such ids would lock the control for good.
    ///
    /// Set through the control here; on a real phone they arrive in the state
    /// file of the build that still had those moves.
    func testAMoveAnOlderBuildHadTakesNoSlotFromTheThree() {
        let store = makeStore()
        let gone: Set<String> = ["cat-cow", "bird-dog", "y-t-w"]
        for id in gone { store.setBlockMoveHidden(id, true) }
        XCTAssertEqual(store.settings.hiddenBlockMoveIDs, gone, "kept, not pruned")
        XCTAssertTrue(store.canHideAnotherBlockMove,
                      "ids nothing can name or bring back must not fill the cap")

        // Both pools count: one list holds the warm-up's and the cool-down's.
        for id in ["side-steps", "chest-wall", "side-bends"] { store.setBlockMoveHidden(id, true) }
        XCTAssertTrue(store.isBlockMoveHidden("side-bends"))
        XCTAssertFalse(store.canHideAnotherBlockMove,
                       "three moves of the pools are the cap, a cool-down position among them")
    }
}
