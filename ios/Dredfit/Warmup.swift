//
//  The warm-up block as data: a pool of fourteen standing moves, six of them
//  per session, 30 s each. No positions, no journal entry, no engine
//  involvement.
//
//  EVERY MOVE IS STANDING, and none of them is strength work. A warm-up
//  raises the temperature and takes the joints through the range the work
//  will use. A trip to the floor, a balance, an isometric hold or a change of
//  position every few moves asks more than that, and pays for it in
//  transition time — so the movements that are about activation or balance
//  rather than a dose (Y-T-W, the bird dog, the single-leg Romanian deadlift,
//  all off the strength ladders) have no place here either.
//
//  Six SLOTS, each drawn from its own group: two to raise the pulse (marching
//  always opens), two for the shoulders and arms, one for the trunk, and a
//  last one chosen by the session's FIRST exercise — half squats before a
//  squat, hip hinges before a hinge. One rotation window over one list keeps
//  a composition balanced only while the list's order is intact, and a move
//  set aside breaks the order; a group per slot cannot lose one.
//
//  A circle REVERSES halfway, and the clock does not stop for it: a tone marks
//  the midpoint and the second half runs straight on. A side switch that
//  re-sets the body — changing the front leg of a lunge — keeps its pause;
//  reversing a circle does not, and a pause there would stop a movement for
//  nothing.
//
//  Every slot therefore costs the same, the transition plus thirty seconds,
//  and every composition 228 s. Nothing here is derived: `BlockReserveTests`
//  computes the same figure from the constants and is what actually fails.
//  The engine's reserve (`warmupMin`) holds that with slack to spare: a
//  shorter block never overruns it.
//
//  Moves that alternate continuously — side steps, torso rotations, side
//  bends, overhead reaches — are NOT split, and the distinction is the steps,
//  not the shape of the movement: they change side every rep, so there is no
//  single moment to announce. A signal invented for them would interrupt a
//  movement rather than mark it.
//

import Foundation
import DredfitCore

/// What the two halves of a split position are.
///
/// The warm-up's split moves all reverse a DIRECTION; sides belong to the
/// cool-down's per-side stretches and the work screen's per-side holds, which
/// share the type through `GuidedPosition`.
enum WarmupHalves: Equatable {
    /// A side switch that re-sets the body — the front leg of a kneeling lunge
    /// changed, the feet stepped over.
    case sides
    /// A side switch made where the body already is: the other wrist, the
    /// knees dropped the other way, the hands walked to the other side.
    case sidesOnTheSpot
    case directions

    /// Whether the switch between the halves stops the clock. A re-set gets
    /// the pause (`Cooldown.sideSwitchPauseSec`); a switch on the spot and a
    /// circle reversing on the move do not — a pause there would stop a
    /// movement for nothing, and the tone alone marks the half.
    var pausesAtTheSwitch: Bool {
        switch self {
        case .sides:                       return true
        case .sidesOnTheSpot, .directions: return false
        }
    }
}

struct WarmupMove: Equatable, Identifiable {
    let id: String
    let name: String
    /// The move reverses direction halfway — a circle whose steps say so.
    ///
    /// A property of the movement, not of where it sits in the composition —
    /// and it decides the WORDS and the tone, never the seconds: the two
    /// halves are the 30 s slot with nothing between them.
    let reverses: Bool
    let steps: [String]

    /// Two halves with the switch between them, or one continuous slot.
    var halves: WarmupHalves? { reverses ? .directions : nil }

    /// Every move is standing, so no transition is a trip to the floor or to
    /// a wall: the supplement of issue #83 is never paid in this block.
    var needsSetup: Bool { false }
}

enum Warmup {

    static let moveSeconds = 30
    /// Six on screen. The pool behind them is fourteen.
    static let moveCount = 6

    /// One 30 s slot split in half — a reversed circle does not get twice the
    /// time, and with no pause between them the two halves ARE the slot.
    static var halfSeconds: Int { moveSeconds / 2 }

    // MARK: - The pool of fourteen

