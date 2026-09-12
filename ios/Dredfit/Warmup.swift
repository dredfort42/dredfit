//
//  The warm-up block as data: a pool of nine mobility moves, six of them per
//  session, 30 s each. No positions, no journal entry, no engine involvement.
//
//  §40.1 sent three movements here out of the strength ladders — Y-T-W,
//  bird-dog and the single-leg Romanian deadlift — because they are about
//  activation, coordination and balance rather than a dose that can be graded,
//  and inside a ladder each stood as a gap in the density.
//
//  Nine moves of 30 s DO NOT FIT the reserve of §37.7а: nine transitions plus
//  nine moves is 360 s against a `warmupMin` of 300, before any supplement. So
//  the block keeps its six slots and composes them from nine — exactly as the
//  cool-down has always composed six positions from a pool of nine (owner's
//  decision, 25.08.2026).
//
//  §41.12 then gave every move with a HALFWAY BOUNDARY the cool-down's counted
//  switch — the only thing that has ever moved this block's length. Four of the
//  nine have one: two are unilateral (single-leg RDL, bird dog) and two are
//  circles whose own steps say to reverse direction halfway (arm circles, hip
//  circles). A composition costs 228 s for its six slots and their transitions,
//  plus the 4 s trip down to the floor when it draws a floor move, plus 4 s per
//  split move: 240 to 244 with nothing set aside, and up to 248 once a move can
//  be (finding 49 widened the rotation's window, and a widened window draws all
//  four split moves — review 06.09.2026, which found `BlockReserveTests` still
//  walking the no-hiding overload and so pinning the wrong worst case).
//  These numbers are the EIGHT-second ones: the transition went 10 → 8 and its
//  supplement 5 → 4 on 06.09.2026, and this comment described the old pair for
//  one release because nothing here is derived — see `BlockReserveTests`, which
//  computes the same figures from the constants and is what actually fails.
//  `warmupMin` grew from 5 to 6 to pay for §41.12 — an ENGINE change, made
//  through the reference chain, because the pair of blocks had spent the old
//  reserve to the second.
//
//  Torso rotations and cat-cow are NOT split, and the distinction is the steps,
//  not the shape of the movement: both alternate continuously — every rep, every
//  breath — so there is no single moment to announce. A signal invented for them
//  would interrupt a movement rather than mark it.
//

import Foundation
import DredfitCore

/// What the two halves of a split warm-up move are.
///
/// The cool-down knows only `sides`, so it has no equivalent of this type: its
/// nine positions are stretches, and a stretch is either symmetrical or done
/// per side. The warm-up has circles.
enum WarmupHalves: Equatable { case sides, directions }

struct WarmupMove: Equatable, Identifiable {
    let id: String
    let name: String
    /// The move happens on the floor. Coming DOWN to the floor is what earns
    /// the supplement of issue #83 — moving between two floor positions does
    /// not — so the flag on the move says where it is, and the composition
    /// below decides who pays.
    let onFloor: Bool
    /// The move has a halfway boundary, and this says WHAT is switched at it
    /// (§41.12). nil is one continuous slot.
    ///
    /// A property of the movement, not of where it sits in the composition —
    /// and it decides the WORDS, never the seconds: sides and directions both
    /// run 15 + 5 + 15. "Switch sides" over a circle the person is about to
    /// reverse would be the same lie in the other direction as the silence
    /// this replaced.
    let halves: WarmupHalves?

    /// Two halves and a switch between them.
    var isSplit: Bool { halves != nil }
    /// The move changes the starting position or needs a prop, so its
    /// transition carries the supplement of issue #83. COMPUTED by the
    /// composition, never written by hand: with three floor moves in the pool,
    /// a per-move flag would charge the supplement up to three times and take
    /// the two blocks 10 s past a reserve that is already spent to the second.
    var needsSetup: Bool
    let steps: [String]
}

enum Warmup {

    static let moveSeconds = 30
    /// Six on screen, as always. The pool behind them is nine.
    static let moveCount = 6

    /// One 30 s slot split in half — a move with two sides or two directions
    /// does not get twice the time. The switch pause rides on TOP of the slot,
    /// exactly as it does in the cool-down (§41.12), which is what the minute
    /// `warmupMin` grew by was bought for.
    static var halfSeconds: Int { moveSeconds / 2 }

