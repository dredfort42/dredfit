package com.dredfit.core

//
//  The two pull ladders — the slot that stands in every session.
//
//  Y-T-W raises are not on the row ladder (activation, not load); their
//  technique lives in `WarmupTechnique`.
//
//  The row is graded by the ANGLE of the support, so the ladder has lower
//  rungs than a horizontal row.
//

// A technique line is ONE literal, because the literal IS the catalog key:
// wrapping it across lines would change what the catalog scanner and the
// compiler read, and shortening the prose to fit a ruler would change the
// technique. The lint's width rule is right for code, and this file is text.

// The towel note rides INSIDE the setup step: the card is pinned to three
// steps and two mistakes (LibraryPinTests), and a grip that hurts ends the
// set before the back does — so it cannot wait for a fourth line that will
// never exist. It sits on this rung and not lower because the edge only
// starts biting once the body is horizontal; every rung above loads the
// same grip harder, and whoever reaches them has read it here.
private val ExerciseLibrary.invertedRow: Technique
    get() = Technique(
        steps = listOf(
            "Lie under a sturdy table and grab the edge with a shoulder-width grip; if the edge cuts into the fingers, lay a rolled towel over it.",
            "Body straight from shoulders to heels; pull the chest to the edge, squeezing the shoulder blades.",
            "Lower slowly until the arms are straight.",
        ),
        mistakes = listOf(
            "Sagging hips — hold the body like a plank.",
            "Pulling only with the arms — start by squeezing the shoulder blades.",
        ))

internal val ExerciseLibrary.pull: List<ExerciseVariation>
    get() = listOf(
        rung("Standing incline row",
             w = 0.12, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Grab a doorframe or a post at chest height, feet right at its base.",
                     "Lean back on straight arms, the body about 80° to the floor.",
                     "Pull the chest to the support, squeezing the shoulder blades, and return slowly to straight arms.",
                 ),
                 mistakes = listOf(
                     "The support is not solid — check the frame and your grip before the first rep.",
                     "Pulling only with the arms — start by squeezing the shoulder blades.",
                 ))),
        rung("High-bar inverted row",
             w = 0.175, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Grab a table edge and walk your feet forward: the body at about 70° to the floor.",
                     "Hold the torso like a plank and pull the chest to the edge, squeezing the shoulder blades.",
                     "Lower slowly to straight arms; the farther the feet, the harder.",
                 ),
                 mistakes = listOf(
                     "Hips sagging — keep one line from shoulders to heels.",
                     "Reaching with the chin instead of the chest — lead with the chest.",
                 ))),
        // The assistance rung into the horizontal row: the body sits at
        // about 50° instead of parallel, and the angle IS the dose.
        rung("Mid-height inverted row",
             w = 0.245, unit = LoadUnit.reps, perSide = false,
             invertedRow.assisted(step = 0, "Grab the table edge and step out so the body sits at about 50° — that angle IS the dose of assistance.")),
        rung("Inverted row (table)",
             w = 0.31, unit = LoadUnit.reps, perSide = false, invertedRow),
        rung("Feet-elevated inverted row",
             w = 0.375, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Same setup, but feet up on a chair — the body is parallel to the floor.",
                     "Pull the chest to the table edge with a rigid torso.",
                     "Pause a second at the top; lower under control.",
                 ),
                 mistakes = listOf(
                     "Reaching with the chin instead of the chest — lead with the chest.",
                     "Rushing the reps — control both directions.",
                 ))),
        rung("Side-shift inverted row",
             w = 0.47, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Lie under the table and grab the edge with a wide grip, body straight.",
                     "Pull the chest toward one hand, shifting the weight onto it; the other one helps hold the line.",
                     "Lower under control; whole set to one side, then switch.",
                 ),
                 mistakes = listOf(
                     "Both arms pulling evenly — then it is just a row.",
                     "Hips sagging — hold the plank line through the set.",
                 ))),
        rung("Archer inverted row",
             w = 0.55, unit = LoadUnit.reps, perSide = true, Technique(
                 steps = listOf(
                     "Set up under the table with a wide grip, body straight.",
                     "Pull the chest toward one hand; the other arm stays nearly straight.",
                     "Lower under control; whole set to one side, then switch.",
                 ),
                 mistakes = listOf(
                     "Hips sagging — hold the plank line through the set.",
                     "Both arms pulling equally — the working arm does the job.",
                 ))),
    )

