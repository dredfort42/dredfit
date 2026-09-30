//
//  "+15 s" on the rest screen (issue #73, item D). Deliberately runs WITHOUT
//  --uitest-fast: that hook collapses a rest to one second, which also
//  collapses the extension cap to two — the control would be disabled before
//  the test could touch it, and the cap is half of what is worth asserting.
//

import XCTest

@MainActor
final class RestExtensionUITests: XCTestCase {

    nonisolated(unsafe) private var app: XCUIApplication!
    private var driver: WorkoutDriver { WorkoutDriver(app: app) }

    // Synchronous, on purpose: an async setUp kills the CI retries (Apple
    // #108565878). Why, and why `app` is `nonisolated(unsafe)`: DredfitUITests.setUp.
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = MainActor.assumeIsolated {
            let app = XCUIApplication()
            app.seedLaunchArguments()
            return app
        }
    }

    /// A 60-second rest may be pushed to 120 and no further, and the control
    /// keeps its place in the row once it is spent — hiding it would move
    /// "Skip rest" out from under the finger.
    func testRestExtendsToTwiceThePlanAndThenGreysOut() {
        app.launch()
        driver.startWorkout()

        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the first set never offered Done")
        driver.coordinateTap(done)

        let extend = app.buttons[AX.extendRest]
        XCTAssertTrue(extend.waitForExistence(timeout: 5), "the rest screen has no +15 s control")
        XCTAssertTrue(extend.isEnabled, "a rest at its planned length must be extendable")

        // 60 planned → 75, 90, 105, 120. The fifth tap has nowhere to go.
        for _ in 0..<4 { driver.coordinateTap(extend) }

        XCTAssertTrue(extend.exists, "the control must stay in the row at the cap")
        XCTAssertFalse(extend.isEnabled, "the cap must disable the control, not hide it")
        XCTAssertTrue(app.buttons[AX.skipRest].exists, "the row lost its other control")
    }
}
