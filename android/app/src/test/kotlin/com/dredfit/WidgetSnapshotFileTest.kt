//
//  The widget snapshot's file (WidgetShared.kt). No Swift twin: iOS's is a
//  synthesized Codable, and its older-build decodes are
//  AppStoreTests+WidgetSnapshot's — Android has no older build. What must
//  hold here is that a written snapshot reads back equal, and that a file
//  this build cannot read is NO snapshot, never half of one.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.nextSession
import com.dredfit.widgets.WidgetSnapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class WidgetSnapshotFileTest : AppStoreTestCase() {

    private fun realSnapshot(): WidgetSnapshot {
        val widget = WidgetRecorder()
        val store = makeStore(widgets = widget)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        return widget.last
    }

    @Test
    fun aWrittenSnapshotReadsBackEqual() {
        val snapshot = realSnapshot()
        assertEquals(snapshot, WidgetSnapshot.decode(snapshot.encode()))
        // Both kinds of day travel: one with a session number, ones with a
        // next date, and the nulls between them.
        val fresh = WidgetRecorder().also { makeStore(path = tempDir.resolve("fresh.json"), widgets = it) }.last
        assertEquals(fresh, WidgetSnapshot.decode(fresh.encode()))
    }

    @Test
    fun aFileThisBuildCannotReadIsNoSnapshot() {
        val good = realSnapshot().encode()
        val broken = listOf(
            "",
            "not json",
            "[]",
            good.replace("\"status\":\"", "\"status\":\"sleeping-"),       // an unknown status
            good.replace("\"totalSteps\":", "\"totalSteps\":\"7\",\"x\":"), // a number as a string
            good.replace("\"weekStart\":\"", "\"weekStart\":\"2026-13-"),   // not a date
            good.replace("\"plan\":", "\"planned\":"),                      // a key gone
            good.replace("\"unit\":\"", "\"unit\":\"kg"),                    // an unknown unit
        )
        for (text in broken) {
            if (text.length > 10) assertNotEquals(good, text, "the fixture's replace must take")
            assertNull(WidgetSnapshot.decode(text), "decoded: ${text.take(80)}")
        }
    }
}
