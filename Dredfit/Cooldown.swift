//
//  Cooldown.swift
//  Dredfit
//
//  The cool-down (issue #28): the engine's duration estimate has reserved
//  3 minutes for it since 1.0 (`cooldownMin`) — the block was promised but
//  never existed. Six positions × 30 s materialise exactly those minutes,
//  so no estimate anywhere changes.
//
//  Composition is deterministic from what was actually performed: three
//  fixed positions (hip flexors, chest and shoulders, and the rest pose —
//  always last) plus three chosen by the session's movements from a pool of
//  nine. Same input, same cool-down — reproducible from the screen alone,
//  like everything else in the app.
//
//  No levels, no journal entry, no engine involvement: skipping a position
//  or the whole block costs nothing and is recorded nowhere.
//

import Foundation
import DredfitCore

struct CooldownPosition: Equatable, Identifiable {
    let id: String
    let name: String
    /// One 30 s slot split into 15 s per side — a per-side position does
    /// not get twice the time. The side-switch pause (issue #35) rides on
    /// top of the slot: 15 + 5 + 15, counted by the app, not the user.
    let perSide: Bool
}

enum Cooldown {

    static let positionSeconds = 30
    static let positionCount = 6

    /// The re-set pause between sides of timed unilateral work (issue #35):
    /// getting out of one side and into the other is not instant, and
    /// without a pause the transition silently eats into the second side.
    /// One app-layer constant shared by the cool-down and the workout's
    /// per-side holds — deliberately not a user setting. The pause rides on
    /// top of the reserved minutes, within the "≈" every estimate carries.
    static let sideSwitchPauseSec = 5

    /// One side of a per-side position: half the 30 s slot, per the
    /// "15 s per side" hint the position has always shown.
    static var sideSeconds: Int { positionSeconds / 2 }

    // MARK: - The pool of nine

    private static var hipFlexors: CooldownPosition {
        CooldownPosition(id: "hip-flexors",
                         name: String(localized: "cooldown.hipFlexors",
                                      defaultValue: "Hip flexor stretch"),
                         perSide: true)
    }
    private static var chestWall: CooldownPosition {
        CooldownPosition(id: "chest-wall",
                         name: String(localized: "cooldown.chestWall",
                                      defaultValue: "Chest and shoulders at the wall"),
                         perSide: false)
    }
    private static var restPose: CooldownPosition {
        CooldownPosition(id: "rest-pose",
                         name: String(localized: "cooldown.restPose",
                                      defaultValue: "Rest pose"),
                         perSide: false)
    }
    private static var forwardFold: CooldownPosition {
        CooldownPosition(id: "forward-fold",
                         name: String(localized: "cooldown.forwardFold",
                                      defaultValue: "Forward fold"),
                         perSide: false)
    }
    private static var latStretch: CooldownPosition {
        CooldownPosition(id: "lat-stretch",
                         name: String(localized: "cooldown.latStretch",
                                      defaultValue: "Lat stretch with support"),
                         perSide: false)
    }
    private static var wrists: CooldownPosition {
        CooldownPosition(id: "wrists",
                         name: String(localized: "cooldown.wrists",
                                      defaultValue: "Wrists and forearms"),
                         perSide: false)
    }
    private static var lyingTwist: CooldownPosition {
        CooldownPosition(id: "lying-twist",
                         name: String(localized: "cooldown.lyingTwist",
                                      defaultValue: "Lying twist"),
                         perSide: true)
    }
    private static var calfWall: CooldownPosition {
        CooldownPosition(id: "calf-wall",
                         name: String(localized: "cooldown.calfWall",
                                      defaultValue: "Calf stretch at the wall"),
                         perSide: true)
    }
    private static var seatedGlute: CooldownPosition {
        CooldownPosition(id: "seated-glute",
                         name: String(localized: "cooldown.seatedGlute",
                                      defaultValue: "Seated glute stretch"),
                         perSide: true)
    }

    /// The movement → position mapping (spec §4). Two patterns can share a
    /// position — the composition deduplicates, it never repeats a stretch.
    private static func position(for pattern: Pattern) -> CooldownPosition {
        switch pattern {
        case .squat, .hinge:            return forwardFold
        case .pull, .pullBar:           return latStretch
        case .pushH, .pushV:            return wrists
        case .coreAntiExt, .coreRot:    return lyingTwist
        case .calf:                     return calfWall
        case .lunge:                    return seatedGlute
        }
    }

    /// The order used to top up when the session's own movements map to
    /// fewer than three distinct positions (a short workout can).
    private static var mappedPool: [CooldownPosition] {
        [forwardFold, latStretch, wrists, lyingTwist, calfWall, seatedGlute]
    }

    // MARK: - Composition

    /// Six positions for what was actually performed, in the order they run:
    /// two fixed, three from the session's movements (session order,
    /// deduplicated, topped up from the pool), and the rest pose last.
    ///
    /// Empty input returns an empty cool-down: a workout where nothing was
    /// performed has nothing to stretch, and the flow skips the block.
    static func positions(performed: [Pattern]) -> [CooldownPosition] {
        guard !performed.isEmpty else { return [] }

        var mapped: [CooldownPosition] = []
        for pattern in performed {
            let candidate = position(for: pattern)
            if !mapped.contains(candidate) { mapped.append(candidate) }
            if mapped.count == 3 { break }
        }
        for candidate in mappedPool where mapped.count < 3 {
            if !mapped.contains(candidate) { mapped.append(candidate) }
        }

        return [hipFlexors, chestWall] + mapped + [restPose]
    }
}
