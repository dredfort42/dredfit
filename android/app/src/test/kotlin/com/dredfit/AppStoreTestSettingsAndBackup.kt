//
//  Port of ios/DredfitTests/AppStoreTests+SettingsAndBackup.swift. One claim
//  about one piece of data: the persisted settings survive a reload, and
//  survive a full export/import intact too — and an import that cannot be
//  read in full moves nothing.
//
//  The backup is bytes on this side (`exportBackup`/`importBackup`); the file
//  the share sheet hands around is the screen's business, so iOS's
//  `testExportKeepsOnlyTheLatestFile` (one temp file per export) has no
//  subject here.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.SwiftDecodingException
import com.dredfit.store.BackupError
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.store.isRestDay
import com.dredfit.store.markTechniqueOpened
import com.dredfit.store.nextSession
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.setReminderTime
import com.dredfit.store.setSounds
import com.dredfit.store.showsTechniqueHint
import com.dredfit.store.toggleRestDay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Test
import java.nio.file.Files
import kotlin.io.path.readText
import kotlin.io.path.writeText
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppStoreTestSettingsAndBackup : AppStoreTestCase() {

    @Test
    fun settingsPersistAcrossReload() {
        val store = makeStore()
        store.toggleRestDay(3)          // Tuesday joins the Mon+Wed+Fri default
        store.setSounds(false)
        store.setReminderTime(hour = 7, minute = 30)

        val reloaded = makeStore()
        assertEquals(setOf(2, 3, 4, 6), reloaded.settings.restWeekdays)
        assertFalse(reloaded.settings.soundsEnabled)
        assertEquals(7, reloaded.settings.reminderHour)
        assertEquals(30, reloaded.settings.reminderMinute)
    }

    /** The technique hint is spent once and stays spent: the flag survives a
     *  reload, and a second open writes nothing — the sheet is opened many
     *  times over the life of the app. */
    @Test
    fun openingTheTechniqueSheetSpendsTheHintOnce() {
        val store = makeStore()
        assertTrue(store.showsTechniqueHint)

        store.markTechniqueOpened()
        assertFalse(store.showsTechniqueHint)
        assertFalse(makeStore().showsTechniqueHint, "the spent hint survives a reload")

        Files.delete(tempPath)
        store.markTechniqueOpened()
        assertFalse(Files.exists(tempPath), "a second open must not write the state file again")
    }

    @Test
    fun restDaysFollowSettings() {
        val store = makeStore()
        assertFalse(store.isRestDay(date(2026, 7, 16)), "Thursday is not rest by default")
        store.toggleRestDay(5)          // Thursday (iOS weekday 5)
        assertTrue(store.isRestDay(date(2026, 7, 16)), "Thursday must follow the setting")
        store.toggleRestDay(5)
        assertFalse(store.isRestDay(date(2026, 7, 16)))
    }

    @Test
    fun atLeastOneTrainingDayRemains() {
        val store = makeStore()
        for (weekday in 1..7) store.toggleRestDay(weekday)   // tries to rest all week
        assertTrue(store.settings.restWeekdays.size <= 6, "the last training day must not become rest")
        // and the next-date search always terminates
        store.nextTrainingDate(date(2026, 7, 16))
    }

    // MARK: - Backup

    @Test
    fun exportImportRoundTrip() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.more, date = date(2026, 7, 16))
        store.toggleRestDay(2)
        val backup = store.exportBackup()

        // a brand-new store on a different file imports the backup
        val other = tempDir.resolve("dredfit-import.json")
        val fresh = makeStore(other)
        assertTrue(fresh.records.isEmpty())
        fresh.importBackup(backup)

        assertEquals(store.engineState, fresh.engineState)
        assertEquals(store.records, fresh.records)
        assertEquals(store.settings, fresh.settings)
        // and the import persisted
        assertEquals(1, makeStore(other).records.size)
    }

    @Test
    fun importRejectsForeignFile() {
        val store = makeStore(tempDir.resolve("dredfit-badimport.json"))
        assertFailsWith<SwiftDecodingException>("a foreign JSON must not import") {
            store.importBackup("{\"foo\": 1}".toByteArray())
        }
        assertTrue(store.records.isEmpty(), "state must stay intact after a failed import")
    }

    /** One setting of an unexpected shape costs that setting, never the
     *  journal beside it. */
    @Test
    fun aMalformedSettingDoesNotCostTheJournal() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        val json = Json.parseToJsonElement(tempPath.readText()).jsonObject
        val settings = JsonObject(json.getValue("settings").jsonObject +
            mapOf("soundsEnabled" to JsonPrimitive("loud"), "reminderHour" to JsonPrimitive(99)))
        tempPath.writeText(JsonObject(json + ("settings" to settings)).toString())

        val relaunched = makeStore()
        assertEquals(1, relaunched.records.size, "the journal must survive")
        assertTrue(relaunched.settings.soundsEnabled, "the bad field falls back to its default")
        assertEquals(23, relaunched.settings.reminderHour, "held to the clock")
    }

    /** The lenient launch decode reads `{"records":[]}` as a clean start. As
     *  an import it would replace a whole history with nothing. */
    @Test
    fun importRefusesAFileItCannotReadInFull() {
        val store = makeStore(tempDir.resolve("dredfit-partial.json"))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        val before = store.engineState
        for (junk in listOf("""{"records":[]}""", """{"engineState":{"nonsense":true},"records":[]}""")) {
            assertFailsWith<BackupError.IncompleteBackup>(junk) { store.importBackup(junk.toByteArray()) }
            assertEquals(1, store.records.size, "the journal must survive a refused import")
            assertEquals(before, store.engineState)
        }
        // A whole backup whose settings block is not an object: on launch that
        // costs the settings their defaults, as an import it is refused.
        val json = Json.parseToJsonElement(store.exportBackup().decodeToString()).jsonObject
        val bad = JsonObject(json + ("settings" to JsonPrimitive(42))).toString()
        assertFailsWith<BackupError.IncompleteBackup> { store.importBackup(bad.toByteArray()) }
        assertEquals(1, store.records.size)
    }

    /** Kotlin-only: the third refusal of `importBackup` — an entry this build
     *  cannot read — had no test on iOS either. On launch that entry is
     *  dropped and the file copied aside; as an import nothing keeps a copy,
     *  so the whole file is refused. */
    @Test
    fun importRefusesABackupWithAnUnreadableEntry() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        val json = Json.parseToJsonElement(store.exportBackup().decodeToString()).jsonObject
        val records = JsonArray(json.getValue("records").jsonArray +
            JsonObject(mapOf("from" to JsonPrimitive("a future build"))))
        val bad = JsonObject(json + ("records" to records)).toString()
        val other = makeStore(tempDir.resolve("dredfit-import.json"))
        assertFailsWith<BackupError.IncompleteBackup> { other.importBackup(bad.toByteArray()) }
        assertTrue(other.records.isEmpty(), "the readable entry must not arrive without the other")
    }
}
