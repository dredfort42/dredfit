//
//  Port of ios/DredfitTests/MigrationV2Tests.swift: a state written before v3
//  is read and carried over rather than started over, and the person is told
//  about it.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.V2State
import com.dredfit.core.migrateFromV2
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.dismissMigrationNotice
import com.dredfit.store.importBackup
import com.dredfit.store.showsMigrationNotice
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MigrationV2Test : AppStoreTestCase() {

    /** A v2 file in the shape v2 actually wrote: `[Pattern: Int]` as an
     *  UNKEYED array, because `Pattern` never adopted `CodingKeyRepresentable`. */
    private fun v2Payload(levels: Map<String, Int>, counter: Int, hasBar: Boolean): String {
        fun v2Pairs(m: Map<String, Int>) = m.toSortedMap().entries.joinToString(",") { (k, v) -> "\"$k\",$v" }
        return """
            {"engineState":{"counter":$counter,"hasBar":$hasBar,
              "levels":[${v2Pairs(levels)}],
              "failStreak":[${v2Pairs(levels.mapValues { 1 })}]},
             "records":[],"settings":null}
        """
    }

    @Test
    fun aV2StateIsCarriedOverRatherThanReset() {
        val loaded = AppData.decode(v2Payload(mapOf("squat" to 20, "push_h" to 12, "pull" to 8), counter = 37, hasBar = true))

        assertFalse(loaded.engineStateReset, "a v2 state must be read, not thrown away")
        assertTrue(loaded.engineStateMigrated, "and the app must know it happened")
        assertEquals(37, loaded.engineState.counter, "rotation phase carries over")
        assertTrue(loaded.engineState.hasBar, "so does the answer about the bar")

        // L=20 is tier 3 in v2, 9 reps. squat's tier 3 maps to variation 5.
        assertEquals(5, loaded.engineState.vars[Pattern.squat], "the rung v2's tier 3 was earned on, not the first one")
        assertEquals(9, loaded.engineState.doses[Pattern.squat],
                     "and the dose they were doing there, carried across unchanged")
        // A descent back into this variation lands under its journal entry,
        // and on its floor without one.
        assertEquals(9, loaded.engineState.shown[Pattern.squat]?.get(5),
                     "the journal has to say they were there, or a descent starts from the floor")
    }

    /**
     * The whole v2 scale, every pattern: 480 cells measured as REAL WORK on
     * both sides — `sets × dose × sides`. The "before" side comes from
     * `V2FormatSnapshot`, not from `Engine.v2LevelTable`, which the migration
     * takes its dose from: an error there would cancel itself out.
     *
     * Ten cells land heavier, only because v2 could hand out a hold below
     * v3's grid floor (an accepted gap, worst ×1.50). They are LISTED, not
     * counted: "at most ten" is satisfied by ten completely different cells.
     */
    @Test
    fun migration_acrossTheWholeV2Scale_landsHeavierOnlyOnTheTenAcceptedCells() {
        val heavier = mutableListOf<String>()
        val carryingVolumeHandles = mutableListOf<String>()
        for (p in Pattern.allCases) {
            for (level in V2FormatSnapshot.levelTable.indices) {
                val migrated = assertNotNull(Engine.migrateFromV2(V2State(counter = 1, hasBar = true, levels = mapOf(p to level))),
                                             "a state carrying one level is still a v2 state")
                val pos = migrated.position(p)
                // A migration writes no sub-step and no cut, which is what
                // makes the plain product the WHOLE plan.
                if (pos.sub != 0 || pos.cut != 0) carryingVolumeHandles += "${p.rawValue} L=$level"
                val now = pos.sets * pos.dose * Library.sides(p, pos.variation)
                val was = V2FormatSnapshot.work(p, level)
                if (now > was) heavier += "${p.rawValue} L=$level: $was -> $now"
            }
        }
        assertEquals(emptyList(), carryingVolumeHandles,
                     "nothing may arrive from a migration with sets already cut or a sub-step already owed")
        assertEquals(listOf(
            "core_anti_ext L=24: 30 -> 45",
            "core_anti_ext L=25: 33 -> 45",
            "core_anti_ext L=26: 36 -> 45",
            "core_anti_ext L=27: 39 -> 45",
            "core_anti_ext L=28: 42 -> 45",
            "core_rot L=24: 60 -> 90",
            "core_rot L=25: 66 -> 90",
            "core_rot L=26: 72 -> 90",
            "core_rot L=27: 78 -> 90",
            "core_rot L=28: 84 -> 90",
        ), heavier.sorted(), "the accepted gap is exactly these ten: a hold v2 set below v3's floor of 15 s comes UP to it")
    }

    @Test
    fun aV3StateIsStillReadAsV3() {
        val state = EngineState.initial.also { it.counter = 5 }
        val loaded = AppData.decode(AppData(engineState = state, records = emptyList(), settings = AppSettings()).encode())
        assertFalse(loaded.engineStateMigrated, "a v3 state is not a migration")
        assertFalse(loaded.engineStateReset)
        assertEquals(5, loaded.engineState.counter)
    }

    @Test
    fun garbageStillFallsBackToACleanStart() {
        val loaded = AppData.decode("""{"engineState":{"nonsense":true},"records":[],"settings":null}""")
        assertTrue(loaded.engineStateReset, "not v2 and not v3 — clean start, as before")
        assertFalse(loaded.engineStateMigrated)
    }

    // MARK: - The one-shot card on Today

    /** Announced ONCE, and carried by the file rather than by the launch that
     *  migrated: an upgrade killed before Today opens must not spend it unseen. */
    @Test
    fun theCardIsPendingAfterAMigrationAndSurvivesARelaunch() {
        val store = storeFrom(v2Payload(mapOf("squat" to 20, "pull" to 8), counter = 4, hasBar = true))
        assertTrue(store.showsMigrationNotice, "the upgrade must be announced")
        store.update { it }   // any write: the file is v3 from here on — the flag has to carry itself

        val onDisk = AppData.decode(Files.readString(tempPath))
        assertFalse(onDisk.engineStateMigrated, "the file is v3 from here on, so nothing migrates a second time")
        assertTrue(makeStore().showsMigrationNotice, "and the card is still owed")
    }

    @Test
    fun dismissingTheCardSpendsItForGood() {
        val store = storeFrom(v2Payload(mapOf("squat" to 20), counter = 4, hasBar = false))
        store.dismissMigrationNotice()
        assertFalse(store.showsMigrationNotice)
        assertFalse(makeStore().showsMigrationNotice, "and it must not come back on the next launch")
    }

    @Test
    fun aFreshInstallIsNeverToldAboutAMigration() {
        assertFalse(makeStore().showsMigrationNotice, "there is nothing to announce to someone with no history")
    }

    /** The THIRD door into the same decode, beside launch and
     *  `reloadIfNeeded`: the settings a restore brings come out of the very
     *  pre-v3 file it migrates, so the card is stamped after them. */
    @Test
    fun restoringAPreV3BackupAnnouncesTheMigrationToo() {
        val store = makeStore()
        assertFalse(store.showsMigrationNotice, "nothing to announce before the restore")

        store.importBackup(v2Payload(mapOf("squat" to 20, "pull" to 8), counter = 4, hasBar = true).toByteArray())

        assertEquals(5, store.engineState.vars[Pattern.squat], "the restore really did carry the positions over")
        assertTrue(store.showsMigrationNotice, "restoring a pre-v3 backup is an upgrade too, and has to say so")
        assertTrue(makeStore().showsMigrationNotice, "and the card outlives the launch that owed it, like the other two doors")
    }
}
