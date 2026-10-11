//
//  Port of ios/DredfitTests/AppStoreTests+DebutBadge.swift: the debut badge
//  is its own subject.
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
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class AppStoreTestDebutBadge : AppStoreTestCase() {

    /** An exercise actually PERFORMED counts toward the debut history, a
     *  skipped one does not: the badge on a new variation stands through a
     *  session that skipped the movement, and goes the moment it is performed. */
    @Test
    fun aPerformedExerciseCountsWhereAPainfulOneDoesNot() {
        // The weekly ceiling holds the slow-adapting patterns to three growth
        // events a week, so every workout here gets its own day.
        val start = Instant.now()
        for ((path, performed) in listOf(tempPath to true, tempDir.resolve("dredfit-hurt.json") to false)) {
            val store = makeStore(path)
            var day = 0L
            // Every probe is passed: that is the only door into a new movement.
            fun train(result: FeedbackResult, skipped: Set<Pattern> = emptySet()) {
                day += 1
                val session = store.nextSession
                val probes = session.exercises.mapNotNull { ex -> ex.probe?.let { ex.pattern to Dose.grid(it.unit).min } }.toMap()
                store.completeWorkout(session = session, result = result, skipped = skipped, probes = probes,
                                      date = start.plusSeconds(day * 86_400))
            }
            fun pullVariation(s: AppStore) = s.nextSession.exercises.first { it.pattern == Pattern.pull }.variation

            while (pullVariation(store) < 2) {
                if (day >= 200) fail("seeding: pull never reached its second variation")
                train(FeedbackResult.more)
            }
            // A SKIP is the signal: the badge is about what the person has DONE.
            if (performed) {
                train(FeedbackResult.plan)
                assertFalse(Pattern.pull in store.debutPatterns, "actually performed — the second variation is no debut")
                continue
            }
            train(FeedbackResult.plan, skipped = setOf(Pattern.pull))
            assertEquals(2, pullVariation(store), "a skip does not change the variation")
            assertTrue(Pattern.pull in store.debutPatterns, "not performed — the second variation is still a debut")
            train(FeedbackResult.plan)
            assertFalse(Pattern.pull in store.debutPatterns, "performed at last — the badge is spent")
        }
    }
}
