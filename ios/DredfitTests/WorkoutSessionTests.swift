import XCTest
import DredfitCore
@testable import Dredfit

/// Every tone and announcement the flow would have made, in order.
@MainActor
final class SignalSpy: WorkoutSignalling {
    enum Event: Equatable {
        case tick, go, switchSides, done, workoutDone, milestone
        case announce(String)
    }
    var events: [Event] = []
    /// The tones alone — announcements are VoiceOver's, not the sounds'.
    var tones: [Event] { events.filter { if case .announce = $0 { return false }; return true } }

    func prime() {}
    func primeSounds() {}
    func tick(_ enabled: Bool) { if enabled { events.append(.tick) } }
    func go(_ enabled: Bool) { if enabled { events.append(.go) } }
    func switchSides(_ enabled: Bool) { if enabled { events.append(.switchSides) } }
    func done(_ enabled: Bool) { if enabled { events.append(.done) } }
    func workoutDone(_ enabled: Bool) { if enabled { events.append(.workoutDone) } }
    func milestone(_ enabled: Bool) { if enabled { events.append(.milestone) } }
    func announce(_ message: String) { events.append(.announce(message)) }
}

/// What the lock-screen tile would have shown.
@MainActor
final class TileSpy: WorkoutActivityDriving {
    var started: RestActivityAttributes.ContentState?
    var updates: [RestActivityAttributes.ContentState] = []
    var ended = 0
    func start(sessionNumber: Int, state: RestActivityAttributes.ContentState) { started = state }
    func update(_ state: RestActivityAttributes.ContentState) { updates.append(state) }
    func end() { ended += 1 }
}

/// The workout flow without its screens: every rule a tap, a tick, a
/// backgrounded phone or a process death runs into. The clock is the test's,
/// so a minute passes in a loop and an absence in one assignment.
@MainActor
final class WorkoutSessionTests: AppStoreTestCase {

    var clock = Date(timeIntervalSince1970: 1_900_000_000)
    let signals = SignalSpy()
    let tile = TileSpy()

    /// A flow already on screen, on `session` or on the one the store would
    /// hand out next.
    func makeFlow(_ store: AppStore, session: Session? = nil,
                  resume: WorkoutSnapshot? = nil, settle: Bool = false) -> WorkoutSession {
        let flow = WorkoutSession(session: session ?? store.nextSession, store: store,
                                  resume: resume, settleImmediately: settle,
                                  liveActivity: tile, signals: signals,
                                  now: { [unowned self] in self.clock })
        flow.appear()
        return flow
    }

    /// `seconds` pass one tick at a time, the way the view's timer runs them.
    func run(_ flow: WorkoutSession, for seconds: Int) {
        for _ in 0..<seconds {
            clock += 1
            flow.tick()
        }
    }

    /// Ticks until `done` holds; fails if it never does.
    @discardableResult
    func run(_ flow: WorkoutSession, until done: () -> Bool, limit: Int = 3_600,
             file: StaticString = #filePath, line: UInt = #line) -> Int {
        var seconds = 0
        while !done() {
            guard seconds < limit else {
                XCTFail("the flow never got there in \(limit) s", file: file, line: line)
                return seconds
            }
            clock += 1
            flow.tick()
            seconds += 1
        }
        return seconds
    }

    /// Session 2 carries the two hold movements: `coreAntiExt` on both sides
    /// at once and `coreRot` per side, three sets of 15 s each.
    func holdSession() -> Session {
        var state = EngineState.initial
        state.counter = 1
        return Engine.generateSession(state)
    }

    func index(of pattern: Pattern, in flow: WorkoutSession) throws -> Int {
        try XCTUnwrap(flow.exercises.firstIndex { $0.pattern == pattern },
                      "\(pattern.rawValue) must be in session \(flow.session.sessionNumber)")
    }

