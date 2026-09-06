//
//  Six positions × 30 s plus their transitions. Composition is deterministic
//  from what was actually performed.
//
//  The header used to say "materialising the 3 minutes `cooldownMin` reserves
//  — so no estimate anywhere changes", and both halves had gone stale:
//  `cooldownMin` is 4 (it rose from 3 to pay for the 10-second transition),
//  while the block's own arithmetic is 270…295 s on EVERY composition, which
//  `cooldownIntroMinutes` rounds up to 5. The number is not restated here any
//  more, precisely because it moved twice without this line moving: what the
//  offer screen promises is derived, and the engine's reserve is the engine's
//  (see `GetReady.setupSupplementSec` for how it is spent).
//
//  No levels, no journal entry, no engine involvement.
//

import Foundation
import DredfitCore

struct CooldownPosition: Equatable, Identifiable {
    let id: String
    let name: String
    /// One 30 s slot split into 15 s per side — a per-side position does not
    /// get twice the time. The side-switch pause rides on top of the slot.
    let perSide: Bool
    /// The position starts on the floor or at a wall, so its transition
    /// carries the supplement of issue #83. The flag travels with the
    /// position, not the index — the set is composed per session. Only
    /// forward fold, the lat stretch and the wrists stay standing.
    let needsSetup: Bool
    let steps: [String]
}

enum Cooldown {

    static let positionSeconds = 30
    static let positionCount = 6

    /// The re-set pause between sides of timed unilateral work (issue #35).
    /// One app-layer constant shared by the cool-down and the workout's
    /// per-side holds — changing it moves both.
    ///
    /// 5 → 4 ON TRIAL (owner, 06.09.2026), alongside the transition going
    /// 10 → 8: turning over inside one position is not travel to another, and
    /// four seconds may be enough for it. Written down as a trial because it
    /// is meant to be judged in use and rolled back if it turns out to rush —
    /// the revert is this one line, and the arithmetic that depends on it is
    /// derived rather than restated (`BlockReserveTests`, `GetReadyTests`).
    ///
    /// It costs nothing at the reserve: shortening only ever leaves slack, and
    /// the pause carries no 3-2-1 to collide with (a tick would bury the
    /// switch tone — `tickHoldSwitchPause`).
    static let sideSwitchPauseSec = 4

    static var sideSeconds: Int { positionSeconds / 2 }

    // MARK: - The pool of nine

