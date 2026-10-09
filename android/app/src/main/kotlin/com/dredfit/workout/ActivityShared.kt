//
//  What the workout's tile shows outside the app. Port of
//  ios/Shared/ActivityShared.swift (`RestActivityAttributes.ContentState`).
//  On iOS it is the Live Activity; its Android twin, an ongoing notification,
//  arrives in phase 3 and reads exactly this.
//

package com.dredfit.workout

import java.time.Instant

data class ActivityState(
    val phase: Phase,
    val title: Words,
    /** null where iOS sends "" — a tile line with nothing to say. */
    val detail: Words?,
    /** The end of whatever the phase counts down — a rest, or a hold. */
    val restEndDate: Instant?,
) {
    /** `hold` is work that owns an end date: the one phase whose copy asks
     *  the athlete to put the phone down, so it must show a countdown. */
    @Suppress("EnumEntryName")
    enum class Phase { work, rest, hold }
}