    /// Session 1 with a probe on its first movement: one set of the next
    /// variation in place of the last working set, the way the engine hands
    /// it over.
    func probeSession() throws -> Session {
        let base = Engine.generateSession(.initial)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base))
        var json = try XCTUnwrap(object as? [String: Any])
        var exercises = try XCTUnwrap(json["exercises"] as? [[String: Any]])
        let probe = SessionProbe(variation: 2, name: "Probe move", unit: .reps, load: 6, perSide: false)
        exercises[0]["probe"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(probe))
        exercises[0]["sets"] = 2
        json["exercises"] = exercises
        return try JSONDecoder().decode(Session.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Sets and rests

    func testDoneOnASetRestsAndTheRestHandsOverTheNextSet() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        signals.events.removeAll()

        flow.completeSet()
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(flow.restClock.remaining, 60)
        XCTAssertEqual(store.pendingWorkout?.restEndDate, clock + 60,
                       "a rest is written down the moment it starts")
        XCTAssertEqual(tile.updates.last?.restEndDate, clock + 60)

        run(flow, for: 60)
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertEqual(signals.tones, [.done, .tick, .tick, .tick, .go],
                       "the set's done, the rest's 3-2-1 and its go — nothing twice")
    }

    func testARestIsExtendedUpToTwiceWhatItPlannedAndNoFurther() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        for _ in 0..<10 { flow.extendRest() }
        XCTAssertEqual(flow.phase, .rest(seconds: 120))
        XCTAssertEqual(flow.restClock.remaining, 120)
        XCTAssertFalse(flow.canExtendRest)
    }

    func testTheLastSetRestsForTheExerciseAndOpensTheNextOneWithoutItsDeclaration() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.setIndex = 2
        flow.holdDeclared = 30
        flow.completeSet()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec))

        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(flow.exIndex, 1)
        XCTAssertEqual(flow.setIndex, 0)
        XCTAssertNil(flow.holdDeclared, "a time declared for one movement does not set the next one's clock")
    }

    // MARK: - The adjuster

    func testOKWritesWhatThePanelWasOpenedOnNotWhatWasOpenBefore() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.startDeclaringHoldTime()
        XCTAssertEqual(flow.editing, .holdTime)
        flow.startAdjusting()
        XCTAssertEqual(flow.editing, .set, "the panel's mode is set by whoever opens it")
        flow.adjustValue = 6
        flow.commitSetEdit()
        XCTAssertNil(flow.editing)
        XCTAssertNil(flow.holdDeclared)
        XCTAssertEqual(try XCTUnwrap(flow.actuals[flow.exercise.pattern]).first, 6)
        XCTAssertEqual(store.pendingWorkout?.setActuals?[flow.exercise.pattern]?.first, 6,
                       "an entered number is written down at once")
    }

    func testTheProbesNumberGoesToItsOwnChannel() throws {
        let store = makeStore()
        let flow = makeFlow(store, session: try probeSession())
        flow.declineWarmup()
        flow.setIndex = flow.exercise.sets
        XCTAssertTrue(flow.onProbeSet)
        flow.startAdjusting()
        XCTAssertEqual(flow.adjustValue, 6, "the probe's own target, not the working sets'")
        flow.adjustValue = 7
        flow.commitSetEdit()
        XCTAssertEqual(flow.probeActuals[flow.exercise.pattern], 7)
        XCTAssertNil(flow.actuals[flow.exercise.pattern],
                     "folding the probe into the working sets would average two variations")
    }

    func testDoneOnAProbeNobodyCorrectedRecordsItsTarget() throws {
        let store = makeStore()
        let flow = makeFlow(store, session: try probeSession())
        flow.declineWarmup()
        flow.setIndex = flow.exercise.sets
        flow.completeSet()
        XCTAssertEqual(flow.probeActuals[flow.exercise.pattern], 6)
        XCTAssertNil(flow.actuals[flow.exercise.pattern])
    }

    // MARK: - Skips

    func testSkippingASetCountsItAndOpensTheNext() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.skipSet()
        XCTAssertEqual(flow.setsSkipped[flow.exercise.pattern], 1)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertEqual(flow.phase, .work, "no rest after a set nobody did")
        XCTAssertEqual(store.pendingWorkout?.setIndex, 1)
    }

    func testSkippingTheLastSetLeftTakesItAndMovesOn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        let pattern = flow.exercise.pattern
        flow.setIndex = 2
        flow.skipRestOfExercise()
        XCTAssertEqual(flow.setsSkipped[pattern], 1)
        XCTAssertFalse(flow.skippedPatterns.contains(pattern), "two sets were done: the movement was trained")
        XCTAssertEqual(flow.exIndex, 1)
    }

    func testASkipThatWouldLeaveTooFewSetsTakesTheWholeMovement() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        let pattern = flow.exercise.pattern
        flow.setIndex = 1
        flow.skipRestOfExercise()
        XCTAssertTrue(flow.skippedPatterns.contains(pattern))
        XCTAssertNil(flow.setsSkipped[pattern])
        XCTAssertEqual(flow.exIndex, 1)
    }

    func testLeavingAnExerciseErasesWhatItRecorded() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        let pattern = flow.exercise.pattern
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.leaveExercise()
        XCTAssertNil(flow.actuals[pattern], "a skip wins over an actual")
        XCTAssertTrue(flow.skippedPatterns.contains(pattern))
        XCTAssertEqual(flow.exIndex, 1)
        XCTAssertEqual(flow.phase, .work)
    }

    func testLeavingTheLastExerciseOffersTheCoolDown() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.leaveExercise()
        XCTAssertEqual(flow.phase, .cooldownIntro)
        XCTAssertEqual(store.pendingWorkout?.atFeedback, true,
                       "with the work behind, a process death restores onto the rating")
    }

    // MARK: - Finish now

    func testFinishNowInsideAMovementCallsItNotFinished() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        let first = flow.exercise.pattern
        flow.completeSet()
        flow.skipRest()
        flow.finishNow()
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertEqual(flow.interruptedPattern, first)
        XCTAssertEqual(flow.skippedPatterns, Set(flow.exercises.map(\.pattern)),
                       "the half-done movement is a skip to the engine too; the label is the difference")
        XCTAssertEqual(tile.ended, 1)
    }

    func testFinishNowInTheRestAfterALastSetCountsThatMovementDone() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        let first = flow.exercise.pattern
        flow.setIndex = 2
        flow.completeSet()
        flow.finishNow()
        XCTAssertNil(flow.interruptedPattern)
        XCTAssertFalse(flow.skippedPatterns.contains(first))
        XCTAssertEqual(flow.skippedPatterns.count, flow.exercises.count - 1)
    }

    // MARK: - The rating

    func testTheRatingIsToldTheWorkoutLessTheTimeAway() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        clock += 600
        flow.sceneLeft()
        clock += 1_200
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 1_200)
        flow.finishNow()
        _ = flow.rate(.plan, overrides: [:])
        XCTAssertEqual(try XCTUnwrap(store.records.last).durationSec, 600)
        XCTAssertNil(store.pendingWorkout, "a rated workout leaves nothing to resume")
    }
}
