//
//  Port of ios/DredfitTests/SetsNoticeTests.swift: what the app SAYS about a
//  set count that moved on its own, and the catalog guards — a sentence
//  nobody translated is a sentence six languages fall back to English on.
//  Swift's extensions (+Credit, +PullCap) are SetsNoticeTestCredit and
//  SetsNoticeTestPullCap, on the shared `SetsNoticeTestCase` below.
//
//  The catalogs and the iOS sources are read in place (`IosCatalogs`). Two
//  scans change subject on this side, because on Android the call sites are
//  Kotlin:
//  - `everyPlainLocalizedLiteralIsACatalogKey` scans the Kotlin sources' keyed
//    calls (`tr("…")`, `Words.of("…")`, `Words.keyed("…", …)`) against the
//    four catalogs `tr` looks up — the widget's sources (widgets/) among
//    them, against the widget catalog like the rest.
//  - `everyCatalogKeyIsStillAskedForBySomeSource` asks whether a key has a
//    caller on EITHER platform: the catalogs are shared, so a key only iOS
//    asks for is alive, and one neither asks for is six translations nobody
//    reads. The Android-only catalog's keys need a Kotlin caller.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.store.AppStore
import com.dredfit.store.aSetJustCameBack
import com.dredfit.store.nextSession
import com.dredfit.ui.today.ExerciseRow
import kotlinx.serialization.json.JsonObject
import java.nio.file.Files
import java.nio.file.Path
import java.time.LocalDate
import java.time.ZoneId
import kotlin.io.path.extension
import kotlin.io.path.name
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/** The helpers every SetsNotice suite shares — Swift's one class body. */
abstract class SetsNoticeTestCase : AppStoreTestCase() {

    private var trained = 0

    /** One workout every two calendar days, so no gap ever reads as a break. */
    fun train(store: AppStore, result: FeedbackResult = FeedbackResult.plan,
              setsSkipped: Map<Pattern, Int> = emptyMap()): Session {
        val session = store.nextSession
        trained += 1
        val zone = ZoneId.systemDefault()
        val date = LocalDate.now(zone).plusDays(-400L + trained * 2).atStartOfDay(zone).toInstant()
        store.completeWorkout(session = session, result = result, setsSkipped = setsSkipped, date = date)
        return session
    }
}

class SetsNoticeTest : SetsNoticeTestCase() {

