//
//  Copy discipline: every line is a fact of mechanics ("lifting with your
//  hips, not your lower back"), never a health promise ("your back will stop
//  hurting") — promises invite App Review questions. Keep that boundary when
//  adding or translating.
//

import Foundation
import DredfitCore

enum LifeBenefit {

    /// Variation override if the pair is in the closed list, otherwise the
    /// movement's base line. Resolved here so TechniqueSheet and
    /// MilestoneView cannot disagree.
    static func text(for pattern: Pattern, variation: Int) -> String {
        overrideText(for: pattern, variation: variation) ?? baseText(for: pattern)
    }

    // MARK: - Base lines (one per movement)

    /// Keyed, not literal: a key stops a future short literal from silently
    /// reusing this translation (the "Done"/"Next" collision of wave 4).
    static func baseText(for pattern: Pattern) -> String {
        switch pattern {
        case .squat:
            return String(localized: "life.squat",
                          defaultValue: "Getting up from the floor or a chair, taking stairs at a run — strength you use every day.")
        case .pushH:
            return String(localized: "life.push_h",
                          defaultValue: "Pushing a heavy door, getting up from the ground, catching yourself when you fall.")
        case .hinge:
            return String(localized: "life.hinge",
                          defaultValue: "Lifting a bag, a child, a suitcase — with your hips, not your lower back.")
        case .pull:
            return String(localized: "life.pull",
                          defaultValue: "A straight back and open shoulders after a day at the desk.")
        case .pushV:
            return String(localized: "life.push_v",
                          defaultValue: "Lifting a suitcase onto the top shelf, reaching the highest cupboard.")
        case .lunge:
            return String(localized: "life.lunge",
                          defaultValue: "A confident step on stairs, uphill, off a curb — balance under load.")
        case .coreAntiExt:
            return String(localized: "life.core_anti_ext",
                          defaultValue: "A lower back that handles long hours of sitting, bending and a heavy backpack.")
        case .coreRot:
            return String(localized: "life.core_rot",
                          defaultValue: "Carrying weight in one hand, reaching sideways — a torso that holds.")
        case .calf:
            return String(localized: "life.calf",
                          defaultValue: "Spring in every step: stairs and running feel lighter on knees and feet.")
        case .pullBar:
            return String(localized: "life.pull_bar",
                          defaultValue: "Holding and pulling your own bodyweight — the most honest measure of strength.")
        }
    }

    // MARK: - Variation overrides (closed list)

    /// The indices are pinned to the library, so a reshuffle of a ladder must
    /// revisit these pairs — and the KEYS name the movement rather than its
    /// index, precisely so the next reshuffle moves a case label and not a
    /// translation. (They used to be `life.override.squat-3` and friends, and
    /// §40.1 moved every one of those numbers.) LifeBenefitTests cross-checks
    /// the pairs against the library by name.
    static func overrideText(for pattern: Pattern, variation: Int) -> String? {
        switch (pattern, variation) {
        case (.squat, 5):      // Pistol squat
            return String(localized: "life.override.pistol-squat",
                          defaultValue: "Standing up from the floor on one leg — no hands, no support.")
        case (.pushH, 3):      // Push-up
            return String(localized: "life.override.push-up",
                          defaultValue: "Your own bodyweight — under full control.")
        case (.pushV, 7):      // Wall handstand push-up
            return String(localized: "life.override.wall-handstand",
                          defaultValue: "Your whole body above your hands — a rare level of control.")
        case (.pullBar, 7):    // Pull-up
            return String(localized: "life.override.pull-up",
                          defaultValue: "Lifting your own bodyweight — the base for any physical task.")
        default:
            return nil
        }
    }
}
