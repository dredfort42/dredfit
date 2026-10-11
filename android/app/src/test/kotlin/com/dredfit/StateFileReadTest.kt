//
//  Port of ios/DredfitTests/StateFileReadTests.swift: the one read path of the
//  state file — what it reports, and what it puts aside before anything can
//  be written over it.
//

package com.dredfit

import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.StateFile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assumptions.assumeFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.time.Instant
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.name
import kotlin.io.path.readBytes
import kotlin.io.path.readText
import kotlin.io.path.writeBytes
import kotlin.io.path.writeText
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class StateFileReadTest {

    @TempDir
    lateinit var dir: Path

    private val file: StateFile get() = StateFile(dir.resolve("dredfit-state.json"))

    private fun corruptCopies(): List<Path> = dir.listDirectoryEntries().filter { it.name.contains(".corrupt") }

    private fun keptBytes(): Set<String> = corruptCopies().map { it.readText() }.toSet()

    private fun aRecord() = WorkoutRecord(sessionNumber = 1, date = Instant.ofEpochSecond(1_800_000_000),
                                          result = FeedbackResult.plan)

    @Test
    fun noFileIsAFreshInstall() {
        assertIs<StateFile.Read.Absent>(file.read(reload = false), "nothing on disk reads as absent")
    }

    @Test
    fun aFileThatCannotBeReadIsLeftAlone() {
        // A directory where the file should be: it exists and yields no bytes,
        // the way a file still under data protection does.
        Files.createDirectory(file.path)
        assertIs<StateFile.Read.Unreadable>(file.read(reload = false), "an unreadable file is not a fresh install")
        assertTrue(Files.exists(file.path))
        assertTrue(corruptCopies().isEmpty(), "nothing is moved aside: it may be the only copy")
    }

    @Test
    fun aWrittenStateReadsBack() {
        val state = EngineState.initial.also { it.counter = 7 }
        file.write(AppData(engineState = state, records = emptyList(), settings = AppSettings()))
        val read = assertIs<StateFile.Read.Loaded>(file.read(reload = false), "a written file reads back")
        assertEquals(7, read.data.engineState.counter)
    }

    @Test
    fun aFileThatDoesNotDecodeIsMovedAside() {
        file.path.writeText("not json")
        assertIs<StateFile.Read.Undecodable>(file.read(reload = false), "garbage does not decode")
        assertFalse(Files.exists(file.path), "moved, so the next write cannot overwrite the only copy")
        val copies = corruptCopies()
        assertEquals(1, copies.size)
        assertEquals("not json", copies.first().readText())
    }

    @Test
    fun aSecondFailureNeverReplacesTheFirstCopy() {
        file.path.writeText("first")
        file.read(reload = false)
        file.path.writeText("second")
        file.read(reload = false)
        assertEquals(setOf("first", "second"), keptBytes())
    }

    @Test
    fun anUnreadableEngineStateKeepsTheJournalAndACopy() {
        file.write(AppData(engineState = EngineState.initial, records = listOf(aRecord()), settings = AppSettings()))
        val json = Json.parseToJsonElement(file.path.readText()).jsonObject
        val original = JsonObject(json + ("engineState" to JsonObject(mapOf("from" to JsonPrimitive("a future build")))))
            .toString().toByteArray()
        file.path.writeBytes(original)

        val read = assertIs<StateFile.Read.Loaded>(file.read(reload = false), "the journal beside it is whole")
        assertTrue(read.data.engineStateReset)
        assertEquals(1, read.data.records.size, "the journal survives a state it cannot read")
        assertTrue(Files.exists(file.path), "copied, not moved")
        val copies = corruptCopies()
        assertEquals(1, copies.size)
        assertContentEquals(original, copies.first().readBytes(), "the plan can still be recovered from the copy")
    }

    // MARK: - When nothing can be put aside

    /** A directory the copy cannot be written into: the move and the copy fail
     *  there, and so would the write that follows them. */
    private fun <T> withLockedDirectory(body: () -> T): T {
        assumeFalse(System.getProperty("user.name") == "root", "root writes through 0o555")
        Files.setPosixFilePermissions(dir, PosixFilePermissions.fromString("r-xr-xr-x"))
        try {
            return body()
        } finally {
            Files.setPosixFilePermissions(dir, PosixFilePermissions.fromString("rwxr-xr-x"))
        }
    }

    @Test
    fun aFileThatCannotBeMovedAsideFreezesInsteadOfStartingOver() {
        file.path.writeText("not json")
        withLockedDirectory {
            assertIs<StateFile.Read.Unreadable>(file.read(reload = false),
                                                "with no copy aside, starting over would write over the only one")
            assertEquals("not json", file.path.readText())
        }
    }

    @Test
    fun aPartlyReadableFileThatCannotBeCopiedAsideFreezes() {
        file.path.writeText("""{"engineState":{"from":"a future build"},"records":[]}""")
        withLockedDirectory {
            assertIs<StateFile.Read.Unreadable>(file.read(reload = false),
                                                "the next write would rewrite the positions with nothing kept aside")
            assertTrue(corruptCopies().isEmpty())
        }
    }

    @Test
    fun droppedRecordsThatCannotBeCopiedAsideFreeze() {
        file.write(AppData(engineState = EngineState.initial, records = listOf(aRecord()), settings = AppSettings()))
        val json = Json.parseToJsonElement(file.path.readText()).jsonObject
        val records = JsonArray(json.getValue("records").jsonArray +
            JsonObject(mapOf("from" to JsonPrimitive("a future build"))))
        val original = JsonObject(json + ("records" to records)).toString()
        val decoded = AppData.decode(original)
        assertFalse(decoded.engineStateReset, "only the entry is damaged")
        assertEquals(1, decoded.droppedRecordCount)
        file.path.writeText(original)
        withLockedDirectory {
            assertIs<StateFile.Read.Unreadable>(file.read(reload = false),
                                                "the next write would drop the entry with nothing kept aside")
            assertEquals(original, file.path.readText())
            assertTrue(corruptCopies().isEmpty())
        }
    }

    // MARK: - Bytes already kept under a later name

    /** Takes the first quarantine name, so the next copy goes under a later one. */
    private fun keepAnEarlierQuarantine(): String {
        val earlier = "an earlier, different quarantine"
        dir.resolve("dredfit-state.corrupt.json").writeText(earlier)
        return earlier
    }

    @Test
    fun bothKindsOfDamageInOneReadAreKeptOnce() {
        val earlier = keepAnEarlierQuarantine()
        val payload = """{"engineState":{"from":"a future build"},"records":[{"from":"a future build"}]}"""
        file.path.writeText(payload)
        val read = assertIs<StateFile.Read.Loaded>(file.read(reload = false), "the rest of the file reads")
        assertTrue(read.data.engineStateReset)
        assertEquals(1, read.data.droppedRecordCount)
        assertEquals(2, corruptCopies().size, "one copy for the two kinds of damage, beside the earlier one")
        assertEquals(setOf(earlier, payload), keptBytes())
    }

    @Test
    fun bytesAlreadyKeptUnderALaterNameDoNotFreeze() {
        keepAnEarlierQuarantine()
        file.path.writeText("""{"engineState":{"from":"a future build"},"records":[]}""")
        assertIs<StateFile.Read.Loaded>(file.read(reload = false), "the journal beside it reads")
        assertEquals(2, corruptCopies().size, "kept under a later name; nothing written over the file")
        withLockedDirectory {
            assertIs<StateFile.Read.Loaded>(file.read(reload = false),
                                            "the bytes are already safe aside, so there is nothing to freeze for")
        }
    }
}
