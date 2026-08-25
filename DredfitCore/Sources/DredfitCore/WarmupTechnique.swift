//
//  The three movements that left the strength ladders for the warm-up (§40.1):
//  they are about coordination, balance and activation rather than a dose that
//  can be graded, and inside a ladder each stood as a gap in the density.
//
//  Their text lives HERE rather than in the app for one reason: it is the same
//  text it always was, and moving it would move its keys out of the core
//  catalog and orphan six languages' worth of translation. Nothing was
//  deleted — only the ladder they hung on. ("Paused jump lunge" WAS deleted,
//  with its exercise: a pause inside a jump is not a rung of difficulty, it is
//  a different movement, and its `w` was invented.)
//
//  Mirrors WARMUP_TECHNIQUE in the reference adaptive_engine.js.
//

import Foundation

public struct WarmupMovement: Equatable, Sendable {
    public let id: String
    public let name: String
    public let steps: [String]
    public let mistakes: [String]
}

public enum WarmupTechnique {

    /// In the order the spec lists them. The app decides which of them run in
    /// a given session; the catalog only says what they are.
    public static var all: [WarmupMovement] { [ytw, birdDog, singleLegDeadlift] }

    public static var ytw: WarmupMovement {
        WarmupMovement(
            id: "y-t-w",
            name: String(localized: "Y-T-W raises", bundle: .module),
            steps: [
                String(localized: "Lie face down, forehead near the floor, arms extended in a Y shape.", bundle: .module),
                String(localized: "Lift the straight arms, hold for 2 seconds squeezing the shoulder blades, then lower.", bundle: .module),
                String(localized: "Repeat in a T position and a W position — all three positions together count as one rep.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Jerking the torso up — only the arms and shoulder blades lift.", bundle: .module),
                String(localized: "Shoulders creeping toward the ears — pull the blades down and back.", bundle: .module),
            ])
    }

    public static var birdDog: WarmupMovement {
        WarmupMovement(
            id: "bird-dog",
            name: String(localized: "Bird dog (hold)", bundle: .module),
            steps: [
                String(localized: "On all fours: hands under the shoulders, knees under the hips.", bundle: .module),
                String(localized: "Extend the opposite arm and leg into one line with the torso.", bundle: .module),
                String(localized: "Hold without wobbling; pelvis and shoulders stay level.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Lower back arching as the leg lifts — the leg goes no higher than the torso.", bundle: .module),
                String(localized: "Torso rotating — imagine a glass of water on your lower back.", bundle: .module),
            ])
    }

    public static var singleLegDeadlift: WarmupMovement {
        WarmupMovement(
            id: "single-leg-rdl",
            name: String(localized: "Single-leg Romanian deadlift", bundle: .module),
            steps: [
                String(localized: "Stand on one leg with a soft knee; hinge forward from the hips with a flat back.", bundle: .module),
                String(localized: "The free leg extends back; torso and leg form one line, hands reaching toward the floor.", bundle: .module),
                String(localized: "Stand back up by squeezing the glute of the standing leg.", bundle: .module),
            ],
            mistakes: [
                String(localized: "Rounding the back — keep the shoulder blades set, hinge from the hips.", bundle: .module),
                String(localized: "Pelvis rotating open — keep the hips square to the floor.", bundle: .module),
            ])
    }
}
