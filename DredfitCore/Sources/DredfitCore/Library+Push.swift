//
//  The two push ladders and the two core ladders of §40.1.
//
//  Bird-dog left the rotation ladder for the warm-up (§40.1): a hold there is
//  about coordination, not volume. Its technique lives on in `WarmupTechnique`.
//

import Foundation

extension ExerciseLibrary {

    static var pushH: [ExerciseVariation] {
        [
            rung(String(localized: "Knee push-up", bundle: .module),
                 w: 0.245, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Hands under the shoulders, knees on the floor; head to knees form a straight line.", bundle: .module),
                         String(localized: "Lower for ~2 seconds until the chest nearly touches the floor, elbows about 45° from the torso.", bundle: .module),
                         String(localized: "Press up on an exhale, keeping the belly tight.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Sagging hips — squeeze your glutes and abs.", bundle: .module),
                         String(localized: "Cutting the range short — the chest should almost touch the floor.", bundle: .module),
                     ])),
            rung(String(localized: "Incline push-up", bundle: .module),
                 w: 0.28, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Put your hands on a stable support about 45 cm high: a windowsill, a table, the arm of a couch.", bundle: .module),
                         String(localized: "Body in one line from head to heels, elbows about 45° from the torso.", bundle: .module),
                         String(localized: "Lower for ~2 seconds until the chest touches the support, press up on an exhale.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "The support wobbles or slides — check it before the first rep.", bundle: .module),
                         String(localized: "Sagging hips — squeeze your glutes and abs.", bundle: .module),
                     ])),
            rung(String(localized: "Push-up", bundle: .module),
                 w: 0.32, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Hands under the shoulders; the body is one straight line from head to heels.", bundle: .module),
                         String(localized: "Lower for ~2 seconds until the chest nearly touches the floor, elbows about 45° from the torso.", bundle: .module),
                         String(localized: "Press up on an exhale; don't fully lock the elbows at the top.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Sagging hips or a raised butt — the core stops working.", bundle: .module),
                         String(localized: "Elbows flared out to 90° — this overloads the shoulders.", bundle: .module),
                     ])),
            rung(String(localized: "Feet-elevated push-up", bundle: .module),
                 w: 0.375, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Feet on a chair or couch, hands under the shoulders on the floor.", bundle: .module),
                         String(localized: "Keep the body rigid and lower until the chest nearly touches the floor.", bundle: .module),
                         String(localized: "The higher the support, the harder it gets — start low.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Lower back arching — don't let the hips sag.", bundle: .module),
                         String(localized: "Leading with the head — keep the neck in line with the torso.", bundle: .module),
                     ])),
            rung(String(localized: "Side-shift push-up", bundle: .module),
                 w: 0.47, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Hands wider than the shoulders: the working hand under its shoulder, the other set out to the side.", bundle: .module),
                         String(localized: "Lower while shifting the weight onto the working arm; the other one only keeps you balanced.", bundle: .module),
                         String(localized: "Press up with the working arm; whole set to one side, then switch.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Weight split evenly — then it is just a push-up.", bundle: .module),
                         String(localized: "Torso turning — keep the hips and shoulders facing the floor.", bundle: .module),
                     ])),
            rung(String(localized: "Archer push-up", bundle: .module),
                 w: 0.60, unit: .reps, perSide: true, Technique(
                     steps: [
                         String(localized: "Take a wide hand position; the body stays one straight line.", bundle: .module),
                         String(localized: "Lower toward one hand, bending that elbow; the other arm stays straight.", bundle: .module),
                         String(localized: "Press up and repeat to the same side for the whole set, then switch.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips rotating — shoulders and hips stay square to the floor.", bundle: .module),
                         String(localized: "Half range — the chest goes down to the working hand.", bundle: .module),
                     ])),
        ]
    }

    private static var pikePushUp: Technique {
        Technique(
            steps: [
                String(localized: "From a push-up position, lift the hips high — the body forms an inverted V.", bundle: .module),
                String(localized: "Bend the elbows, lowering the top of the head toward the floor between the hands.", bundle: .module),
                String(localized: "Press back up without dropping the hips.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Hips dropping as the arms bend — keep the V shape.", bundle: .module),
                String(localized: "Bumping the head on the floor — lower slowly, with control.", bundle: .module),
            ])
    }

    static var pushV: [ExerciseVariation] {
        [
            rung(String(localized: "Wall push-up", bundle: .module),
                 w: 0.125, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Stand a step away from a wall, palms on it slightly wider than shoulders, at chest height.", bundle: .module),
                         String(localized: "Bend the elbows, bringing the face toward the wall, body in one line.", bundle: .module),
                         String(localized: "Push back to straight arms; the farther the feet, the harder.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips dropping back — the whole body moves as one line.", bundle: .module),
                         String(localized: "Elbows flared to 90° — keep them closer to the torso.", bundle: .module),
                     ])),
            // Two assistance rungs into the pike: the lower the support, the
            // more of your weight reaches the shoulders.
            rung(String(localized: "Pike push-up, hands on a table", bundle: .module),
                 w: 0.17, unit: .reps, perSide: false,
                 pikePushUp.assisted(step: 0, String(
                     localized: "Put your hands on a table and step back — the body still makes an angle, but the support carries part of the shoulders' load.",
                     bundle: .module))),
            rung(String(localized: "Pike push-up, hands on a chair", bundle: .module),
                 w: 0.225, unit: .reps, perSide: false,
                 pikePushUp.assisted(step: 0, String(
                     localized: "Put your hands on a chair seat and step back — the lower the support, the more weight reaches the shoulders.",
                     bundle: .module))),
            rung(String(localized: "Pike push-up", bundle: .module),
                 w: 0.31, unit: .reps, perSide: false, pikePushUp),
            rung(String(localized: "Feet-elevated pike push-up", bundle: .module),
                 w: 0.39, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Put your feet on a chair or a low bed and walk your hands back into a steep inverted V.", bundle: .module),
                         String(localized: "Bend the elbows, lowering the top of the head toward the floor between the hands.", bundle: .module),
                         String(localized: "Press back up; the higher the feet, the closer this gets to a handstand.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips sagging toward the floor — keep the V sharp, weight over the hands.", bundle: .module),
                         String(localized: "Starting too high — if the head cannot reach the floor with control, lower the feet.", bundle: .module),
                     ])),
            rung(String(localized: "Wall handstand negative", bundle: .module),
                 w: 0.45, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Walk up into a wall handstand: hands a palm's length from the wall, heels resting on it.", bundle: .module),
                         String(localized: "Lower the top of the head toward the floor over 3–5 seconds, elbows tracking forward and down.", bundle: .module),
                         String(localized: "Come down at the bottom, get back up and repeat — no need to press up.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Dropping instead of lowering — the negative takes at least 3 seconds.", bundle: .module),
                         String(localized: "Arching the lower back — keep the core and glutes tight.", bundle: .module),
                     ])),
            rung(String(localized: "Wall handstand push-up", bundle: .module),
                 w: 0.55, unit: .reps, perSide: false, Technique(
                     steps: [
                         String(localized: "Getting in: face away from the wall, hands a palm's length from it, and walk your feet up until your heels rest on it.", bundle: .module),
                         String(localized: "Bend the elbows slowly, lowering the top of the head toward the floor.", bundle: .module),
                         String(localized: "Getting out: walk the feet back down the wall. If you have to bail mid-rep, turn your head to one side and step over — never collapse straight down.",
                                bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Arching the lower back — keep the core and glutes tight.", bundle: .module),
                         String(localized: "Elbows drifting outward — track them forward and down.", bundle: .module),
                     ])),
        ]
    }

    static var coreAntiExt: [ExerciseVariation] {
        [
            rung(String(localized: "Knee plank", bundle: .module),
                 w: 0.020, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "Forearms on the floor, elbows under the shoulders, knees down.", bundle: .module),
                         String(localized: "Head to knees — one straight line; belly pulled in.", bundle: .module),
                         String(localized: "Breathe steadily and hold for the planned time.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips sagging — tuck the pelvis slightly.", bundle: .module),
                         String(localized: "Shoulders at the ears — push the floor away, keep the neck long.", bundle: .module),
                     ])),
            rung(String(localized: "High plank", bundle: .module),
                 w: 0.025, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "A push-up position: hands under the shoulders, arms straight, feet hip-width.", bundle: .module),
                         String(localized: "One straight line from head to heels; glutes and abs braced.", bundle: .module),
                         String(localized: "Breathe steadily; on straight arms the lever is shorter than on the forearms.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips hiked up — easier, but pointless.", bundle: .module),
                         String(localized: "Shoulders drifting past the hands — keep them right over the wrists.", bundle: .module),
                     ])),
            rung(String(localized: "Plank", bundle: .module),
                 w: 0.030, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "Forearms on the floor, elbows under the shoulders, feet hip-width.", bundle: .module),
                         String(localized: "One straight line from head to heels; glutes and abs braced.", bundle: .module),
                         String(localized: "Breathe steadily; shaking is fine, a sagging line is not.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips hiked up — easier, but pointless.", bundle: .module),
                         String(localized: "Lower back sagging — that strains the spine; better to stop early.", bundle: .module),
                     ])),
            rung(String(localized: "Hollow hold", bundle: .module),
                 w: 0.036, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "Lie on your back, press the lower back into the floor, arms extended overhead.", bundle: .module),
                         String(localized: "Lift the shoulder blades and straight legs 15–20 cm off the floor.", bundle: .module),
                         String(localized: "Hold the hollow shape with the lower back pressed down the whole time.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Lower back lifting off the floor — raise the legs higher or bend the knees.", bundle: .module),
                         String(localized: "Holding your breath — keep breathing shallow and steady.", bundle: .module),
                     ])),
            rung(String(localized: "Long-lever plank", bundle: .module),
                 w: 0.050, unit: .hold, perSide: false, Technique(
                     steps: [
                         String(localized: "Take a plank on the forearms, elbows well ahead of the shoulders.", bundle: .module),
                         String(localized: "Keep one straight line from head to heels, glutes tight.", bundle: .module),
                         String(localized: "The farther the elbows, the harder — breathe steadily and hold.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips sagging — tuck the pelvis and brace the abs.", bundle: .module),
                         String(localized: "Elbows too far too soon — increase the lever gradually.", bundle: .module),
                     ])),
        ]
    }

    private static var kneelingSidePlank: Technique {
        Technique(
            steps: [
                String(localized: "Lie on your side, elbow under the shoulder, knees bent and stacked.", bundle: .module),
                String(localized: "Lift the hips until knees, hips and shoulders form a straight line.", bundle: .module),
                String(localized: "Hold without letting the hips drop; free hand on the waist.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Hips sagging — keep the body line straight.", bundle: .module),
                String(localized: "Torso tipping forward — shoulders and hips in one plane.", bundle: .module),
            ])
    }

    static var coreRot: [ExerciseVariation] {
        [
            rung(String(localized: "Kneeling side plank", bundle: .module),
                 w: 0.022, unit: .hold, perSide: true, kneelingSidePlank),
            // The assistance rung: the top foot still carries weight, but the
            // base is narrower.
            rung(String(localized: "Kneeling side plank, top leg extended", bundle: .module),
                 w: 0.028, unit: .hold, perSide: true,
                 kneelingSidePlank.assisted(step: 2, String(
                     localized: "Extend the top leg forward and put that foot on the floor — a narrower base, and more work for the torso.",
                     bundle: .module))),
            rung(String(localized: "Side plank", bundle: .module),
                 w: 0.034, unit: .hold, perSide: true, Technique(
                     steps: [
                         String(localized: "Lie on your side, elbow under the shoulder, feet stacked.", bundle: .module),
                         String(localized: "Lift the hips until feet–hips–shoulders form a straight line.", bundle: .module),
                         String(localized: "Hold without letting the hips drop; free hand on the waist or up.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips sagging — keep the body line straight.", bundle: .module),
                         String(localized: "Torso tipping forward — shoulders and hips in one plane.", bundle: .module),
                     ])),
            rung(String(localized: "Side plank with leg raise", bundle: .module),
                 w: 0.044, unit: .hold, perSide: true, Technique(
                     steps: [
                         String(localized: "Get into a side plank on the elbow.", bundle: .module),
                         String(localized: "Raise the top leg 20–30 cm and hold it straight.", bundle: .module),
                         String(localized: "Hips high, the body in one plane.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips dropping when the leg lifts — stabilize the plank first.", bundle: .module),
                         String(localized: "Leg drifting forward — keep it in line with the torso.", bundle: .module),
                     ])),
            rung(String(localized: "Star side plank", bundle: .module),
                 w: 0.058, unit: .hold, perSide: true, Technique(
                     steps: [
                         String(localized: "From a side plank, raise the top leg and the top arm at once.", bundle: .module),
                         String(localized: "The body forms a star: straight line plus raised limbs.", bundle: .module),
                         String(localized: "Hips high the whole hold; look straight ahead.", bundle: .module),
                     ],
                     mistakes: [
                         String(localized: "Hips dropping — the base line comes first, the star second.", bundle: .module),
                         String(localized: "Body folding forward — shoulders, hips and legs in one plane.", bundle: .module),
                     ])),
        ]
    }
}
