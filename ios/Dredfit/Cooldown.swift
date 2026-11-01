//
//  The cool-down block as data: six positions × 30 s plus their transitions,
//  from standing DOWN to lying, one zone of the body each. No ladder, no
//  journal entry, no engine involvement.
//
//  ONE WAY DOWN, and nothing to fetch. Two positions standing, then a single
//  descent — onto one knee, onto both knees, onto the back — and nobody gets
//  up again until the block is over. The block used to go down onto one knee,
//  up to a wall, stand, and go down again, with a wall and a support at hip
//  height in every session; each of those is a transition that costs time and
//  asks for something the stretch itself does not need. The order is not a
//  taste either: standing still straight after effort is when people feel
//  light-headed, and lying down is where the heart rate comes back fastest.
//
//  THE SAME ZONES EVERY SESSION. Each slot belongs to a zone — chest and
//  shoulders or wrists, the back of the thighs, the hip flexors, the back,
//  the glutes, the spine — and two of the zones alternate their variant from
//  session to session. Following today's movements instead read the first
//  three movements of the session, so it almost always landed on the same
//  three positions, and the twist that now closes the block never came up.
//
//  A side changes ON THE SPOT, on a tone with the clock running — the warm-up's
//  rule for its circles. The pause stays only where the body has to re-set:
//  changing the leg of a kneeling lunge is getting up and down again, and
//  fifteen seconds would lose three of theirs to it.
//
//  The block's length is not restated here: what the offer screen promises is
//  derived (`cooldownIntroMinutes`), and the engine's reserve is the engine's
//  (`BlockReserveTests` holds the arithmetic).
//

import Foundation
import DredfitCore

struct CooldownPosition: Equatable, Identifiable {
    /// Where the body is. The block only ever moves DOWN this order.
    enum Level: Int, Comparable {
        case standing, halfKneeling, kneeling, lying

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    let name: String
    let level: Level
    /// nil: held whole. Otherwise one 30 s slot split into 15 s per side — a
    /// per-side position does not get twice the time — and whether the switch
    /// between them stops the clock (`WarmupHalves.pausesAtTheSwitch`).
    let halves: WarmupHalves?
    /// The transition into this position carries the supplement of issue #83.
    /// COMPUTED by the composition, never written by hand: the supplement pays
    /// for the one trip down to the floor, so only the first position below
    /// standing carries it.
    var needsSetup: Bool
    let steps: [String]

    var perSide: Bool { halves != nil }
}

enum Cooldown {

    static let positionSeconds = 30
    static let positionCount = 6

    /// The re-set pause between sides of timed unilateral work (issue #35).
    /// One app-layer constant shared by the cool-down and the workout's
    /// per-side holds — changing it moves both.
    ///
    /// Four is ON TRIAL: turning over inside one position is not travel to
    /// another, and four seconds may be enough for it. Written down as a trial
    /// because it is meant to be judged in use and rolled back to five if it
    /// turns out to rush. The revert is more than this line: `GetReadyTests`
    /// pins the value, `BlockPauseTests` ties it to the count-in
    /// (`GetReady.countInSeconds`, the same beat), and `BlockReserveTests`
    /// pins the block totals it feeds.
    ///
    /// Four rather than five costs nothing at the reserve: shortening only
    /// ever leaves slack, and the pause carries no 3-2-1 to collide with (a
    /// tick would bury the switch tone — `tickHoldSwitchPause`).
    static let sideSwitchPauseSec = 4

    static var sideSeconds: Int { positionSeconds / 2 }

    /// What the position itself takes, its transition excluded: the slot, plus
    /// the switch pause when its halves stop the clock. ONE function for the
    /// offer screen, the header that counts what is left, and the reserve
    /// tests — copies of a formula agree only until one of them is edited.
    static func slotSeconds(of position: CooldownPosition) -> Int {
        positionSeconds + (position.halves?.pausesAtTheSwitch == true ? sideSwitchPauseSec : 0)
    }

    // MARK: - The pool of ten

    /// In the ORDER THE BLOCK RUNS: standing first, the kneeling lunge as the
    /// one trip down, then kneeling, then lying. The composition sorts what it
    /// draws by level and then by this order, so a position refilled into an
    /// emptied zone still lands on its own level and the block never climbs.
    /// The standing lunge is last: it is the hip flexors' fallback and nothing
    /// else's (`fallbackOnly`).
    private static var pool: [CooldownPosition] {
        [chestOpener, wrists, halfFold, hipFlexors, childSideReach, restPose,
         lyingFigureFour, kneesToChest, lyingTwist, standingHipFlexors]
    }