    private static var hipFlexors: CooldownPosition {
        CooldownPosition(id: "hip-flexors",
                         name: String(localized: "cooldown.hipFlexors",
                                      defaultValue: "Hip flexor stretch"),
                         perSide: true,
                         needsSetup: true,
                         steps: [
                             String(localized: "cooldown.hipFlexors.step1",
                                    defaultValue: "Kneel on one knee, the other foot planted in front."),
                             String(localized: "cooldown.hipFlexors.step2",
                                    defaultValue: "Tuck the pelvis and shift it slightly forward until the front of the hip stretches."),
                             String(localized: "cooldown.hipFlexors.step3",
                                    defaultValue: "Hold steady and breathe — no bouncing."),
                         ])
    }
    private static var chestWall: CooldownPosition {
        CooldownPosition(id: "chest-wall",
                         name: String(localized: "cooldown.chestWall",
                                      defaultValue: "Chest and shoulders at the wall"),
                         perSide: true,
                         needsSetup: true,
                         steps: [
                             String(localized: "cooldown.chestWall.step1",
                                    defaultValue: "Forearm on the wall, elbow at shoulder height."),
                             String(localized: "cooldown.chestWall.step2",
                                    defaultValue: "Turn the chest away from the wall until the front of the shoulder stretches."),
                             String(localized: "cooldown.chestWall.step3",
                                    defaultValue: "Keep the shoulder down, away from the ear — turn to a stretch, not into pain."),
                         ])
    }
    private static var restPose: CooldownPosition {
        CooldownPosition(id: "rest-pose",
                         name: String(localized: "cooldown.restPose",
                                      defaultValue: "Rest pose"),
                         perSide: false,
                         needsSetup: true,
                         steps: [
                             String(localized: "cooldown.restPose.step1",
                                    defaultValue: "Knees on the floor, sit back onto the heels."),
                             String(localized: "cooldown.restPose.step2",
                                    defaultValue: "Fold forward, arms stretched ahead, forehead down."),
                             String(localized: "cooldown.restPose.step3",
                                    defaultValue: "Breathe slowly, sending the breath into the back."),
                         ])
    }
    private static var forwardFold: CooldownPosition {
        CooldownPosition(id: "forward-fold",
                         name: String(localized: "cooldown.forwardFold",
                                      defaultValue: "Forward fold"),
                         perSide: false,
                         needsSetup: false,
                         steps: [
                             String(localized: "cooldown.forwardFold.step1",
                                    defaultValue: "Feet hip-width; fold forward from the hips, knees soft."),
                             String(localized: "cooldown.forwardFold.step2",
                                    defaultValue: "Let the head and arms hang heavy — no reaching for the floor."),
                             String(localized: "cooldown.forwardFold.step3",
                                    defaultValue: "To come up, unroll the spine slowly, one vertebra at a time."),
                         ])
    }
    private static var latStretch: CooldownPosition {
        CooldownPosition(id: "lat-stretch",
                         name: String(localized: "cooldown.latStretch",
                                      defaultValue: "Lat stretch with support"),
                         perSide: false,
                         needsSetup: false,
                         steps: [
                             String(localized: "cooldown.latStretch.step1",
                                    defaultValue: "Hold a support at hip height with both hands, feet under the hips."),
                             String(localized: "cooldown.latStretch.step2",
                                    defaultValue: "Sit the hips back on straight arms until the sides of the back stretch."),
                             String(localized: "cooldown.latStretch.step3",
                                    defaultValue: "Keep the head between the arms and breathe."),
                         ])
    }
    private static var wrists: CooldownPosition {
        CooldownPosition(id: "wrists",
                         name: String(localized: "cooldown.wrists",
                                      defaultValue: "Wrists and forearms"),
                         perSide: true,
                         needsSetup: false,
                         steps: [
                             String(localized: "cooldown.wrists.step1",
                                    defaultValue: "Arm straight, palm down; gently pull the fingers down and toward you."),
                             String(localized: "cooldown.wrists.step2",
                                    defaultValue: "Then turn the palm up and repeat the gentle pull."),
                             String(localized: "cooldown.wrists.step3",
                                    defaultValue: "Pull only to a stretch — ease off at anything sharp or tingling."),
                         ])
    }
    private static var lyingTwist: CooldownPosition {
        CooldownPosition(id: "lying-twist",
                         name: String(localized: "cooldown.lyingTwist",
                                      defaultValue: "Lying twist"),
                         perSide: true,
                         needsSetup: true,
                         steps: [
                             String(localized: "cooldown.lyingTwist.step1",
                                    defaultValue: "On your back, knees bent; drop both knees to one side."),
                             String(localized: "cooldown.lyingTwist.step2",
                                    defaultValue: "Shoulders stay on the floor, head turns the other way."),
                             String(localized: "cooldown.lyingTwist.step3",
                                    defaultValue: "Let the weight sink on its own — don't push the knees down."),
                         ])
    }
    private static var calfWall: CooldownPosition {
        CooldownPosition(id: "calf-wall",
                         name: String(localized: "cooldown.calfWall",
                                      defaultValue: "Calf stretch at the wall"),
                         perSide: true,
                         needsSetup: true,
                         steps: [
                             String(localized: "cooldown.calfWall.step1",
                                    defaultValue: "Hands on the wall, one leg stepped back, heel on the floor."),
                             String(localized: "cooldown.calfWall.step2",
                                    defaultValue: "Back knee straight; lean toward the wall until the calf stretches."),
                             String(localized: "cooldown.calfWall.step3",
                                    defaultValue: "Keep the heel down — no bouncing."),
                         ])
    }
    private static var seatedGlute: CooldownPosition {
        CooldownPosition(id: "seated-glute",
                         name: String(localized: "cooldown.seatedGlute",
                                      defaultValue: "Seated glute stretch"),
                         perSide: true,
                         needsSetup: true,
                         steps: [
                             String(localized: "cooldown.seatedGlute.step1",
                                    defaultValue: "Sit tall; place one ankle over the opposite knee."),
                             String(localized: "cooldown.seatedGlute.step2",
                                    defaultValue: "Lean forward from the hips with a straight back until the glute stretches."),
                             String(localized: "cooldown.seatedGlute.step3",
                                    defaultValue: "The knee falls open on its own — don't press it down."),
                         ])
    }

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

    /// Top-up order when the session's movements map to fewer than three
    /// distinct positions. A session with several movements skipped gets
    /// there — only what was performed is mapped — and so does one whose
    /// movements share a position: squat and hinge both fold forward, the two
    /// pushes both land on the wrists, and both core patterns twist.
    private static var mappedPool: [CooldownPosition] {
        [forwardFold, latStretch, wrists, lyingTwist, calfWall, seatedGlute]
    }

    // MARK: - Composition

    /// The whole pool of nine, in no particular order — for `honoured` below
    /// and for the sheet's name lookup. `mappedPool` is the six that a
    /// movement can point at; these three are the fixed frame around them.
    private static var wholePool: [CooldownPosition] {
        [hipFlexors, chestWall, restPose] + mappedPool
    }

