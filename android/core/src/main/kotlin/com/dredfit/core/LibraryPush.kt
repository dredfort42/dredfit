package com.dredfit.core

//
//  The two push ladders and the two core ladders.
//
//  Bird-dog is not on the rotation ladder: a hold there is about
//  coordination, not volume. Its technique lives in `WarmupTechnique`.
//

// A technique line is ONE literal, because the literal IS the catalog key:
// wrapping it across lines would change what the catalog scanner and the
// compiler read, and shortening the prose to fit a ruler would change the
// technique. The lint's width rule is right for code, and this file is text.

internal val ExerciseLibrary.pushH: List<ExerciseVariation>
    get() = listOf(
        rung("Knee push-up",
             w = 0.245, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Hands under the shoulders, knees on the floor; head to knees form a straight line.",
                     "Lower for ~2 seconds until the chest nearly touches the floor, elbows about 45° from the torso.",
                     "Press up on an exhale, keeping the belly tight.",
                 ),
                 mistakes = listOf(
                     "Sagging hips — squeeze your glutes and abs.",
                     "Cutting the range short — the chest should almost touch the floor.",
                 ))),
        rung("Incline push-up",
             w = 0.28, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Put your hands on a stable support about 45 cm high: a windowsill, a table, the arm of a couch.",
                     "Body in one line from head to heels, elbows about 45° from the torso.",
                     "Lower for ~2 seconds until the chest touches the support, press up on an exhale.",
                 ),
                 mistakes = listOf(
                     "The support wobbles or slides — check it before the first rep.",
                     "Sagging hips — squeeze your glutes and abs.",
                 ))),
        rung("Push-up",
             w = 0.32, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Hands under the shoulders; the body is one straight line from head to heels.",
                     "Lower for ~2 seconds until the chest nearly touches the floor, elbows about 45° from the torso.",
                     "Press up on an exhale; don't fully lock the elbows at the top.",
                 ),
                 mistakes = listOf(
                     "Sagging hips or a raised butt — the core stops working.",
                     "Elbows flared out to 90° — this overloads the shoulders.",
                 ))),
        rung("Feet-elevated push-up",
             w = 0.375, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Feet on a chair or couch, hands under the shoulders on the floor.",
                     "Keep the body rigid and lower until the chest nearly touches the floor.",
                     "The higher the support, the harder it gets — start low.",
                 ),
                 mistakes = listOf(
                     "Lower back arching — don't let the hips sag.",
                     "Leading with the head — keep the neck in line with the torso.",
                 ))),
        rung("Side-shift push-up",
             w = 0.47, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Hands wider than the shoulders: the working hand under its shoulder, the other set out to the side.",
                     "Lower while shifting the weight onto the working arm; the other one only keeps you balanced.",
                     "Press up with the working arm; whole set to one side, then switch.",
                 ),
                 mistakes = listOf(
                     "Weight split evenly — then it is just a push-up.",
                     "Torso turning — keep the hips and shoulders facing the floor.",
                 ))),
        rung("Archer push-up",
             w = 0.60, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Take a wide hand position; the body stays one straight line.",
                     "Lower toward one hand, bending that elbow; the other arm stays straight.",
                     "Press up and repeat to the same side for the whole set, then switch.",
                 ),
                 mistakes = listOf(
                     "Hips rotating — shoulders and hips stay square to the floor.",
                     "Half range — the chest goes down to the working hand.",
                 ))),
    )

private val ExerciseLibrary.pikePushUp: Technique
    get() = Technique(
        steps = listOf(
            "From a push-up position, lift the hips high — the body forms an inverted V.",
            "Bend the elbows, lowering the top of the head toward the floor between the hands.",
            "Press back up without dropping the hips.",
        ),
        mistakes = listOf(
            "Hips dropping as the arms bend — keep the V shape.",
            "Bumping the head on the floor — lower slowly, with control.",
        ))

internal val ExerciseLibrary.pushV: List<ExerciseVariation>
    get() = listOf(
        rung("Wall push-up",
             w = 0.125, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Stand a step away from a wall, palms on it slightly wider than shoulders, at chest height.",
                     "Bend the elbows, bringing the face toward the wall, body in one line.",
                     "Push back to straight arms; the farther the feet, the harder.",
                 ),
                 mistakes = listOf(
                     "Hips dropping back — the whole body moves as one line.",
                     "Elbows flared to 90° — keep them closer to the torso.",
                 ))),
        // Two assistance rungs into the pike: the lower the support, the
        // more of your weight reaches the shoulders.
        rung("Pike push-up, hands on a table",
             w = 0.17, unit = LoadUnit.reps, perSide = false,
             pikePushUp.assisted(step = 0, "Put your hands on a table and step back — the body still makes an angle, but the support carries part of the shoulders' load.")),
        rung("Pike push-up, hands on a chair",
             w = 0.225, unit = LoadUnit.reps, perSide = false,
             pikePushUp.assisted(step = 0, "Put your hands on a chair seat and step back — the lower the support, the more weight reaches the shoulders.")),
        rung("Pike push-up",
             w = 0.31, unit = LoadUnit.reps, perSide = false, pikePushUp),
        rung("Feet-elevated pike push-up",
             w = 0.39, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Put your feet on a chair or a low bed and walk your hands back into a steep inverted V.",
                     "Bend the elbows, lowering the top of the head toward the floor between the hands.",
                     "Press back up; the higher the feet, the closer this gets to a handstand.",
                 ),
                 mistakes = listOf(
                     "Hips sagging toward the floor — keep the V sharp, weight over the hands.",
                     "Starting too high — if the head cannot reach the floor with control, lower the feet.",
                 ))),
        rung("Wall handstand negative",
             w = 0.45, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Walk up into a wall handstand: hands a palm's length from the wall, heels resting on it.",
                     "Lower the top of the head toward the floor over 3–5 seconds, elbows tracking forward and down.",
                     "Come down at the bottom, get back up and repeat — no need to press up.",
                 ),
                 mistakes = listOf(
                     "Dropping instead of lowering — the negative takes at least 3 seconds.",
                     "Arching the lower back — keep the core and glutes tight.",
                 ))),
        rung("Wall handstand push-up",
             w = 0.55, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Getting in: face away from the wall, hands a palm's length from it, and walk your feet up until your heels rest on it.",
                     "Bend the elbows slowly, lowering the top of the head toward the floor.",
                     "Getting out: walk the feet back down the wall. If you have to come down mid-rep, turn your head to one side and step over — never collapse straight down.",
                 ),
                 mistakes = listOf(
                     "Arching the lower back — keep the core and glutes tight.",
                     "Elbows drifting outward — track them forward and down.",
                 ))),
    )

