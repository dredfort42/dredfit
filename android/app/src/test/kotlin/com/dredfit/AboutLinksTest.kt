//
//  Settings' Android-only wording and links (owner decisions, 09.10.2026),
//  no Swift twin: where About's rows lead and when they show, and which
//  caption stands under "Play tones in Silent mode". The rows' two states on
//  screen are the connected AboutSectionTest's.
//

package com.dredfit

import com.dredfit.ui.settings.AboutLinks
import com.dredfit.ui.settings.SilentModeCaption
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class AboutLinksTest {

    /** The Play listing does not exist yet, so the rows ship hidden. Flipping
     *  the flag in build.gradle.kts is the owner's call once it does — and
     *  this line changes with it, on purpose. */
    @Test
    fun theRowsShipHiddenUntilTheListingIsLive() {
        assertFalse(BuildConfig.PLAY_LISTING_LIVE)
    }

    /** The listing is the application id's: a renamed id would send "Rate"
     *  to another app's page, or to none. */
    @Test
    fun theLinksNameThisAppsListing() {
        assertEquals(BuildConfig.APPLICATION_ID, AboutLinks.LISTING_ID)
        assertEquals("market://details?id=com.dredfit.dredfit", AboutLinks.PLAY_STORE_APP)
        assertEquals("https://play.google.com/store/apps/details?id=com.dredfit.dredfit", AboutLinks.PLAY_LISTING_WEB)
    }

    /** OFF: iOS's own caption, true here (silent mutes the tones, the
     *  haptics carry on). ON: Android's — iOS's names the ringer SWITCH. */
    @Test
    fun theSilentModeCaptionIsAndroidsWhenTheSwitchIsOn() {
        val off = SilentModeCaption.key(playsTonesInSilentMode = false)
        val on = SilentModeCaption.key(playsTonesInSilentMode = true)
        assertEquals("In Silent mode the tones go quiet — the vibration keeps going.", off)
        assertEquals("The tones play even when the phone is set to silent or vibrate.", on)

        val ios = IosCatalogs.strings("Dredfit/Localizable.xcstrings")
        val android = IosCatalogs.strings(SetsNoticeTest.ANDROID_CATALOG)
        assertNotNull(ios[off], "the OFF caption is the iOS catalog's")
        assertNotNull(android[on], "the ON caption is the Android catalog's")
        assertNull(android[off])
    }
}
