package com.dredfit.core

//
//  The four lower-body ladders — squat, hinge, lunge, calf.
//  Split out of Library.swift so neither file approaches the lint's ceiling;
//  the ladders themselves are one table each.
//
//  The single-leg Romanian deadlift is not on the hinge ladder: it is about
//  balance, not dose, and would be a gap in the ladder. Its technique lives
//  in `WarmupTechnique`.
//

// A technique line is ONE literal, because the literal IS the catalog key:
// wrapping it across lines would change what the catalog scanner and the
// compiler read, and shortening the prose to fit a ruler would change the
// technique. The lint's width rule is right for code, and this file is text.

// The technique an assistance rung inherits, named once so the rung and
// its base cannot drift apart.
private val ExerciseLibrary.bulgarianSplitSquat: Technique
    get() = Technique(
        steps = listOf(
            "Rear foot on a chair or couch behind you, front foot a stride ahead.",
            "Lower straight down until the rear knee almost touches the floor.",
            "Drive up through the front heel; torso leaning slightly forward.",
        ),
        mistakes = listOf(
            "Stance too short — the front knee travels far past the toes.",
            "Loading the rear leg — it is only there for balance.",
        ))

internal val ExerciseLibrary.squat: List<ExerciseVariation>
    get() = listOf(
        rung("Squat",
             w = 0.43, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Feet shoulder-width apart, toes slightly out, weight over the whole foot.",
                     "Sit back and down for ~2 seconds; knees track over the toes, back straight.",
                     "Thighs parallel to the floor at the bottom; drive up on an exhale.",
                 ),
                 mistakes = listOf(
                     "Knees caving inward — keep them tracking over your feet.",
                     "Heels lifting off the floor — depth matters more than speed.",
                 ))),
        rung("Split squat",
             w = 0.55, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Step forward one stride; both feet stay on the floor, weight on the front leg.",
                     "Lower straight down for ~2 seconds until the rear knee almost touches the floor.",
                     "Drive up through the front heel; the feet stay put for the whole set.",
                 ),
                 mistakes = listOf(
                     "Stance too short — the front knee travels far past the toes.",
                     "Weight shifting to the rear leg — it only holds your balance.",
                 ))),
        rung("Bulgarian split squat",
             w = 0.70, unit = LoadUnit.reps, perSide = true, bulgarianSplitSquat),
        rung("Single-leg squat to a chair",
             w = 0.78, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Stand on one leg with your back to a chair, the other leg extended forward, arms out in front.",
                     "Sit back for ~2 seconds until the glutes touch the seat lightly — without sitting down.",
                     "Stand up through the heel of the working leg; the lower the seat, the harder.",
                 ),
                 mistakes = listOf(
                     "Dropping onto the chair — the touch stays light and controlled.",
                     "Helping with the other leg — it hangs forward the whole time.",
                 ))),
        rung("Pistol squat",
             w = 1.00, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Stand on one leg, the other extended forward, arms out for balance.",
                     "Lower slowly until the hamstring rests on the calf, heel on the floor.",
                     "Stand up without your hands; start with a doorframe assist if needed.",
                 ),
                 mistakes = listOf(
                     "Dropping down without control — the descent must be slow.",
                     "Knee drifting sideways — keep it tracking over the foot.",
                 ))),
        rung("Shrimp squat",
             w = 1.15, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Stand on one leg; bend the other back and hold its foot with one hand.",
                     "Lower slowly until the back knee gently touches the floor.",
                     "Stand up through the heel of the working leg, chest up.",
                 ),
                 mistakes = listOf(
                     "Knee crashing into the floor — the descent stays slow and controlled.",
                     "Leaning far forward — keep the chest up and the core braced.",
                 ))),
    )

private val ExerciseLibrary.singleLegGluteBridge: Technique
    get() = Technique(
        steps = listOf(
            "Lie on your back, one foot near the glutes, the other leg extended.",
            "Lift the hips with one leg to a straight line, keeping the pelvis level.",
            "Pause a second at the top, lower slowly.",
        ),
        mistakes = listOf(
            "Pelvis tilting sideways — keep both hip bones pointing at the ceiling.",
            "Helping with the free leg — it stays out of the movement.",
        ))

private val ExerciseLibrary.singleLegSlidingCurl: Technique
    get() = Technique(
        steps = listOf(
            "Lie on your back, one heel on a towel, the other leg raised; hips in a bridge.",
            "Slide the heel away until the leg is almost straight, hips stay up.",
            "Pull the heel back to the glute with that one leg — that's one rep.",
        ),
        mistakes = listOf(
            "Hips dropping as the leg extends — keep the bridge the whole time.",
            "Jerky pulls — slide out and back slowly, with control.",
        ))

