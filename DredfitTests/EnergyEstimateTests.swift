import XCTest
import DredfitCore
@testable import Dredfit

/// The calorie model, pinned to arithmetic rather than to "about right".
///
/// A calorie estimate is the one number in this app nobody can check by
/// looking: in Health it reads exactly like a measured one. So every constant
/// here is asserted against a hand-computed figure, and the resting ladder is
/// asserted by WHICH rung answered — three rungs that all return something
/// plausible are indistinguishable from a ladder that never degrades.
final class EnergyEstimateTests: XCTestCase {

    /// 35 minutes: 5 warm-up, 9 of repetitions, 17 of rest, 4 of cool-down.
    /// The warm-up and cool-down are literals ON PURPOSE — the sentinel that
    /// they follow the engine is `testSegmentsReadTheEngineSBlockLengths`, and
    /// an arithmetic pin that moves with the config pins nothing.
    private let control = SessionSegments(warmupSec: 300, repWorkSec: 540,
                                          holdWorkSec: 0, restSec: 1020,
                                          cooldownSec: 240)
    private let kg = 80.0

    private func standardResting(_ kg: Double) -> RestingRate {
        EnergyEstimate.resting(basalKcal: nil, minutes: 35,
                               bodyMassKg: kg, profile: .unknown)
    }

    // MARK: - The number itself

    /// Gross = (5x3.5 + 9x6.0 + 17x1.8 + 4x2.3) MET-minutes x 3.5 x 80 / 200
    ///       = 111.3 x 1.4 = 155.82 kcal.
    /// Resting at one standard MET = 1.4 kcal/min x 35 = 49 kcal.
    func testControlSessionAtEightyKilograms() throws {
        let kcal = try XCTUnwrap(EnergyEstimate.activeKcal(control, bodyMassKg: kg,
                                                           resting: standardResting(kg)))
        XCTAssertEqual(kcal, 155.82 - 49, accuracy: 0.01)
    }

    /// The whole point of subtracting a resting term: writing the gross figure
    /// would inflate this session by 46 %, and Health would show it as fact.
    func testRestingIsSubtractedNotIgnored() throws {
        let kcal = try XCTUnwrap(EnergyEstimate.activeKcal(control, bodyMassKg: kg,
                                                           resting: standardResting(kg)))
        XCTAssertLessThan(kcal, 155.82 * 0.75,
                          "an estimate that ignores rest lands near the gross figure")
    }

    /// Mifflin for a 30-year-old man of 180 cm and 80 kg: 1780 kcal/day, so
    /// 43.26 over the 35 minutes — six kcal less than the constant subtracts.
    func testMifflinRestingChangesTheAnswer() throws {
        let profile = BodyProfile(heightCm: 180, ageYears: 30, sex: .male)
        let resting = EnergyEstimate.resting(basalKcal: nil, minutes: 35,
                                             bodyMassKg: kg, profile: profile)
        XCTAssertEqual(resting.source, .mifflin)
        let kcal = try XCTUnwrap(EnergyEstimate.activeKcal(control, bodyMassKg: kg,
                                                           resting: resting))
        XCTAssertEqual(kcal, 155.82 - 1780.0 / 1440 * 35, accuracy: 0.01)
    }

    /// Weight is the one factor the whole estimate scales by, and it scales
    /// both terms — so twice the body is exactly twice the number.
    func testTheEstimateIsLinearInBodyMass() throws {
        let light = try XCTUnwrap(EnergyEstimate.activeKcal(control, bodyMassKg: 60,
                                                            resting: standardResting(60)))
        let heavy = try XCTUnwrap(EnergyEstimate.activeKcal(control, bodyMassKg: 120,
                                                            resting: standardResting(120)))
        XCTAssertEqual(heavy, light * 2, accuracy: 0.01)
    }

    func testAnImpossibleBodyMassYieldsNothing() {
        for mass in [0.0, -80.0, .nan, .infinity] {
            XCTAssertNil(EnergyEstimate.activeKcal(control, bodyMassKg: mass,
                                                   resting: standardResting(80)),
                         "\(mass) kg is not a body")
        }
    }

    /// A hand-edited journal can produce a negative rest — the decode of
    /// `SessionExercise` clamps nothing. Duration survives that on its own
    /// final clamp; a calorie count must refuse instead of inventing one.
    func testAnImplausibleSegmentationYieldsNothing() {
        var broken = control
        broken.restSec = -600
        XCTAssertNil(EnergyEstimate.activeKcal(broken, bodyMassKg: kg,
                                               resting: standardResting(kg)))
    }

