//
//  What the app SAYS about a set count that moved on its own.
//
//  Sets move without levels: a movement whose sets the person skipped comes
//  back with fewer of them, and comes back UP again as the engine hands them
//  over one good session at a time. A plan that quietly got easier reads as a
//  bug exactly the way a plan that quietly got harder does — so the one moment
//  the person cannot account for, a set arriving back, gets a sentence on the
//  card.
//
//  The suite also carries the catalog guards, because a sentence nobody
//  translated is a sentence six languages fall back to English on.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SetsNoticeTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-notice" }

    /// The checkout root, from this file's own compile-time path. Derived in
    /// ONE place — same reasoning as `LifeBenefitTests.repoRoot`: the two
    /// `deletingLastPathComponent()` steps used to be written out twice
    /// below, so moving this file one directory would have had to be noticed
    /// twice, and each copy fails with "no such file" rather than a clear
    /// mis-derived-path error.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DredfitTests/
            .deletingLastPathComponent()   // repo root
    }

    /// Seeded through the state file, like the app's own load. The pull slot
    /// is in every session, so it is the movement a trajectory can be walked
    /// on without waiting for the rotation.
    ///
    /// SEEDED IN THE v3 SHAPE — `vars`/`doses`/`shown`, never `levels`. The v2
    /// shape this carried decoded into nothing for a whole release cycle
    /// (§40.8) and nothing here checked: the store started clean and the
    /// trajectory below was walked from the first rung of every ladder, not
    /// from the position the seed named. The guard after the load is what
    /// makes the seed a fact rather than a hope.
    ///
    /// The dose is the grid FLOOR of the seeded variation, and that is what
    /// keeps the twelve appearances below free of probes: §40.4 offers one
    /// only at the dose ceiling, and one growth event per session cannot walk
    /// a whole grid in twelve. A probe takes a working set out of the plan,
    /// which is precisely the number this suite reads.
    private func store(variation: Int = 4) throws -> AppStore {
        func at(_ p: Pattern) -> Int { min(variation, Library.count(p)) }
        func floorDose(_ p: Pattern, _ v: Int) -> Int { Dose.grid(Library.unit(p, v)).min }
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(at($0))" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(floorDose($0, at($0)))" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        // The journal of what was shown: a descent lands IN it (§40.6), so a
        // state without one would send every movement to the floor of the
        // first variation whatever the seed said.
        let journal = Pattern.allCases.map { p in
            let rows = (1...at(p)).map { "\"\($0)\":\(floorDose(p, $0))" }.joined(separator: ",")
            return "\"\(p.rawValue)\",{\(rows)}"
        }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"vars":[\(vars)],"doses":[\(doses)],
                        "shown":[\(journal)],"failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        // The seed must actually load — a state that failed to decode would
        // start clean and make every assertion here vacuous. Both coordinates
        // are checked: the position, and the journal a clean start has none of.
        XCTAssertEqual(store.engineState.vars[.pull], at(.pull),
                       "the seed did not load: the pull slot is not where it was written")
        XCTAssertEqual(store.engineState.shownDose(.pull, variation: at(.pull)),
                       floorDose(.pull, at(.pull)),
                       "the seed did not load: the journal of what was shown is not there")
        return store
    }

    private var trained = 0

    /// One workout, one calendar day apart, so no gap ever reads as a break.
    @discardableResult
    private func train(_ store: AppStore, result: FeedbackResult = .plan,
                       setsSkipped: SetFacts.Skips = [:]) -> Session {
        let session = store.nextSession
        trained += 1
        let date = Calendar.current.date(byAdding: .day, value: -400 + trained * 2,
                                         to: Calendar.current.startOfDay(for: .now))!
        _ = store.completeWorkout(session: session, result: result,
                                  setsSkipped: setsSkipped, date: date)
        return session
    }

    private func pull(_ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == .pull })
    }

    /// The other end of the axis: a set comes back, and the card says so
    /// once — the appearance the set actually arrives on.
    ///
    /// The set is taken off by the PERSON now, mid-workout, not by a pain
    /// report, which makes the sentence matter more rather than less. They
    /// know why it went; only the engine knows why it came back.
    func testTheCardSaysWhenASetComesBack() throws {
        let store = try store()
        // The way a set comes off at all now: skipped during the session, and
        // written by the engine when the rating lands.
        train(store, setsSkipped: [.pull: 1])
        XCTAssertGreaterThan(store.engineState.cutOf(.pull), 0,
                             "the skipped set did not land as a cut — there is no trajectory")

        var announced = 0
        var seenBack = false
        for _ in 0..<12 {
            let plan = store.nextSession
            if try store.aSetJustCameBack(in: pull(plan)) { announced += 1 }
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
            XCTAssertFalse(store.aSetJustCameBack(in: ex))
        }
    }

    // MARK: - The catalog (all shipping languages)

    /// A key the catalog does not carry falls back to English in every
    /// language at once — six locales lost to one missing string, which is
    /// exactly what happened last release. Every sentence the wave's screens
    /// carry, all shipping languages, checked against the file rather than the
    /// bundle.
    func testTheWavesLinesAreInTheCatalogInEveryLanguage() throws {
        let catalogURL = repoRoot.appendingPathComponent("Dredfit/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        // The pain line went with the channel, and the plan's two session
        // handles went the same way — the sentences that replaced them are
        // on the work screen, where the decision is taken now.
        let keys = [
            "A set is back — your body is coping.",
            "Make it easier",
            "Enter what you actually did. The plan follows your numbers.",
            // The two escapes under the button that logs the set, and what
            // the set-level one promises about the next plan.
            "Skip this set",
            "Skip remaining sets",
            "The plan keeps this set off next time. Nothing else about the movement changes.",
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

    /// The one rung left says something, and says nothing when there is
    /// nothing to say. Deliberately not compared against the English wording:
    /// the test runs in whatever language the simulator is set to, and a
    /// translated answer is a correct answer.
    func testTheNoteSaysSomethingAndOnlyWhenThereIsSomethingToSay() {
        XCTAssertFalse(ExerciseRow.note(setCameBack: true)?.isEmpty ?? true)
        XCTAssertNil(ExerciseRow.note(setCameBack: false))
    }

    /// The general form of the same guard, over the whole app: every plain
    /// localized literal the sources ask for is a key the catalog carries.
    ///
    /// The scan covers `Text("…")` and `Button("…")` as well as
    /// `String(localized: "…")`. It did not before, and that is precisely the
    /// hole finding S5-4 came through — a SwiftUI `Text` literal is localized
    /// through the same catalog, so a sentence typed straight into a view
    /// looks fine in English and falls back to English everywhere else.
    ///
    /// One key that is not there — a rename on one side, a sentence typed
    /// straight into a view — and the string falls back to English in all six
    /// translated languages at once, which is how last release lost them.
    func testEveryPlainLocalizedLiteralIsACatalogKey() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Dredfit/Localizable.xcstrings"))
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
            at: repoRoot.appendingPathComponent("Dredfit"), includingPropertiesForKeys: nil))

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

    // SNIPPED: five tests of the pain line and the pain cut. "Time to see a
    // specialist" counted reports over a movement's history and the card's
    // "fewer sets for now — you said this one hurt" explained a cut the pain
    // channel made. Neither has an input any more.
    //
    // What stays is the rung the person cannot otherwise account for — a set
    // coming BACK — and it matters more now, not less: sets are taken off by
    // the person's own handle, so the card has to say when the engine hands one
    // back on its own.
}
