//
//  Port of ios/DredfitTests/CareNoteTests.swift: the care card's
//  acknowledgement (#101) — one timestamp recording that the
//  contraindication checklist was on screen and confirmed, and nothing else
//  stored or gated on it.
//

package com.dredfit

import com.dredfit.store.AppSettings
import com.dredfit.store.completeOnboarding
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CareNoteTest : AppStoreTestCase() {

    /** Completing the onboarding — reachable only through the care card's
     *  button since #101 — records the acknowledgement, across a relaunch. */
    @Test
    fun completingOnboardingRecordsTheAcknowledgement() {
        val store = makeStore()
        assertNull(store.settings.careAcknowledgedAt)

        store.completeOnboarding()
        assertTrue(store.settings.onboardingCompleted)
        assertNotNull(store.settings.careAcknowledgedAt)

        assertNotNull(makeStore().settings.careAcknowledgedAt, "the acknowledgement must survive a relaunch")
    }

    /** A settings block written before the field existed decodes with no
     *  acknowledgement — no migration, nobody asked retroactively. */
    @Test
    fun oldSettingsDecodeWithoutTheField() {
        val settings = AppSettings.fromJson(Json.parseToJsonElement("""
            {"restWeekdays":[1],"soundsEnabled":true,"reminderEnabled":false,
             "reminderHour":9,"reminderMinute":0,"onboardingCompleted":true}
        """))
        assertTrue(settings.onboardingCompleted)
        assertNull(settings.careAcknowledgedAt, "an absent field must decode as nil, not fail or invent a date")
    }

    /** The field round-trips: what one build writes, the next one reads.
     *  Swift's `Date(timeIntervalSinceReferenceDate: 800_000_000)`. */
    @Test
    fun acknowledgementRoundTripsThroughCoding() {
        val settings = AppSettings(careAcknowledgedAt = Instant.ofEpochSecond(978_307_200L + 800_000_000L))
        val decoded = AppSettings.fromJson(Json.parseToJsonElement(settings.toJson().toString()))
        assertEquals(settings.careAcknowledgedAt, decoded.careAcknowledgedAt)
    }
}
