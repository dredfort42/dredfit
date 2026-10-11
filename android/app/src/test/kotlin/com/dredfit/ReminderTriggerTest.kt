//
//  What rebuilds the reminder window besides the app's own returns
//  (reminders/ReminderReceiver.kt). Android-only — iOS's calendar triggers
//  survive a reboot and follow a zone change by themselves. The list lives
//  twice, in `ReminderTriggers.actions` and in the manifest's intent filter
//  (the system reads only the second), so this suite holds them together,
//  and holds the two receivers to their exposure.
//

package com.dredfit

import com.dredfit.reminders.ReminderTriggers
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReminderTriggerTest {

    private val android = "http://schemas.android.com/apk/res/android"

    private fun receivers(): Map<String, Element> {
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val doc = factory.newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val nodes = doc.getElementsByTagName("receiver")
        return (0 until nodes.length).map { nodes.item(it) as Element }.associateBy { it.getAttributeNS(android, "name") }
    }

    private fun actions(receiver: Element): Set<String> {
        val nodes = receiver.getElementsByTagName("action")
        return (0 until nodes.length).map { (nodes.item(it) as Element).getAttributeNS(android, "name") }.toSet()
    }

    @Test
    fun theManifestListensForExactlyTheTriggers() {
        val reschedule = receivers().getValue(".reminders.ReminderRescheduleReceiver")
        assertEquals(ReminderTriggers.actions, actions(reschedule))
    }

    /** The boot, the clock, the zone and an update — each loses something an
     *  alarm holds. */
    @Test
    fun theTriggersAreTheFourThatMoveAnAlarm() {
        for (action in listOf("android.intent.action.BOOT_COMPLETED", "android.intent.action.TIME_SET",
                              "android.intent.action.TIMEZONE_CHANGED", "android.intent.action.MY_PACKAGE_REPLACED")) {
            assertTrue(ReminderTriggers.reschedules(action), action)
        }
        assertFalse(ReminderTriggers.reschedules(null))
        assertFalse(ReminderTriggers.reschedules("android.intent.action.DATE_CHANGED"),
                    "midnight moves no alarm: the window already holds tomorrow")
    }

    /** The system's broadcasts need an exported receiver; the alarm's own
     *  must not be — another app could post the reminder through it. */
    @Test
    fun onlyTheRebuildIsExported() {
        val all = receivers()
        assertEquals("true", all.getValue(".reminders.ReminderRescheduleReceiver").getAttributeNS(android, "exported"))
        assertEquals("false", all.getValue(".reminders.ReminderReceiver").getAttributeNS(android, "exported"))
        assertTrue(actions(all.getValue(".reminders.ReminderReceiver")).isEmpty(), "reached by its PendingIntent alone")
    }

    /** No exact-alarm permission: the reminder is an inexact alarm allowed
     *  in Doze (android/README.md says why); USE_EXACT_ALARM is Play-
     *  restricted and SCHEDULE_EXACT_ALARM denied by default from 14. */
    @Test
    fun theManifestAsksForNoExactAlarm() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertFalse("SCHEDULE_EXACT_ALARM" in manifest)
        assertFalse("USE_EXACT_ALARM" in manifest)
        assertTrue("android.permission.RECEIVE_BOOT_COMPLETED" in manifest)
    }
}