    /// The pause at the switch. `Cooldown.sideSwitchPauseSec`, not a number of
    /// its own: one beat, one length, and that constant is already shared with
    /// the workout's per-side holds.
    ///
    /// The RAW constant, not `Cooldown.switchPauseSeconds`: the warm-up's own
    /// lengths ignore `--uitest-fast` (`moveSeconds` does), and a pause that
    /// collapsed while the two halves it separates did not would give the
    /// block a shape under the flag that it never has in production.
    static var switchPauseSeconds: Int { Cooldown.sideSwitchPauseSec }

    // MARK: - The pool of nine

    /// In DISPLAY order: standing work first, floor work last, so a session
    /// goes down to the floor once and stays there.
    private static var pool: [WarmupMove] {
        [
            move(id: "marching", name: String(localized: "Marching in place"),
                 onFloor: false, halves: nil, steps: [
                String(localized: "warmup.marching.step1",
                       defaultValue: "March at an easy pace, lifting the knees to hip height."),
                String(localized: "warmup.marching.step2",
                       defaultValue: "Swing the arms freely and keep the shoulders relaxed."),
            ]),
            move(id: "arm-circles", name: String(localized: "Arm circles"),
                 onFloor: false, halves: .directions, steps: [
                String(localized: "warmup.armCircles.step1",
                       defaultValue: "Circle straight arms forward — big, slow circles."),
                String(localized: "warmup.armCircles.step2",
                       defaultValue: "Halfway through, switch direction and circle backward."),
            ]),
            move(id: "torso-rotations", name: String(localized: "Torso rotations"),
                 onFloor: false, halves: nil, steps: [
                String(localized: "warmup.torsoRotations.step1",
                       defaultValue: "Feet planted, hips facing forward; turn the torso side to side."),
                String(localized: "warmup.torsoRotations.step2",
                       defaultValue: "Let the arms swing loose — momentum, not force."),
            ]),
            move(id: "hip-circles", name: String(localized: "Hip circles"),
                 onFloor: false, halves: .directions, steps: [
                String(localized: "warmup.hipCircles.step1",
                       defaultValue: "Hands on the hips, feet shoulder-width; draw slow circles with the hips."),
                String(localized: "warmup.hipCircles.step2",
                       defaultValue: "Keep the knees soft and switch direction halfway."),
            ]),
            move(id: "half-squats", name: String(localized: "Half squats"),
                 onFloor: false, halves: nil, steps: [
                String(localized: "warmup.halfSquats.step1",
                       defaultValue: "Sit back to half depth, arms reaching forward for balance."),
                String(localized: "warmup.halfSquats.step2",
                       defaultValue: "Heels stay down; rise smoothly without locking the knees."),
            ]),
            // The three that came out of the ladders. Their names and steps
            // stay in the CORE catalog, where they already had six languages —
            // nothing was retranslated, only re-homed (§40.1).
            fromLibrary(WarmupTechnique.singleLegDeadlift, onFloor: false, halves: .sides),
            move(id: "cat-cow", name: String(localized: "Cat-cow"),
                 onFloor: true, halves: nil, steps: [
                String(localized: "warmup.catCow.step1",
                       defaultValue: "On all fours: exhale, round the back and tuck the chin."),
                String(localized: "warmup.catCow.step2",
                       defaultValue: "Inhale, arch gently and look slightly up — one slow wave per breath."),
            ]),
            fromLibrary(WarmupTechnique.birdDog, onFloor: true, halves: .sides),
            fromLibrary(WarmupTechnique.ytw, onFloor: true, halves: nil),
        ]
    }

    /// No default for `halves`, deliberately: an omitted argument would be a
    /// move running thirty seconds on one leg or in one direction, and that is
    /// exactly the silence §41.12 came to end. A compile error is a stronger
    /// guard than a grep (the rule `SetsHandle` keeps for the same reason).
    private static func move(id: String, name: String, onFloor: Bool,
                             halves: WarmupHalves?, steps: [String]) -> WarmupMove {
        WarmupMove(id: id, name: name, onFloor: onFloor, halves: halves,
                   needsSetup: false, steps: steps)
    }

    private static func fromLibrary(_ movement: WarmupMovement, onFloor: Bool,
                                    halves: WarmupHalves?) -> WarmupMove {
        WarmupMove(id: movement.id, name: movement.name, onFloor: onFloor,
                   halves: halves, needsSetup: false, steps: movement.steps)
    }

