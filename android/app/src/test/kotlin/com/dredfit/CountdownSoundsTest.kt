//
//  Port of ios/DredfitTests/CountdownSoundsTests.swift: the "Minimal+" set of
//  issue #84 — seven generated sounds, one synthesis rule, a strict loudness
//  hierarchy. The tones are code, so their frequencies, peaks and envelopes
//  are facts a test can hold, and here they are read straight off the PCM the
//  player is handed.
//
//  Not ported: `testTonesAreValidMonoPCMWav` — iOS wraps the samples in a WAV
//  for AVAudioPlayer; AudioTrack takes the 16-bit mono samples themselves, and
//  their format is the builder's (CountdownSounds.track), not a file header.
//  `testTonesArePlayableAtTheExpectedDuration` reads the duration off the
//  sample count instead of off a player.
//

package com.dredfit

import com.dredfit.signals.SignalTone
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CountdownSoundsTest {

    private class Sound(val name: String, val tone: ShortArray, val seconds: Double, val peak: Double)

    private val set = listOf(
        Sound("tick", SignalTone.tick, 0.20, 0.32),
        Sound("go", SignalTone.go, 0.55, 0.80),
        Sound("switchSides", SignalTone.switchSides, 0.48, 0.66),
        Sound("done", SignalTone.done, 0.62, 0.66),
        Sound("workoutDone", SignalTone.workoutDone, 1.00, 0.85),
        Sound("milestone", SignalTone.milestone, 1.35, 0.88),
        Sound("reminder", SignalTone.reminder, 1.05, 0.50),
    )

    private fun peak(tone: ShortArray): Double = (tone.maxOfOrNull { abs(it.toInt()) } ?: 0) / 32_767.0

    private fun crossings(s: List<Short>): Int = s.zipWithNext().count { (a, b) -> (a < 0) != (b < 0) }

    /** |x| under a ~3 ms moving average: the envelope an ear counts taps by. */
    private fun envelope(tone: ShortArray): DoubleArray {
        val all = tone.map { abs(it.toInt()).toDouble() }
        val window = (0.003 * SignalTone.sampleRate).toInt()
        val out = DoubleArray(all.size)
        var running = 0.0
        for (i in all.indices) {
            running += all[i]
            if (i >= window) running -= all[i - window]
            out[i] = running / minOf(i + 1, window)
        }
        return out
    }

    private fun argmax(v: DoubleArray, range: IntRange): Int = range.maxByOrNull { v[it] } ?: range.first
    private fun argmin(v: DoubleArray, range: IntRange): Int = range.minByOrNull { v[it] } ?: range.first

    @Test
    fun tonesAreAtTheExpectedDuration() {
        for (sound in set) {
            assertEquals(sound.seconds, sound.tone.size / SignalTone.sampleRate.toDouble(), 0.01, sound.name)
        }
    }

    /** Peaks land on their targets, and the order holds: the frequent is
     *  quiet, the rare is bright. */
    @Test
    fun peaksMatchTheHierarchy() {
        for (sound in set) {
            assertEquals(sound.peak, peak(sound.tone), sound.peak * 0.02, "${sound.name}: peak off its target")
        }
        assertTrue(peak(SignalTone.tick) < peak(SignalTone.switchSides))
        assertEquals(peak(SignalTone.switchSides), peak(SignalTone.done), 0.01,
                     "the two mid-hierarchy signals share a level")
        assertTrue(peak(SignalTone.done) < peak(SignalTone.go))
        assertTrue(peak(SignalTone.go) < peak(SignalTone.workoutDone))
        assertTrue(peak(SignalTone.workoutDone) < peak(SignalTone.milestone))
    }

    @Test
    fun goStandsOutFromTick() {
        assertTrue(SignalTone.go.size > SignalTone.tick.size * 2)
        assertTrue(peak(SignalTone.go) > peak(SignalTone.tick))
    }

    /** The switch tone (issue #35) is a flat double tap: two G6 attacks 75 ms
     *  apart — a rhythm, not a melody. */
    @Test
    fun switchIsAFlatDoubleTap() {
        val rate = SignalTone.sampleRate.toDouble()
        val env = envelope(SignalTone.switchSides)
        val first = argmax(env, 0 until (0.030 * rate).toInt())
        val trough = argmin(env, first until (0.090 * rate).toInt())
        val second = argmax(env, trough until (0.130 * rate).toInt())
        assertTrue(env[second] > env[trough] * 1.8, "the second tap must rise clear of the first one's decay")
        assertEquals(0.075, (second - first) / rate, 0.015,
                     "75 ms apart — quicker than the 95-110 ms of the melodic pairs")

        // Same pitch at both ends, measured over signal, not over the
        // trailing silence of the buffer.
        val sw = SignalTone.switchSides.toList()
        val window = (0.035 * rate).toInt()
        val lastVoiced = sw.indexOfLast { it.toInt() != 0 }
        val opening = crossings(sw.take(window))
        val closing = crossings(sw.subList(lastVoiced + 1 - window, lastVoiced + 1))
        assertEquals(1.0, opening.toDouble() / closing, 0.06, "both taps sit on one pitch, within a semitone")
    }

    @Test
    fun goRises() {
        val go = SignalTone.go.toList()
        assertTrue(crossings(go.takeLast(2000)) > crossings(go.take(2000)), "the go must rise")
    }

    @Test
    fun doneFalls() {
        val done = SignalTone.done.toList()
        assertTrue(crossings(done.take(2000)) > crossings(done.takeLast(2000)), "done must open high and settle low")
    }

    /** The finale completes the go's motif with the octave. 0.85–0.90 s is the
     *  C7 alone, before the trailing silence. */
    @Test
    fun workoutDoneAscends() {
        val tone = SignalTone.workoutDone.toList()
        val lateStart = (0.85 * SignalTone.sampleRate).toInt()
        val late = tone.subList(lateStart, lateStart + 2000)
        assertTrue(crossings(late) > crossings(tone.take(2000)), "the finale must end above its start")
    }

    /** The milestone's echo: the fifth note is the fourth at half voice. */
    @Test
    fun milestoneEchoIsQuieter() {
        val fourthPeak = SignalTone.note(2093.00, 0.85, 0.224).maxOf { abs(it) }
        val fifthPeak = SignalTone.note(2093.00, 0.80, 0.240, amp = 0.5).maxOf { abs(it) }
        assertEquals(fourthPeak * 0.5, fifthPeak, fourthPeak * 0.05, "the echo sits ~6 dB under the note it repeats")
    }

    @Test
    fun toneEdgesAreClickFree() {
        for (sound in set) {
            assertTrue(abs(sound.tone.first().toInt()) < 1_000, sound.name)
            assertTrue(abs(sound.tone.last().toInt()) < 1_000, sound.name)
        }
    }

    /** No RNG anywhere in the set: two independent builds are identical, and
     *  they reproduce the shipped tone. */
    @Test
    fun generationIsDeterministic() {
        fun build() = SignalTone.mix(
            listOf(0.0 to SignalTone.note(1046.50, 0.30, 0.080), 0.095 to SignalTone.note(1567.98, 0.45, 0.128)),
            total = 0.55, peak = 0.80)
        assertContentEquals(build(), build(), "the synthesis must be fully deterministic")
        assertContentEquals(SignalTone.go, build(), "and reproduce the shipped tone exactly")
    }
}
