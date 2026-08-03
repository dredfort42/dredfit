//
//  Warmup.swift
//  Dredfit
//
//  The warm-up block as data: six universal mobility moves, 30 s each —
//  ~3 minutes before the first exercise. Extracted from WorkoutFlowView
//  when the moves gained technique steps (issue #34): the flow file walks
//  the block, this file knows what the block is.
//
//  No levels, no journal entry, no engine involvement — same as ever.
//

import Foundation

struct WarmupMove: Equatable, Identifiable {
    let id: String
    let name: String
    /// 2–3 numbered lines for the mini technique sheet (issue #34) — how
    /// to do the move, in the same voice as the exercise library.
    let steps: [String]
}

enum Warmup {

    static let moveSeconds = 30

    static var moves: [WarmupMove] {
        [
            WarmupMove(
                id: "marching",
                name: String(localized: "Marching in place"),
                steps: [
                    String(localized: "warmup.marching.step1",
                           defaultValue: "March at an easy pace, lifting the knees to hip height."),
                    String(localized: "warmup.marching.step2",
                           defaultValue: "Swing the arms freely and keep the shoulders relaxed."),
                ]),
            WarmupMove(
                id: "arm-circles",
                name: String(localized: "Arm circles"),
                steps: [
                    String(localized: "warmup.armCircles.step1",
                           defaultValue: "Circle straight arms forward — big, slow circles."),
                    String(localized: "warmup.armCircles.step2",
                           defaultValue: "Halfway through, switch direction and circle backward."),
                ]),
            WarmupMove(
                id: "torso-rotations",
                name: String(localized: "Torso rotations"),
                steps: [
                    String(localized: "warmup.torsoRotations.step1",
                           defaultValue: "Feet planted, hips facing forward; turn the torso side to side."),
                    String(localized: "warmup.torsoRotations.step2",
                           defaultValue: "Let the arms swing loose — momentum, not force."),
                ]),
            WarmupMove(
                id: "hip-circles",
                name: String(localized: "Hip circles"),
                steps: [
                    String(localized: "warmup.hipCircles.step1",
                           defaultValue: "Hands on the hips, feet shoulder-width; draw slow circles with the hips."),
                    String(localized: "warmup.hipCircles.step2",
                           defaultValue: "Keep the knees soft and switch direction halfway."),
                ]),
            WarmupMove(
                id: "half-squats",
                name: String(localized: "Half squats"),
                steps: [
                    String(localized: "warmup.halfSquats.step1",
                           defaultValue: "Sit back to half depth, arms reaching forward for balance."),
                    String(localized: "warmup.halfSquats.step2",
                           defaultValue: "Heels stay down; rise smoothly without locking the knees."),
                ]),
            WarmupMove(
                id: "cat-cow",
                name: String(localized: "Cat-cow"),
                steps: [
                    String(localized: "warmup.catCow.step1",
                           defaultValue: "On all fours: exhale, round the back and tuck the chin."),
                    String(localized: "warmup.catCow.step2",
                           defaultValue: "Inhale, arch gently and look slightly up — one slow wave per breath."),
                ]),
        ]
    }
}

// MARK: - The stage machine (issue #52)

extension Warmup {

    /// Where inside a move the countdown is: the "Get ready" transition, then
    /// the move itself. The same shape as the cool-down's stage machine — the
    /// block that opens a workout and the block that closes it now walk their
    /// positions the same way.
    enum Stage { case getReady, move }

    static func stageSeconds(_ stage: Stage) -> Int {
        switch stage {
        case .getReady: return GetReady.stageSeconds
        case .move:     return moveSeconds
        }
    }

    /// The stage after the given one — into the move within a position,
    /// otherwise on to the next position's transition. nil when the block
    /// is over.
    static func step(after step: (index: Int, stage: Stage)) -> (index: Int, stage: Stage)? {
        switch step.stage {
        case .getReady:
            return (step.index, .move)
        case .move:
            let next = step.index + 1
            guard next < moves.count else { return nil }
            return (next, .getReady)
        }
    }

    /// Where a finished stage lands: `entered` names the stage the audible
    /// boundary opened — a transition opens silently, everything else is the
    /// usual go — while index/stage/remaining are the countdown's new
    /// position, after any backgrounded time has been absorbed.
    struct Advance {
        let entered: Stage
        let index: Int
        let stage: Stage
        let remaining: Int
    }

    /// A stage ran out. Whole stages a long absence (`overshoot` seconds past
    /// the boundary) already covered are absorbed silently — a backgrounded
    /// warm-up must not stretch itself one move at a time. nil when the block
    /// is over, immediately or inside the overshoot.
    static func advance(from current: (index: Int, stage: Stage),
                        overshoot: Int) -> Advance? {
        guard var landing = step(after: current) else { return nil }
        let entered = landing.stage
        var remainder = overshoot
        while remainder >= stageSeconds(landing.stage) {
            remainder -= stageSeconds(landing.stage)
            guard let next = step(after: landing) else { return nil }
            landing = next
        }
        return Advance(entered: entered, index: landing.index, stage: landing.stage,
                       remaining: stageSeconds(landing.stage) - remainder)
    }
}
