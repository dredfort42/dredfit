//
//  About's two Play rows in both states of `BuildConfig.PLAY_LISTING_LIVE`
//  (owner decision 09.10.2026): absent while the listing does not exist, and
//  once it does, "Rate" opens the Play Store's page and "Recommend" shares
//  the web link. The section alone, so the flag's other state is reachable
//  without a second build; the shipped default is AboutLinksTest's (JVM),
//  and the real sheet's is TabsAndSettingsTest's.
//

package com.dredfit

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.anyIntent
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.espresso.intent.matcher.IntentMatchers.hasData
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.dredfit.ui.settings.AboutLinks
import com.dredfit.ui.settings.AboutSection
import com.dredfit.ui.theme.DredfitTheme
import org.hamcrest.Matchers.allOf
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AboutSectionTest {

    @get:Rule
    val compose = createComposeRule()

    private fun show(listingLive: Boolean) {
        compose.setContent { DredfitTheme(dark = false) { AboutSection(listingLive = listingLive) } }
        compose.onNodeWithTag("version-line").assertExists()
    }

    private fun count(tag: String) = compose.onAllNodesWithTag(tag).fetchSemanticsNodes().size

    @Test
    fun noPlayRowsBeforeTheListingIsLive() {
        show(listingLive = false)
        assertEquals(0, count("rate-app"))
        assertEquals(0, count("recommend-app"))
    }

    @Test
    fun aLiveListingIsRatedInThePlayStoreAndRecommendedByItsWebLink() {
        show(listingLive = true)
        Intents.init()
        try {
            // Stubbed: nothing leaves the test for the Play Store or a chooser.
            intending(anyIntent()).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            compose.onNodeWithTag("rate-app").performClick()
            intended(allOf(hasAction(Intent.ACTION_VIEW), hasData(AboutLinks.PLAY_STORE_APP)))

            compose.onNodeWithTag("recommend-app").performClick()
            intended(hasAction(Intent.ACTION_CHOOSER))
            val chooser = Intents.getIntents().last { it.action == Intent.ACTION_CHOOSER }
            @Suppress("DEPRECATION")
            val send = checkNotNull(chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT))
            assertEquals(Intent.ACTION_SEND, send.action)
            assertEquals("text/plain", send.type)
            assertEquals(AboutLinks.PLAY_LISTING_WEB, send.getStringExtra(Intent.EXTRA_TEXT))
        } finally {
            Intents.release()
        }
    }
}
