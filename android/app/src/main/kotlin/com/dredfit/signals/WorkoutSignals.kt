//
//  The device half of ios/Dredfit/WorkoutSignals.swift: each signal as a
//  pair — the tone (CountdownSounds.kt) and its haptic twin — behind the one
//  sounds toggle, which the flow passes as `enabled`. The decisions (when a
//  tick, a go or a prime happens) are the flow's, in workout/, and pinned by
//  its JVM tests; this file only makes them physical.
//
//  The haptic WEIGHTS are what silent mode reads, so each signal keeps one of
//  its own, as on iOS: tick = the lightest tick, switch = a click, done (stop
//  holding) = a heavy click, go / workout done / milestone = the double
//  "success". Four signals a person on the floor can tell apart blind.
//

package com.dredfit.signals

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.compose.runtime.mutableStateOf
import com.dredfit.signals.CountdownSounds.Tone
import com.dredfit.workout.WorkoutSignalling
import com.dredfit.workout.Words

/**
 * The real tones, haptics and announcements.
 *
 * `prime()` is the haptic half of the pair iOS calls one or two seconds
 * before a count. iOS's `prepare()` spins the Taptic Engine up; Android has
 * no public counterpart — the vibrator HAL wakes on the call itself — so what
 * is warmed here is everything the call does NOT have to do on the beat:
 * the service binder (`hasVibrator`, the first IPC); the four effects are
 * built with the signals. The flow still calls it at exactly the moments iOS does, so the
 * day a device API to pre-arm the motor exists, this is the one line it goes in.
 */
class DeviceSignals(
    context: Context,
    /** `AppSettings.playsTonesInSilentMode`, read at every firing: a choice
     *  imported with a backup is in force on the next tone. */
    private val playsInSilentMode: () -> Boolean,
) : WorkoutSignalling {

    private val sounds = CountdownSounds(context.applicationContext)
    private val vibrator: Vibrator? = context.applicationContext.getSystemService(Vibrator::class.java)

    // Built with the signals, not on the beat.
    private val tickEffect = VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
    private val switchEffect = VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
    private val doneEffect = VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
    private val successEffect = VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK)

    /** What a screen reader says next — the flow screen renders it as a polite
     *  live region (WorkoutFlowView.kt), the Compose form of iOS's
     *  `AccessibilityNotification.Announcement`. */
    val announcement = mutableStateOf<Words?>(null)

    override fun prime() {
        vibrator?.hasVibrator()
    }

    override fun primeSounds() = sounds.prime()

    override fun tick(enabled: Boolean) = fire(enabled, Tone.Tick, tickEffect)

    override fun go(enabled: Boolean) = fire(enabled, Tone.Go, successEffect)

    override fun switchSides(enabled: Boolean) = fire(enabled, Tone.SwitchSides, switchEffect)

    override fun done(enabled: Boolean) = fire(enabled, Tone.Done, doneEffect)

    override fun workoutDone(enabled: Boolean) = fire(enabled, Tone.WorkoutDone, successEffect)

    override fun milestone(enabled: Boolean) = fire(enabled, Tone.Milestone, successEffect)

    override fun announce(message: Words) {
        announcement.value = message
    }

    /** The UI suite's ear: every pair as it fires. Set only by androidTest
     *  (OngoingWorkoutTest, to hear a countdown with the app in the
     *  background); nothing in the app writes it. */
    @Volatile
    var firedForTests: ((Tone) -> Unit)? = null

    private fun fire(enabled: Boolean, tone: Tone, effect: VibrationEffect) {
        if (!enabled) return
        firedForTests?.invoke(tone)
        sounds.play(tone, playsInSilentMode())
        vibrator?.vibrate(effect)
    }
}
