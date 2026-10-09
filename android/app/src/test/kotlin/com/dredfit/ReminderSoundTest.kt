//
//  Port of ios/DredfitTests/ReminderSoundTests.swift — the reminder's branded
//  sound file (#84, stage C): written once, never rewritten, and any
//  provisioning failure degrades to the stock sound rather than a silent
//  reminder. All three Swift tests; "the stock sound" is a null file here,
//  which `ensureChannel` turns into the stock channel.
//
//  Android-only: the WAV's header (iOS's `testTonesAreValidMonoPCMWav` holds
//  the same bytes in CountdownSoundsTests — the Kotlin player needs no file,
//  so that test was not ported there) and the channel ids, whose version
//  must move with the file's.
//

package com.dredfit

import com.dredfit.reminders.ReminderChannel
import com.dredfit.reminders.ReminderSoundFile
import com.dredfit.signals.SignalTone
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReminderSoundTest {

    @TempDir
    lateinit var tempLibrary: Path

    private val root: File get() = tempLibrary.toFile()

    /** The first call provisions sounds/dredfit_reminder_v1.wav with the
     *  generated tone; the second leaves the existing file untouched — the
     *  channel holds the file by its URI, so the bytes must never change
     *  under a name that already shipped. */
    @Test
    fun writesTheFileOnceAndNeverRewritesIt() {
        val file = assertNotNull(ReminderSoundFile.provision(root), "the branded sound must be used")
        assertEquals(File(File(root, "sounds"), "dredfit_reminder_v1.wav"), file)
        assertContentEquals(ReminderSoundFile.wav, file.readBytes(), "the file carries the generated tone, byte for byte")

        // A marker byte proves the second call does not rewrite the file.
        file.writeBytes(byteArrayOf(0xFF.toByte()))
        ReminderSoundFile.provision(root)
        assertContentEquals(byteArrayOf(0xFF.toByte()), file.readBytes(), "an existing file must be left exactly as it was")
    }

    /** A root that cannot hold a sounds directory (the path is a file) must
     *  degrade to the stock sound — never crash, never go silent. */
    @Test
    fun fallsBackToDefaultWhenProvisioningFails() {
        val blocked = File(root, "blocked")
        blocked.writeText("not a directory")
        assertNull(ReminderSoundFile.provision(blocked), "a failed write must fall back to the system sound")
    }

    /** Re-provisioning after a wipe (cleared data, reinstall) starts clean. */
    @Test
    fun recreatesTheFileAfterAWipe() {
        ReminderSoundFile.provision(root)
        File(root, "sounds").deleteRecursively()

        val file = assertNotNull(ReminderSoundFile.provision(root))
        assertContentEquals(ReminderSoundFile.wav, file.readBytes())
        assertFalse(File(File(root, "sounds"), "dredfit_reminder_v1.wav.partial").exists(), "no half-written file is left")
    }

    // MARK: - Android-only

    /** The 44-byte RIFF header of CountdownSounds.swift's `wavFile`, then
     *  the samples little-endian: 16-bit mono PCM at 44.1 kHz. */
    @Test
    fun theFileIsAMonoPcmWavOfTheReminderTone() {
        val wav = ReminderSoundFile.wav
        val samples = SignalTone.reminder
        val b = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        fun tag(at: Int) = String(wav, at, 4, Charsets.US_ASCII)
        assertEquals(44 + samples.size * 2, wav.size)
        assertEquals("RIFF", tag(0))
        assertEquals(36 + samples.size * 2, b.getInt(4))
        assertEquals("WAVE", tag(8))
        assertEquals("fmt ", tag(12))
        assertEquals(16, b.getInt(16))
        assertEquals(1, b.getShort(20).toInt(), "linear PCM")
        assertEquals(1, b.getShort(22).toInt(), "mono")
        assertEquals(44_100, b.getInt(24))
        assertEquals(88_200, b.getInt(28), "byte rate")
        assertEquals(2, b.getShort(32).toInt(), "block align")
        assertEquals(16, b.getShort(34).toInt(), "bits per sample")
        assertEquals("data", tag(36))
        assertEquals(samples.size * 2, b.getInt(40))
        for (i in samples.indices step 997) assertEquals(samples[i], b.getShort(44 + i * 2), "sample $i")
        assertEquals((1.05 * 44_100).toInt(), samples.size, "1.05 s, as on iOS")
    }

    /** The file's version and the channel's move together: a new tone is a
     *  new file AND a new channel, because a channel's sound is fixed at
     *  creation and a recreated id gets its old settings back. */
    @Test
    fun theChannelCarriesTheSoundsVersion() {
        val v = ReminderSoundFile.VERSION
        assertEquals("dredfit_reminder_v$v.wav", ReminderSoundFile.NAME)
        assertEquals("reminder-v$v", ReminderChannel.id(branded = true))
        assertNotEquals(ReminderChannel.id(branded = true), ReminderChannel.id(branded = false),
                        "the stock-sound channel must not take the branded one's id — its sound could never change")
    }

    @Test
    fun everyOtherReminderChannelIsStaleAndNothingElseIs() {
        val current = ReminderChannel.id(branded = true)
        val existing = listOf("workout", "reminder-v0", current, ReminderChannel.id(branded = false), "miscellaneous")
        assertEquals(listOf("reminder-v0", ReminderChannel.id(branded = false)), ReminderChannel.stale(existing, current))
        assertTrue(ReminderChannel.stale(listOf("workout", current), current).isEmpty(),
                   "the workout's channel and the current one stay")
    }
}
