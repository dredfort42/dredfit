//
//  What the app declares to Health Connect, held to what it asks for. Android
//  only — iOS lists its types in code and its usage strings in Info.plist.
//  The permission set lives twice, in `HealthConnectWriter.permissions` (what
//  the switch asks for) and in the manifest (what the system lets it ask
//  for, and what the Play declaration lists), so this suite holds them
//  together — and holds the release manifest to no more than that: the
//  debug manifest's three extras are the connected suite's.
//

package com.dredfit

import com.dredfit.health.HealthConnectWriter
import com.dredfit.health.HealthPrivacyActivity
import org.w3c.dom.Element
import java.io.File
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HealthPermissionsTest {

    private val android = "http://schemas.android.com/apk/res/android"

    private fun elements(manifest: String, tag: String): List<Element> {
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val doc = factory.newDocumentBuilder().parse(File(manifest))
        val nodes = doc.getElementsByTagName(tag)
        return (0 until nodes.length).map { nodes.item(it) as Element }
    }

    private fun Element.name(): String = getAttributeNS(android, "name")

    private fun permissions(manifest: String): Set<String> =
        elements(manifest, "uses-permission").map { it.name() }.toSet()

    @Test
    fun theReleaseManifestDeclaresExactlyWhatTheSwitchAsksFor() {
        val health = permissions("src/main/AndroidManifest.xml").filter { it.startsWith("android.permission.health.") }.toSet()
        assertEquals(HealthConnectWriter.permissions, health)
    }

    /** iOS writes the workout and its ACTIVE energy, and reads weight,
     *  resting energy and workouts; height, birth date and sex have no
     *  Health Connect reader that could change a number (HealthStore.kt). */
    @Test
    fun theSetIsIOSsShareAndReadSets() {
        assertEquals(setOf("android.permission.health.WRITE_EXERCISE",
                           "android.permission.health.WRITE_ACTIVE_CALORIES_BURNED",
                           "android.permission.health.READ_WEIGHT",
                           "android.permission.health.READ_BASAL_METABOLIC_RATE",
                           "android.permission.health.READ_EXERCISE"),
                     HealthConnectWriter.permissions)
    }

    @Test
    fun theDebugExtrasStayInTheDebugManifest() {
        val debug = permissions("src/debug/AndroidManifest.xml")
        assertTrue(debug.isNotEmpty(), "the premise: the debug manifest is read")
        val main = permissions("src/main/AndroidManifest.xml")
        assertTrue(debug.none { it in main }, "a test's permission in the release manifest: $debug")
        assertTrue(debug.none { it in HealthConnectWriter.permissions }, "the switch never asks for a test's permission")
    }

    /** Health Connect is on-device IPC: still no network. */
    @Test
    fun theAppStillAsksForNoNetwork() {
        assertFalse("android.permission.INTERNET" in permissions("src/main/AndroidManifest.xml"))
    }

    /** The privacy-policy link on Health Connect's permission screen: the
     *  intent filter on Android 10–13, the alias on 14+, both to the one
     *  activity, the alias startable by the system only. */
    @Test
    fun thePrivacyPolicyLinkHasBothDoors() {
        val activity = elements("src/main/AndroidManifest.xml", "activity").single { it.name() == ".health.HealthPrivacyActivity" }
        assertEquals("true", activity.getAttributeNS(android, "exported"))
        val actions = activity.getElementsByTagName("action")
        assertEquals("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE", (actions.item(0) as Element).name())

        val alias = elements("src/main/AndroidManifest.xml", "activity-alias").single { it.name() == "ViewPermissionUsageActivity" }
        assertEquals(".health.HealthPrivacyActivity", alias.getAttributeNS(android, "targetActivity"))
        assertEquals("android.permission.START_VIEW_PERMISSION_USAGE", alias.getAttributeNS(android, "permission"))
        assertEquals("android.intent.action.VIEW_PERMISSION_USAGE", (alias.getElementsByTagName("action").item(0) as Element).name())
        assertEquals("android.intent.category.HEALTH_PERMISSIONS", (alias.getElementsByTagName("category").item(0) as Element).name())
    }

    /** Android 11–13 hide other packages: without the query the Health
     *  Connect app would read as missing. */
    @Test
    fun theHealthConnectAppIsVisible() {
        val packages = elements("src/main/AndroidManifest.xml", "package").map { it.name() }
        assertTrue(HealthConnectWriter.PROVIDER in packages)
    }

    /** The policy in the reader's language where the site has one. */
    @Test
    fun thePolicyOpensInTheReadersLanguage() {
        assertEquals("https://dredfit.com/privacy.html", HealthPrivacyActivity.policyUrl(Locale.ENGLISH))
        assertEquals("https://dredfit.com/ru/privacy.html", HealthPrivacyActivity.policyUrl(Locale.forLanguageTag("ru")))
        assertEquals("https://dredfit.com/pt-br/privacy.html", HealthPrivacyActivity.policyUrl(Locale.forLanguageTag("pt-BR")))
        assertEquals("https://dredfit.com/de/privacy.html", HealthPrivacyActivity.policyUrl(Locale.GERMANY))
        assertEquals("https://dredfit.com/privacy.html", HealthPrivacyActivity.policyUrl(Locale.JAPANESE),
                     "a language the site does not have reads the English page")
    }
}