    /// Two fixed positions, three from the session's movements (session
    /// order, deduplicated, topped up from the pool), rest pose last —
    /// minus anything in `hidden`.
    ///
    /// A hidden FIXED position does not leave a hole: the middle grows into
    /// its slot, so the block is six either way (UX review 05.09.2026, finding
    /// 49 — "Chest and shoulders at the wall" stood second in every single
    /// cool-down, and someone with no free wall had no way to say so once).
    /// With nothing hidden the arithmetic below is the old one exactly: two
    /// fixed, three mapped, rest pose.
    ///
    /// Empty input returns an empty cool-down — the flow skips the block.
    static func positions(performed: [Pattern],
                          hiding hidden: Set<String>) -> [CooldownPosition] {
        guard !performed.isEmpty else { return [] }
        let setAside = honoured(hidden)

        let opening = [hipFlexors, chestWall].filter { !setAside.contains($0.id) }
        let closing = [restPose].filter { !setAside.contains($0.id) }
        let middleCount = max(positionCount - opening.count - closing.count, 0)

        var mapped: [CooldownPosition] = []
        for pattern in performed where mapped.count < middleCount {
            let candidate = position(for: pattern)
            guard !setAside.contains(candidate.id), !mapped.contains(candidate) else { continue }
            mapped.append(candidate)
        }
        for candidate in mappedPool where mapped.count < middleCount {
            guard !setAside.contains(candidate.id), !mapped.contains(candidate) else { continue }
            mapped.append(candidate)
        }

        return opening + mapped + closing
    }

    /// The block's own rule with nothing set aside. The app never calls it, and
    /// the reserve gate calls it only where the claim IS about the block before
    /// anything was set aside — see `Warmup.moves(sessionNumber:)` for what
    /// walking it as if it were the shipped rule cost (review 06.09.2026).
    static func positions(performed: [Pattern]) -> [CooldownPosition] {
        positions(performed: performed, hiding: [])
    }

    /// As many of `hidden` as the block can afford, in pool order — the twin
    /// of `Warmup.honoured` and for the same reason: the guarantee that a
    /// block never empties belongs to the composer, not to the settings that
    /// hold the list. Nine in the pool against six on screen, so three.
    private static func honoured(_ hidden: Set<String>) -> Set<String> {
        let whole = wholePool
        let affordable = max(whole.count - positionCount, 0)
        guard hidden.count > affordable else { return hidden }
        return Set(whole.map(\.id).filter(hidden.contains).prefix(affordable))
    }

    /// The name behind an id — see `Warmup.name(ofMove:)`. nil for an id from
    /// the warm-up's pool.
    static func name(ofPosition id: String) -> String? {
        wholePool.first { $0.id == id }?.name
    }

    // MARK: - The stage machine (issue #35)

    /// A bilateral position runs `.single`; a per-side one runs `.firstSide`
    /// → `.switchPause` → `.secondSide` — 15 + 5 + 15. Both open with
    /// `.getReady` (issue #52).
    enum Stage { case getReady, single, firstSide, switchPause, secondSide }

    /// The transition's length depends on the position it announces (issue
    /// #83), so a stage alone no longer has one.
    static func stageSeconds(_ stage: Stage, of position: CooldownPosition) -> Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        switch stage {
        case .getReady:               return GetReady.stageSeconds(needsSetup: position.needsSetup)
        case .single:                 return positionSeconds
        case .firstSide, .secondSide: return sideSeconds
        case .switchPause:            return sideSwitchPauseSec
        }
    }

    /// The workout's per-side holds play the same pause with no position
    /// attached — and collapse under --uitest-fast with everything else.
    static var switchPauseSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        return sideSwitchPauseSec
    }

    static let openingStage = Stage.getReady

    /// nil when the block is over.
    static func step(after step: (index: Int, stage: Stage),
                     positions: [CooldownPosition]) -> (index: Int, stage: Stage)? {
        guard step.index < positions.count else { return nil }
        switch step.stage {
        case .getReady:    return (step.index, positions[step.index].perSide ? .firstSide : .single)
        case .firstSide:   return (step.index, .switchPause)
        case .switchPause: return (step.index, .secondSide)
        case .single, .secondSide:
            let next = step.index + 1
            guard next < positions.count else { return nil }
            return (next, openingStage)
        }
    }

    /// `entered` names the stage the audible boundary opened; index/stage/
    /// remaining are where the countdown landed. A long absence crosses
    /// several boundaries, so the two can disagree — callers choosing a
    /// signal must read both.
    struct Advance {
        let entered: Stage
        let index: Int
        let stage: Stage
        let remaining: Int
    }

    /// Whole stages a long absence (`overshoot` seconds past the boundary)
    /// already covered are absorbed. nil when the block is over — immediately
    /// or inside the overshoot.
    static func advance(from current: (index: Int, stage: Stage),
                        overshoot: Int,
                        positions: [CooldownPosition]) -> Advance? {
        guard var landing = step(after: current, positions: positions) else { return nil }
        let entered = landing.stage
        var remainder = overshoot
        while remainder >= stageSeconds(landing.stage, of: positions[landing.index]) {
            remainder -= stageSeconds(landing.stage, of: positions[landing.index])
            guard let next = step(after: landing, positions: positions) else { return nil }
            landing = next
        }
        return Advance(entered: entered, index: landing.index, stage: landing.stage,
                       remaining: stageSeconds(landing.stage, of: positions[landing.index]) - remainder)
    }
}