    /// In DISPLAY order, group by group, with the two lead-in-only moves last.
    private static var pool: [WarmupMove] {
        [
            // Raise the pulse.
            move(id: "marching", name: String(localized: "Marching in place"),
                 reverses: false, steps: [
                String(localized: "warmup.marching.step1",
                       defaultValue: "March at an easy pace, lifting the knees to hip height."),
                String(localized: "warmup.marching.step2",
                       defaultValue: "Swing the arms freely and keep the shoulders relaxed."),
            ]),
            move(id: "side-steps", name: String(localized: "Side steps"),
                 reverses: false, steps: [
                String(localized: "warmup.sideSteps.step1",
                       defaultValue: "Step one foot out to the side as both arms swing up overhead."),
                String(localized: "warmup.sideSteps.step2",
                       defaultValue: "Bring the feet together as the arms come down, then step to the other side — no jumping."),
            ]),
            move(id: "heels-to-glutes", name: String(localized: "Heels to glutes"),
                 reverses: false, steps: [
                String(localized: "warmup.heelsToGlutes.step1",
                       defaultValue: "Walk in place, bringing each heel up toward the glutes."),
                String(localized: "warmup.heelsToGlutes.step2",
                       defaultValue: "Stay light on the balls of the feet — no jumping, no hurry."),
            ]),
            // Shoulders and arms.
            move(id: "arm-circles", name: String(localized: "Arm circles"),
                 reverses: true, steps: [
                String(localized: "warmup.armCircles.step1",
                       defaultValue: "Circle straight arms forward — big, slow circles."),
                String(localized: "warmup.armCircles.step2",
                       defaultValue: "Halfway through, switch direction and circle backward."),
            ]),
            move(id: "arm-swings", name: String(localized: "Arm swings"),
                 reverses: false, steps: [
                String(localized: "warmup.armSwings.step1",
                       defaultValue: "Open the arms wide at chest height, then swing them in to hug yourself."),
                String(localized: "warmup.armSwings.step2",
                       defaultValue: "Keep it loose; switch which arm crosses on top each time."),
            ]),
            move(id: "reach-and-pull", name: String(localized: "Reach and pull back"),
                 reverses: false, steps: [
                String(localized: "warmup.reachPull.step1",
                       defaultValue: "Reach both arms forward at shoulder height, letting the shoulder blades spread."),
                String(localized: "warmup.reachPull.step2",
                       defaultValue: "Pull the elbows back past the ribs and squeeze the shoulder blades together."),
            ]),
            move(id: "wrist-circles", name: String(localized: "Wrist circles"),
                 reverses: true, steps: [
                String(localized: "warmup.wristCircles.step1",
                       defaultValue: "Make loose fists and circle the wrists slowly, elbows still."),
                String(localized: "warmup.wristCircles.step2",
                       defaultValue: "Halfway through, switch direction."),
            ]),
            move(id: "overhead-reaches", name: String(localized: "Overhead reaches"),
                 reverses: false, steps: [
                String(localized: "warmup.overheadReaches.step1",
                       defaultValue: "Reach one arm up high, lengthening that side, then the other."),
                String(localized: "warmup.overheadReaches.step2",
                       defaultValue: "Draw each elbow down toward the ribs on the way back; keep the lower back still."),
            ]),
            // The trunk.
            move(id: "torso-rotations", name: String(localized: "Torso rotations"),
                 reverses: false, steps: [
                String(localized: "warmup.torsoRotations.step1",
                       defaultValue: "Feet planted, hips facing forward; turn the torso side to side."),
                String(localized: "warmup.torsoRotations.step2",
                       defaultValue: "Let the arms swing loose — momentum, not force."),
            ]),
            move(id: "side-bends", name: String(localized: "Side bends"),
                 reverses: false, steps: [
                String(localized: "warmup.sideBends.step1",
                       defaultValue: "Feet hip-width; slide one hand down the side of the thigh as you bend to that side."),
                String(localized: "warmup.sideBends.step2",
                       defaultValue: "Come up through the middle and bend to the other side — no leaning forward."),
            ]),
            move(id: "hip-circles", name: String(localized: "Hip circles"),
                 reverses: true, steps: [
                String(localized: "warmup.hipCircles.step1",
                       defaultValue: "Hands on the hips, feet shoulder-width; draw slow circles with the hips."),
                String(localized: "warmup.hipCircles.step2",
                       defaultValue: "Keep the knees soft and switch direction halfway."),
            ]),
            move(id: "standing-cat-cow", name: String(localized: "Standing cat-cow"),
                 reverses: false, steps: [
                String(localized: "warmup.standingCatCow.step1",
                       defaultValue: "Knees slightly bent, hands on the thighs; exhale, round the back and tuck the chin."),
                String(localized: "warmup.standingCatCow.step2",
                       defaultValue: "Inhale, arch gently and open the chest — one slow wave per breath."),
            ]),
            // Lead-ins only (`leadIn(for:)`).
            move(id: "hip-hinges", name: String(localized: "Hip hinges"),
                 reverses: false, steps: [
                String(localized: "warmup.hipHinges.step1",
                       defaultValue: "Hands on the hips, knees soft; push the hips back as the chest leans forward."),
                String(localized: "warmup.hipHinges.step2",
                       defaultValue: "Keep the back flat and go only as far as is comfortable, then stand tall."),
            ]),
            // Slow, and said so: thirty seconds at an easy pace is fifteen to
            // twenty half squats — more than a first working set of 3×4 —
            // and the block is meant to leave the legs fresh for that set.
            move(id: "half-squats", name: String(localized: "Half squats"),
                 reverses: false, steps: [
                String(localized: "warmup.halfSquats.step1",
                       defaultValue: "Heels down, sit back to half depth with the arms reaching forward for balance."),
                String(localized: "warmup.halfSquats.step2",
                       defaultValue: "Slow and easy — about ten in all; rise without locking the knees."),
            ]),
        ]
    }

