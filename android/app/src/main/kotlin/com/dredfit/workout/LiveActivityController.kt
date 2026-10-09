//
//  The tile as the workout flow drives it. Port of the `WorkoutActivityDriving`
//  protocol of ios/Dredfit/LiveActivityController.swift; the controller
//  itself (ActivityKit there, an ongoing notification here) is phase 3. A
//  test watches what the tile would show through this seam.
//

package com.dredfit.workout

interface WorkoutActivityDriving {
    fun start(sessionNumber: Int, state: ActivityState)
    fun update(state: ActivityState)
    fun end()
}
