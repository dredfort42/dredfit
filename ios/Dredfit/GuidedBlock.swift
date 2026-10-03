//
//  The warm-up and the cool-down run the same machine: each position is
//  announced by a transition, then held whole or in two halves with a switch
//  between them, all on one clock. One engine for both, so a rule cannot live
//  in one block and be missing from the other.
//

import Foundation

/// The two guided blocks of a workout.
enum GuidedBlock {
    case warmup, cooldown
}

/// What a guided block's stage machine reads off a position.
protocol GuidedPosition {
    var id: String { get }
    var name: String { get }
    /// The transition into it pays the setup supplement (issue #83).
    var needsSetup: Bool { get }
    /// nil for a position held whole; otherwise what its two halves are.
    var halves: WarmupHalves? { get }
}

extension WarmupMove: GuidedPosition {}

extension CooldownPosition: GuidedPosition {
    /// A stretch has two halves only when it is held on each side in turn.
    var halves: WarmupHalves? { perSide ? .sides : nil }
}

/// Every position opens with `.getReady` (issue #52). One held whole runs
/// `.whole`; one with a halfway boundary runs `.firstHalf` → `.switchPause`
/// → `.secondHalf` — 15 + 4 + 15 (§41.12).
///
/// HALF, not side: half of the warm-up's split moves switch a direction
/// rather than a side, and a stage named for one of the two kinds would be
/// wrong for the other every time it was read.
enum GuidedStage { case getReady, whole, firstHalf, switchPause, secondHalf }

/// Where a block stands: which position, which stage of it, and the clock.
struct GuidedBlockRun: Equatable {
    var index = 0
    var stage: GuidedStage = .getReady
    var clock = Countdown()
}

extension GuidedBlock {

    /// The transition's length depends on the position it announces (issue
    /// #83), so a stage alone has none. The position is passed rather than an
    /// index: the list is composed per session, and an index into it names
    /// nothing on its own.
    func stageSeconds(_ stage: GuidedStage, of position: any GuidedPosition) -> Int {
        #if DEBUG
        // --uitest-fast collapses every stage of the cool-down; the warm-up
        // keeps its lengths and only its transitions collapse (`GetReady`).
        if self == .cooldown, CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        switch stage {
        case .getReady:
            return GetReady.stageSeconds(needsSetup: position.needsSetup)
        case .whole:
            return self == .warmup ? Warmup.moveSeconds : Cooldown.positionSeconds
        case .firstHalf, .secondHalf:
            return self == .warmup ? Warmup.halfSeconds : Cooldown.sideSeconds
        case .switchPause:
            return self == .warmup ? Warmup.switchPauseSeconds : Cooldown.sideSwitchPauseSec
        }
    }

    /// The stage after `step`; nil when the block is over.
    static func step(after step: (index: Int, stage: GuidedStage),
                     positions: [any GuidedPosition]) -> (index: Int, stage: GuidedStage)? {
        guard step.index < positions.count else { return nil }
        switch step.stage {
        case .getReady:
            return (step.index, positions[step.index].halves == nil ? .whole : .firstHalf)
        case .firstHalf:   return (step.index, .switchPause)
        case .switchPause: return (step.index, .secondHalf)
        case .whole, .secondHalf:
            let next = step.index + 1
            guard next < positions.count else { return nil }
            return (next, .getReady)
        }
    }

    /// `entered` names the stage the audible boundary opened; index/stage/
    /// remaining are where the countdown landed. A long absence crosses
    /// several boundaries, so the two can disagree — callers choosing a
    /// signal must read both.
    struct Advance {
        let entered: GuidedStage
        let index: Int
        let stage: GuidedStage
        let remaining: Int
    }

    /// Whole stages an overshoot of `overshoot` seconds past the boundary
    /// already covered are absorbed — a block must not stretch itself one
    /// position at a time. nil when the block is over, immediately or inside
    /// the overshoot.
    func advance(from current: (index: Int, stage: GuidedStage),
                 overshoot: Int,
                 positions: [any GuidedPosition]) -> Advance? {
        guard var landing = Self.step(after: current, positions: positions) else { return nil }
        let entered = landing.stage
        var remainder = overshoot
        while remainder >= stageSeconds(landing.stage, of: positions[landing.index]) {
            remainder -= stageSeconds(landing.stage, of: positions[landing.index])
            guard let next = Self.step(after: landing, positions: positions) else { return nil }
            landing = next
        }
        return Advance(entered: entered, index: landing.index, stage: landing.stage,
                       remaining: stageSeconds(landing.stage, of: positions[landing.index]) - remainder)
    }
}
