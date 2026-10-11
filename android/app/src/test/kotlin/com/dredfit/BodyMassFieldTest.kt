//
//  The weight row's rules (ui/settings/SettingsHealthSection.kt), which sit in
//  the SwiftUI body on iOS and have no Swift test: what a typed entry asks
//  for, and which caption names the number in force. Android-only rule suite.
//

package com.dredfit

import com.dredfit.store.AppSettings
import com.dredfit.ui.settings.BodyMassField
import com.dredfit.ui.settings.BodyMassField.Commit
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class BodyMassFieldTest {

    @Test
    fun onlyAnEmptyFieldClearsTheWeight() {
        assertEquals(Commit.Clear, BodyMassField.commit("", pounds = false))
        assertEquals(Commit.Clear, BodyMassField.commit("   ", pounds = false))
    }

    /** A typo is not a request to erase the number. */
    @Test
    fun anUnreadableEntryKeepsTheNumber() {
        for (typed in listOf("abc", "72..5", "0", "-70", "NaN", "Infinity")) {
            assertEquals(Commit.Keep, BodyMassField.commit(typed, pounds = false), typed)
        }
    }

    /** The comma is accepted because half the shipping languages type one. */
    @Test
    fun aCommaIsADecimalMark() {
        assertEquals(Commit.Set(72.5), BodyMassField.commit(" 72,5 ", pounds = false))
        assertEquals(Commit.Set(72.5), BodyMassField.commit("72.5", pounds = false))
    }

    /** The store keeps kilograms always: pounds are converted on the way in. */
    @Test
    fun poundsAreStoredAsKilograms() {
        val set = assertIs<Commit.Set>(BodyMassField.commit("160", pounds = true))
        assertEquals(72.574779, set.kg, 0.000_001)
    }

    private val day = Instant.parse("2026-10-01T09:07:39Z")

    @Test
    fun theCaptionNamesWhyAMissingWeightMatters() {
        assertEquals("Without it, workouts are saved with no calorie estimate.",
                     BodyMassField.captionKey(AppSettings(healthEnabled = true)))
        assertEquals("Without it, workouts are saved with no calorie estimate.",
                     BodyMassField.captionKey(AppSettings(healthEnabled = false)))
    }

    @Test
    fun theCaptionNamesTheOriginOfTheNumberInForce() {
        assertEquals("From Health Connect, %@. A newer weight — typed here or logged there — takes over.",
                     BodyMassField.captionKey(AppSettings(healthEnabled = true, bodyMassKg = 72.5, bodyMassFromHealth = true,
                                                          bodyMassDate = day)))
        assertEquals("Set in the app, %@. A newer weight logged in Health Connect takes over.",
                     BodyMassField.captionKey(AppSettings(healthEnabled = true, bodyMassKg = 72.5, bodyMassDate = day)))
    }

    /** With the switch off nothing competes with the number; an undated
     *  number says nothing rather than a guessed day. */
    @Test
    fun noCaptionWithoutACompetitorOrADate() {
        assertNull(BodyMassField.captionKey(AppSettings(healthEnabled = false, bodyMassKg = 72.5, bodyMassDate = day)))
        assertNull(BodyMassField.captionKey(AppSettings(healthEnabled = true, bodyMassKg = 72.5, bodyMassDate = null)))
    }
}