    /// Same seconds under load, less energy: a hold has no concentric phase.
    func testHoldsCostLessThanRepetitionsForTheSameSeconds() throws {
        var dynamic = control
        dynamic.repWorkSec = 600
        var isometric = control
        isometric.repWorkSec = 0
        isometric.holdWorkSec = 600
        let moving = try XCTUnwrap(EnergyEstimate.activeKcal(dynamic, bodyMassKg: kg,
                                                             resting: standardResting(kg)))
        let holding = try XCTUnwrap(EnergyEstimate.activeKcal(isometric, bodyMassKg: kg,
                                                              resting: standardResting(kg)))
        XCTAssertLessThan(holding, moving)
    }

    // MARK: - The resting ladder

    /// Apple's own figure for this person beats the population formula, which
    /// beats the constant every textbook applies to everybody.
    func testTheRestingLadderPrefersHealthThenFormulaThenConstant() {
        let full = BodyProfile(heightCm: 180, ageYears: 30, sex: .male)
        let fromHealth = EnergyEstimate.resting(basalKcal: 42, minutes: 35,
                                                bodyMassKg: kg, profile: full)
        XCTAssertEqual(fromHealth.source, .healthBasal)
        XCTAssertEqual(fromHealth.kcalPerMin, 1.2, accuracy: 0.0001)

        XCTAssertEqual(EnergyEstimate.resting(basalKcal: nil, minutes: 35,
                                              bodyMassKg: kg, profile: full).source,
                       .mifflin)
        XCTAssertEqual(EnergyEstimate.resting(basalKcal: nil, minutes: 35,
                                              bodyMassKg: kg, profile: .unknown).source,
                       .standardMET)
    }

    /// A watch that was not on the wrist reports a sum, not a refusal — and a
    /// sum of five kcal over half an hour is a hole in the data, not a body.
    func testAnImplausibleBasalSumFallsThroughToTheNextRung() {
        let full = BodyProfile(heightCm: 180, ageYears: 30, sex: .male)
        XCTAssertEqual(EnergyEstimate.resting(basalKcal: 5, minutes: 35,
                                              bodyMassKg: kg, profile: full).source,
                       .mifflin)
        XCTAssertEqual(EnergyEstimate.resting(basalKcal: 5000, minutes: 35,
                                              bodyMassKg: kg, profile: .unknown).source,
                       .standardMET)
    }

    /// Half a profile is not a profile: Mifflin needs both the height and the
    /// age, and missing either drops to the constant rather than guessing one.
    func testAPartialProfileDoesNotReachTheFormula() {
        for profile in [BodyProfile(heightCm: 180, ageYears: nil, sex: .male),
                        BodyProfile(heightCm: nil, ageYears: 30, sex: .male)] {
            XCTAssertEqual(EnergyEstimate.resting(basalKcal: nil, minutes: 35,
                                                  bodyMassKg: kg, profile: profile).source,
                           .standardMET)
        }
    }

    /// The two published equations differ by one constant. An unset or
    /// non-binary answer takes their mean — defaulting to the male form would
    /// be a claim about the person, not an admission of not knowing.
    func testAnUnstatedSexTakesTheMeanOfBothEquations() throws {
        let male = try XCTUnwrap(EnergyEstimate.mifflinKcalPerMin(kg: kg, cm: 180,
                                                                  age: 30, sex: .male))
        let female = try XCTUnwrap(EnergyEstimate.mifflinKcalPerMin(kg: kg, cm: 180,
                                                                    age: 30, sex: .female))
        for unstated: BodySex? in [BodySex.other, nil] {
            let mean = try XCTUnwrap(EnergyEstimate.mifflinKcalPerMin(kg: kg, cm: 180,
                                                                      age: 30, sex: unstated))
            XCTAssertEqual(mean, (male + female) / 2, accuracy: 0.000_001)
        }
        XCTAssertNotEqual(male, female, "the sex term must actually do something")
    }

    // MARK: - Segmentation

    private func exercise(_ pattern: Pattern, unit: LoadUnit = .reps, load: Int,
                          perSide: Bool = false, sets: Int,
                          restSetSec: Int = 60, restExerciseSec: Int = 60) -> SessionExercise {
        SessionExercise(pattern: pattern, name: "x", variation: 1, unit: unit,
                        load: load, perSide: perSide, sets: sets,
                        restSetSec: restSetSec, restExerciseSec: restExerciseSec,
                        loads: nil, probe: nil)
    }

