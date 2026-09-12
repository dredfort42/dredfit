//
//  What a session costs, in the unit Apple Health accepts for it.
//
//  App layer on purpose. `generateSession` and `applyFeedback` never see a
//  Date and never see a body; a calorie is a fact about a person, not about a
//  ladder, so none of this belongs in DredfitCore or in golden.json.
//
//  Pure arithmetic over values, so it is not the main actor's business — and
//  the Health reader hands these types across an async boundary (same reason
//  as SetFacts).
//

import Foundation
import DredfitCore

/// What Health can tell us about the body doing the work, beyond its mass.
///
/// Every field is optional and stays optional all the way down. HealthKit
/// deliberately does NOT report whether a read was granted — a refusal and a
/// profile nobody ever filled in are the same empty answer — so "absent" here
/// is the ordinary case, not the error case.
nonisolated struct BodyProfile: Equatable, Sendable {
    var heightCm: Double?
    var ageYears: Double?
    var sex: BodySex?

    static let unknown = BodyProfile()
}

nonisolated enum BodySex: Equatable, Sendable { case female, male, other }

/// The seconds a planned session spends in each state it can be in.
///
/// Also the ONE home of the session-duration arithmetic: `estimatedDurationSec`
/// reads `totalSec` from here instead of spelling the sum out again. The two
/// copies that used to exist disagreed about the cool-down by a minute, and
/// that minute went to Apple Health unnoticed for a whole release.
nonisolated struct SessionSegments: Equatable, Sendable {
    var warmupSec: Double = 0
    var repWorkSec: Double = 0
    var holdWorkSec: Double = 0
    var restSec: Double = 0
    var cooldownSec: Double = 0

    var totalSec: Double {
        warmupSec + repWorkSec + holdWorkSec + restSec + cooldownSec
    }

    /// The journal is an input. `sets`, `load` and the rest come back out of
    /// the file unclamped — `SessionExercise.init(from:)` decodes them raw —
    /// so a hand-edited record can produce a negative rest or an infinity
    /// here. The duration estimate survives that on its own final clamp;
    /// energy refuses to guess instead, because a wrong calorie count is
    /// indistinguishable in Health from a right one.
    var isPlausible: Bool {
        let all = [warmupSec, repWorkSec, holdWorkSec, restSec, cooldownSec]
        guard all.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        return totalSec > 0 && totalSec <= 24 * 3600
    }
}

/// Which rung of the resting ladder produced a number. Named rather than
/// implied so a test can assert the ladder DEGRADED in the right order: three
/// rungs that each return something plausible are indistinguishable otherwise.
nonisolated enum RestingSource: Equatable, Sendable {
    case healthBasal
    case mifflin
    case standardMET
}

nonisolated struct RestingRate: Equatable, Sendable {
    let kcalPerMin: Double
    let source: RestingSource
}

