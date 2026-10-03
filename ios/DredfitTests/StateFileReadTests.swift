import XCTest
import DredfitCore
@testable import Dredfit

/// The one read path of the state file: what it reports, and what it puts
/// aside before anything can be written over it.
@MainActor
final class StateFileReadTests: XCTestCase {

    nonisolated(unsafe) private var dir: URL!
    private var file: StateFile { StateFile(url: dir.appendingPathComponent("dredfit-state.json")) }

    override func setUp() async throws {
        try await super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("statefile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        try await super.tearDown()
    }

    private func corruptCopies() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".corrupt") }
    }

    func testNoFileIsAFreshInstall() {
        guard case .absent = file.read(reload: false) else { return XCTFail("nothing on disk reads as absent") }
    }

    func testAFileThatCannotBeReadIsLeftAlone() throws {
        // A directory where the file should be: it exists and yields no bytes,
        // the way a file still under data protection does.
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: false)
        guard case .unreadable = file.read(reload: false) else { return XCTFail("an unreadable file is not a fresh install") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(try corruptCopies().isEmpty, "nothing is moved aside: it may be the only copy")
    }

    func testAWrittenStateReadsBack() throws {
        var state = EngineState.initial
        state.counter = 7
        try file.write(AppData(engineState: state, records: [], settings: AppSettings()))
        guard case .loaded(let data) = file.read(reload: false) else { return XCTFail("a written file reads back") }
        XCTAssertEqual(data.engineState.counter, 7)
    }

    func testAFileThatDoesNotDecodeIsMovedAside() throws {
        try Data("not json".utf8).write(to: file.url)
        guard case .undecodable = file.read(reload: false) else { return XCTFail("garbage does not decode") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path),
                       "moved, so the next write cannot overwrite the only copy")
        let copies = try corruptCopies()
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(copies.first)), Data("not json".utf8))
    }

    func testASecondFailureNeverReplacesTheFirstCopy() throws {
        try Data("first".utf8).write(to: file.url)
        _ = file.read(reload: false)
        try Data("second".utf8).write(to: file.url)
        _ = file.read(reload: false)
        let kept = try corruptCopies().map { try Data(contentsOf: $0) }
        XCTAssertEqual(Set(kept), [Data("first".utf8), Data("second".utf8)])
    }

    func testAnUnreadableEngineStateKeepsTheJournalAndACopy() throws {
        let record = WorkoutRecord(sessionNumber: 1, date: Date(timeIntervalSince1970: 1_800_000_000),
                                   result: .plan)
        try file.write(AppData(engineState: .initial, records: [record], settings: AppSettings()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file.url))
                                 as? [String: Any])
        json["engineState"] = ["from": "a future build"]
        let original = try JSONSerialization.data(withJSONObject: json)
        try original.write(to: file.url)

        guard case .loaded(let data) = file.read(reload: false) else {
            return XCTFail("the journal beside it is whole")
        }
        XCTAssertTrue(data.engineStateReset)
        XCTAssertEqual(data.records.count, 1, "the journal survives a state it cannot read")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path), "copied, not moved")
        XCTAssertEqual(try corruptCopies().map { try Data(contentsOf: $0) }, [original],
                       "the plan can still be recovered from the copy")
    }
}
