//
//  The tones, synthesised in code — no media file ships with the app, as on
//  iOS. Port of ios/Dredfit/CountdownSounds.swift: `SignalTone` is the same
//  synthesis to the sample (pure arithmetic, pinned by CountdownSoundsTest on
//  the JVM), `CountdownSounds` the player.
//
//  HOW IT SOUNDS NEXT TO MUSIC. iOS plays in the `.ambient` category with
//  `.mixWithOthers`: at media volume, over whatever is playing, never pausing
//  or ducking it, and muted by the ring/silent switch unless "Play tones in
//  Silent mode" says otherwise. The Android equivalents, one for one:
//
//  - Media volume: USAGE_MEDIA routes to the music stream. A sonification
//    usage would follow the system/ring volume, which routinely sits near
//    zero while music plays — the reason iOS avoided system sounds.
//  - Mixing: NO audio focus is requested. Focus is what makes another app
//    pause or duck; a countdown must never pause the music somebody is
//    training to, and iOS does not duck either (no `.duckOthers`).
//  - The silent switch: the ringer mode. Silent or vibrate mutes the tones
//    unless `playsTonesInSilentMode` is on; the haptic twin carries the count
//    either way (`WorkoutSignals.kt`).
//

package com.dredfit.signals

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import com.dredfit.core.roundedAwayFromZero
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * The "Minimal+" set (issue #84): one C-major language — a fifth up means
 * start, a flat double tap means switch — every note an additive pair
 * (fundamental + a 15 % octave harmonic) under an exponential decay, and a
 * strict loudness hierarchy: tick < switchSides = done < go < workoutDone <
 * milestone. CountdownSounds.swift says why each shape is the shape it is.
 */
object SignalTone {

    const val sampleRate = 44_100

    private const val C6 = 1046.50
    private const val E6 = 1318.51
    private const val G6 = 1567.98
    private const val C7 = 2093.00

    /** One second of the 3-2-1 countdown: a short G6, the quietest voice. */
    val tick: ShortArray by lazy { mix(listOf(0.0 to note(G6, 0.18, 0.040)), total = 0.20, peak = 0.32) }

    /** Something starts: the fifth up, C6 → G6. */
    val go: ShortArray by lazy {
        mix(listOf(0.0 to note(C6, 0.30, 0.080), 0.095 to note(G6, 0.45, 0.128)), total = 0.55, peak = 0.80)
    }

    /** Switch sides: two fast taps on one pitch, 75 ms apart — a rhythm,
     *  not a contour. */
    val switchSides: ShortArray by lazy {
        mix(listOf(0.0 to note(G6, 0.18, 0.060), 0.075 to note(G6, 0.40, 0.130)), total = 0.48, peak = 0.66)
    }

    /** The effort is over: top-down C7 → G6. */
    val done: ShortArray by lazy {
        mix(listOf(0.0 to note(C7, 0.30, 0.072), 0.110 to note(G6, 0.50, 0.136)), total = 0.62, peak = 0.66)
    }

    /** The workout is assembled: the go's motif completed by the octave. */
    val workoutDone: ShortArray by lazy {
        mix(listOf(0.0 to note(C6, 0.40, 0.112), 0.130 to note(G6, 0.45, 0.128),
                   0.260 to note(C7, 0.70, 0.176)), total = 1.00, peak = 0.85)
    }

    /** A milestone: the major arpeggio with a −6 dB echo of the top note. */
    val milestone: ShortArray by lazy {
        mix(listOf(0.0 to note(C6, 0.45, 0.112), 0.120 to note(E6, 0.45, 0.120),
                   0.240 to note(G6, 0.50, 0.136), 0.360 to note(C7, 0.85, 0.224),
                   0.520 to note(C7, 0.80, 0.240, amp = 0.5)), total = 1.35, peak = 0.88)
    }

    /** The reminder: the go's motif slowed and softened. Not played in-app —
     *  it is the notification channel's (reminders/, phase 3). */
    val reminder: ShortArray by lazy {
        mix(listOf(0.0 to note(C6, 0.50, 0.144), 0.140 to note(G6, 0.90, 0.240)), total = 1.05, peak = 0.50)
    }

    /** One additive note under an exponential decay, opened by a 4 ms
     *  half-cosine ramp and closed by a 5 ms one. */
    fun note(hz: Double, seconds: Double, tau: Double, amp: Double = 1.0): DoubleArray {
        val rate = sampleRate.toDouble()
        val count = (seconds * rate).toInt()
        val attack = 176                         // 4 ms
        val release = min(220, count / 3)        // 5 ms
        return DoubleArray(count) { i ->
            val t = i / rate
            var value = (sin(2 * PI * hz * t) + 0.15 * sin(4 * PI * hz * t)) * exp(-t / tau) * amp
            if (i < attack) value *= 0.5 - 0.5 * cos(PI * i / (attack - 1))
            if (count - i <= release) value *= 0.5 - 0.5 * cos(PI * (count - i) / release)
            value
        }
    }

    /** Overlap-add, then ONE normalisation of the mixed signal to the
     *  sound's peak — per note would break the loudness hierarchy. Clamped
     *  before 16 bits: a peak past 1.0 distorts at the edit rather than
     *  overflowing at the first countdown. */
    fun mix(events: List<Pair<Double, DoubleArray>>, total: Double, peak: Double): ShortArray {
        val rate = sampleRate.toDouble()
        val buffer = DoubleArray((total * rate).toInt())
        for ((start, samples) in events) {
            val offset = (start * rate).toInt()
            for (i in samples.indices) {
                if (offset + i < buffer.size) buffer[offset + i] += samples[i]
            }
        }
        val maxAbs = buffer.maxOfOrNull { abs(it) } ?: 0.0
        val scale = if (maxAbs > 0) peak / maxAbs else 0.0
        return ShortArray(buffer.size) { i ->
            val clamped = (buffer[i] * scale).coerceIn(-1.0, 1.0)
            roundedAwayFromZero(clamped * 32_767).toInt().toShort()
        }
    }
}

/**
 * The player: one static AudioTrack per tone, built by `prime()` — the first
 * tick of a countdown must not pay for synthesis and buffer setup, which is
 * why the flow primes at its start (`WorkoutSession.appear`).
 */
class CountdownSounds(context: Context) {

    private val audio: AudioManager? = context.getSystemService(AudioManager::class.java)

    /** The six the flow plays. No player for the reminder: it never plays
     *  in-app. */
    enum class Tone(val samples: () -> ShortArray) {
        Tick({ SignalTone.tick }), Go({ SignalTone.go }), SwitchSides({ SignalTone.switchSides }),
        Done({ SignalTone.done }), WorkoutDone({ SignalTone.workoutDone }), Milestone({ SignalTone.milestone }),
    }

    private val tracks: Map<Tone, AudioTrack> by lazy { Tone.entries.associateWith { track(it.samples()) } }

    /** Construction is the work: calling this early means the first tick
     *  pays none of it. */
    fun prime() {
        tracks.size
    }

    /** The silent switch's half: a phone set to silent or vibrate keeps the
     *  tones quiet unless the person let them through. */
    fun play(tone: Tone, playsInSilentMode: Boolean) {
        if (!playsInSilentMode && audio?.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val track = tracks[tone] ?: return
        // Rewound first: ticks arrive a second apart, and a firing must not
        // be swallowed because the previous one is still tailing off.
        try {
            track.stop()
            track.reloadStaticData()
            track.play()
        } catch (_: IllegalStateException) {
            // A track the system took back (audio server restart): the tone is
            // lost, the haptic twin still lands, and nothing else depends on it.
        }
    }

    private fun track(samples: ShortArray): AudioTrack {
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(SignalTone.sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build())
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(samples.size * 2)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()
        track.write(samples, 0, samples.size)
        return track
    }
}
