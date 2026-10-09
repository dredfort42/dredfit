//
//  The reminder's branded sound (#84, stage C). Port of
//  ios/Dredfit/ReminderSoundFile.swift. A notification sound must be a real
//  file the system can open — the one place the "generated, not shipped" rule
//  meets the filesystem. The WAV is still generated (SignalTone.reminder),
//  written once, and never rewritten.
//
//  WHY A VERSION IN THE NAME, TWICE. iOS caches notification sounds by NAME;
//  Android fixes a channel's sound when the channel is CREATED — afterwards
//  only the person can change it, and recreating a deleted channel under the
//  same id restores its old settings. So a future timbre ships as new bytes
//  under a new name AND a new channel id (`_v2`, `reminder-v2`), and the old
//  channel is deleted. Both carry `VERSION`, so they cannot drift apart.
//
//  Deliberately independent of `settings.soundsEnabled`: notifications are the
//  system's channel and follow the system's settings for it; the app's switch
//  governs the in-workout tones only.
//
//  Plain Kotlin (java.io): the channel itself is created in
//  SystemNotificationScheduler.kt.
//

package com.dredfit.reminders

import com.dredfit.signals.SignalTone
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

object ReminderSoundFile {

    const val VERSION = 1

    const val NAME = "dredfit_reminder_v$VERSION.wav"

    /** The folder under `filesDir` the FileProvider hands the system
     *  (res/xml/share_paths.xml names it). */
    const val DIRECTORY = "sounds"

    /** The generated tone as a 16-bit mono PCM WAV — CountdownSounds.swift's
     *  `wavFile`, byte for byte. */
    val wav: ByteArray by lazy { wavFile(SignalTone.reminder) }

    /**
     * Ensures `<root>/sounds/dredfit_reminder_v1.wav` exists and returns it.
     * Idempotent: an existing file is left untouched. Any failure to
     * provision returns null, and the reminder falls back to the system's
     * sound — a reminder with the stock sound beats a silent one.
     */
    fun provision(root: File): File? {
        val directory = File(root, DIRECTORY)
        val file = File(directory, NAME)
        if (file.exists()) return file
        return try {
            if (!directory.isDirectory && !directory.mkdirs()) return null
            // Written aside and moved: a file cut short by a full disk would
            // otherwise stand as the "existing file" forever.
            val partial = File(directory, "$NAME.partial")
            partial.writeBytes(wav)
            if (!partial.renameTo(file)) {
                partial.delete()
                return null
            }
            file
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            null
        }
    }

    private fun wavFile(samples: ShortArray): ByteArray {
        val dataSize = samples.size * 2
        val out = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)
        out.put("RIFF".toByteArray(Charsets.US_ASCII))
        out.putInt(36 + dataSize)
        out.put("WAVE".toByteArray(Charsets.US_ASCII))
        out.put("fmt ".toByteArray(Charsets.US_ASCII))
        out.putInt(16)                              // PCM chunk size
        out.putShort(1)                             // linear PCM
        out.putShort(1)                             // mono
        out.putInt(SignalTone.sampleRate)
        out.putInt(SignalTone.sampleRate * 2)       // byte rate
        out.putShort(2)                             // block align
        out.putShort(16)                            // bits per sample
        out.put("data".toByteArray(Charsets.US_ASCII))
        out.putInt(dataSize)
        for (sample in samples) out.putShort(sample)
        return out.array()
    }
}

/** Which notification channel the reminder posts to. */
object ReminderChannel {

    private const val PREFIX = "reminder-v"

    /** The branded channel of this sound version, or — when the sound file
     *  could not be written — a channel with the system's sound. Two ids,
     *  because a channel's sound cannot change after creation: once the file
     *  can be written, the next reminder moves to the branded channel. */
    fun id(branded: Boolean): String = if (branded) "$PREFIX${ReminderSoundFile.VERSION}" else "$PREFIX${ReminderSoundFile.VERSION}-stock"

    /** Reminder channels of other versions, or of the other kind: deleted,
     *  so Settings lists one "Reminder", never two. Other channels (the
     *  workout's) are not this rule's. */
    fun stale(existing: List<String>, current: String): List<String> =
        existing.filter { it.startsWith(PREFIX) && it != current }
}
