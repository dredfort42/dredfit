//
//  LifeBenefit.swift
//  Dredfit
//
//  The "why" layer (issue #25): one line per movement translating abstract
//  levels into everyday ability — the language people actually use when they
//  tell a friend what changed. Lives entirely in the app layer: the engine
//  knows nothing about it, the golden fixtures cannot move.
//
//  Two-level dictionary by design. Every movement has a base line; a closed
//  list of standout variations overrides it where the variation is brighter
//  than the movement itself ("Pistol squat" says more than "Squat"). The
//  override → base rule is resolved here, in one place, so TechniqueSheet
//  and MilestoneView can never disagree.
//
//  Copy discipline: every line is a fact of mechanics ("lifting with your
//  hips, not your lower back"), never a health promise ("your back will stop
//  hurting") — promises would betray the app's honest tone and invite
//  App Review questions. Keep that boundary when adding or translating.
//

import Foundation
import DredfitCore

enum LifeBenefit {

    /// The line for a given exercise: variation override if the pair is in
    /// the closed list, otherwise the movement's base line.
    static func text(for pattern: Pattern, tier: Int) -> String {
        overrideText(for: pattern, tier: tier) ?? baseText(for: pattern)
    }

    // MARK: - Base lines (one per movement)

    /// Keyed, not literal: these strings are full sentences and safe from
    /// collisions, but keys keep them greppable and stop a future short
    /// literal from silently reusing a translation (see the "Done"/"Next"
    /// collision found in wave 4).
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

    /// The closed list from the spec — grows only by owner decision. Tiers
    /// are pinned to the library: a future reshuffle of variations must
    /// revisit these pairs (the unit test cross-checks names).
    static func overrideText(for pattern: Pattern, tier: Int) -> String? {
        switch (pattern, tier) {
        case (.squat, 3):      // Pistol squat
            return String(localized: "life.override.squat-3",
                          defaultValue: "Standing up from the floor on one leg — no hands, no support.")
        case (.pushH, 2):      // Push-up
            return String(localized: "life.override.push_h-2",
                          defaultValue: "Your own bodyweight — under full control.")
        case (.pushV, 4):      // Chest-to-wall handstand push-up
            return String(localized: "life.override.push_v-4",
                          defaultValue: "Your whole body above your hands — a rare level of control.")
        case (.pullBar, 4):    // Pull-up
            return String(localized: "life.override.pull_bar-4",
                          defaultValue: "Lifting your own bodyweight — the base for any physical task.")
        default:
            return nil
        }
    }
}
