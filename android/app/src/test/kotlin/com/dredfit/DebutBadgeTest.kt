//
//  Port of ios/DredfitTests/DebutBadgeTests.swift: the "new variation" pill —
//  a movement the next plan carries on a variation above everything the
//  journal shows performed.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.debutPatterns
import com.dredfit.store.nextSession
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

class DebutBadgeTest : AppStoreTestCase() {

    /** Every workout gets its own day (stacked on one instant the weekly
     *  ceiling would hold the walk short of any boundary), and every probe is
     *  PASSED — the only door into a new movement. */
    private var day = 0L
    private val start: Instant = Instant.now()

    private fun train(store: AppStore, result: FeedbackResult, skipped: Set<Pattern> = emptySet()) {
        day += 1
        val session = store.nextSession
        val probes = session.exercises.mapNotNull { ex -> ex.probe?.let { ex.pattern to Dose.grid(it.unit).min } }.toMap()
        store.completeWorkout(session = session, result = result, overrides = emptyMap(), skipped = skipped,
                              probes = probes, date = start.plusSeconds(day * 86_400))
    }

    /** The first plan must not open covered in "new variation" pills. */
    @Test
    fun freshStoreHasNoDebuts() {
        assertTrue(makeStore().debutPatterns.isEmpty(), "nothing has been performed yet, so nothing can be new")
    }

    @Test
    fun debutAppearsWhenAPatternCrossesIntoANewVariation() {
        val store = makeStore()
        var sawDebut = false
        // A variation is a whole grid of doses, so the walk needs room.
        for (i in 0 until 120) {
            val debuts = store.debutPatterns
            if (debuts.isNotEmpty()) {
                sawDebut = true
                val session = store.nextSession
                for (p in debuts) {
                    val planned = session.exercises.firstOrNull { it.pattern == p }
                    assertNotNull(planned, "a debut must be in the next session")
                    val maxPerformed = store.records.mapNotNull { record ->
                        if (record.skipped?.contains(p) == true) null
                        else record.exercises?.filter { it.pattern == p }?.maxOfOrNull { it.variation }
                    }.maxOrNull() ?: 0
                    assertTrue(planned.variation > maxPerformed, "$p: a debut is a variation above everything performed")
                }
                break
            }
            train(store, FeedbackResult.more)
        }
        assertTrue(sawDebut, "the run must cross at least one variation boundary")
    }

    /** Walked to until the pull SLOT has a debut — not `debutPatterns.first()`
     *  (one session can carry several) — because the slot stands in every
     *  session, so the badge can still be asked about after a skip. */
    private fun walkToAPullDebut(store: AppStore, limit: Int = 200): Pattern? {
        val slot = store.nextSession.exercises.firstOrNull { it.pattern in Pattern.pullSide }?.pattern
            ?: fail("every session carries a pull slot — without one there is no subject")
        var walked = 0
        while (slot !in store.debutPatterns) {
            if (walked >= limit) return null
            train(store, FeedbackResult.more)
            walked += 1
        }
        return slot
    }

    /** Performing the new variation retires its badge. */
    @Test
    fun debutClearsAfterTheVariationIsPerformed() {
        val store = makeStore()
        val debut = walkToAPullDebut(store)
            ?: fail("the pull slot never reached a new variation — the walk is broken")
        train(store, FeedbackResult.plan)
        assertFalse(debut in store.debutPatterns, "a performed variation is no longer a debut")
    }

    @Test
    fun skippingTheDebutKeepsTheBadge() {
        val store = makeStore()
        val debut = walkToAPullDebut(store)
            ?: fail("the pull slot never reached a new variation — the walk is broken")
        train(store, FeedbackResult.plan, skipped = setOf(debut))
        assertTrue(store.nextSession.exercises.any { it.pattern == debut },
                   "the pull slot stays in every plan, so the badge is still being asked about")
        assertTrue(debut in store.debutPatterns, "skipping must not count as performing the variation")
    }
}