    /// Always in the block: the two that open it cold and the one that takes
    /// the spine through its range.
    ///
    /// "Permanent" is about the ROTATION, not about the athlete: since finding
    /// 49 a permanent move can be set aside like any other, and it then gives
    /// its slot to a rotating one rather than shortening the block.
    private static let permanentIDs: Set<String> = ["marching", "arm-circles", "cat-cow"]

    // MARK: - Composition

    /// The six moves of session `sessionNumber`, drawn from the pool of nine
    /// with `hidden` set aside.
    ///
    /// Three are fixed; the other three step through the remaining six by one
    /// per session, so each rotating move appears in three sessions out of six
    /// and the block never repeats itself two weeks running. Deterministic in
    /// the session number and the hidden set alone, which is what lets a
    /// restored snapshot recompute the same list instead of carrying it.
    ///
    /// Cat-cow used to fall in 100 % of sessions and the only way to say "not
    /// this one" was the same tap, every workout, forever — for a sore wrist
    /// that is the cost that makes people drop the whole block instead
    /// (UX review 05.09.2026, finding 49).
    static func moves(sessionNumber: Int, hiding hidden: Set<String>) -> [WarmupMove] {
        // `pool` is a computed property that builds nine localized moves, so
        // it is read ONCE here and everything below works off the array.
        let whole = pool
        let setAside = honoured(hidden, of: whole)
        let all = whole.filter { !setAside.contains($0.id) }
        let permanent = all.filter { permanentIDs.contains($0.id) }
        let rotating = all.filter { !permanentIDs.contains($0.id) }
        // A hidden permanent move widens the rotation's window instead of
        // leaving a hole: nine in the pool against six on screen is exactly
        // the slack `honoured` spends, so the block is always six.
        let slots = min(max(moveCount - permanent.count, 0), rotating.count)
        var chosen: Set<String> = []
        if slots > 0 {
            // Nonnegative modulo: a hand-edited session number can be
            // anything, and Swift's % is a remainder. `rotating` is non-empty
            // here — `slots > 0` cannot hold otherwise — but the guard is what
            // says so out loud, because a % 0 is a crash, not a wrong list.
            let start = ((sessionNumber - 1) % rotating.count + rotating.count) % rotating.count
            chosen = Set((0..<slots).map { rotating[(start + $0) % rotating.count].id })
        }
        var composed = all.filter { permanentIDs.contains($0.id) || chosen.contains($0.id) }
        // Only the FIRST floor move pays the supplement of issue #83: the trip
        // that changes the starting position is the trip down to the floor.
        // Charging it again between two floor positions would spend a reserve
        // the two blocks have already spent to the second.
        if let first = composed.firstIndex(where: { $0.onFloor }) {
            composed[first].needsSetup = true
        }
        return composed
    }

    /// The block's own rule with nothing set aside — what the pool composes
    /// before any athlete has said anything. The app never calls it.
    ///
    /// Nor does the reserve gate any more, except for the claims that are
    /// explicitly about "before anything was set aside": `BlockReserveTests`
    /// walked this overload for the WORST case and so measured a block the app
    /// cannot draw — 260 s against the 265 the widened window costs (review
    /// 06.09.2026). A convenience overload is a fine thing; a convenience
    /// overload that a gate reaches for is how the gate stops watching.
    static func moves(sessionNumber: Int) -> [WarmupMove] {
        moves(sessionNumber: sessionNumber, hiding: [])
    }

    /// As many of `hidden` as the block can afford, in pool order.
    ///
    /// The guarantee that a block never empties lives HERE and not in the
    /// settings that hold the list (finding 49): `AppStore.maxHiddenBlockMoves`
    /// caps what the control can add, but a state file written by an older
    /// build, an imported backup or a future cap must not be able to compose a
    /// warm-up of two moves — or of none, which would index out of bounds on
    /// the first screen. Six of nine are shown, so at most three can go.
    private static func honoured(_ hidden: Set<String>, of whole: [WarmupMove]) -> Set<String> {
        let affordable = max(whole.count - moveCount, 0)
        guard hidden.count > affordable else { return hidden }
        return Set(whole.map(\.id).filter(hidden.contains).prefix(affordable))
    }

    /// The composition of the session in front of the person — the block
    /// screens read this and nothing else.
    ///
    /// No default for `hiding`, deliberately, and for the reason `move(id:...)`
    /// below gives about `halves`: an omitted argument here is a control the
    /// athlete used that the block ignores, which is worse than not offering
    /// it. One caller, and a compile error is a stronger guard than a grep.
    static func moves(for session: Session, hiding hidden: Set<String>) -> [WarmupMove] {
        moves(sessionNumber: session.sessionNumber, hiding: hidden)
    }