    /// A record from before the flow measured its blocks: the plan stands in,
    /// which is the only honest fallback and also the old behaviour.
    private func segments(_ exercises: [SessionExercise], skipped: Set<Pattern> = [],
                          warmupSec: Int? = nil, cooldownSec: Int? = nil) throws -> SessionSegments {
        try XCTUnwrap(EnergyEstimate.segments(exercises: exercises, skipped: skipped,
                                              warmupSec: warmupSec, cooldownSec: cooldownSec))
    }

    /// The one guard that catches a warm-up or cool-down copied as a literal:
    /// the two used to be spelled 5 and 3 here while the engine had moved the
    /// cool-down to 4, and the extra minute went to Health unnoticed.
    func testSegmentsReadTheEngineSBlockLengths() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)])
        XCTAssertEqual(seg.warmupSec, Double(EngineConfig.warmupMin * 60))
        XCTAssertEqual(seg.cooldownSec, Double(EngineConfig.cooldownMin * 60))
    }

    /// 3 sets x 10 reps x 2.5 s of work; 2 rests between sets plus one after
    /// the exercise. Per-side doubles the work and nothing else.
    func testSegmentsCountWorkRestAndSides() throws {
        let plain = try segments([exercise(.squat, load: 10, sets: 3,
                                           restSetSec: 60, restExerciseSec: 90)])
        XCTAssertEqual(plain.repWorkSec, 3 * 10 * 2.5)
        XCTAssertEqual(plain.restSec, 2 * 60 + 90)

        let sided = try segments([exercise(.lunge, load: 10, perSide: true, sets: 3,
                                           restSetSec: 60, restExerciseSec: 90)])
        XCTAssertEqual(sided.repWorkSec, plain.repWorkSec * 2)
        XCTAssertEqual(sided.restSec, plain.restSec)
    }

    /// A hold's dose IS its seconds, and it lands in its own segment — the
    /// whole reason a plank does not get charged at a push-up's rate.
    func testHoldsLandInTheirOwnSegment() throws {
        let seg = try segments([exercise(.coreAntiExt, unit: .hold, load: 30, sets: 3)])
        XCTAssertEqual(seg.holdWorkSec, 90)
        XCTAssertEqual(seg.repWorkSec, 0)
    }

    func testASkippedExerciseIsNotCharged() throws {
        let exercises = [exercise(.squat, load: 10, sets: 3),
                         exercise(.pushH, load: 10, sets: 3)]
        let whole = try segments(exercises)
        let partial = try segments(exercises, skipped: [.pushH])
        XCTAssertLessThan(partial.totalSec, whole.totalSec)
        XCTAssertEqual(partial.repWorkSec, whole.repWorkSec / 2)
    }

    /// A record written before the exercise snapshot existed cannot be priced
    /// from its rating alone.
    func testNoExercisesMeansNoSegmentation() {
        XCTAssertNil(EnergyEstimate.segments(exercises: [], skipped: [],
                                             warmupSec: nil, cooldownSec: nil))
    }

    // MARK: - Blocks that did not happen

    /// Both blocks end on one tap of a footer button. Charging their planned
    /// minutes anyway billed 9 minutes — 27 % of a median session — to a
    /// person who may have declined both.
    func testDeclinedBlocksAreNotCharged() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)],
                               warmupSec: 0, cooldownSec: 0)
        XCTAssertEqual(seg.warmupSec, 0)
        XCTAssertEqual(seg.cooldownSec, 0)
    }

    func testAPartlyDoneBlockIsChargedForWhatItRan() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)],
                               warmupSec: 120, cooldownSec: 60)
        XCTAssertEqual(seg.warmupSec, 120)
        XCTAssertEqual(seg.cooldownSec, 60)
    }

    /// The plan is the ceiling, mirroring what the wall clock is for the
    /// session: a block runs long for reasons that are not effort — a
    /// technique sheet, a pause for the doorbell.
    func testABlockCannotBillMoreThanItsPlan() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)],
                               warmupSec: 99 * 60, cooldownSec: 99 * 60)
        XCTAssertEqual(seg.warmupSec, Double(EngineConfig.warmupMin * 60))
        XCTAssertEqual(seg.cooldownSec, Double(EngineConfig.cooldownMin * 60))
    }

    /// A corrupt negative reads as "not performed", never as a credit that
    /// shortens the session below zero.
    func testANegativeBlockMeasurementReadsAsZero() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)],
                               warmupSec: -600, cooldownSec: -1)
        XCTAssertEqual(seg.warmupSec, 0)
        XCTAssertEqual(seg.cooldownSec, 0)
    }

    /// No work, no calorie. This session used to be priced at 24.8 kcal on the
    /// standard rung — the lowest figure in the whole golden fixture, for a
    /// workout in which nothing was performed.
    func testASessionWithNoWorkPerformedYieldsNoCalorie() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)], skipped: [.squat])
        XCTAssertGreaterThan(seg.totalSec, 0, "the blocks still took time")
        XCTAssertNil(EnergyEstimate.activeKcal(seg, bodyMassKg: kg,
                                               resting: standardResting(kg)),
                     "a workout entry claiming calories for no work is a claim about "
                     + "training that did not happen")
    }

    /// The rule is about WORK, not about the blocks: a session that did its
    /// exercises and declined both blocks still costs something.
    func testWorkWithoutBlocksStillCosts() throws {
        let seg = try segments([exercise(.squat, load: 10, sets: 3)],
                               warmupSec: 0, cooldownSec: 0)
        XCTAssertNotNil(EnergyEstimate.activeKcal(seg, bodyMassKg: kg,
                                                  resting: standardResting(kg)))
    }

    // MARK: - The wall clock as a ceiling

    func testAPausedSessionDoesNotBillThePause() {
        XCTAssertEqual(EnergyEstimate.actualityFactor(planSec: 2100, actualSec: 4200), 1)
        XCTAssertEqual(EnergyEstimate.actualityFactor(planSec: 2100, actualSec: nil), 1)
    }

    func testASessionCutShortCostsLess() {
        XCTAssertEqual(EnergyEstimate.actualityFactor(planSec: 2100, actualSec: 1050),
                       0.5, accuracy: 0.000_001)
    }

    /// A wall clock moved backwards leaves a negative duration; the plan wins
    /// rather than the estimate collapsing to zero.
    func testACorruptDurationLeavesThePlanAlone() {
        XCTAssertEqual(EnergyEstimate.actualityFactor(planSec: 2100, actualSec: -600), 1)
    }

    // MARK: - What a block ending resolves to

    /// The distinction the whole model turns on: a declined block is ZERO, an
    /// unmeasured one is nil. Zero bills nothing; nil falls back to the plan.
    func testADeclinedBlockResolvesToZeroNotToUnknown() {
        XCTAssertEqual(BlockRun.seconds(began: nil, ended: Date(timeIntervalSince1970: 1000)), 0)
    }

    func testABlockResolvesToTheSecondsItRan() {
        let began = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(BlockRun.seconds(began: began, ended: began.addingTimeInterval(185)), 185)
    }

    /// A wall clock moved backwards mid-block must not produce a negative
    /// length, which would shorten the session it is added to.
    func testABackwardsClockResolvesToZero() {
        let began = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(BlockRun.seconds(began: began, ended: began.addingTimeInterval(-90)), 0)
    }

    // MARK: - The revision, and what obliges it to move

    /// A version stamp nobody is forced to raise is worse than none: it goes
    /// on asserting that today's calorie came out of yesterday's model. This
    /// test is that force. It pins every number the estimate is made of, and
    /// the figure they produce together — so ANY change to the model lands
    /// here first, with instructions.
    ///
    /// If this fails and the change was deliberate: bump
    /// `EnergyEstimate.modelRevision`, then update the numbers below.
    func testTheModelConstantsArePinnedToTheRevision() throws {
        let bump = "the model changed — bump EnergyEstimate.modelRevision, then update this test"
        XCTAssertEqual(EnergyEstimate.modelRevision, 1, bump)
        XCTAssertEqual(EnergyEstimate.secondsPerRep, 2.5, bump)
        XCTAssertEqual([EnergyEstimate.warmupMET, EnergyEstimate.repWorkMET,
                        EnergyEstimate.holdWorkMET, EnergyEstimate.restMET,
                        EnergyEstimate.cooldownMET],
                       [3.5, 6.0, 4.0, 1.8, 2.3], bump)
        XCTAssertEqual(EnergyEstimate.plausibleRestingKcalPerMin, 0.5...3.0, bump)
        XCTAssertEqual(EnergyEstimate.standardRestingKcalPerMin(kg: 80), 1.4, accuracy: 0.000_001,
                       bump)
        // The PRICING in one number: a rearranged `activeKcal` — the resting
        // term dropped, a segment weighted differently — moves it even when
        // every constant above still reads the same. It does NOT cover
        // `segments` itself, which builds no part of this literal; that is
        // what the segmentation tests above are for. Both halves have to move
        // the revision, and only one of them can be pinned here.
        let kcal = try XCTUnwrap(EnergyEstimate.activeKcal(control, bodyMassKg: kg,
                                                           resting: standardResting(kg)))
        XCTAssertEqual(kcal, 106.82, accuracy: 0.01, bump)
    }
}