internal val ExerciseLibrary.hinge: List<ExerciseVariation>
    get() = listOf(
        rung("Glute bridge",
             w = 0.175, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Lie on your back, feet close to the glutes hip-width apart, arms at your sides.",
                     "Lift the hips until knees, hips and shoulders form one straight line.",
                     "Squeeze the glutes for a second at the top, then lower slowly without touching the floor.",
                 ),
                 mistakes = listOf(
                     "Arching the lower back — don't push past the straight line.",
                     "Pushing through the toes — keep the weight on the heels.",
                 ))),
        // The assistance rung: the free heel stays on the floor and pushes
        // exactly as much as it takes to keep the pelvis level.
        rung("Assisted single-leg glute bridge",
             w = 0.26, unit = LoadUnit.reps, perSide = true,
             singleLegGluteBridge.assisted(step = 1, "Lift the hips with the working leg, pushing gently through the heel of the other — the easier it goes, the less you push.")),
        rung("Single-leg glute bridge",
             w = 0.35, unit = LoadUnit.reps, perSide = true, singleLegGluteBridge),
        rung("Sliding leg curl",
             w = 0.45, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Lie on your back, heels on a towel on a smooth floor, hips lifted.",
                     "Slide the heels away until the legs are almost straight, hips stay up.",
                     "Pull the heels back toward the glutes — that's one rep.",
                 ),
                 mistakes = listOf(
                     "Hips dropping as the legs extend — keep the bridge the whole time.",
                     "Jerky pulls — slide out and back slowly, with control.",
                 ))),
        // Down on one leg, back up on two: the assistance is the easy half
        // of the rep.
        rung("Negative single-leg sliding curl",
             w = 0.65, unit = LoadUnit.reps, perSide = true,
             singleLegSlidingCurl.assisted(step = 2, "Pull back with BOTH legs — here the hard half of the rep is the lowering only.")),
        rung("Single-leg sliding leg curl",
             w = 0.90, unit = LoadUnit.reps, perSide = true, singleLegSlidingCurl),
        rung("Assisted Nordic curl",
             w = 1.10, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Kneel down and have someone hold your shins, or hook them under a couch.",
                     "Lower forward with a straight body as slowly as the hamstrings can hold you.",
                     "Catch yourself with your hands near the floor and push back up — no need to pull yourself up.",
                 ),
                 mistakes = listOf(
                     "Folding at the hips — one straight line from knees to head.",
                     "Free fall — if you cannot hold it, put your hands down sooner.",
                 ))),
    )

internal val ExerciseLibrary.lunge: List<ExerciseVariation>
    get() = listOf(
        rung("Static lunge",
             w = 0.56, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Step into a lunge stance and stay in it for the whole set.",
                     "Lower straight down until the rear knee almost touches the floor.",
                     "Drive up through the front heel, torso upright.",
                 ),
                 mistakes = listOf(
                     "Front knee traveling far past the toes — take a longer stance.",
                     "Torso tipping forward — keep the chest up.",
                 ))),
        rung("Reverse lunge",
             w = 0.62, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "From standing, step back and lower the rear knee almost to the floor.",
                     "The front shin stays near vertical; weight on the front heel.",
                     "Push off and return to standing — that's one rep.",
                 ),
                 mistakes = listOf(
                     "Too short a step back — the front knee gets overloaded.",
                     "Losing balance — fix your eyes on a point ahead.",
                 ))),
        rung("Paused lunge",
             w = 0.74, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Step back into a lunge, rear knee almost to the floor.",
                     "Hold the bottom for a full 3 seconds, weight on the front heel.",
                     "Stand up through the front heel and repeat — every rep gets the pause.",
                 ),
                 mistakes = listOf(
                     "Skipping the pause — count the three seconds out loud.",
                     "Slumping at the bottom — keep the torso upright for all three seconds.",
                 ))),
        rung("Jump lunge",
             w = 0.98, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "From a lunge, jump up and switch legs in the air.",
                     "Land softly in a lunge on the other side, knee almost to the floor.",
                     "Keep a steady rhythm; use the arms for balance.",
                 ),
                 mistakes = listOf(
                     "Landing stiff on a straight leg — absorb by bending.",
                     "Knee slamming into the floor — control the depth.",
                 ))),
    )

private val ExerciseLibrary.singleLegCalfRaise: Technique
    get() = Technique(
        steps = listOf(
            "Stand on one leg, hand on a wall for balance.",
            "Rise onto the ball of the foot as high as possible, pause for a second.",
            "Lower slowly, heel to the floor (or below step level).",
        ),
        mistakes = listOf(
            "Helping with the other leg — it stays off the floor.",
            "Ankle rolling outward — press through the big toe.",
        ))

internal val ExerciseLibrary.calf: List<ExerciseVariation>
    get() = listOf(
        rung("Calf raises",
             w = 0.45, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Stand with feet hip-width; hand on a wall for balance.",
                     "Rise as high as you can onto the balls of the feet, pause a second at the top.",
                     "Lower slowly; for more range, stand with the toes on a step edge.",
                 ),
                 mistakes = listOf(
                     "Fast bouncing — move slowly with a pause at the top.",
                     "Cutting the range — rise all the way up.",
                 ))),
        // The hand is not only for balance here: how much of your weight it
        // takes IS the dose of assistance.
        rung("Assisted single-leg calf raise",
             w = 0.65, unit = LoadUnit.reps, perSide = true,
             singleLegCalfRaise.assisted(step = 0, "Stand on one leg and lean on a wall or a table with one hand so it takes some of your weight.")),
        rung("Single-leg calf raise",
             w = 0.90, unit = LoadUnit.reps, perSide = true, singleLegCalfRaise),
        rung("Single-leg calf raise with pause",
             w = 1.05, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Same as the single-leg raise, but with a 3-second pause at the top.",
                     "Up in 1 second, hold for 3, down for 3.",
                     "Full range beats rep count.",
                 ),
                 mistakes = listOf(
                     "Skipping the pause — hold an honest 3 seconds at the top.",
                     "Knee bending — the leg stays straight; only the ankle works.",
                 ))),
        rung("Single-leg calf raise on a step",
             w = 1.25, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Stand on one leg with the ball of the foot on a step edge.",
                     "Lower the heel below the step level, feel the stretch.",
                     "Rise as high as possible, pause a second, lower for 3 seconds.",
                 ),
                 mistakes = listOf(
                     "Short bottom range — the heel must drop below the step.",
                     "Bouncing out of the stretch — pause briefly at the bottom too.",
                 ))),
    )