    /// The name behind an id, for the sheet's list of what has been set aside:
    /// it holds ids and no moves. nil for an id from the cool-down's pool —
    /// one list covers both, and the caller asks both pools.
    static func name(ofMove id: String) -> String? {
        pool.first { $0.id == id }?.name
    }

    /// How many distinct compositions there are before they repeat. The
    /// reserve tests walk all of them: with a pool, "the block fits" is a
    /// claim about every session, not about one.
    static var compositionCount: Int { pool.count - permanentIDs.count }

    /// What the offer screen promises, DERIVED — a hand-typed 5 would go stale
    /// the first time a move is added or the composition changes. Rounded up:
    /// a promise the block overruns is worse than one it beats.
    static func introMinutes(_ moves: [WarmupMove]) -> Int {
        let seconds = moves.reduce(0) { total, move in
            total + stageSeconds(.getReady, of: move) + slotSeconds(of: move)
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }
}

// MARK: - The stage machine (issue #52)

extension Warmup {

    /// `.move` is the whole slot of a move with no halfway boundary; one that
    /// has a boundary runs `.firstHalf` → `.switchPause` → `.secondHalf`
    /// instead — 15 + 5 + 15, the cool-down's stages under the cool-down's
    /// rules (§41.12). Both open with `.getReady` (issue #52).
    ///
    /// HALF, not side, where the cool-down says `.firstSide`: half of this
    /// block's split moves switch a direction rather than a side, and a stage
    /// named for one of the two kinds would be wrong for the other every time
    /// it was read. The cool-down keeps its name because it only ever has
    /// sides.
    enum Stage { case getReady, move, firstHalf, switchPause, secondHalf }

    /// The transition's length depends on the move it announces (issue #83),
    /// so a stage alone no longer has one. The move is passed rather than an
    /// index for the same reason the cool-down passes its position: the list
    /// is composed per session, and an index into "the moves" no longer names
    /// anything on its own.
    static func stageSeconds(_ stage: Stage, of move: WarmupMove) -> Int {
        switch stage {
        case .getReady:               return GetReady.stageSeconds(needsSetup: move.needsSetup)
        case .move:                   return moveSeconds
        case .firstHalf, .secondHalf: return halfSeconds
        case .switchPause:            return switchPauseSeconds
        }
    }

    /// What the move itself takes, its transition excluded: the slot, plus the
    /// switch pause when it has two halves. ONE function rather than the
    /// formula spelled out at each caller — the offer screen, the reserve test
    /// and §41.12's arithmetic have to agree, and three copies of a formula
    /// agree only until one of them is edited.
    static func slotSeconds(of move: WarmupMove) -> Int {
        move.isSplit ? halfSeconds * 2 + switchPauseSeconds : moveSeconds
    }

    /// nil when the block is over.
    static func step(after step: (index: Int, stage: Stage),
                     moves: [WarmupMove]) -> (index: Int, stage: Stage)? {
        guard step.index < moves.count else { return nil }
        switch step.stage {
        case .getReady:
            return (step.index, moves[step.index].isSplit ? .firstHalf : .move)
        case .firstHalf:   return (step.index, .switchPause)
        case .switchPause: return (step.index, .secondHalf)
        case .move, .secondHalf:
            let next = step.index + 1
            guard next < moves.count else { return nil }
            return (next, .getReady)
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
    /// already covered are absorbed — a backgrounded warm-up must not stretch
    /// itself one move at a time. nil when the block is over, immediately or
    /// inside the overshoot.
    static func advance(from current: (index: Int, stage: Stage),
                        overshoot: Int,
                        moves: [WarmupMove]) -> Advance? {
        guard var landing = step(after: current, moves: moves) else { return nil }
        let entered = landing.stage
        var remainder = overshoot
        while remainder >= stageSeconds(landing.stage, of: moves[landing.index]) {
            remainder -= stageSeconds(landing.stage, of: moves[landing.index])
            guard let next = step(after: landing, moves: moves) else { return nil }
            landing = next
        }
        return Advance(entered: entered, index: landing.index, stage: landing.stage,
                       remaining: stageSeconds(landing.stage, of: moves[landing.index]) - remainder)
    }
}