internal val ExerciseLibrary.coreAntiExt: List<ExerciseVariation>
    get() = listOf(
        rung("Knee plank",
             w = 0.020, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "Forearms on the floor, elbows under the shoulders, knees down.",
                     "Head to knees — one straight line; belly pulled in.",
                     "Breathe steadily and hold for the planned time.",
                 ),
                 mistakes = listOf(
                     "Hips sagging — tuck the pelvis slightly.",
                     "Shoulders at the ears — push the floor away, keep the neck long.",
                 ))),
        rung("High plank",
             w = 0.025, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "A push-up position: hands under the shoulders, arms straight, feet hip-width.",
                     "One straight line from head to heels; glutes and abs braced.",
                     "Breathe steadily; on straight arms the lever is shorter than on the forearms.",
                 ),
                 mistakes = listOf(
                     "Hips hiked up — easier, but pointless.",
                     "Shoulders drifting past the hands — keep them right over the wrists.",
                 ))),
        rung("Plank",
             w = 0.030, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "Forearms on the floor, elbows under the shoulders, feet hip-width.",
                     "One straight line from head to heels; glutes and abs braced.",
                     "Breathe steadily; shaking is fine, a sagging line is not.",
                 ),
                 mistakes = listOf(
                     "Hips hiked up — easier, but pointless.",
                     "Lower back sagging — that strains the spine; better to stop early.",
                 ))),
        rung("Hollow hold",
             w = 0.036, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "Lie on your back, press the lower back into the floor, arms extended overhead.",
                     "Lift the shoulder blades and straight legs 15–20 cm off the floor.",
                     "Hold the hollow shape with the lower back pressed down the whole time.",
                 ),
                 mistakes = listOf(
                     "Lower back lifting off the floor — raise the legs higher or bend the knees.",
                     "Holding your breath — keep breathing shallow and steady.",
                 ))),
        rung("Long-lever plank",
             w = 0.050, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "Take a plank on the forearms, elbows well ahead of the shoulders.",
                     "Keep one straight line from head to heels, glutes tight.",
                     "The farther the elbows, the harder — breathe steadily and hold.",
                 ),
                 mistakes = listOf(
                     "Hips sagging — tuck the pelvis and brace the abs.",
                     "Elbows too far too soon — increase the lever gradually.",
                 ))),
    )

private val ExerciseLibrary.kneelingSidePlank: Technique
    get() = Technique(
        steps = listOf(
            "Lie on your side, elbow under the shoulder, knees bent and stacked.",
            "Lift the hips until knees, hips and shoulders form a straight line.",
            "Hold without letting the hips drop; free hand on the waist.",
        ),
        mistakes = listOf(
            "Hips sagging — keep the body line straight.",
            "Torso tipping forward — shoulders and hips in one plane.",
        ))

internal val ExerciseLibrary.coreRot: List<ExerciseVariation>
    get() = listOf(
        rung("Kneeling side plank",
             w = 0.022, unit = LoadUnit.hold, perSide = true, kneelingSidePlank),
        // The assistance rung: the top foot still carries weight, but the
        // base is narrower.
        rung("Kneeling side plank, top leg extended",
             w = 0.028, unit = LoadUnit.hold, perSide = true,
             kneelingSidePlank.assisted(step = 2, "Extend the top leg forward and put that foot on the floor — a narrower base, and more work for the torso.")),
        rung("Side plank",
             w = 0.034, unit = LoadUnit.hold, perSide = true, Technique(
                 steps = listOf(
                     "Lie on your side, elbow under the shoulder, feet stacked.",
                     "Lift the hips until feet–hips–shoulders form a straight line.",
                     "Hold without letting the hips drop; free hand on the waist or up.",
                 ),
                 mistakes = listOf(
                     "Hips sagging — keep the body line straight.",
                     "Torso tipping forward — shoulders and hips in one plane.",
                 ))),
        rung("Side plank with leg raise",
             w = 0.044, unit = LoadUnit.hold, perSide = true, Technique(
                 steps = listOf(
                     "Get into a side plank on the elbow.",
                     "Raise the top leg 20–30 cm and hold it straight.",
                     "Hips high, the body in one plane.",
                 ),
                 mistakes = listOf(
                     "Hips dropping when the leg lifts — stabilize the plank first.",
                     "Leg drifting forward — keep it in line with the torso.",
                 ))),
        rung("Star side plank",
             w = 0.058, unit = LoadUnit.hold, perSide = true, Technique(
                 steps = listOf(
                     "From a side plank, raise the top leg and the top arm at once.",
                     "The body forms a star: straight line plus raised limbs.",
                     "Hips high the whole hold; look straight ahead.",
                 ),
                 mistakes = listOf(
                     "Hips dropping — the base line comes first, the star second.",
                     "Body folding forward — shoulders, hips and legs in one plane.",
                 ))),
    )