nonisolated enum EnergyEstimate {

    // MARK: - The constants, and where they come from

    /// Which revision of THIS model produced a calorie, stamped onto the
    /// sample so a figure written today stays distinguishable from one written
    /// after the next change. Bump it whenever any number below moves, or
    /// whenever the segmentation changes shape — a version nobody is obliged
    /// to raise is a stale truth claim, and worse than no version at all.
    /// `testTheModelConstantsArePinnedToTheRevision` is that obligation.
    ///
    /// 1 — the first shipped model: five METs, a resting ladder of three
    ///     rungs, blocks measured rather than assumed.
    static let modelRevision = 1

    /// Seconds one repetition is under way — the engine's own figure, and the
    /// one the duration estimate has always used.
    static let secondsPerRep = 2.5

    /// MET values: Compendium of Physical Activities (Ainsworth 2011),
    /// conditioning-exercise section. They are GROSS — a multiple of the
    /// standard resting rate, not energy above it — because the oxygen cost of
    /// moving a body is set by its mass and by the movement, not by whose body
    /// it is. Only the resting term below is individualised, and that
    /// asymmetry is the whole model: scaling the activity by someone's resting
    /// metabolism would claim their push-up costs less than another person's.
    static let warmupMET = 3.5      // calisthenics, light-to-moderate effort
    static let repWorkMET = 6.0     // resistance training, vigorous effort
    static let holdWorkMET = 4.0    // the same shape held still: no concentric phase
    static let restMET = 1.8        // standing, a few steps between sets
    static let cooldownMET = 2.3    // stretching

    /// 1 MET = 3.5 ml O2 per kg per minute, and a litre of O2 costs about
    /// 5 kcal. `kcal/min = MET x 3.5 x kg / 200` falls out of those two.
    private static let mlO2PerKgMinPerMET = 3.5
    private static let kcalDivisor = 200.0

    /// A resting rate outside this band is not a body at rest, it is a hole in
    /// the data, and it falls through to the next rung. This catches the empty
    /// and the absurd — a watch absent for the whole session. A watch taken
    /// off for HALF of it still reads plausible; nothing in the data
    /// distinguishes that case, and pretending otherwise would be a guard that
    /// cannot go red.
    static let plausibleRestingKcalPerMin = 0.5...3.0

    // MARK: - Segmentation

    /// `nil` when there is nothing to segment: a record written before the
    /// exercise snapshot existed carries no plan, and a session cannot be
    /// priced from its rating alone.
    ///
    /// `warmupSec` and `cooldownSec` are what the two guided blocks ACTUALLY
    /// ran. Both have a footer button that ends the block on one tap, and for
    /// a while this function charged their full planned length regardless —
    /// nine minutes, 27 % of a median session, billed to a person who may have
    /// declined both. `nil` means a record written before the flow measured
    /// them; zero means declined. Neither argument carries a default: an
    /// omitted one would silently restore exactly that defect.
    static func segments(exercises: [SessionExercise],
                         skipped: Set<Pattern>,
                         warmupSec: Int?,
                         cooldownSec: Int?) -> SessionSegments? {
        guard !exercises.isEmpty else { return nil }
        var seg = SessionSegments()
        seg.warmupSec = performed(warmupSec, planned: EngineConfig.warmupMin * 60)
        seg.cooldownSec = performed(cooldownSec, planned: EngineConfig.cooldownMin * 60)
        for ex in exercises where !skipped.contains(ex.pattern) {
            let sides: Double = ex.perSide ? 2 : 1
            let sets = Double(ex.sets)
            // A repetition is under way for `secondsPerRep`; a hold's dose IS
            // its seconds. The whole sum runs in Double because these come
            // back out of the journal unclamped and would trap in Int.
            let perSet = ex.unit == .reps
                ? Double(ex.load) * sides * secondsPerRep
                : Double(ex.load) * sides
            if ex.unit == .reps {
                seg.repWorkSec += sets * perSet
            } else {
                seg.holdWorkSec += sets * perSet
            }
            seg.restSec += (sets - 1) * Double(ex.restSetSec) + Double(ex.restExerciseSec)
        }
        return seg
    }

    /// The plan is a CEILING here, the mirror of what the wall clock is for
    /// the session as a whole. A block runs longer than planned for reasons
    /// that are not effort — a get-ready screen, a technique sheet, a pause
    /// for the doorbell — so the surplus is not charged. A block cut short
    /// really was shorter, and a block never begun is zero.
    private static func performed(_ measured: Int?, planned: Int) -> Double {
        guard let measured else { return Double(planned) }
        return Double(min(max(measured, 0), planned))
    }

    // MARK: - The resting ladder

    /// Top rung first, each falling through silently to the next. The order is
    /// the point: Apple's own figure for this person beats a population
    /// formula, and the formula beats the constant that every textbook applies
    /// to everybody. `minutes` must be the length of the interval the basal
    /// sum was read over, not the length of the plan — a session that sat
    /// paused for twenty minutes has more basal energy in it than plan.
    static func resting(basalKcal: Double?, minutes: Double,
                        bodyMassKg: Double, profile: BodyProfile) -> RestingRate {
        if let basalKcal, basalKcal.isFinite, minutes > 0 {
            let rate = basalKcal / minutes
            if plausibleRestingKcalPerMin.contains(rate) {
                return RestingRate(kcalPerMin: rate, source: .healthBasal)
            }
        }
        if let cm = profile.heightCm, let age = profile.ageYears,
           let rate = mifflinKcalPerMin(kg: bodyMassKg, cm: cm, age: age, sex: profile.sex) {
            return RestingRate(kcalPerMin: rate, source: .mifflin)
        }
        return RestingRate(kcalPerMin: standardRestingKcalPerMin(kg: bodyMassKg),
                           source: .standardMET)
    }

    /// Mifflin-St Jeor (1990), kcal per day. The two published equations differ
    /// in exactly one constant: +5 for men, -161 for women. An unset or
    /// non-binary answer takes their mean — defaulting to either one would be
    /// a claim about the person rather than an admission that we do not know.
    static func mifflinKcalPerMin(kg: Double, cm: Double, age: Double,
                                  sex: BodySex?) -> Double? {
        guard kg > 0, cm > 0, age >= 0,
              kg.isFinite, cm.isFinite, age.isFinite else { return nil }
        let sexTerm: Double
        switch sex {
        case .male: sexTerm = 5
        case .female: sexTerm = -161
        case .other, nil: sexTerm = (5 - 161) / 2
        }
        let perDay = 10 * kg + 6.25 * cm - 5 * age + sexTerm
        guard perDay.isFinite, perDay > 0 else { return nil }
        return perDay / (24 * 60)
    }

    /// The bottom rung: one standard MET, the same rate the compendium's own
    /// numbers are ratios of.
    static func standardRestingKcalPerMin(kg: Double) -> Double {
        mlO2PerKgMinPerMET * kg / kcalDivisor
    }

    // MARK: - The number that goes to Health

    /// Active energy: the gross cost of the session minus this person's own
    /// resting cost over the same minutes. `activeEnergyBurned` means "above
    /// rest" in Health, and an app that writes the gross figure inflates every
    /// workout by roughly a quarter.
    ///
    /// `nil` rather than zero when it cannot be computed. A workout with no
    /// energy sample is an honest record; a workout carrying a zero is a claim
    /// that nothing was spent.
    static func activeKcal(_ segments: SessionSegments,
                           bodyMassKg: Double,
                           resting: RestingRate) -> Double? {
        guard bodyMassKg > 0, bodyMassKg.isFinite, segments.isPlausible,
              resting.kcalPerMin.isFinite, resting.kcalPerMin >= 0 else { return nil }
        // No work, no calorie. A session whose every exercise was skipped used
        // to be priced at its two guided blocks alone — 25 kcal at 80 kg, the
        // lowest figure in the whole golden fixture, for a workout in which
        // nothing was performed. Whatever those minutes cost, a WORKOUT entry
        // claiming them is a claim about training that did not happen.
        guard segments.repWorkSec + segments.holdWorkSec > 0 else { return nil }
        let perMETMinute = mlO2PerKgMinPerMET * bodyMassKg / kcalDivisor
        let metMinutes = segments.warmupSec / 60 * warmupMET
            + segments.repWorkSec / 60 * repWorkMET
            + segments.holdWorkSec / 60 * holdWorkMET
            + segments.restSec / 60 * restMET
            + segments.cooldownSec / 60 * cooldownMET
        let net = metMinutes * perMETMinute
            - segments.totalSec / 60 * resting.kcalPerMin
        guard net.isFinite, net > 0 else { return nil }
        return net
    }

    /// The wall clock is a CEILING, never a source. A workout paused, or left
    /// in the background for twenty minutes, bills none of those minutes: its
    /// `durationSec` runs past the plan and the plan wins. A session cut short
    /// really did cost less, so a shorter actual duration scales the plan down
    /// in proportion — gross and resting terms alike, which is why one factor
    /// on the net is the whole correction.
    static func actualityFactor(planSec: Double, actualSec: Int?) -> Double {
        guard let actualSec, planSec > 0, planSec.isFinite else { return 1 }
        let actual = Double(actualSec)
        guard actual.isFinite, actual >= 0 else { return 1 }
        return min(1, actual / planSec)
    }
}
