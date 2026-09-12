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
    /// ONE place — same reasoning as `LifeBenefitTests.iosRoot`: the two
    /// `deletingLastPathComponent()` steps used to be written out twice
    /// below, so moving this file one directory would have had to be noticed
    /// twice, and each copy fails with "no such file" rather than a clear
    /// mis-derived-path error.
    /// Two steps up is `ios/` — the platform root, not the repository root,
    /// since the Swift side moved under it. Every catalog this test opens
    /// lives under `ios/`, so the paths below stay relative to it.
    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DredfitTests/
            .deletingLastPathComponent()   // ios/
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
    ///
    /// The keys are the LIVE ones. Three entries here kept naming sentences
    /// that later waves had reworded on screen, so the catalog carried three
    /// dead keys nobody could delete without going red — a pin that guards
    /// the corpse rather than the string (12.09.2026).
    func testTheWavesLinesAreInTheCatalogInEveryLanguage() throws {
        let catalogURL = iosRoot.appendingPathComponent("Dredfit/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        // The pain line went with the channel, and the plan's two session
        // handles went the same way — the sentences that replaced them are
        // on the work screen, where the decision is taken now. `Easier · %@`
        // went with the third: R30 moved the variation handle into the
        // technique sheet, and the six keys below are what it says there.
        let keys = [
            "A set is back.",
            "Make it easier",
            "Enter what you actually did. The plan follows your numbers.",
            // The two escapes under the button that logs the set, and what
            // the set-level one promises about the next plan.
            "Skip this set",
            "Skip remaining sets",
            "The plan keeps this set off next time. Nothing else about the movement changes.",
            "The probe just comes back next time. The working sets lose nothing.",
            // The handle's own line left the plan with the handle (R30). What
            // stands in its place is the block in the technique sheet and the
            // one line that says the sheet is there.
            "technique.stepDown.kicker",
            "technique.stepDown.switch",
            "technique.stepDown.unitToHold",
            "technique.stepDown.unitToReps",
            "technique.stepDown.a11ySwitch",
            "technique.stepDown.confirmTitle",
            "technique.stepDown.confirmBody",
            "plan.techniqueHint",
            "plan.probeNote",
            "%lld positions · about %lld min",
            "Going all out on one set weakens the ones after it. What counts is the whole exercise.",
            "Cool-down",
            "Start the cool-down",
            "cooldown.skip",
            "The work is done. A few minutes of stretching helps it settle. Some of the positions follow the movements you did today.",
            "Warm-up",
            "Start the warm-up",
            "Skip warm-up",
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

    /// The row's number does not count the probe — `sets` is already one lower,
    /// because the probe replaces the last of them (§40.4). So a plan of three
    /// sets whose third is a probe read "2 × 15" and said nothing about the set
    /// standing after it, while the announced duration counted it.
    ///
    /// Both halves asserted: the line names the movement the probe offers, and
    /// an exercise without a probe says nothing at all — a note that always
    /// appears is not a note.
    func testAnExerciseWithAProbeSaysSoOnThePlan() throws {
        let probe = SessionProbe(variation: 3, name: "Bar hang", unit: .hold,
                                 load: 15, perSide: false)
        let withProbe = SessionExercise(
            pattern: .pull, name: "Inverted row", variation: 2, unit: .reps,
            load: 15, perSide: false, sets: 2, restSetSec: 60, restExerciseSec: 90,
            loads: nil, probe: probe)
        let line = try XCTUnwrap(ExerciseRow.probeNote(withProbe))
        XCTAssertTrue(line.contains("Bar hang"),
                      "the note must name the movement the probe offers: \(line)")
        XCTAssertTrue(line.contains(probe.display),
                      "the note must carry the probe's own dose: \(line)")

        let plain = SessionExercise(
            pattern: .pull, name: "Inverted row", variation: 2, unit: .reps,
            load: 15, perSide: false, sets: 3, restSetSec: 60, restExerciseSec: 90,
            loads: nil, probe: nil)
        XCTAssertNil(ExerciseRow.probeNote(plain))
        XCTAssertEqual(ExerciseRow.notes(plain, setCameBack: false), [])
        XCTAssertEqual(ExerciseRow.notes(withProbe, setCameBack: true).count, 2,
                       "a set coming back and a probe are two facts, not one sentence")
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
    /// A key that IS its own English text can never carry `%1$@`-style
    /// specifiers, because nothing generates one: `String(localized:)` and
    /// `Text(_:)` build the key from the interpolation and always emit the
    /// bare `%@` / `%lld` form. A positional key is therefore a key nothing
    /// will ever look up — the string falls back to English in all six
    /// languages while both gates stay green, since the completeness check
    /// only asks whether the catalog's own keys are translated, and the scan
    /// above normalises the two forms to the same token on purpose.
    ///
    /// Six of them were written by hand in one wave (self-review 06.09.2026).
    /// A KEYED entry is exempt and stays exempt: its key is an identifier, so
    /// its value is free to reorder arguments, which is the whole reason
    /// positional specifiers exist.
    func testNoTextKeyCarriesPositionalSpecifiers() throws {
        for catalog in ["Dredfit/Localizable.xcstrings", "DredfitWidgets/Localizable.xcstrings"] {
            let data = try Data(contentsOf: iosRoot.appendingPathComponent(catalog))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let keys = try XCTUnwrap(json["strings"] as? [String: Any]).keys
            let identifier = try NSRegularExpression(
                pattern: #"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9-]+)+$"#)
            let positional = try NSRegularExpression(pattern: #"%\d+\$"#)
            for key in keys {
                let range = NSRange(key.startIndex..<key.endIndex, in: key)
                guard identifier.firstMatch(in: key, range: range) == nil else { continue }
                XCTAssertNil(positional.firstMatch(in: key, range: range),
                             "\(catalog): \"\(key)\" is a text key with a positional "
                                + "specifier — the runtime looks up the bare form and "
                                + "never finds this entry")
            }
        }
    }

    func testEveryPlainLocalizedLiteralIsACatalogKey() throws {
        // BOTH catalogs, each against its own sources. The widget target was
        // never scanned at all, and three of its strings were missing when a
        // review finally looked (self-review 05.09.2026).
        try assertLiteralsAreKeys(sources: "Dredfit", catalog: "Dredfit/Localizable.xcstrings")
        try assertLiteralsAreKeys(sources: "DredfitWidgets",
                                  catalog: "DredfitWidgets/Localizable.xcstrings",
                                  minimum: 10)
    }

    /// Comparison runs on a NORMALISED form: every interpolation in the source
    /// and every format specifier in the catalog collapses to one token, and
    /// runs of whitespace collapse to a single space.
    ///
    /// That is what lets the scan cover the two shapes it used to be blind to,
    /// and both had really gone missing by the time anyone checked:
    ///
    /// - INTERPOLATED literals. The old scan excluded a backslash on purpose,
    ///   reasoning that the catalog key is the `%@`/`%lld` form rather than
    ///   the source text — true, and it meant `"≈ \(floor)–\(full) min"` was
    ///   never checked against anything.
    /// - MULTI-LINE literals. Every pattern wanted `"…"` on one line, so a
    ///   `"""` block was invisible; a reworded alert orphaned its old key and
    ///   the new one reached no catalog.
    ///
    /// Normalising both sides costs the ability to catch a wrong specifier
    /// TYPE (`%@` where `%lld` belongs), which no test here ever had. What it
    /// buys is that a string cannot go missing entirely, which is the failure
    /// that actually happens: English in all six languages, both gates green.
    /// The reverse of the scan above: every key the catalog carries is a
    /// literal some source file still asks for. Eleven keys sat in the
    /// catalog with no caller left — three of them pinned by name in
    /// `testTheWavesLinesAreInTheCatalogInEveryLanguage` after later waves
    /// had reworded the sentences on screen, so nobody could delete the
    /// corpses without going red, and six languages went on being asked to
    /// keep them translated (12.09.2026).
    ///
    /// Comments are stripped first: a sentence quoted in a comment is not a
    /// caller, and four of the eleven were found by a plain grep exactly
    /// that way. Every quoted literal counts, whatever construct it stands
    /// in — `Label`, `Section`, `.alert` — because the question here is
    /// only whether the key is asked for at all.
    func testEveryCatalogKeyIsStillAskedForBySomeSource() throws {
        try assertKeysAreLiterals(sources: "Dredfit", catalog: "Dredfit/Localizable.xcstrings")
        try assertKeysAreLiterals(sources: "DredfitWidgets",
                                  catalog: "DredfitWidgets/Localizable.xcstrings",
                                  minimum: 10)
    }

    private func assertKeysAreLiterals(sources: String, catalog: String,
                                       minimum: Int = 100,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) throws {
        let data = try Data(contentsOf: iosRoot.appendingPathComponent(catalog))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = try XCTUnwrap(json["strings"] as? [String: Any]).keys
        let quote = #"\x22"#
        let literal = try NSRegularExpression(
            pattern: quote + "{3}" + #"([\s\S]*?)"# + quote + "{3}"
                + #"|"# + quote + #"((?:[^"# + quote + #"\\\n]|\\.)+)"# + quote)
        let lineComment = try NSRegularExpression(pattern: #"//[^\n]*"#)
        let blockComment = try NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)

        let dir = iosRoot.appendingPathComponent(sources)
        let found = try XCTUnwrap(FileManager.default.enumerator(at: dir,
                                                                 includingPropertiesForKeys: nil))
        var asked = Set<String>()
        for case let url as URL in found where url.pathExtension == "swift" {
            var src = try String(contentsOf: url, encoding: .utf8)
            for stripper in [blockComment, lineComment] {
                src = stripper.stringByReplacingMatches(
                    in: src, range: NSRange(src.startIndex..<src.endIndex, in: src),
                    withTemplate: "")
            }
            let whole = NSRange(src.startIndex..<src.endIndex, in: src)
            for match in literal.matches(in: src, range: whole) {
                let body = Range(match.range(at: 1), in: src)
                    ?? Range(match.range(at: 2), in: src)
                guard let body else { continue }
                asked.insert(Self.normalized(Self.unescaped(String(src[body]))))
            }
        }
        XCTAssertGreaterThan(asked.count, minimum, "the scan of \(sources) found almost nothing",
                             file: file, line: line)
        for key in keys where !asked.contains(Self.normalized(key)) {
            XCTFail("\(catalog): \"\(key)\" has no caller left in \(sources) — a dead key "
                    + "is six translations nobody reads", file: file, line: line)
        }
    }

    private func assertLiteralsAreKeys(sources: String, catalog: String,
                                       minimum: Int = 100,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) throws {
        let data = try Data(contentsOf: iosRoot.appendingPathComponent(catalog))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(try XCTUnwrap(json["strings"] as? [String: Any]).keys.map(Self.normalized))

        // `Text(verbatim:)` and `Button(action:)` do not match: both patterns
        // require a quote straight after the paren.
        let call = #"(?:String\(\s*localized:|(?<![\w.])Text\(|(?<![\w.])Button\()"#
        // ONE pass with an alternation, not two passes over the same file: a
        // `"""` body and a single-line body can never both claim the same
        // text, so the overlap that has to be reasoned about simply does not
        // arise. `[\s\S]` rather than `.` plus an option — the body of a block
        // spans lines by definition, and spelling that into the class leaves
        // nothing for a matching option to get wrong.
        //
        // Escapes are allowed in the single-line arm, so an interpolation no
        // longer ends the match. The keyed form
        // `String(localized: "key", defaultValue:)` lands there too and
        // captures the key — which is what the catalog is asked for.
        //
        // The quote is spelled `\x22` throughout. Written literally, a run of
        // three inside a raw string is read by eye as a delimiter by the next
        // person and — as this scan found out — is easy to miscount by one
        // while editing, which silently turns the block arm into "one quote,
        // then anything".
        let quote = #"\x22"#
        let literal = try NSRegularExpression(
            pattern: call + #"\s*(?:"# + quote + "{3}" + #"([\s\S]*?)"# + quote + "{3}"
                + #"|"# + quote + #"((?:[^"# + quote + #"\\\n]|\\.)+)"# + quote + #")"#)

        let dir = iosRoot.appendingPathComponent(sources)
        let found = try XCTUnwrap(FileManager.default.enumerator(at: dir,
                                                                 includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in found where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            let whole = NSRange(src.startIndex..<src.endIndex, in: src)
            for match in literal.matches(in: src, range: whole) {
                // Group 1 is the block body, group 2 the single-line one;
                // exactly one of the two arms took part in any given match.
                let body = Range(match.range(at: 1), in: src)
                    ?? Range(match.range(at: 2), in: src)
                guard let body else { continue }
                let text = String(src[body])
                let key = Self.normalized(Self.unescaped(text))
                // An empty literal is a spacer, not a sentence.
                guard !key.isEmpty else { continue }
                checked += 1
                XCTAssertTrue(keys.contains(key),
                              "\(url.lastPathComponent): \"\(text)\" is not in \(catalog)",
                              file: file, line: line)
            }
        }
        XCTAssertGreaterThan(checked, minimum, "the scan of \(sources) found almost nothing",
                             file: file, line: line)
    }

    /// Interpolations, format specifiers and line breaks all become one token,
    /// so a source literal and its catalog key compare equal.
    /// The scan's own arithmetic, pinned directly: it is the only logic in
    /// this file that a green run does NOT exercise, because the shapes it
    /// handles are the ones no source literal happens to use today. A helper
    /// nobody tests is how a gate starts passing for the wrong reason.
    func testTheScanNormalisesSourceAndCatalogToTheSameForm() {
        // An escaped literal and the catalog's real newline are the same key.
        XCTAssertEqual(Self.normalized(Self.unescaped(#"First\nSecond"#)),
                       Self.normalized("First\nSecond"))
        XCTAssertEqual(Self.normalized(Self.unescaped(#"He said \"go\"."#)),
                       Self.normalized("He said \"go\"."))
        // Interpolation against its specifier, including two in a row — the
        // pair that used to collapse into one token and hid a present key.
        XCTAssertEqual(Self.normalized(#"\(sets) × \(dose)\(side)"#),
                       Self.normalized("%lld × %lld%@"))
        XCTAssertEqual(Self.normalized(#"\(a) · \(b)"#),
                       Self.normalized("%1$@ · %2$@"),
                       "positional and bare forms name the same string")
        // A nested call is one token, not two.
        XCTAssertEqual(Self.normalized(#"was \(date.formatted(.relative(presentation: .named)))."#),
                       Self.normalized("was %@."))
        // A lone percent is a percent sign, and must not eat what follows.
        XCTAssertEqual(Self.normalized("100% of %@"), Self.normalized(#"100% of \(x)"#))
        // A multi-line body's continuations and indentation are layout.
        XCTAssertEqual(Self.normalized("Two\n    lines"), Self.normalized("Two lines"))
        // And two different strings must NOT collide.
        XCTAssertNotEqual(Self.normalized("%lld sets"), Self.normalized("%lld reps"))
    }

    /// What the compiler makes of the source text, on the SOURCE side only:
    /// the catalog's keys arrive through `JSONSerialization` already
    /// unescaped, so touching them again would double-unescape.
    ///
    /// The single-line arm of the scan admits escapes (`\\.`), which is what
    /// lets it see interpolation at all — and the same step made a literal
    /// like `Text("First\nSecond")` visible for the first time. Compared raw,
    /// its two characters `\` and `n` never equal the catalog's real newline,
    /// so a string that IS present and IS translated would be reported
    /// missing, sending the next reader to `verbatim` or to weakening the
    /// assertion (review 06.09.2026). No such literal exists today; this is
    /// the guard that keeps the first one from looking like a catalog bug.
    ///
    /// `\(` is deliberately left standing: it is an interpolation, and
    /// `normalized` is what turns it into a token. A line continuation
    /// (`\` before a real newline) is left too, for the same reason.
    private static func unescaped(_ text: String) -> String {
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "\\", text.index(after: index) < text.endIndex else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let next = text[text.index(after: index)]
            switch next {
            case "(", "\n":
                out.append(text[index])
                out.append(next)
            case "n", "t":
                out.append(" ")
            default:
                out.append(next)
            }
            index = text.index(index, offsetBy: 2)
        }
        return out
    }

    private static func normalized(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "\\(") ?? rest.range(of: "%") {
            out += rest[rest.startIndex..<open.lowerBound]
            rest = rest[open.lowerBound...]
            if rest.hasPrefix("\\(") {
                // Balanced, so a nested call like `\(a.b(c))` is one token.
                var depth = 0
                var index = rest.index(rest.startIndex, offsetBy: 1)
                while index < rest.endIndex {
                    if rest[index] == "(" { depth += 1 }
                    if rest[index] == ")" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    index = rest.index(after: index)
                }
                guard index < rest.endIndex else { break }
                rest = rest[rest.index(after: index)...]
            } else {
                // EXACTLY ONE specifier, never a run of them: scanning by
                // character class swallowed `%lld%@` whole, because `%` is
                // itself in the class — so a two-argument key normalised to
                // one token, stopped matching its own source literal, and the
                // scan reported a key that was present all along.
                var scan = rest.dropFirst()                      // past the "%"
                scan = scan.drop(while: \.isNumber)
                if scan.first == "$" { scan = scan.dropFirst() } else { scan = rest.dropFirst() }
                let width = ["@", "lld", "d", "f"].first { scan.hasPrefix($0) }
                // A lone "%" is a percent sign, not a placeholder.
                guard let width else {
                    out += "%"
                    rest = rest.dropFirst()
                    continue
                }
                rest = scan.dropFirst(width.count)
            }
            out += "\u{FFFC}"
        }
        out += rest
        // A multi-line literal's continuations, indentation and newlines are
        // layout; the catalog key holds the sentence.
        return out.replacingOccurrences(of: "\\\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
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
