//
//  SetsHandleNoticeTests.swift
//  DredfitTests
//
//  v2.25 (spec §36.2, §36.5): what the app SAYS about the sets handle.
//  The handle moves sets and never the level, so a card can go from
//  `4×4 /side` to `1×4 /side` with nothing else on screen having changed —
//  and a plan that quietly got easier reads as a bug exactly the way a plan
//  that quietly got harder does. Two sentences answer it, in the card.
//
//  And one older line finally works: "time to see a specialist" used to hang
//  on a RUN of pain reports, which the 3 / 6 / 12 rest is built to break, so
//  it never reached anybody it was written for. It reads the engine's memory
//  of pain now.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SetsHandleNoticeTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-notice-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// Seeded through the state file, like the app's own load. The pull slot
    /// is in every session, so it is the movement a trajectory can be walked
    /// on without waiting for the rotation. No time budget: the budget's own
    /// cut would confuse what the handle did with what the clock did.
    private func store(level: Int = 40) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"levels":[\(levels)],"failStreak":[],"timeBudgetMin":0},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,"timeBudgetChosen":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    private var trained = 0

    /// One workout, one calendar day apart, so no gap ever reads as a break.
    @discardableResult
    private func train(_ store: AppStore, discomfort: Set<Pattern> = [],
                       result: FeedbackResult = .plan) -> Session {
        let session = store.nextSession
        trained += 1
        let date = Calendar.current.date(byAdding: .day, value: -400 + trained * 2,
                                         to: Calendar.current.startOfDay(for: .now))!
        _ = store.completeWorkout(session: session, result: result,
                                  discomfort: discomfort, date: date)
        return session
    }

    /// Trains clean until the movement is neither frozen nor waiting on an
    /// open episode — i.e. the rest the engine assigned has been served.
    private func serveTheRest(_ store: AppStore, _ pattern: Pattern) {
        var guardrail = 0
        while store.engineState.freezeRemaining(pattern) > 0
                || store.engineState.sore[pattern] != nil {
            train(store)
            guardrail += 1
            XCTAssertLessThan(guardrail, 40, "the rest never ended")
            if guardrail >= 40 { return }
        }
    }

    private func pull(_ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == .pull })
    }

    // MARK: - The specialist line (spec §36.5)

    /// The trajectory the line was written for: it hurts, it rests, it comes
    /// back, it hurts again — three times over. The run of reports is broken
    /// by the rest EVERY time, which is why the old streak threshold was
    /// unreachable; the memory of pain is not.
    func testTheSpecialistLineArrivesOnTheThirdReport() throws {
        let store = try store()

        train(store, discomfort: [.pull])
        XCTAssertEqual(store.engineState.painSeen[.pull], 1)
        XCTAssertNil(store.painNote(.pull), "one report is not a trend")

        serveTheRest(store, .pull)
        train(store, discomfort: [.pull])
        XCTAssertEqual(store.engineState.painSeen[.pull], 2)
        XCTAssertNil(store.painNote(.pull),
                     "two reports with the assigned rest between them are still not three")

        serveTheRest(store, .pull)
        train(store, discomfort: [.pull])

        XCTAssertEqual(store.engineState.painSeen[.pull], 3)
        XCTAssertEqual(store.painNote(.pull), .seeSpecialist)
        // The evidence that the threshold had to move: the run the old line
        // read is back at one, because the rest it prescribes ends it.
        XCTAssertLessThan(store.discomfortStreak(.pull), AppStore.painSpecialistThreshold)
        // And the sentence reaches the screen: it is drawn under the resting
        // movements, and after a report the movement is resting.
        XCTAssertTrue(store.restingPatterns.contains(.pull))
    }

    /// The softer line is untouched: two reports on two consecutive
    /// appearances is still "it hurt both times", and it is still the journal
    /// that says so.
    func testTwoReportsInARowStillReadAsTheSofterLine() throws {
        let store = try store()
        train(store, discomfort: [.pull])
        train(store, discomfort: [.pull])
        XCTAssertEqual(store.discomfortStreak(.pull), 2)
        XCTAssertEqual(store.engineState.painSeen[.pull], 2)
        XCTAssertEqual(store.painNote(.pull), .hurtAgain)
    }

    /// The memory outranks the run wherever both could fire — only one
    /// sentence is ever shown, and three reports is the stronger fact.
    func testTheMemoryOutranksTheRun() throws {
        let store = try store()
        train(store, discomfort: [.pull])
        train(store, discomfort: [.pull])
        train(store, discomfort: [.pull])
        XCTAssertGreaterThanOrEqual(store.discomfortStreak(.pull), 2)
        XCTAssertEqual(store.painNote(.pull), .seeSpecialist)
    }

    // MARK: - Why the card shows the number it does (spec §36.2)

    /// A report takes sets off at a level that does not move, so the card
    /// says why — and says it about the movement that hurt, not about the
    /// whole plan.
    func testTheCardExplainsAPlanCutByPain() throws {
        let store = try store()
        let before = try pull(train(store, discomfort: [.pull]))
        let now = try pull(store.nextSession)

        XCTAssertLessThan(now.sets, before.sets, "the handle must have moved")
        XCTAssertEqual(store.setsNote(for: now), .painCut)
        for ex in store.nextSession.exercises where ex.pattern != .pull {
            XCTAssertNil(store.setsNote(for: ex),
                         "\(ex.pattern.rawValue) was never reported as painful")
        }
    }

    /// …and stops saying it once the episode is over: the sentence promises
    /// the sets back "when it passes", so it may not outlive the passing.
    func testThePainLineGoesWithTheEpisode() throws {
        let store = try store()
        train(store, discomfort: [.pull])
        serveTheRest(store, .pull)
        XCTAssertNil(store.engineState.sore[.pull])
        XCTAssertNotEqual(store.setsNote(for: try pull(store.nextSession)), .painCut)
    }

    /// The other end of the handle: a set comes back, and the card says so
    /// once — the appearance the set actually arrives on.
    func testTheCardSaysWhenASetComesBack() throws {
        let store = try store()
        train(store, discomfort: [.pull])
        serveTheRest(store, .pull)

        var announced = 0
        var seenBack = false
        for _ in 0..<12 {
            let plan = store.nextSession
            if store.setsNote(for: try pull(plan)) == .setBack { announced += 1 }
            let before = try pull(plan).sets
            train(store)
            if try pull(store.nextSession).sets > before { seenBack = true }
        }
        XCTAssertTrue(seenBack, "no set ever came back — the trajectory proves nothing")
        XCTAssertGreaterThan(announced, 0, "a set came back with nothing said about it")
    }

    /// A card that has no story says nothing at all: no report, no return,
    /// no line. The plan is the default state of the app and must stay quiet.
    func testAnUntouchedPlanCarriesNoLine() throws {
        let store = try store()
        for ex in store.nextSession.exercises {
            XCTAssertNil(store.setsNote(for: ex))
        }
    }

    // MARK: - The catalog (all shipping languages)

    /// A key the catalog does not carry falls back to English in every
    /// language at once — six locales lost to one missing string, which is
    /// exactly what happened last release. Both new sentences, all shipping
    /// languages, checked against the file rather than the bundle.
    func testBothNewLinesAreInTheCatalogInEveryLanguage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DredfitTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Dredfit/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        let keys = [
            "Fewer sets for now — you said this one hurt. They come back once it passes.",
            "A set is back — your body is coping.",
        ]
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any],
                                      "\(key) is not in the catalog at all")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for lang in ["en", "ru", "es", "pt-BR", "de", "fr", "it"] {
                let unit = (localizations[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) is missing \(lang)")
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key): \(lang)")
            }
        }
    }

    /// Both rungs of the note say something, and they do not say the same
    /// thing. Deliberately not compared against the English wording: the test
    /// runs in whatever language the simulator is set to, and a translated
    /// answer is a correct answer.
    func testBothRungsOfTheNoteSaySomething() {
        XCTAssertFalse(ExerciseRow.note(.painCut)?.isEmpty ?? true)
        XCTAssertFalse(ExerciseRow.note(.setBack)?.isEmpty ?? true)
        XCTAssertNotEqual(ExerciseRow.note(.painCut), ExerciseRow.note(.setBack))
        XCTAssertNil(ExerciseRow.note(nil))
    }

    /// The general form of the same guard, over the whole app: every plain
    /// `String(localized: "…")` the sources ask for is a key the catalog
    /// carries. One key that is not — a rename on one side, a sentence typed
    /// straight into a view — and the string falls back to English in all six
    /// translated languages at once, which is how last release lost them.
    func testEveryPlainLocalizedLiteralIsACatalogKey() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DredfitTests/
            .deletingLastPathComponent()   // repo root
        let data = try Data(contentsOf: root.appendingPathComponent("Dredfit/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(try XCTUnwrap(json["strings"] as? [String: Any]).keys)

        // The class excludes a backslash on purpose, so an interpolated
        // literal — whose catalog key is the %@/%lld form, not the source
        // text — is skipped rather than wrongly reported.
        let pattern = try NSRegularExpression(
            pattern: #"String\(localized:\s*"([^"\\]*)"\s*\)"#)
        let sources = try XCTUnwrap(FileManager.default.enumerator(
            at: root.appendingPathComponent("Dredfit"), includingPropertiesForKeys: nil))

        var checked = 0
        for case let url as URL in sources where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(src.startIndex..<src.endIndex, in: src)
            for match in pattern.matches(in: src, range: range) {
                guard let found = Range(match.range(at: 1), in: src) else { continue }
                checked += 1
                XCTAssertTrue(keys.contains(String(src[found])),
                              "\(url.lastPathComponent): \"\(src[found])\" is not in the catalog")
            }
        }
        XCTAssertGreaterThan(checked, 100, "the scan found almost nothing — check the pattern")
    }
}
