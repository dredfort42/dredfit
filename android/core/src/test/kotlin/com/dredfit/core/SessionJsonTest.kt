//
//  The session's wire shape against what Swift actually writes. Journal
//  records and the rating undo embed a `Session`, so a backup crosses the two
//  ports only if both read and write it the same way.
//
//  swift/sessions.json was written by Swift's plain `JSONEncoder` over
//  `Engine.generateSession` (android/tools/swift-backup-probe, regenerate.sh):
//  [0] the initial plan, [1] counter 1 with the bar, [2] the first uneven plan
//  of a run (`loads`), [3] the first plan of that run with a `probe`.
//

package com.dredfit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SessionJsonTest {

    private val swift: JsonArray by lazy {
        val text = assertNotNull(javaClass.getResource("/swift/sessions.json")).readText()
        Json.parseToJsonElement(text) as JsonArray
    }

    @Test
    fun swiftSessionsDecodeAndReencodeToTheSameJson() {
        assertEquals(4, swift.size)
        for (element in swift) {
            val session = Session.fromJson(element)
            assertEquals(normal(element), normal(session.toJson()), "session ${session.sessionNumber}")
        }
    }

    @Test
    fun theFixtureCoversLoadsAndAProbe() {
        val sessions = swift.map { Session.fromJson(it) }
        assertTrue(sessions.any { s -> s.exercises.any { it.loads != null } }, "an uneven plan")
        assertTrue(sessions.any { s -> s.exercises.any { it.probe != null } }, "a probe")
    }

    /** The decoded plan is the plan this engine draws from the same state —
     *  the two ports agree on the content, not only on the shape. */
    @Test
    fun theInitialPlanIsTheOneKotlinDraws() {
        assertEquals(Engine.generateSession(EngineState.initial), Session.fromJson(swift[0]))
        val barState = EngineState.initial.also { it.counter = 1; it.hasBar = true }
        assertEquals(Engine.generateSession(barState), Session.fromJson(swift[1]))
    }

    /** `setsFloor` is service state: never written, and `copy()` keeps it. */
    @Test
    fun setsFloorStaysOffTheWireAndSurvivesCopy() {
        val ex = Engine.generateSession(EngineState.initial).exercises.first()
        val probing = SessionExercise.fromJson(ex.toJson()).copy(setsFloor = 1)
        assertTrue("setsFloor" !in probing.toJson())
        assertEquals(1, probing.copy(sets = 4).setsFloor)
        assertEquals(probing, probing.copy(setsFloor = 2), "two plans that differ only here are the same plan")
    }

    /** A record from before v3 carries `tier`, no `variation`: it reads as
     *  variation 0 rather than being dropped. An unknown pattern throws, as
     *  Swift's synthesized decoding does. */
    @Test
    fun legacyExerciseReadsAsVariationZeroAndUnknownPatternThrows() {
        val legacy = Json.parseToJsonElement("""
            {"pattern":"squat","name":"Box squat","tier":2,"unit":"reps","load":8,"perSide":false,
             "sets":3,"restSetSec":60,"restExerciseSec":60}""")
        val ex = SessionExercise.fromJson(legacy)
        assertEquals(0, ex.variation)
        assertEquals(null, ex.loads)
        val unknown = Json.parseToJsonElement(legacy.toString().replace("\"squat\"", "\"handstand\""))
        assertFailsWith<SwiftDecodingException> { SessionExercise.fromJson(unknown) }
    }

    /** A Swift `Date` read here and written back is the same Double. */
    @Test
    fun aSwiftDateRoundTripsExactly() {
        for (seconds in listOf(809_895_600.0, 810_987_690.123456, -1.5, 0.000_001, 1.234_567_891_234e9)) {
            val instant = assertNotNull(SwiftJson.date(JsonPrimitive(seconds)))
            assertEquals(seconds, SwiftJson.sinceReference(instant))
            assertEquals(instant, SwiftJson.swiftDate(instant))
        }
    }

    /** Key order is a hash order on the Swift side and numbers print
     *  differently (`24` against `24.0`); neither is part of the shape. */
    private fun normal(e: JsonElement): Any? = when (e) {
        is JsonObject -> e.mapValues { normal(it.value) }
        is JsonArray -> e.map { normal(it) }
        is JsonNull -> null
        is JsonPrimitive -> if (e.isString) e.content
            else e.content.toBooleanStrictOrNull() ?: BigDecimal(e.content).stripTrailingZeros()
    }
}
