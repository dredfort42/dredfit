//
//  The technique of three of the warm-up's nine movements (the pool lives in
//  the app's Warmup.swift): they are about coordination, balance and
//  activation rather than a dose that can be graded, so they are not on any
//  strength ladder.
//
//  Their text lives HERE rather than in the app because moving it would move
//  its keys out of the core catalog and orphan six languages' worth of
//  translation.
//
//  Mirrors WARMUP_TECHNIQUE in the reference adaptive_engine.js.
//

package com.dredfit.core

// A technique line is ONE literal, because the literal IS the catalog key:
// wrapping it across lines would change what the catalog scanner reads.

data class WarmupMovement(
    val id: String,
    val name: String,
    val steps: List<String>,
    val mistakes: List<String>,
)

object WarmupTechnique {

    /** All three, for the library pin to sweep. The app takes them one by one
     *  into its pool, which sets their order and which of them run. */
    val all: List<WarmupMovement> get() = listOf(ytw, birdDog, singleLegDeadlift)

    val ytw: WarmupMovement
        get() = WarmupMovement(
            id = "y-t-w",
            name = "Y-T-W raises",
            steps = listOf(
                "Lie face down, forehead near the floor, arms extended in a Y shape.",
                "Lift the straight arms, hold for 2 seconds squeezing the shoulder blades, then lower.",
                "Repeat in a T position and a W position — all three positions together count as one rep.",
            ),
            mistakes = listOf(
                "Jerking the torso up — only the arms and shoulder blades lift.",
                "Shoulders creeping toward the ears — pull the blades down and back.",
            ),
        )

    val birdDog: WarmupMovement
        get() = WarmupMovement(
            id = "bird-dog",
            name = "Bird dog (hold)",
            steps = listOf(
                "On all fours: hands under the shoulders, knees under the hips.",
                "Extend the opposite arm and leg into one line with the torso.",
                "Hold without wobbling; pelvis and shoulders stay level.",
            ),
            mistakes = listOf(
                "Lower back arching as the leg lifts — the leg goes no higher than the torso.",
                "Torso rotating — imagine a glass of water on your lower back.",
            ),
        )

    val singleLegDeadlift: WarmupMovement
        get() = WarmupMovement(
            id = "single-leg-rdl",
            name = "Single-leg Romanian deadlift",
            steps = listOf(
                "Stand on one leg with a soft knee; hinge forward from the hips with a flat back.",
                "The free leg extends back; torso and leg form one line, hands reaching toward the floor.",
                "Stand back up by squeezing the glute of the standing leg.",
            ),
            mistakes = listOf(
                "Rounding the back — keep the shoulder blades set, hinge from the hips.",
                "Pelvis rotating open — keep the hips square to the floor.",
            ),
        )
}