    private static var chestOpener: CooldownPosition {
        position("chest-opener", String(localized: "cooldown.chestOpener", defaultValue: "Chest opener"),
                 .standing, nil, [
            String(localized: "cooldown.chestOpener.step1",
                   defaultValue: "Stand tall with the palms on the lower back, fingers pointing down."),
            String(localized: "cooldown.chestOpener.step2",
                   defaultValue: "Draw the elbows back toward each other and open the chest; keep the shoulders down."),
            String(localized: "cooldown.chestOpener.step3",
                   defaultValue: "Breathe slowly and keep the lower back still."),
        ])
    }
    private static var wrists: CooldownPosition {
        position("wrists", String(localized: "cooldown.wrists", defaultValue: "Wrists and forearms"),
                 .standing, .sidesOnTheSpot, [
            String(localized: "cooldown.wrists.step1",
                   defaultValue: "Arm straight, palm down; gently pull the fingers down and toward you."),
            String(localized: "cooldown.wrists.step2",
                   defaultValue: "Then turn the palm up and repeat the gentle pull."),
            String(localized: "cooldown.wrists.step3",
                   defaultValue: "Pull only to a stretch — ease off at anything sharp or tingling."),
        ])
    }
    /// HALF, and with the hands on the thighs: a full fold puts the head below
    /// the heart straight after the effort, which is when a standing body is
    /// most likely to feel light-headed.
    private static var halfFold: CooldownPosition {
        position("half-fold", String(localized: "cooldown.halfFold", defaultValue: "Half forward fold"),
                 .standing, nil, [
            String(localized: "cooldown.halfFold.step1",
                   defaultValue: "Feet hip-width, knees soft, hands on the thighs."),
            String(localized: "cooldown.halfFold.step2",
                   defaultValue: "Hinge forward with a flat back until the backs of the thighs stretch; head in line with the back."),
            String(localized: "cooldown.halfFold.step3",
                   defaultValue: "Come up slowly, pressing the hands into the thighs."),
        ])
    }
    /// The one position whose switch keeps the pause: changing the front leg
    /// of a kneeling lunge is a whole re-set of the body.
    private static var hipFlexors: CooldownPosition {
        position("hip-flexors", String(localized: "cooldown.hipFlexors", defaultValue: "Hip flexor stretch"),
                 .halfKneeling, .sides, [
            String(localized: "cooldown.hipFlexors.step1",
                   defaultValue: "Kneel on one knee, the other foot planted in front; pad the knee if the floor is hard."),
            String(localized: "cooldown.hipFlexors.step2",
                   defaultValue: "Tuck the pelvis and shift it slightly forward until the front of the hip stretches."),
            String(localized: "cooldown.hipFlexors.step3",
                   defaultValue: "Hold steady and breathe — no bouncing."),
        ])
    }
    private static var childSideReach: CooldownPosition {
        position("child-side-reach",
                 String(localized: "cooldown.childSideReach", defaultValue: "Rest pose, side reach"),
                 .kneeling, .sidesOnTheSpot, [
            String(localized: "cooldown.childSideReach.step1",
                   defaultValue: "Kneel, sit back toward the heels and walk both hands forward on the floor."),
            String(localized: "cooldown.childSideReach.step2",
                   defaultValue: "Walk the hands to one side until the side of the back stretches."),
            String(localized: "cooldown.childSideReach.step3",
                   defaultValue: "Knees wider apart if the knees or hips object."),
        ])
    }
    private static var restPose: CooldownPosition {
        position("rest-pose", String(localized: "cooldown.restPose", defaultValue: "Rest pose"),
                 .kneeling, nil, [
            String(localized: "cooldown.restPose.step1",
                   defaultValue: "Knees on the floor and a little apart, sit back toward the heels."),
            String(localized: "cooldown.restPose.step2",
                   defaultValue: "Fold forward, arms stretched ahead, forehead down."),
            String(localized: "cooldown.restPose.step3",
                   defaultValue: "Breathe slowly, sending the breath into the back."),
        ])
    }
    /// Lying rather than seated: sitting tall on the floor is hard with tight
    /// hips and loads the knee, and lying keeps the head down after the
    /// kneeling positions instead of bringing it back up.
    private static var lyingFigureFour: CooldownPosition {
        position("lying-figure-four",
                 String(localized: "cooldown.lyingFigureFour", defaultValue: "Figure-four stretch, lying"),
                 .lying, .sidesOnTheSpot, [
            String(localized: "cooldown.lyingFigureFour.step1",
                   defaultValue: "On your back, knees bent; cross one ankle over the opposite knee."),
            String(localized: "cooldown.lyingFigureFour.step2",
                   defaultValue: "Draw the supporting thigh toward the chest until the crossed hip stretches."),
            String(localized: "cooldown.lyingFigureFour.step3",
                   defaultValue: "Head and shoulders stay on the floor."),
        ])
    }
    private static var kneesToChest: CooldownPosition {
        position("knees-to-chest", String(localized: "cooldown.kneesToChest", defaultValue: "Knees to chest"),
                 .lying, nil, [
            String(localized: "cooldown.kneesToChest.step1",
                   defaultValue: "On your back, hug both knees toward the chest."),
            String(localized: "cooldown.kneesToChest.step2",
                   defaultValue: "Let the lower back settle into the floor and breathe slowly."),
        ])
    }
    /// The block's last position, and its close: lying, breathing slowly, and
    /// told how to get up.
    private static var lyingTwist: CooldownPosition {
        position("lying-twist", String(localized: "cooldown.lyingTwist", defaultValue: "Lying twist"),
                 .lying, .sidesOnTheSpot, [
            String(localized: "cooldown.lyingTwist.step1",
                   defaultValue: "On your back, knees bent; drop both knees to one side."),
            String(localized: "cooldown.lyingTwist.step2",
                   defaultValue: "Shoulders stay on the floor, head turns the other way."),
            String(localized: "cooldown.lyingTwist.step3",
                   defaultValue: "Let the knees sink on their own and breathe slowly; to get up, roll onto your side first."),
        ])
    }
    /// The hip flexors' fallback for someone who cannot kneel. Standing, so it
    /// keeps the block's one-way order; stepping the feet over is a re-set, so
    /// it keeps the pause too.
    private static var standingHipFlexors: CooldownPosition {
        position("standing-hip-flexors",
                 String(localized: "cooldown.standingHipFlexors", defaultValue: "Hip flexor stretch, standing"),
                 .standing, .sides, [
            String(localized: "cooldown.standingHipFlexors.step1",
                   defaultValue: "Stand in a long split stance, back heel lifted, hands on the hips."),
            String(localized: "cooldown.standingHipFlexors.step2",
                   defaultValue: "Tuck the pelvis under until the front of the back hip stretches."),
            String(localized: "cooldown.standingHipFlexors.step3",
                   defaultValue: "Hold steady and breathe — no bouncing."),
        ])
    }

