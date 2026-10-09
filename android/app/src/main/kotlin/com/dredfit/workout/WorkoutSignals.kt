//
//  What the workout flow plays and says — the DECISIONS only. Port of the
//  `WorkoutSignalling` half of ios/Dredfit/WorkoutSignals.swift: the flow
//  reaches the device through this, so a test hears every tone it would have
//  made. The tones themselves (synthesised, no media files) and the
//  vibrations are the device half, `signals/` in phase 2c; each pair sits
//  behind the one sounds toggle, passed as `enabled` exactly as on iOS.
//

package com.dredfit.workout

interface WorkoutSignalling {
    /** The haptic half: the vibrator warmed a second or two ahead of a 3-2-1
     *  (`WorkoutSession.primeBeforeTheCount`). */
    fun prime()
    /** The tone half: the audio output paid for before the first tick. */
    fun primeSounds()
    fun tick(enabled: Boolean)
    fun go(enabled: Boolean)
    fun switchSides(enabled: Boolean)
    fun done(enabled: Boolean)
    fun workoutDone(enabled: Boolean)
    fun milestone(enabled: Boolean)
    /** Spoken by the screen reader, whatever the sounds switch says. */
    fun announce(message: Words)
}
