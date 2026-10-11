//
//  What Health Connect opens when someone taps the privacy policy link on
//  its permission screen for Dredfit — required: without an activity for
//  `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` (Android 10–13) and
//  the `VIEW_PERMISSION_USAGE` alias (Android 14+), Health Connect does not
//  show the app its permission screen at all (HealthConnectTest pins both).
//  No Swift twin: HealthKit shows the usage strings of Info.plist instead.
//
//  It shows the privacy policy itself — dredfit.com/privacy.html, in the
//  app's language where the site has one — in the browser, rather than as
//  a copy inside the app: the app holds no
//  INTERNET permission (so no WebView can load it), and a second copy of a
//  legal text would drift from the one the site publishes.
//

package com.dredfit.health

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.util.Locale

class HealthPrivacyActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(policyUrl(resources.configuration.locales[0])))
                              .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            // No browser on the phone: nothing can open a link, and no
            // message would give it one.
        }
        // Theme.NoDisplay: gone before it would be drawn.
        finish()
    }

    companion object {
        /** The site's policy page in the reader's language: the site has
         *  one per shipping language (sitemap.xml), English at the root. */
        fun policyUrl(locale: Locale): String {
            val dir = when (locale.language) {
                "de", "es", "fr", "it", "ru" -> locale.language + "/"
                "pt" -> "pt-br/"
                else -> ""
            }
            return "https://dredfit.com/${dir}privacy.html"
        }
    }
}