    /// No default for `halves`, deliberately: an omitted argument would be a
    /// one-sided stretch held thirty seconds on one side, with no switch
    /// announced — or a re-set with no pause to make it in.
    private static func position(_ id: String, _ name: String, _ level: CooldownPosition.Level,
                                 _ halves: WarmupHalves?, _ steps: [String]) -> CooldownPosition {
        CooldownPosition(id: id, name: name, level: level, halves: halves,
                         needsSetup: false, steps: steps)
    }

    // MARK: - Composition

    /// The six zones, each a slot: its ids in order of preference, and whether
    /// the zone alternates its variant from session to session or always opens
    /// on the first one it can.
    private static let zones: [(ids: [String], rotates: Bool)] = [
        (["chest-opener", "wrists"], true),
        (["half-fold"], false),
        (["hip-flexors", "standing-hip-flexors"], false),
        (["child-side-reach", "rest-pose"], true),
        (["lying-figure-four", "knees-to-chest"], false),
        (["lying-twist"], false),
    ]

    /// Positions that stand in for their own zone's first choice and are never
    /// drawn to refill another one.
    private static let fallbackOnly: Set<String> = ["standing-hip-flexors"]

    /// The six positions of session `sessionNumber` with `hidden` set aside.
    ///
    /// Deterministic in its two inputs alone. A rotating zone advances one
    /// variant per session over its WHOLE list, so a set-aside variant passes
    /// its turn to the next one; any other zone opens on its first variant
    /// still available. A zone whose every variant is set aside leaves its
    /// slot empty, and the first positions of the pool not yet drawn fill it —
    /// the block is six whatever is set aside, which is also what keeps the
    /// cap of three (`AppStore.maxHiddenBlockMoves`) a floor argument. What is
    /// drawn is then put in order, level by level, so the block only ever
    /// goes down.
    ///
    /// `hidden` exists because a position can fall in every session, and
    /// without it the only way to say "not this one" — no floor to kneel on, a
    /// knee that objects — would be the same tap, every workout, forever.
    static func positions(sessionNumber: Int, hiding hidden: Set<String>) -> [CooldownPosition] {
        // `pool` builds ten localized positions, so it is read ONCE here.
        let whole = pool
        let setAside = honoured(hidden, of: whole)
        let level = Dictionary(uniqueKeysWithValues: whole.map { ($0.id, $0.level) })
        let open = { (id: String, chosen: [String]) in !setAside.contains(id) && !chosen.contains(id) }
        var chosen: [String] = []
        var emptied: [CooldownPosition.Level] = []
        for zone in zones {
            let turn: [String]
            if zone.rotates {
                // Nonnegative modulo: a hand-edited session number can be
                // anything, and Swift's % is a remainder.
                let count = zone.ids.count
                let start = ((sessionNumber - 1) % count + count) % count
                turn = (0..<count).map { zone.ids[(start + $0) % count] }
            } else {
                turn = zone.ids
            }
            if let pick = turn.first(where: { open($0, chosen) }) {
                chosen.append(pick)
            } else if let first = zone.ids.first, let zoneLevel = level[first] {
                emptied.append(zoneLevel)
            }
        }
        // A zone set aside entirely is refilled from its OWN level first — the
        // finishing twist gives its slot to another position lying down, not
        // to one standing up — and only then from anywhere in the pool. Never
        // with a zone's own fallback, which would stretch the same muscle
        // twice: the standing lunge stands in for the kneeling one and for
        // nothing else.
        let refills = whole.filter { !fallbackOnly.contains($0.id) }
        for zoneLevel in emptied {
            if let refill = refills.first(where: { $0.level == zoneLevel && open($0.id, chosen) }) {
                chosen.append(refill.id)
            }
        }
        for position in refills where chosen.count < positionCount && open(position.id, chosen) {
            chosen.append(position.id)
        }
        let order = Dictionary(uniqueKeysWithValues: whole.enumerated().map { ($1.id, $0) })
        var composed = whole.filter { chosen.contains($0.id) }
            .sorted { ($0.level, order[$0.id] ?? 0) < ($1.level, order[$1.id] ?? 0) }
        // Only the trip DOWN pays the supplement: one per block, on the first
        // position below standing. Charging every floor position would spend
        // reserve on moves nobody makes.
        if let first = composed.firstIndex(where: { $0.level > .standing }) {
            composed[first].needsSetup = true
        }
        return composed
    }