    /// No default for `reverses`, deliberately: an omitted argument would be a
    /// circle running thirty seconds in one direction with no switch
    /// announced. A compile error is a stronger guard than a grep (the rule
    /// `SetsHandle` keeps for the same reason).
    private static func move(id: String, name: String, reverses: Bool,
                             steps: [String]) -> WarmupMove {
        WarmupMove(id: id, name: name, reverses: reverses, steps: steps)
    }

    // MARK: - Composition

    /// The first five slots and where each draws from, in display order.
    ///
    /// Each group's rotation runs over its WHOLE list and advances one move
    /// per session; a move set aside — or the one the lead-in already took —
    /// passes its turn to the next in its group. Run over the whole list, the
    /// rotation's period is the same whatever is set aside
    /// (`rotationPeriod`), which is what lets the reserve tests walk every
    /// composition there is.
    ///
    /// Marching is a group of its own: it opens every block cold, and the
    /// first thing a cold body gets is the gentlest raise there is.
    private static let groups: [(ids: [String], slots: Int)] = [
        (["marching"], 1),
        (["side-steps", "heels-to-glutes"], 1),
        (["arm-circles", "arm-swings", "reach-and-pull", "wrist-circles", "overhead-reaches"], 2),
        (["torso-rotations", "side-bends", "hip-circles", "standing-cat-cow"], 1),
    ]

    /// The last slot: the move that prepares the session's first exercise —
    /// the block's one specific part, and the reason half squats do not
    /// precede a session that opens on a push.
    ///
    /// Total over `Pattern`, with no default: a new pattern is a compile error
    /// here rather than a session that silently opens without a lead-in. Only
    /// four patterns open a session today — squat, horizontal push, hinge,
    /// pull (`Pattern.ordered` against the rotation) — but every pattern has
    /// to land on a sensible move all the same.
    static func leadIn(for pattern: Pattern) -> String {
        switch pattern {
        case .squat, .lunge, .calf:  return "half-squats"
        case .hinge:                 return "hip-hinges"
        case .pushH:                 return "arm-swings"
        case .pushV:                 return "overhead-reaches"
        case .pull, .pullBar:        return "reach-and-pull"
        case .coreAntiExt:           return "standing-cat-cow"
        case .coreRot:               return "torso-rotations"
        }
    }

    /// The six moves of session `sessionNumber` opening on `opening`, drawn
    /// from the pool with `hidden` set aside.
    ///
    /// Deterministic in its three inputs alone, which is what lets a restored
    /// snapshot recompute the same list instead of carrying it.
    ///
    /// `hidden` exists because a move can fall in session after session — the
    /// opener in every one — and without it the only way to say "not this
    /// one" would be the same tap, every workout, forever: for a sore wrist
    /// that is the cost that makes people drop the whole block instead.
    static func moves(sessionNumber: Int, opening: Pattern?,
                      hiding hidden: Set<String>) -> [WarmupMove] {
        // `pool` is a computed property that builds fourteen localized moves,
        // so it is read ONCE here and everything below works off the array.
        let whole = pool
        let setAside = honoured(hidden, of: whole)
        let lead = opening.map(leadIn(for:)).flatMap { setAside.contains($0) ? nil : $0 }
        var taken = setAside
        if let lead { taken.insert(lead) }
        var chosen: Set<String> = []
        for group in groups {
            let drawn = draw(group.slots, of: group.ids, session: sessionNumber, passing: taken)
            chosen.formUnion(drawn)
            taken.formUnion(drawn)
        }
        // A group whose every move is set aside leaves its slot empty, and the
        // block is six whatever is set aside: the first moves of the pool not
        // yet taken fill in. In pool order, so an emptied raise slot is
        // refilled by the other raise move first.
        let bodyCount = moveCount - (lead == nil ? 0 : 1)
        for move in whole where chosen.count < bodyCount && !taken.contains(move.id) {
            chosen.insert(move.id)
        }
        return whole.filter { chosen.contains($0.id) } + whole.filter { $0.id == lead }
    }

