//
//  The four lower-body ladders of §40.1 — squat, hinge, lunge, calf.
//  Split out of Library.swift so neither file approaches the lint's ceiling;
//  the ladders themselves are one table each, in the spec's order.
//
//  The single-leg Romanian deadlift left the hinge ladder for the warm-up
//  (§40.1): it is about balance, not dose, and it stood in the ladder as a
//  gap. Its technique lives on in `WarmupTechnique`.
//

import Foundation

extension ExerciseLibrary {

    // The technique an assistance rung inherits, named once so the rung and
    // its base cannot drift apart.
    private static var bulgarianSplitSquat: Technique {
        Technique(
            steps: [
                String(localized: "Rear foot on a chair or couch behind you, front foot a stride ahead.", bundle: .module),
                String(localized: "Lower straight down until the rear knee almost touches the floor.", bundle: .module),
                String(localized: "Drive up through the front heel; torso leaning slightly forward.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Stance too short — the front knee travels far past the toes.", bundle: .module),
                String(localized: "Loading the rear leg — it is only there for balance.", bundle: .module),
            ])
    }

    static var squat: [ExerciseVariation] {
        [
            rung(String(localized: "Squat", bundle: .module),
                 w: 0.43, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Feet shoulder-width apart, toes slightly out, weight over the whole foot.", bundle: .module),
                         String(localized: "Sit back and down for ~2 seconds; knees track over the toes, back straight.", bundle: .module),
                         String(localized: "Thighs parallel to the floor at the bottom; drive up on an exhale.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Knees caving inward — keep them tracking over your feet.", bundle: .module),
                         String(localized: "Heels lifting off the floor — depth matters more than speed.", bundle: .module),
                     ])),
            rung(String(localized: "Split squat", bundle: .module),
                 w: 0.55, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Step forward one stride; both feet stay on the floor, weight on the front leg.", bundle: .module),
                         String(localized: "Lower straight down for ~2 seconds until the rear knee almost touches the floor.", bundle: .module),
                         String(localized: "Drive up through the front heel; the feet stay put for the whole set.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Stance too short — the front knee travels far past the toes.", bundle: .module),
                         String(localized: "Weight shifting to the rear leg — it only holds your balance.", bundle: .module),
                     ])),
            rung(String(localized: "Bulgarian split squat", bundle: .module),
                 w: 0.70, unit: .reps, perSide: true, bulgarianSplitSquat),
            rung(String(localized: "Single-leg squat to a chair", bundle: .module),
                 w: 0.78, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Stand on one leg with your back to a chair, the other leg extended forward, arms out in front.", bundle: .module),
                         String(localized: "Sit back for ~2 seconds until the glutes touch the seat lightly — without sitting down.", bundle: .module),
                         String(localized: "Stand up through the heel of the working leg; the lower the seat, the harder.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Dropping onto the chair — the touch stays light and controlled.", bundle: .module),
                         String(localized: "Helping with the other leg — it hangs forward the whole time.", bundle: .module),
                     ])),
            rung(String(localized: "Pistol squat", bundle: .module),
                 w: 1.00, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Stand on one leg, the other extended forward, arms out for balance.", bundle: .module),
                         String(localized: "Lower slowly until the hamstring rests on the calf, heel on the floor.", bundle: .module),
                         String(localized: "Stand up without your hands; start with a doorframe assist if needed.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Dropping down without control — the descent must be slow.", bundle: .module),
                         String(localized: "Knee drifting sideways — keep it tracking over the foot.", bundle: .module),
                     ])),
            rung(String(localized: "Shrimp squat", bundle: .module),
                 w: 1.15, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Stand on one leg; bend the other back and hold its foot with one hand.", bundle: .module),
                         String(localized: "Lower slowly until the back knee gently touches the floor.", bundle: .module),
                         String(localized: "Stand up through the heel of the working leg, chest up.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Knee crashing into the floor — the descent stays slow and controlled.", bundle: .module),
                         String(localized: "Leaning far forward — keep the chest up and the core braced.", bundle: .module),
                     ])),
        ]
    }

    private static var singleLegGluteBridge: Technique {
        Technique(
            steps: [
                String(localized: "Lie on your back, one foot near the glutes, the other leg extended.", bundle: .module),
                String(localized: "Lift the hips with one leg to a straight line, keeping the pelvis level.", bundle: .module),
                String(localized: "Pause a second at the top, lower slowly.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Pelvis tilting sideways — keep both hip bones pointing at the ceiling.", bundle: .module),
                String(localized: "Helping with the free leg — it stays out of the movement.", bundle: .module),
            ])
    }

    private static var singleLegSlidingCurl: Technique {
        Technique(
            steps: [
                String(localized: "Lie on your back, one heel on a towel, the other leg raised; hips in a bridge.", bundle: .module),
                String(localized: "Slide the heel away until the leg is almost straight, hips stay up.", bundle: .module),
                String(localized: "Pull the heel back to the glute with that one leg — that's one rep.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Hips dropping as the leg extends — keep the bridge the whole time.", bundle: .module),
                String(localized: "Jerky pulls — slide out and back slowly, with control.", bundle: .module),
            ])
    }

    static var hinge: [ExerciseVariation] {
        [
            rung(String(localized: "Glute bridge", bundle: .module),
                 w: 0.175, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Lie on your back, feet close to the glutes hip-width apart, arms at your sides.", bundle: .module),
                         String(localized: "Lift the hips until knees, hips and shoulders form one straight line.", bundle: .module),
                         String(localized: "Squeeze the glutes for a second at the top, then lower slowly without touching the floor.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Arching the lower back — don't push past the straight line.", bundle: .module),
                         String(localized: "Pushing through the toes — keep the weight on the heels.", bundle: .module),
                     ])),
            // The assistance rung: the free heel stays on the floor and pushes
            // exactly as much as it takes to keep the pelvis level.
            rung(String(localized: "Assisted single-leg glute bridge", bundle: .module),
                 w: 0.26, unit: .reps, perSide: true,
                 singleLegGluteBridge.assisted(step: 1, String(
                     localized: "Lift the hips with the working leg, pushing gently through the heel of the other — the easier it goes, the less you push.",
                     bundle: .module))),
            rung(String(localized: "Single-leg glute bridge", bundle: .module),
                 w: 0.35, unit: .reps, perSide: true, singleLegGluteBridge),
            rung(String(localized: "Sliding leg curl", bundle: .module),
                 w: 0.45, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Lie on your back, heels on a towel on a smooth floor, hips lifted.", bundle: .module),
                         String(localized: "Slide the heels away until the legs are almost straight, hips stay up.", bundle: .module),
                         String(localized: "Pull the heels back toward the glutes — that's one rep.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips dropping as the legs extend — keep the bridge the whole time.", bundle: .module),
                         String(localized: "Jerky pulls — slide out and back slowly, with control.", bundle: .module),
                     ])),
            // Down on one leg, back up on two: the assistance is the easy half
            // of the rep.
            rung(String(localized: "Negative single-leg sliding curl", bundle: .module),
                 w: 0.65, unit: .reps, perSide: true,
                 singleLegSlidingCurl.assisted(step: 2, String(
                     localized: "Pull back with BOTH legs — here the hard half of the rep is the lowering only.",
                     bundle: .module))),
            rung(String(localized: "Single-leg sliding leg curl", bundle: .module),
                 w: 0.90, unit: .reps, perSide: true, singleLegSlidingCurl),
            rung(String(localized: "Assisted Nordic curl", bundle: .module),
                 w: 1.10, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Kneel down and have someone hold your shins, or hook them under a couch.", bundle: .module),
                         String(localized: "Lower forward with a straight body as slowly as the hamstrings can hold you.", bundle: .module),
                         String(localized: "Catch yourself with your hands near the floor and push back up — no need to pull yourself up.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Folding at the hips — one straight line from knees to head.", bundle: .module),
                         String(localized: "Free fall — if you cannot hold it, put your hands down sooner.", bundle: .module),
                     ])),
        ]
    }

    static var lunge: [ExerciseVariation] {
        [
            rung(String(localized: "Static lunge", bundle: .module),
                 w: 0.56, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Step into a lunge stance and stay in it for the whole set.", bundle: .module),
                         String(localized: "Lower straight down until the rear knee almost touches the floor.", bundle: .module),
                         String(localized: "Drive up through the front heel, torso upright.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Front knee traveling far past the toes — take a longer stance.", bundle: .module),
                         String(localized: "Torso tipping forward — keep the chest up.", bundle: .module),
                     ])),
            rung(String(localized: "Reverse lunge", bundle: .module),
                 w: 0.62, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "From standing, step back and lower the rear knee almost to the floor.", bundle: .module),
                         String(localized: "The front shin stays near vertical; weight on the front heel.", bundle: .module),
                         String(localized: "Push off and return to standing — that's one rep.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Too short a step back — the front knee gets overloaded.", bundle: .module),
                         String(localized: "Losing balance — fix your eyes on a point ahead.", bundle: .module),
                     ])),
            rung(String(localized: "Paused lunge", bundle: .module),
                 w: 0.74, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Step back into a lunge, rear knee almost to the floor.", bundle: .module),
                         String(localized: "Hold the bottom for a full 3 seconds, weight on the front heel.", bundle: .module),
                         String(localized: "Stand up through the front heel and repeat — every rep gets the pause.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Skipping the pause — count the three seconds out loud.", bundle: .module),
                         String(localized: "Slumping at the bottom — keep the torso upright for all three seconds.", bundle: .module),
                     ])),
            rung(String(localized: "Jump lunge", bundle: .module),
                 w: 0.98, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "From a lunge, jump up and switch legs in the air.", bundle: .module),
                         String(localized: "Land softly in a lunge on the other side, knee almost to the floor.", bundle: .module),
                         String(localized: "Keep a steady rhythm; use the arms for balance.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Landing stiff on a straight leg — absorb by bending.", bundle: .module),
                         String(localized: "Knee slamming into the floor — control the depth.", bundle: .module),
                     ])),
        ]
    }

    private static var singleLegCalfRaise: Technique {
        Technique(
            steps: [
                String(localized: "Stand on one leg, hand on a wall for balance.", bundle: .module),
                String(localized: "Rise onto the ball of the foot as high as possible, pause for a second.", bundle: .module),
                String(localized: "Lower slowly, heel to the floor (or below step level).", bundle: .module),
            ],
            mistakes: [
                String(localized: "Helping with the other leg — it stays off the floor.", bundle: .module),
                String(localized: "Ankle rolling outward — press through the big toe.", bundle: .module),
            ])
    }

    static var calf: [ExerciseVariation] {
        [
            rung(String(localized: "Calf raises", bundle: .module),
                 w: 0.45, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Stand with feet hip-width; hand on a wall for balance.", bundle: .module),
                         String(localized: "Rise as high as you can onto the balls of the feet, pause a second at the top.", bundle: .module),
                         String(localized: "Lower slowly; for more range, stand with the toes on a step edge.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Fast bouncing — move slowly with a pause at the top.", bundle: .module),
                         String(localized: "Cutting the range — rise all the way up.", bundle: .module),
                     ])),
            // The hand is not only for balance here: how much of your weight it
            // takes IS the dose of assistance.
            rung(String(localized: "Assisted single-leg calf raise", bundle: .module),
                 w: 0.65, unit: .reps, perSide: true,
                 singleLegCalfRaise.assisted(step: 0, String(
                     localized: "Stand on one leg and lean on a wall or a table with one hand so it takes some of your weight.",
                     bundle: .module))),
            rung(String(localized: "Single-leg calf raise", bundle: .module),
                 w: 0.90, unit: .reps, perSide: true, singleLegCalfRaise),
            rung(String(localized: "Single-leg calf raise with pause", bundle: .module),
                 w: 1.05, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Same as the single-leg raise, but with a 3-second pause at the top.", bundle: .module),
                         String(localized: "Up in 1 second, hold for 3, down for 3.", bundle: .module),
                         String(localized: "Full range beats rep count.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Skipping the pause — hold an honest 3 seconds at the top.", bundle: .module),
                         String(localized: "Knee bending — the leg stays straight; only the ankle works.", bundle: .module),
                     ])),
            rung(String(localized: "Single-leg calf raise on a step", bundle: .module),
                 w: 1.25, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Stand on one leg with the ball of the foot on a step edge.", bundle: .module),
                         String(localized: "Lower the heel below the step level, feel the stretch.", bundle: .module),
                         String(localized: "Rise as high as possible, pause a second, lower for 3 seconds.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Short bottom range — the heel must drop below the step.", bundle: .module),
                         String(localized: "Bouncing out of the stretch — pause briefly at the bottom too.", bundle: .module),
                     ])),
        ]
    }
}
