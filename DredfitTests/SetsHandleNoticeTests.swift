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
    private func train(_ store: AppStore, result: FeedbackResult = .plan) -> Session {
        let session = store.nextSession
        trained += 1
        let date = Calendar.current.date(byAdding: .day, value: -400 + trained * 2,
                                         to: Calendar.current.startOfDay(for: .now))!
        _ = store.completeWorkout(session: session, result: result, date: date)
        return session
    }

    private func pull(_ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == .pull })
    }

    /// The other end of the handle: a set comes back, and the card says so
    /// once — the appearance the set actually arrives on.
    ///
    /// v2.26 (§37.5): the set is taken off by the PERSON now, not by a pain
    /// report, which makes the sentence matter more rather than less. They
    /// know why it went; only the engine knows why it came back.
    func testTheCardSaysWhenASetComesBack() throws {
        let store = try store()
        store.takeSetOff(.pull)

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

        // v2.26: the pain line went with the channel; the handles' own
        // sentences joined. Every one of them is user-facing on the plan.
        let keys = [
            "A set is back — your body is coping.",
            "Fewer sets",
            "More sets",
            "Full workout",
            "Make it easier",
            "Takes one set off every movement. Your levels do not change.",
            "Enter what you actually did. The plan follows your numbers.",
            "Shorter today · %lld → %lld min",
            "Easier · %@",
            "%lld positions · about %lld min",
            "Do the plan, and leave your maximum for the last set.",
            "Cool-down",
            "Start the cool-down",
            "Skip the cool-down",
            "The work is done. A few minutes of stretching helps it settle.",
            "Warm-up",
            "Start the warm-up",
            "Skip the warm-up",
            "A few easy minutes to get the body ready. Skip it if you are already warm.",
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
    func testTheNoteSaysSomethingAndOnlyWhenThereIsSomethingToSay() {
        XCTAssertFalse(ExerciseRow.note(.setBack)?.isEmpty ?? true)
        XCTAssertNil(ExerciseRow.note(nil))
    }

    /// The general form of the same guard, over the whole app: every plain
    /// localized literal the sources ask for is a key the catalog carries.
    ///
    /// v2.26: the scan covers `Text("…")` and `Button("…")` as well as
    /// `String(localized: "…")`. It did not before, and that is precisely the
    /// hole finding S5-4 came through — a SwiftUI `Text` literal is localized
    /// through the same catalog, so a sentence typed straight into a view
    /// looks fine in English and falls back to English everywhere else.
    ///
    /// One key that is not there — a rename on one side, a sentence typed
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
        let patterns = try [
            #"String\(localized:\s*"([^"\\]*)"\s*\)"#,
            #"\bText\(\s*"([^"\\]*)"\s*\)"#,
            #"\bButton\(\s*"([^"\\]*)"\s*[,)]"#,
        ].map { try NSRegularExpression(pattern: $0) }
        let sources = try XCTUnwrap(FileManager.default.enumerator(
            at: root.appendingPathComponent("Dredfit"), includingPropertiesForKeys: nil))

        var checked = 0
        for case let url as URL in sources where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(src.startIndex..<src.endIndex, in: src)
            for pattern in patterns {
                for match in pattern.matches(in: src, range: range) {
                    guard let found = Range(match.range(at: 1), in: src) else { continue }
                    let literal = String(src[found])
                    // An empty literal is a spacer, not a sentence.
                    guard !literal.isEmpty else { continue }
                    checked += 1
                    XCTAssertTrue(keys.contains(literal),
                                  "\(url.lastPathComponent): \"\(literal)\" is not in the catalog")
                }
            }
        }
        XCTAssertGreaterThan(checked, 100, "the scan found almost nothing — check the pattern")
    }

    // SNIPPED v2.26 (§37.0): five tests of the pain line and the pain cut.
    // "Time to see a specialist" counted reports over a movement's history and
    // the card's "fewer sets for now — you said this one hurt" explained a cut
    // the pain channel made. Neither has an input any more.
    //
    // What stays is the rung the person cannot otherwise account for — a set
    // coming BACK — and it matters more now, not less: sets are taken off by
    // the person's own handle, so the card has to say when the engine hands one
    // back on its own.
}