    /** Seeded in the v3 shape through the state file, at the grid FLOOR of
     *  each variation: the plan offers a probe only at the ceiling, and a
     *  probe takes a working set out — the number this suite reads. */
    private fun store(variation: Int = 4): AppStore {
        fun at(p: Pattern) = minOf(variation, Library.count(p))
        fun floorDose(p: Pattern, v: Int) = Dose.grid(Library.unit(p, v)).min
        val journal = Pattern.allCases.joinToString(",") { p ->
            val rows = (1..at(p)).joinToString(",") { "\"$it\":${floorDose(p, it)}" }
            "\"${p.rawValue}\",{$rows}"
        }
        val store = storeFrom("""
            {"engineState":{"counter":0,"vars":[${pairs { at(it) }}],"doses":[${pairs { floorDose(it, at(it)) }}],
                            "shown":[$journal],"failStreak":[${pairs { 0 }}]},
             "records":[],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
        assertEquals(at(Pattern.pull), store.engineState.vars[Pattern.pull],
                     "the seed did not load: the pull slot is not where it was written")
        assertEquals(floorDose(Pattern.pull, at(Pattern.pull)),
                     store.engineState.shownDose(Pattern.pull, variation = at(Pattern.pull)),
                     "the seed did not load: the journal of what was shown is not there")
        return store
    }

    private fun pull(session: Session): SessionExercise =
        assertNotNull(session.exercises.firstOrNull { it.pattern == Pattern.pull })

    /** A set comes back, and the card says so — on the appearance the set
     *  actually arrives on. Taken off by the PERSON: only the engine knows
     *  why it came back. */
    @Test
    fun theCardSaysWhenASetComesBack() {
        val store = store()
        train(store, setsSkipped = mapOf(Pattern.pull to 1))
        assertTrue(store.engineState.cutOf(Pattern.pull) > 0,
                   "the skipped set did not land as a cut — there is no trajectory")

        var announced = 0
        var seenBack = false
        repeat(12) {
            val plan = store.nextSession
            if (store.aSetJustCameBack(pull(plan))) announced += 1
            val before = pull(plan).sets
            train(store)
            if (pull(store.nextSession).sets > before) seenBack = true
        }
        assertTrue(seenBack, "no set ever came back — the trajectory proves nothing")
        assertTrue(announced > 0, "a set came back with nothing said about it")
    }

    /** The plan is the default state of the app and must stay quiet. */
    @Test
    fun anUntouchedPlanCarriesNoLine() {
        val store = store()
        for (ex in store.nextSession.exercises) assertFalse(store.aSetJustCameBack(ex))
    }

    // MARK: - The catalog (all shipping languages)

    /** The LIVE keys of the lines, in every shipping language, checked
     *  against the file rather than the generated resources. */
    @Test
    fun theListedLinesAreInTheCatalogInEveryLanguage() {
        val strings = IosCatalogs.strings("Dredfit/Localizable.xcstrings")
        val keys = listOf(
            "A set is back.",
            "Make it easier",
            "Enter what you actually did. The plan follows your numbers.",
            "Skip this set",
            "Skip remaining sets",
            "The plan keeps this set off next time. Nothing else about the movement changes.",
            "The probe just comes back next time. The working sets lose nothing.",
            "technique.stepDown.kicker",
            "technique.stepDown.switch",
            "technique.stepDown.unitToHold",
            "technique.stepDown.unitToReps",
            "technique.stepDown.a11ySwitch",
            "technique.stepDown.confirmTitle",
            "technique.stepDown.confirmBody",
            "plan.techniqueHint",
            "plan.probeNote",
            "plan.heldBackByPulls",
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
        )
        for (key in keys) {
            val entry = strings[key] as? JsonObject ?: fail("$key is not in the catalog at all")
            for (lang in listOf("en", "ru", "es", "pt-BR", "de", "fr", "it")) {
                assertFalse(IosCatalogs.unit(entry, lang)?.isEmpty() ?: true, "$key is missing $lang")
                assertEquals("translated", IosCatalogs.unit(entry, lang, field = "state"), "$key: $lang")
            }
        }
    }

    /** The one rung left says something, and nothing when there is nothing
     *  to say. Not compared against the wording: a translation is correct. */
    @Test
    fun theNoteSaysSomethingAndOnlyWhenThereIsSomethingToSay() {
        assertFalse(ExerciseRow.note(setCameBack = true)?.english?.isEmpty() ?: true)
        assertNull(ExerciseRow.note(setCameBack = false))
    }

    /** The row's number does not count the probe, so the note names the set
     *  standing after it; without a probe the row says nothing. */
    @Test
    fun anExerciseWithAProbeSaysSoOnThePlan() {
        val probe = SessionProbe(variation = 3, name = "Bar hang", unit = LoadUnit.hold, load = 15, perSide = false)
        val withProbe = SessionExercise(pattern = Pattern.pull, name = "Inverted row", variation = 2,
                                        unit = LoadUnit.reps, load = 15, perSide = false, sets = 2, restSetSec = 60,
                                        restExerciseSec = 90, loads = null, probe = probe)
        val line = assertNotNull(ExerciseRow.probeNote(withProbe)).english
        assertTrue("Bar hang" in line, "the note must name the movement the probe offers: $line")
        assertTrue(probe.display in line, "the note must carry the probe's own dose: $line")

        val plain = withProbe.copy(sets = 3, probe = null)
        assertNull(ExerciseRow.probeNote(plain))
        assertEquals(emptyList(), ExerciseRow.notes(plain, setCameBack = false))
        assertEquals(2, ExerciseRow.notes(withProbe, setCameBack = true).size,
                     "a set coming back and a probe are two facts, not one sentence")
    }

    /** A text key (its own English) can never carry `%1$@`: nothing generates
     *  one, so such a key is never looked up. A KEYED entry is exempt — its
     *  value is free to reorder arguments. */
    @Test
    fun noTextKeyCarriesPositionalSpecifiers() {
        val identifier = Regex("""^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9-]+)+$""")
        val positional = Regex("""%\d+\$""")
        for (catalog in listOf("Dredfit/Localizable.xcstrings", "DredfitWidgets/Localizable.xcstrings")) {
            for (key in IosCatalogs.strings(catalog).keys) {
                if (identifier.containsMatchIn(key)) continue
                assertFalse(positional.containsMatchIn(key),
                            "$catalog: \"$key\" is a text key with a positional specifier — the runtime " +
                                "looks up the bare form and never finds this entry")
            }
        }
    }

    /** Every key the Android sources ask for by literal is a key a catalog
     *  carries: one that is not falls back to English in all six languages.
     *  (See the header for why the scan reads Kotlin here.) */
    @Test
    fun everyPlainLocalizedLiteralIsACatalogKey() {
        val keys = CATALOGS.flatMap { IosCatalogs.strings(it).keys }.mapTo(HashSet(), ::normalized)
        // A key with a Kotlin template in it is built at run time, not asked
        // for by literal (`"$key.step${i + 1}"`): the scan cannot read it.
        val call = """(?:(?<![\w.])tr\(|Words\.of\(|Words\.keyed\()"""
        val literal = Regex(call + """\s*"((?:[^"\\\n]|\\.)*)"""")
        var checked = 0
        for (file in kotlinSources()) {
            for (match in literal.findAll(Files.readString(file))) {
                val text = match.groupValues[1]
                if (Regex("""(?<!\\)\$""").containsMatchIn(text)) continue
                val key = normalized(unescaped(text))
                if (key.isEmpty()) continue
                checked += 1
                assertTrue(key in keys, "${file.name}: \"$text\" is in no catalog")
            }
        }
        // 89 on 09.10.2026; the floor only proves the scan found the calls.
        assertTrue(checked > 50, "the scan of the Kotlin sources found almost nothing ($checked)")
    }

    /** The reverse: every key the shared catalogs carry is a literal some
     *  source — Swift or Kotlin — still asks for. Comments are stripped: a
     *  sentence quoted in a comment is not a caller. */
    @Test
    fun everyCatalogKeyIsStillAskedForBySomeSource() {
        val kotlin = askedFor(kotlinSources())
        assertKeysAreLiterals(sources = "Dredfit", catalog = "Dredfit/Localizable.xcstrings", alsoAsked = kotlin)
        assertKeysAreLiterals(sources = "DredfitWidgets", catalog = "DredfitWidgets/Localizable.xcstrings",
                              alsoAsked = kotlin, minimum = 10)
        // The Android-only catalog has no Swift caller by definition.
        for (key in IosCatalogs.strings(ANDROID_CATALOG).keys) {
            assertTrue(normalized(key) in kotlin, "$ANDROID_CATALOG: \"$key\" has no caller left in the Android sources")
        }
    }

    /** A key in the Android-only catalog AND a shared one would be two
     *  translations of one key, and `tr` would read whichever it asks first. */
    @Test
    fun theAndroidCatalogRepeatsNoSharedKey() {
        val android = IosCatalogs.strings(ANDROID_CATALOG).keys
        assertTrue(android.isNotEmpty(), "the Android catalog read as empty")
        for (catalog in CATALOGS - ANDROID_CATALOG) {
            val shared = IosCatalogs.strings(catalog).keys intersect android
            assertTrue(shared.isEmpty(), "$catalog repeats $shared")
        }
    }

    /** The scan's own arithmetic, pinned directly. */
    @Test
    fun theScanNormalisesSourceAndCatalogToTheSameForm() {
        // An escaped literal and the catalog's real newline are the same key.
        assertEquals(normalized("First\nSecond"), normalized(unescaped("""First\nSecond""")))
        assertEquals(normalized("He said \"go\"."), normalized(unescaped("""He said \"go\".""")))
        // Interpolation against its specifier, two in a row included.
        assertEquals(normalized("%lld × %lld%@"), normalized("""\(sets) × \(dose)\(side)"""))
        assertEquals(normalized("%1\$@ · %2\$@"), normalized("""\(a) · \(b)"""),
                     "positional and bare forms name the same string")
        // A nested call is one token, not two.
        assertEquals(normalized("was %@."), normalized("""was \(date.formatted(.relative(presentation: .named)))."""))
        // A lone percent is a percent sign, and must not eat what follows.
        assertEquals(normalized("""100% of \(x)"""), normalized("100% of %@"))
        // A multi-line body's continuations and indentation are layout.
        assertEquals(normalized("Two lines"), normalized("Two\n    lines"))
        // And two different strings must NOT collide.
        assertNotEquals(normalized("%lld reps"), normalized("%lld sets"))
    }

    // MARK: - The scan

    private fun assertKeysAreLiterals(sources: String, catalog: String, alsoAsked: Set<String>, minimum: Int = 100) {
        val asked = askedFor(swiftSources(sources))
        assertTrue(asked.size > minimum, "the scan of $sources found almost nothing")
        for (key in IosCatalogs.strings(catalog).keys) {
            val form = normalized(key)
            if (form in asked || form in alsoAsked) continue
            fail("$catalog: \"$key\" has no caller left in $sources or the Android sources — " +
                     "a dead key is six translations nobody reads")
        }
    }

    /** Every quoted literal of the files, comments stripped, normalised. */
    private fun askedFor(files: List<Path>): Set<String> {
        val q = "\\x22"
        val literal = Regex("$q{3}([\\s\\S]*?)$q{3}|$q((?:[^$q\\\\\\n]|\\\\.)+)$q")
        val lineComment = Regex("//[^\\n]*")
        val blockComment = Regex("/\\*[\\s\\S]*?\\*/")
        val asked = HashSet<String>()
        for (file in files) {
            var src = Files.readString(file)
            for (stripper in listOf(blockComment, lineComment)) src = stripper.replace(src, "")
            for (match in literal.findAll(src)) {
                val body = match.groups[1]?.value ?: match.groups[2]?.value ?: continue
                asked += normalized(unescaped(body))
            }
        }
        return asked
    }

    private fun swiftSources(dir: String): List<Path> =
        Files.walk(IosCatalogs.iosRoot.resolve(dir)).use { s -> s.filter { it.extension == "swift" }.toList() }

    /** The app's hand-written Kotlin: the generated lookups under l10n/ name
     *  every key and would make the reverse scan vacuous. */
    private fun kotlinSources(): List<Path> =
        Files.walk(IosCatalogs.iosRoot.resolveSibling("android/app/src/main/kotlin")).use { s ->
            s.filter { it.extension == "kt" && "l10n" !in it.map(Path::toString) }.toList()
        }

    companion object {
        /** The strings only Android says, beside the three shared catalogs
         *  (scripts/export_android_strings.py says why it is its own). */
        const val ANDROID_CATALOG = "../android/app/Localizable.xcstrings"

        private val CATALOGS = listOf("Dredfit/Localizable.xcstrings", "DredfitWidgets/Localizable.xcstrings",
                                      "DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings",
                                      ANDROID_CATALOG)

        /** What the compiler makes of a source literal: `\n`/`\t` are layout,
         *  `\x` is `x`; `\(` (an interpolation) and a line continuation stay
         *  for `normalized`. Swift's `SetsNoticeTests.unescaped`. */
        fun unescaped(text: String): String {
            val out = StringBuilder()
            var i = 0
            while (i < text.length) {
                if (text[i] != '\\' || i + 1 >= text.length) {
                    out.append(text[i]); i += 1; continue
                }
                when (val next = text[i + 1]) {
                    '(', '\n' -> out.append('\\').append(next)
                    'n', 't' -> out.append(' ')
                    else -> out.append(next)
                }
                i += 2
            }
            return out.toString()
        }

        /** Interpolations and format specifiers each become ONE token, and
         *  runs of whitespace one space. Swift's `SetsNoticeTests.normalized`,
         *  step for step: an interpolation anywhere is taken before a `%`. */
        fun normalized(text: String): String {
            val out = StringBuilder()
            var rest = text
            while (true) {
                val open = rest.indexOf("\\(").takeIf { it >= 0 } ?: rest.indexOf('%').takeIf { it >= 0 } ?: break
                out.append(rest, 0, open)
                rest = rest.substring(open)
                if (rest.startsWith("\\(")) {
                    // Balanced, so a nested call like `\(a.b(c))` is one token.
                    var depth = 0
                    var index = 1
                    while (index < rest.length) {
                        if (rest[index] == '(') depth += 1
                        if (rest[index] == ')') {
                            depth -= 1
                            if (depth == 0) break
                        }
                        index += 1
                    }
                    if (index >= rest.length) break
                    rest = rest.substring(index + 1)
                } else {
                    // EXACTLY ONE specifier, never a run of them.
                    var scan = rest.substring(1).dropWhile { it.isDigit() }
                    scan = if (scan.startsWith("$")) scan.substring(1) else rest.substring(1)
                    val width = listOf("@", "lld", "d", "f").firstOrNull { scan.startsWith(it) }
                    if (width == null) {
                        // A lone "%" is a percent sign, not a placeholder.
                        out.append('%')
                        rest = rest.substring(1)
                        continue
                    }
                    rest = scan.substring(width.length)
                }
                out.append('￼')
            }
            out.append(rest)
            // Unicode whitespace, as Swift's `isWhitespace` — `\s` would miss a
            // no-break space.
            return out.toString().replace("\\\n", " ").map { if (it.isWhitespace()) ' ' else it }
                .joinToString("").split(' ').filter { it.isNotEmpty() }.joinToString(" ")
        }
    }
}
