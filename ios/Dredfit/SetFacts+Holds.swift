//
//  What a hold's clock is set to, what a tap ending it is worth, and how far
//  its summary may correct it.
//

import Foundation
import DredfitCore

nonisolated extension SetFacts {
    // MARK: - Correcting a hold on its summary

    /// The range a hold's recorded seconds may be corrected within on the
    /// movement's summary.
    ///
    /// ONLY THE LAST WORKING SET IS CORRECTED. Every earlier set ended on its
    /// signal or under a thumb and stands as it ran: its range is the number
    /// itself, and its card opens no panel — one with both ends dead reads as
    /// a broken control.
    ///
    /// The last one goes down to the corridor's floor, and up as far as
    /// nothing stopped it. With nothing after it — no rest starts on its
    /// signal, and the person may have kept holding — the corridor is the
    /// ceiling: the "Went differently" of the last hold, on its card. A set a
    /// REST followed — the last working set of a probing hold, whose signal
    /// starts the rest before the probe — ended where its LAST side ended, and
    /// the ceiling is what that side's clock ran. When its clock ended it,
    /// that is the seconds recorded. When a thumb did (`endedByTap`), it is
    /// the estimate plus the reach allowance it paid (`holdReachSeconds`):
    /// the clock's reading at the tap everywhere but the corridor's floor,
    /// where a tap at 4–7 s records 5 and the ceiling of 8 can lie up to 4 s
    /// over the reading — only the reading itself would be exact, and nothing
    /// keeps it. More would be seconds nobody could have held, and on a
    /// probing hold one step of them can decide whether the probe counts at
    /// all.
    ///
    /// What is wanted next time is a different channel (`raisedSteps`): a
    /// number entered on a card is written down as HELD (`recordingSet`), so
    /// no card may invite the number the next plan should start from.
    ///
    /// `measured` is what the clock recorded for the set (`summaryMeasured`),
    /// or what the card shows when no clock ran for it. For a set ended by tap
    /// that is already the clock less the reach allowance, and an earlier set
    /// stands at it: the allowance is a guess about a walk to the phone either
    /// way.
    static func correctionRange(measured: Int, isLastSet: Bool,
                                restFollowed: Bool, endedByTap: Bool) -> ClosedRange<Int> {
        let corridor = corridor(for: .hold)
        let fixed = min(max(measured, corridor.lowerBound), corridor.upperBound)
        guard isLastSet else { return fixed...fixed }
        guard restFollowed else { return corridor }
        let ran = endedByTap ? measured + holdReachSeconds : measured
        return corridor.lowerBound...min(max(ran, corridor.lowerBound), corridor.upperBound)
    }

    // MARK: - What a hold is worth when a thumb ends it

    /// Seconds taken off a hold that ended by TAP.
    ///
    /// The tap happens AFTER the effort has stopped: the person comes off the
    /// floor and reaches for the phone, and the timestamp of the thumb is not
    /// the timestamp of the last second held. A relative of
    /// `WorkoutSession.holdMistapSeconds`, which exists for the other half of
    /// the same fact — a tap is evidence about a hand, not about a plank.
    ///
    /// Three rather than a measurement: the honest direction is DOWN, because
    /// a number the athlete did not earn is the one the engine then plans
    /// from. Reading the lift of the phone off CoreMotion would be the real
    /// answer; nothing here reads it.
    static let holdReachSeconds = 3

    /// What a hold ended by tap records. Never below the corridor's own floor
    /// — five seconds is the least a hold can be STORED as — and never more
    /// than the thumb's own allowance below what the clock saw.
    static func holdEndedByTap(heldSeconds: Int) -> Int {
        max(corridor(for: .hold).lowerBound, heldSeconds - holdReachSeconds)
    }

    // MARK: - The set the run opens by itself

    /// Whether the hands-free run opens the set at `index` BY ITSELF.
    ///
    /// One question, two callers, because they have to agree: the rest's end
    /// starts that set, and the rest's screen offers a pause precisely because
    /// it will. A rest whose clock starts nothing needs no pause — nothing
    /// happens without the person — and a rest that does start something and
    /// offers no way to stop it is how a set goes by while somebody answers
    /// the door.
    ///
    /// `running` is the run's own flag: one tap bought THIS exercise, so the
    /// next movement is a decision of its own. The probe is excluded: it is
    /// one set of a movement nobody has done, possibly in another unit, and
    /// being dropped into a countdown for it is exactly the surprise a probe
    /// must never spring.
    static func runOpensSet(_ index: Int, of exercise: SessionExercise,
                            running: Bool) -> Bool {
        guard running, exercise.unit == .hold else { return false }
        let total = exercise.sets + (exercise.probe == nil ? 0 : 1)
        guard index >= 0, index < total else { return false }
        return !(exercise.probe != nil && index >= exercise.sets)
    }

    /// The last seconds of a rest are counted out loud, and this is how much
    /// of that the app is allowed to have missed before the go it played
    /// stops counting as heard. One second is the tick's own period; three is
    /// the 3-2-1 itself.
    static let restGoHeardWithinSec = 3.0

    /// Whether the set a rest hands over to still needs counting in.
    ///
    /// A rest that ran out under the person's eyes has already done it — its
    /// own 3-2-1 ends on the go that starts the hold, and a second window on
    /// top of that would announce the same start twice. Two cases still need
    /// the beat:
    ///
    /// - the rest was CUT SHORT BY A TAP. A tap is somebody saying "I am
    ///   ready", and the hold must not land under the thumb that said it.
    /// - the app was SUSPENDED across the end of the rest and comes back to
    ///   find it over. The go was played to a locked phone or to nobody at
    ///   all, and a signal nobody could hear cannot be what started a plank.
    static func restHandsOverWithCountIn(endedByTap: Bool, overshootSec: Double) -> Bool {
        endedByTap || overshootSec > restGoHeardWithinSec
    }

    // MARK: - The time a hold is set to run

    /// The seconds set `index` of a hold counts down from.
    ///
    /// Without a declaration this is `inForce`. With one, THE DECLARATION
    /// STANDS IN FOR THE PLAN: the athlete said before the effort how long
    /// they mean to hold, and that is what the clock is set to for every set
    /// of the exercise.
    ///
    /// It is not simply the declared number on every set, because a set that
    /// was cut short has already said something: the sets after it follow what
    /// was actually shown, capped by what was declared. That is the same
    /// asymmetry `inForce` applies against the plan — a shortfall carries
    /// forward, a surplus does not — with the declaration as the ceiling
    /// instead of the plan, and the same rule `holdSideSeconds` applies
    /// between the two sides of one set.
    ///
    /// A declaration BELOW the plan is allowed and means what it says. Doing
    /// less than planned is a decision the person is entitled to take, and it
    /// reaches the engine as the honest number it is.
    ///
    /// A declaration governs a HOLD only. Reps have no control that sets a
    /// target before the effort, so one found beside them came off a snapshot
    /// and they read `inForce`, the number their shortfall carries forward
    /// through. The gate is here and not at the callers because the work
    /// screen, the clock, the declaration's own seed and the header's price
    /// all ask this, and a caller that left the gate out would answer
    /// differently from the rest.
    static func holdTarget(_ facts: PerSet, _ ex: SessionExercise,
                           set index: Int, declared: Int?) -> Int {
        guard ex.unit == .hold, let declared else { return inForce(facts, ex, set: index) }
        // Clamped where it is READ, like everything else that can come back
        // off disk: the declaration is carried in the workout snapshot.
        let ceiling = min(max(declared, corridor(for: .hold).lowerBound),
                          corridor(for: .hold).upperBound)
        let values = facts[ex.pattern] ?? []
        let index = max(index, 0)
        guard index > 0, !values.isEmpty else { return ceiling }
        return min(values[min(index, values.count) - 1], ceiling)
    }
}