    /// The block's own rule with nothing set aside. The app never calls it, and
    /// the reserve gate calls it only where the claim IS about the block before
    /// anything was set aside; the shipped rule is the `hiding:` one (see
    /// `Warmup.moves(sessionNumber:opening:)` for what a gate walking the
    /// convenience overload stops seeing).
    static func positions(sessionNumber: Int) -> [CooldownPosition] {
        positions(sessionNumber: sessionNumber, hiding: [])
    }

    /// How many sessions before the compositions repeat: the least common
    /// multiple of the rotating zones' sizes, fixed whatever is set aside
    /// because each rotation runs over its whole list.
    static var rotationPeriod: Int {
        zones.filter(\.rotates).map(\.ids.count).reduce(1) { period, size in
            var (a, b) = (period, size)
            while b != 0 { (a, b) = (b, a % b) }
            return period / a * size
        }
    }

    /// As many of `hidden` as the block can afford, in pool order — the twin
    /// of `Warmup.honoured` and for the same reason: the guarantee that a
    /// block never empties belongs to the composer, not to the settings that
    /// hold the list. Ten in the pool against six on screen, less the fallback
    /// that refills no other zone, so three.
    private static func honoured(_ hidden: Set<String>, of whole: [CooldownPosition]) -> Set<String> {
        let affordable = max(whole.count - fallbackOnly.count - positionCount, 0)
        guard hidden.count > affordable else { return hidden }
        return Set(whole.map(\.id).filter(hidden.contains).prefix(affordable))
    }

    /// The name behind an id — see `Warmup.name(ofMove:)`. nil for an id from
    /// the warm-up's pool, and for a position an earlier build had and this one
    /// does not.
    static func name(ofPosition id: String) -> String? {
        pool.first { $0.id == id }?.name
    }

    /// The workout's per-side holds play the same pause with no position
    /// attached — and collapse under --uitest-fast with everything else.
    static var switchPauseSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        return sideSwitchPauseSec
    }
}
