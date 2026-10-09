//
//  One line of mechanics per movement — a fact ("lifting with your hips, not
//  your lower back"), never a health promise. Port of
//  ios/Dredfit/LifeBenefit.swift; keep that boundary when adding or
//  translating.
//

package com.dredfit.workout

import com.dredfit.core.Pattern

object LifeBenefit {

    /** The variation's override if the pair is in the closed list, otherwise
     *  the movement's base line. */
    fun text(pattern: Pattern, variation: Int): Words = overrideText(pattern, variation) ?: baseText(pattern)

    /** Keyed, not literal: a key stops a future short literal from silently
     *  reusing this translation. */
    fun baseText(pattern: Pattern): Words = when (pattern) {
        Pattern.squat -> Words.keyed("life.squat",
            "Getting up from the floor or a chair, taking stairs at a run — strength you use every day.")
        Pattern.pushH -> Words.keyed("life.push_h",
            "Pushing a heavy door, getting up from the ground, catching yourself when you fall.")
        Pattern.hinge -> Words.keyed("life.hinge",
            "Lifting a bag, a child, a suitcase — with your hips, not your lower back.")
        Pattern.pull -> Words.keyed("life.pull",
            "A straight back and open shoulders after a day at the desk.")
        Pattern.pushV -> Words.keyed("life.push_v",
            "Lifting a suitcase onto the top shelf, reaching the highest cupboard.")
        Pattern.lunge -> Words.keyed("life.lunge",
            "A confident step on stairs, uphill, off a curb — balance under load.")
        Pattern.coreAntiExt -> Words.keyed("life.core_anti_ext",
            "A lower back that handles long hours of sitting, bending and a heavy backpack.")
        Pattern.coreRot -> Words.keyed("life.core_rot",
            "Carrying weight in one hand, reaching sideways — a torso that holds.")
        Pattern.calf -> Words.keyed("life.calf",
            "Spring in every step: stairs and running feel lighter on knees and feet.")
        Pattern.pullBar -> Words.keyed("life.pull_bar",
            "Holding and pulling your own bodyweight — the most honest measure of strength.")
    }

    /** The closed list: the indices are pinned to the library, the KEYS name
     *  the movement. LifeBenefitTest cross-checks the pairs by name. */
    fun overrideText(pattern: Pattern, variation: Int): Words? = when {
        pattern == Pattern.squat && variation == 5 -> Words.keyed("life.override.pistol-squat",
            "Standing up from the floor on one leg — no hands, no support.")
        pattern == Pattern.pushH && variation == 3 -> Words.keyed("life.override.push-up",
            "Your own bodyweight — under full control.")
        pattern == Pattern.pushV && variation == 7 -> Words.keyed("life.override.wall-handstand",
            "Your whole body above your hands — a rare level of control.")
        pattern == Pattern.pullBar && variation == 7 -> Words.keyed("life.override.pull-up",
            "Lifting your own bodyweight — the base for any physical task.")
        else -> null
    }
}
