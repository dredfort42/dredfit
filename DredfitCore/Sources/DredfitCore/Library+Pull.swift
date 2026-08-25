//
//  The two pull ladders of §40.1 — the slot that stands in every session.
//
//  Y-T-W raises left the row ladder for the warm-up (§40.1): activation, not
//  load. Their technique lives on in `WarmupTechnique`.
//
//  The row is graded by the ANGLE of the support: three new lower rungs
//  replace the drop from "nothing" straight to a horizontal row.
//

import Foundation

extension ExerciseLibrary {

    private static var invertedRow: Technique {
        Technique(
            steps: [
                String(localized: "Lie under a sturdy table and grab the edge with a shoulder-width grip.", bundle: .module),
                String(localized: "Body straight from shoulders to heels; pull the chest to the edge, squeezing the shoulder blades.", bundle: .module),
                String(localized: "Lower slowly until the arms are straight.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Sagging hips — hold the body like a plank.", bundle: .module),
                String(localized: "Pulling only with the arms — start by squeezing the shoulder blades.", bundle: .module),
            ])
    }

    static var pull: [ExerciseVariation] {
        [
            rung(String(localized: "Standing incline row", bundle: .module),
                 w: 0.12, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Grab a doorframe or a post at chest height, feet right at its base.", bundle: .module),
                         String(localized: "Lean back on straight arms, the body about 80° to the floor.", bundle: .module),
                         String(localized: "Pull the chest to the support, squeezing the shoulder blades, and return slowly to straight arms.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "The support is not solid — check the frame and your grip before the first rep.", bundle: .module),
                         String(localized: "Pulling only with the arms — start by squeezing the shoulder blades.", bundle: .module),
                     ])),
            rung(String(localized: "High-bar inverted row", bundle: .module),
                 w: 0.175, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Grab a table edge and walk your feet forward: the body at about 70° to the floor.", bundle: .module),
                         String(localized: "Hold the torso like a plank and pull the chest to the edge, squeezing the shoulder blades.", bundle: .module),
                         String(localized: "Lower slowly to straight arms; the farther the feet, the harder.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips sagging — keep one line from shoulders to heels.", bundle: .module),
                         String(localized: "Reaching with the chin instead of the chest — lead with the chest.", bundle: .module),
                     ])),
            // The assistance rung into the horizontal row: the body sits at
            // about 50° instead of parallel, and the angle IS the dose.
            rung(String(localized: "Mid-height inverted row", bundle: .module),
                 w: 0.245, unit: .reps, perSide: false,
                 invertedRow.assisted(step: 0, String(
                     localized: "Grab the table edge and step out so the body sits at about 50° — that angle IS the dose of assistance.",
                     bundle: .module))),
            rung(String(localized: "Inverted row (table)", bundle: .module),
                 w: 0.31, unit: .reps, perSide: false, invertedRow),
            rung(String(localized: "Feet-elevated inverted row", bundle: .module),
                 w: 0.375, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Same setup, but feet up on a chair — the body is parallel to the floor.", bundle: .module),
                         String(localized: "Pull the chest to the table edge with a rigid torso.", bundle: .module),
                         String(localized: "Pause a second at the top; lower under control.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Reaching with the chin instead of the chest — lead with the chest.", bundle: .module),
                         String(localized: "Rushing the reps — control both directions.", bundle: .module),
                     ])),
            rung(String(localized: "Side-shift inverted row", bundle: .module),
                 w: 0.47, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Lie under the table and grab the edge with a wide grip, body straight.", bundle: .module),
                         String(localized: "Pull the chest toward one hand, shifting the weight onto it; the other one helps hold the line.", bundle: .module),
                         String(localized: "Lower under control; whole set to one side, then switch.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Both arms pulling evenly — then it is just a row.", bundle: .module),
                         String(localized: "Hips sagging — hold the plank line through the set.", bundle: .module),
                     ])),
            rung(String(localized: "Archer inverted row", bundle: .module),
                 w: 0.55, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Set up under the table with a wide grip, body straight.", bundle: .module),
                         String(localized: "Pull the chest toward one hand; the other arm stays nearly straight.", bundle: .module),
                         String(localized: "Lower under control; whole set to one side, then switch.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips sagging — hold the plank line through the set.", bundle: .module),
                         String(localized: "Both arms pulling equally — the working arm does the job.", bundle: .module),
                     ])),
        ]
    }

    private static var negativePullUp: Technique {
        Technique(
            steps: [
                String(localized: "Step on a support or jump so the chin ends up above the bar.", bundle: .module),
                String(localized: "Lower yourself slowly to straight arms over 3–5 seconds, controlling every inch.", bundle: .module),
                String(localized: "Get back on the support and repeat — no pulling up needed.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Dropping instead of lowering — the negative takes at least 3 seconds.", bundle: .module),
                String(localized: "Relaxed shoulders at the bottom — keep the shoulder blades engaged to the end.", bundle: .module),
            ])
    }

    /// The ladder that carries the library's ONE unit boundary. Rung 2 is
    /// seconds, rung 3 is reps; the ratio between them is undefined, so the
    /// density invariant skips that edge and the only way across it is a probe
    /// (§40.1, §40.10 п. 3) — which is also the only way to compare them.
    static var pullBar: [ExerciseVariation] {
        [
            rung(String(localized: "Bar hang", bundle: .module),
                 w: 0.028, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "Grab the bar slightly wider than shoulder width, palms facing away.", bundle: .module),
                         String(localized: "Hang on straight arms and pull the shoulders slightly down — an active hang, shoulders away from the ears.", bundle: .module),
                         String(localized: "Keep the body tight, legs together; breathe steadily for the whole hang.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Shoulders at the ears — pull the shoulder blades down; the hang must be active.", bundle: .module),
                         String(localized: "Swinging — keep the body braced, no pendulum.", bundle: .module),
                     ])),
            rung(String(localized: "Scapular hang", bundle: .module),
                 w: 0.040, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "Hang on straight arms, grip slightly wider than shoulders, palms facing away.", bundle: .module),
                         String(localized: "Without bending the elbows, pull the shoulder blades down and back — the body rises a couple of centimetres.", bundle: .module),
                         String(localized: "Hold that position for the whole set; the elbows stay straight.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Bending the elbows — that is a pull-up, not shoulder-blade work.", bundle: .module),
                         String(localized: "Shoulders creeping back to the ears — keep them down for the whole hold.", bundle: .module),
                     ])),
            // Two assistance rungs into the negative: the more feet help, the
            // more weight the chair takes.
            rung(String(localized: "Negative pull-up, both feet assisting", bundle: .module),
                 w: 0.18, unit: .reps, perSide: false,
                 negativePullUp.assisted(step: 1, String(
                     localized: "Lower over 3–5 seconds, helping with BOTH feet on a chair just enough to keep the descent slow.",
                     bundle: .module))),
            rung(String(localized: "Negative pull-up, one foot assisting", bundle: .module),
                 w: 0.26, unit: .reps, perSide: false,
                 negativePullUp.assisted(step: 1, String(
                     localized: "Lower over 3–5 seconds with ONE foot left on the chair — half as much help.",
                     bundle: .module))),
            rung(String(localized: "Negative pull-up", bundle: .module),
                 w: 0.35, unit: .reps, perSide: false, negativePullUp),
            rung(String(localized: "Partial pull-up", bundle: .module),
                 w: 0.425, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Hang on straight arms, grip slightly wider than shoulders, palms facing away.", bundle: .module),
                         String(localized: "Start by squeezing the shoulder blades and pull up to a right angle at the elbows.", bundle: .module),
                         String(localized: "Lower slowly to straight arms — that's one rep.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Jerking and kicking with the legs — only the back and arms work.", bundle: .module),
                         String(localized: "Cutting the bottom range — every rep starts from fully straight arms.", bundle: .module),
                     ])),
            rung(String(localized: "Pull-up", bundle: .module),
                 w: 0.50, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Hang on straight arms, grip slightly wider than shoulders, palms facing away.", bundle: .module),
                         String(localized: "Pull up, starting by squeezing the shoulder blades, until the chin rises above the bar.", bundle: .module),
                         String(localized: "Lower under control to fully straight arms, no swinging.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Swinging and jerking the body — using momentum doesn't count.", bundle: .module),
                         String(localized: "Half range at the bottom — each rep starts from straight arms.", bundle: .module),
                     ])),
        ]
    }
}