private val ExerciseLibrary.negativePullUp: Technique
    get() = Technique(
        steps = listOf(
            "Step on a support or jump so the chin ends up above the bar.",
            "Lower yourself slowly to straight arms over 3–5 seconds, controlling every inch.",
            "Get back on the support and repeat — no pulling up needed.",
        ),
        mistakes = listOf(
            "Dropping instead of lowering — the negative takes at least 3 seconds.",
            "Relaxed shoulders at the bottom — keep the shoulder blades engaged to the end.",
        ))

/// The ladder that carries the library's ONE unit boundary. Rung 2 is
/// seconds, rung 3 is reps; the ratio between them is undefined, so the
/// density invariant skips that edge and the only way across it is a probe
/// — which is also the only way to compare them.
internal val ExerciseLibrary.pullBar: List<ExerciseVariation>
    get() = listOf(
        rung("Bar hang",
             w = 0.028, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "Grab the bar slightly wider than shoulder width, palms facing away.",
                     "Hang on straight arms and pull the shoulders slightly down — an active hang, shoulders away from the ears.",
                     "Keep the body tight, legs together; breathe steadily for the whole hang.",
                 ),
                 mistakes = listOf(
                     "Shoulders at the ears — pull the shoulder blades down; the hang must be active.",
                     "Swinging — keep the body braced, no pendulum.",
                 ))),
        rung("Scapular hang",
             w = 0.040, unit = LoadUnit.hold, perSide = false, Technique(
                 steps = listOf(
                     "Hang on straight arms, grip slightly wider than shoulders, palms facing away.",
                     "Without bending the elbows, pull the shoulder blades down and back — the body rises a couple of centimetres.",
                     "Hold that position for the whole set; the elbows stay straight.",
                 ),
                 mistakes = listOf(
                     "Bending the elbows — that is a pull-up, not shoulder-blade work.",
                     "Shoulders creeping back to the ears — keep them down for the whole hold.",
                 ))),
        // Two assistance rungs into the negative: the more feet help, the
        // more weight the chair takes.
        rung("Negative pull-up, both feet assisting",
             w = 0.18, unit = LoadUnit.reps, perSide = false,
             negativePullUp.assisted(step = 1, "Lower over 3–5 seconds, helping with BOTH feet on a chair just enough to keep the descent slow.")),
        rung("Negative pull-up, one foot assisting",
             w = 0.26, unit = LoadUnit.reps, perSide = false,
             negativePullUp.assisted(step = 1, "Lower over 3–5 seconds with ONE foot left on the chair — half as much help.")),
        rung("Negative pull-up",
             w = 0.35, unit = LoadUnit.reps, perSide = false, negativePullUp),
        rung("Partial pull-up",
             w = 0.425, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Hang on straight arms, grip slightly wider than shoulders, palms facing away.",
                     "Start by squeezing the shoulder blades and pull up to a right angle at the elbows.",
                     "Lower slowly to straight arms — that's one rep.",
                 ),
                 mistakes = listOf(
                     "Jerking and kicking with the legs — only the back and arms work.",
                     "Cutting the bottom range — every rep starts from fully straight arms.",
                 ))),
        rung("Pull-up",
             w = 0.50, unit = LoadUnit.reps, perSide = false, Technique(
                 steps = listOf(
                     "Hang on straight arms, grip slightly wider than shoulders, palms facing away.",
                     "Pull up, starting by squeezing the shoulder blades, until the chin rises above the bar.",
                     "Lower under control to fully straight arms, no swinging.",
                 ),
                 mistakes = listOf(
                     "Swinging and jerking the body — using momentum doesn't count.",
                     "Half range at the bottom — each rep starts from straight arms.",
                 ))),
    )
