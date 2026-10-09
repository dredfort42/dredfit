//
//  How an addition "for next time" is printed — one place for the four
//  screens that print one. Port of ios/Dredfit/RaiseLabel.swift.
//

package com.dredfit.workout

import com.dredfit.core.Dose
import com.dredfit.core.LoadUnit

object RaiseLabel {
    fun added(steps: Int, unit: LoadUnit): Int = maxOf(0, steps) * Dose.grid(unit).step

    /** "+5 s" / "+1". The unit is a word, so the hold form goes through the
     *  catalog; the reps form is plain. */
    fun text(steps: Int, unit: LoadUnit): Words {
        val n = added(steps, unit)
        return if (unit == LoadUnit.hold) Words.of("+%lld s", n) else Words.join("+%lld", n)
    }

    fun spoken(steps: Int, unit: LoadUnit): Words {
        val n = added(steps, unit)
        return if (unit == LoadUnit.hold) Words.of("plus %lld seconds for next time", n)
        else Words.of("plus %lld reps for next time", n)
    }
}
