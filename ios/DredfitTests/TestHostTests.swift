import XCTest
@testable import Dredfit

final class TestHostTests: XCTestCase {

    /// `DredfitApp` starts no store while this variable is set, so the unit
    /// tests never load the simulator's state file or write the App Group
    /// snapshot. If an Xcode stopped setting it, the host store would come
    /// back silently; this is where that shows.
    func testUnitTestsRunWithTheVariableThatKeepsTheHostStoreAway() {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"])
    }
}
