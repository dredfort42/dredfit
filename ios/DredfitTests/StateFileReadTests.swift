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

    // MARK: - When nothing can be put aside

    /// A directory the copy cannot be written into: the move and the copy fail
    /// there, and so would the write that follows them.
    private func lockDirectory() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    }

    private func unlockDirectory() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
    }

    func testAFileThatCannotBeMovedAsideFreezesInsteadOfStartingOver() throws {
        try XCTSkipIf(getuid() == 0, "root writes through 0o555")
        try Data("not json".utf8).write(to: file.url)
        try lockDirectory()
        defer { unlockDirectory() }
        guard case .unreadable = file.read(reload: false) else {
            return XCTFail("with no copy aside, starting over would write over the only one")
        }
        XCTAssertEqual(try Data(contentsOf: file.url), Data("not json".utf8))
    }

    func testAPartlyReadableFileThatCannotBeCopiedAsideFreezes() throws {
        try XCTSkipIf(getuid() == 0, "root writes through 0o555")
        let json = #"{"engineState":{"from":"a future build"},"records":[]}"#
        try Data(json.utf8).write(to: file.url)
        try lockDirectory()
        defer { unlockDirectory() }
        guard case .unreadable = file.read(reload: false) else {
            return XCTFail("the next write would rewrite the positions with nothing kept aside")
        }
        XCTAssertTrue(try corruptCopies().isEmpty)
    }

    func testDroppedRecordsThatCannotBeCopiedAsideFreeze() throws {
        try XCTSkipIf(getuid() == 0, "root writes through 0o555")
        let record = WorkoutRecord(sessionNumber: 1, date: Date(timeIntervalSince1970: 1_800_000_000),
                                   result: .plan)
        try file.write(AppData(engineState: .initial, records: [record], settings: AppSettings()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file.url))
                                 as? [String: Any])
        json["records"] = try XCTUnwrap(json["records"] as? [Any]) + [["from": "a future build"]]
        let original = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AppData.self, from: original)
        XCTAssertFalse(decoded.engineStateReset, "only the entry is damaged")
        XCTAssertEqual(decoded.droppedRecordCount, 1)
        try original.write(to: file.url)
        try lockDirectory()
        defer { unlockDirectory() }
        guard case .unreadable = file.read(reload: false) else {
            return XCTFail("the next write would drop the entry with nothing kept aside")
        }
        XCTAssertEqual(try Data(contentsOf: file.url), original)
        XCTAssertTrue(try corruptCopies().isEmpty)
    }

    // MARK: - Bytes already kept under a later name

    /// Takes the first quarantine name, so the next copy goes under a later one.
    private func keepAnEarlierQuarantine() throws -> Data {
        let earlier = Data("an earlier, different quarantine".utf8)
        try earlier.write(to: dir.appendingPathComponent("dredfit-state.corrupt.json"))
        return earlier
    }

    func testBothKindsOfDamageInOneReadAreKeptOnce() throws {
        let earlier = try keepAnEarlierQuarantine()
        let payload = Data(#"{"engineState":{"from":"a future build"},"records":[{"from":"a future build"}]}"#.utf8)
        try payload.write(to: file.url)
        guard case .loaded(let data) = file.read(reload: false) else {
            return XCTFail("the rest of the file reads")
        }
        XCTAssertTrue(data.engineStateReset)
        XCTAssertEqual(data.droppedRecordCount, 1)
        let kept = try corruptCopies().map { try Data(contentsOf: $0) }
        XCTAssertEqual(kept.count, 2, "one copy for the two kinds of damage, beside the earlier one")
        XCTAssertEqual(Set(kept), [earlier, payload])
    }

    func testBytesAlreadyKeptUnderALaterNameDoNotFreeze() throws {
        try XCTSkipIf(getuid() == 0, "root writes through 0o555")
        _ = try keepAnEarlierQuarantine()
        let payload = Data(#"{"engineState":{"from":"a future build"},"records":[]}"#.utf8)
        try payload.write(to: file.url)
        guard case .loaded = file.read(reload: false) else { return XCTFail("the journal beside it reads") }
        XCTAssertEqual(try corruptCopies().count, 2, "kept under a later name; nothing written over the file")
        try lockDirectory()
        defer { unlockDirectory() }
        guard case .loaded = file.read(reload: false) else {
            return XCTFail("the bytes are already safe aside, so there is nothing to freeze for")
        }
    }
}