    /// The block's own rule with nothing set aside — what the pool composes
    /// before any athlete has said anything. The app never calls it.
    ///
    /// Nor does the reserve gate, except for the claims that are explicitly
    /// about "before anything was set aside": a convenience overload is a fine
    /// thing; a convenience overload that a gate reaches for is how the gate
    /// stops watching.
    static func moves(sessionNumber: Int, opening: Pattern?) -> [WarmupMove] {
        moves(sessionNumber: sessionNumber, opening: opening, hiding: [])
    }

    /// `slots` moves of `ids`, starting where session `session` puts the
    /// group's rotation and passing over anything in `passing`.
    private static func draw(_ slots: Int, of ids: [String], session: Int,
                             passing: Set<String>) -> [String] {
        guard !ids.isEmpty else { return [] }
        // Nonnegative modulo: a hand-edited session number can be anything,
        // and Swift's % is a remainder. `ids` is non-empty here, and the guard
        // is what says so out loud, because a % 0 is a crash, not a wrong list.
        let start = ((session - 1) % ids.count + ids.count) % ids.count
        let turn = (0..<ids.count).map { ids[(start + $0) % ids.count] }
        return Array(turn.filter { !passing.contains($0) }.prefix(slots))
    }

    /// As many of `hidden` as the block can afford, in pool order.
    ///
    /// The guarantee that a block never empties lives HERE and not in the
    /// settings that hold the list: `AppStore.maxHiddenBlockMoves` caps what
    /// the control can add, but a state file written by an older
    /// build, an imported backup or a future cap must not be able to compose a
    /// warm-up of two moves — or of none, which would index out of bounds on
    /// the first screen. Six of fourteen are shown, so at most eight can go.
    private static func honoured(_ hidden: Set<String>, of whole: [WarmupMove]) -> Set<String> {
        let affordable = max(whole.count - moveCount, 0)
        guard hidden.count > affordable else { return hidden }
        return Set(whole.map(\.id).filter(hidden.contains).prefix(affordable))
    }

    /// The composition of the session in front of the person — the block
    /// screens read this and nothing else.
    ///
    /// No default for `hiding`, deliberately, and for the reason `move(id:...)`
    /// above gives about `reverses`: an omitted argument here is a control the
    /// athlete used that the block ignores, which is worse than not offering
    /// it. One caller, and a compile error is a stronger guard than a grep.
    static func moves(for session: Session, hiding hidden: Set<String>) -> [WarmupMove] {
        moves(sessionNumber: session.sessionNumber,
              opening: session.exercises.first?.pattern, hiding: hidden)
    }

    /// The name behind an id, for the sheet's list of what has been set aside:
    /// it holds ids and no moves. nil for an id from the cool-down's pool —
    /// one list covers both, and the caller asks both pools — and for a move
    /// an earlier build had and this one does not.
    static func name(ofMove id: String) -> String? {
        pool.first { $0.id == id }?.name
    }

    /// How many sessions before the compositions repeat: the least common
    /// multiple of the group sizes, fixed whatever is set aside because each
    /// rotation runs over its whole list. The reserve tests walk all of them:
    /// with a pool, "the block fits" is a claim about every session, not
    /// about one.
    static var rotationPeriod: Int {
        groups.map(\.ids.count).reduce(1) { period, size in
            var (a, b) = (period, size)
            while b != 0 { (a, b) = (b, a % b) }
            return period / a * size
        }
    }

    /// What the offer screen promises, DERIVED — a hand-typed 4 would go stale
    /// the first time the transition or the slot changes. Rounded up: a
    /// promise the block overruns is worse than one it beats.
    static func introMinutes(_ moves: [WarmupMove]) -> Int {
        let seconds = moves.reduce(0) { total, move in
            total + GuidedBlock.warmup.stageSeconds(.getReady, of: move) + moveSeconds
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }
}
