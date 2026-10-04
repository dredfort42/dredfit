import XCTest
import DredfitCore
@testable import Dredfit

/// The haptic prime before every 3-2-1: once, about a second before its
/// first tick, never with the sounds off and never for a countdown that
/// sounds no 3-2-1. A countdown passing its four is primed by that tick; one
/// that starts on its four, or comes back from standing still with its next
/// signal less than a second away, is primed where it starts or comes back.
extension WorkoutSessionTests {

    /// The second a countdown shows one second before its 3.
    private var primedAt: Int { WorkoutSession.countdownSignalSeconds + 1 }

    /// The warm-up, standing on the first stage of its first position.
    private func warmupOnItsFirstPosition() -> WorkoutSession {
        let flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow, until: { flow.warmup.stage != .getReady })
        return flow
    }

    /// The warm-up, at the start of the first transition no tap opened.
    private func warmupOnItsSecondTransition() -> WorkoutSession {
        let flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow, until: { flow.warmup.index == 1 })
        return flow
    }

    /// The warm-up, at the start of the first half of a split move.
    private func warmupOnASplitMove() -> WorkoutSession {
        let flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow, until: { flow.warmup.stage == .firstHalf })
        return flow
    }

    /// An ordinary rest, left for the background with half a minute on it.
    private func restLeftAtThirty(_ store: AppStore) -> WorkoutSession {
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        run(flow, until: { flow.restClock.remaining == 30 })
        flow.sceneLeft()
        return flow
    }

    // MARK: - The way back into a paused position

    func testTheWayBackInIsPrimedOnceASecondBeforeItsFirstTick() {
        let flow = warmupOnItsFirstPosition()
        run(flow, for: 3)
        flow.toggleBlockPause()
        clock += 120
        signals.primes = 0
        signals.events.removeAll()

        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isReentering, "the premise")
        XCTAssertEqual(signals.primes, 1, "the way back in starts on its four, after a pause of any length")
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testALongerWayBackInIsPrimedAtItsFourNotAtItsStart() {
        let flow = warmupOnItsFirstPosition()
        flow.toggleBlockPause()
        signals.primes = 0
        // No path opens one: the way back in is the count-in's four seconds.
        // A longer one must not lose its prime to its length.
        flow.blockPause.beginReentry(seconds: primedAt + 3, now: clock)
        run(flow, until: { flow.blockPause.reentryRemaining == primedAt + 1 })
        XCTAssertEqual(signals.primes, 0, "primed at its start, it would be cold by the 3")
        run(flow, for: 1)
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { !flow.blockPause.isPaused })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    // MARK: - The guided blocks' own clocks

    func testAStartTapOpensTheTransitionOnItsFourPrimed() {
        let flow = makeFlow(makeStore())
        signals.primes = 0
        flow.beginWarmup()
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds, "the premise")
        XCTAssertEqual(signals.primes, 1, "no tick reports the second a countdown starts on")
        signals.events.removeAll()
        run(flow, until: { flow.warmup.stage != .getReady })
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testATransitionNoTapOpenedIsPrimedAtItsFourAndOnlyThere() {
        let flow = warmupOnItsSecondTransition()
        XCTAssertEqual(flow.warmup.stage, .getReady, "the premise")
        signals.primes = 0
        run(flow, until: { flow.warmup.clock.remaining == primedAt + 1 })
        XCTAssertEqual(signals.primes, 0, "opened on a done eight seconds out or more, it is cold by the 3")
        run(flow, for: 1)
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { flow.warmup.stage != .getReady })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testImReadyCutsTheTransitionToItsFourPrimed() {
        let flow = warmupOnItsSecondTransition()
        run(flow, until: { flow.warmup.clock.remaining == primedAt + 2 })
        signals.primes = 0
        signals.events.removeAll()

        flow.countIn(.warmup)
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds, "the premise")
        XCTAssertEqual(signals.primes, 1, "no tick reports the second a countdown starts on")
        run(flow, until: { flow.warmup.stage != .getReady })
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testAPositionIsPrimedAtItsFourAndOnlyThere() {
        let flow = warmupOnItsFirstPosition()
        let stage = flow.warmup.stage
        signals.primes = 0
        run(flow, until: { flow.warmup.clock.remaining == primedAt + 1 })
        XCTAssertEqual(signals.primes, 0, "opened on a go fifteen seconds out or more, it is cold by the 3")
        run(flow, for: 1)
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { flow.warmup.stage != stage })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testTheSwitchPauseIsNeverPrimed() {
        let flow = warmupOnASplitMove()
        run(flow, until: { flow.warmup.clock.remaining == 1 })
        signals.primes = 0
        run(flow, until: { flow.warmup.stage == .secondHalf })
        XCTAssertEqual(signals.primes, 0, "the switch pause sounds no 3-2-1: its ticks would bury the switch tone")
    }

    func testALongerSwitchPauseIsNeverPrimedEither() {
        let flow = warmupOnASplitMove()
        // No split move pauses longer than the count-in; one that did would
        // pass its four with nothing to prime for.
        flow.enterStage(index: flow.warmup.index, stage: .switchPause, remaining: primedAt + 3, of: .warmup)
        signals.primes = 0
        run(flow, until: { flow.warmup.stage == .secondHalf })
        XCTAssertEqual(signals.primes, 0)
    }

    // MARK: - The hold's own clock

    func testAHoldsOwnLastSecondsArePrimedAtItsFour() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, until: { flow.holding })
        signals.primes = 0
        signals.events.removeAll()
        run(flow, until: { flow.holdClock.remaining == primedAt + 1 })
        XCTAssertEqual(signals.primes, 0, "the go a whole set earlier is the last impulse before it")
        run(flow, for: 1)
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { !flow.holding })
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .done])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testTheSecondSideIsPrimedAtItsOwnFour() throws {
        let (flow, _) = try holdFlow(.coreRot)
        flow.startHold()
        run(flow, until: { flow.holdSwitchPausing })
        signals.primes = 0
        run(flow, until: { flow.holding })
        XCTAssertEqual(signals.primes, 0, "the switch pause sounds no 3-2-1")
        run(flow, until: { flow.holdClock.remaining == primedAt + 1 })
        XCTAssertEqual(signals.primes, 0)
        run(flow, for: 1)
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { !flow.holding })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    // MARK: - A countdown that stood still

    func testARestReadAboutOnItsFourIsPrimedWhenTheSheetCloses() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, until: { flow.restStartsTheNextSet })
        run(flow, until: { flow.restClock.remaining == primedAt })
        flow.freezeRestForTechnique()
        clock += 120
        signals.primes = 0
        signals.events.removeAll()

        flow.resumeRestCountdown()
        XCTAssertEqual(signals.primes, 1, "two minutes on the technique page let the engine go cold")
        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testARestReadAboutWithTimeLeftIsPrimedOnlyAtItsFour() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, until: { flow.restStartsTheNextSet })
        run(flow, until: { flow.restClock.remaining == 30 })
        flow.freezeRestForTechnique()
        clock += 120
        signals.primes = 0

        flow.resumeRestCountdown()
        XCTAssertEqual(signals.primes, 0, "thirty seconds out, a prime would be cold again by the 3")
        run(flow, until: { flow.restClock.remaining == primedAt })
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testATransitionReadAboutInItsLastSecondsIsPrimedWhenTheSheetCloses() {
        let flow = warmupOnItsSecondTransition()
        run(flow, until: { flow.warmup.clock.remaining == 2 })
        flow.freezeForPositionTechnique()
        clock += 120
        signals.primes = 0
        signals.events.removeAll()

        flow.resumePositionCountdown()
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { flow.warmup.stage != .getReady })
        XCTAssertEqual(signals.tones, [.tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testTheWayBackInReadAboutIsPrimedWhenTheSheetCloses() {
        let flow = warmupOnItsFirstPosition()
        flow.toggleBlockPause()
        flow.toggleBlockPause()
        run(flow, for: 1)
        XCTAssertTrue(flow.blockPause.isReentering, "the premise")
        flow.freezeForPositionTechnique()
        clock += 120
        signals.primes = 0
        signals.events.removeAll()

        flow.resumePositionCountdown()
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { !flow.blockPause.isPaused })
        XCTAssertEqual(signals.tones, [.tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testAHeldBlockReadAboutPrimesNothing() {
        let flow = warmupOnItsFirstPosition()
        flow.toggleBlockPause()
        flow.freezeForPositionTechnique()
        clock += 120
        signals.primes = 0

        flow.resumePositionCountdown()
        XCTAssertTrue(flow.blockPause.isHeld, "the premise: the person's pause outranks the sheet")
        XCTAssertEqual(signals.primes, 0, "a held block counts nothing down")
    }

    func testASwitchPauseReadAboutPrimesNothing() {
        let flow = warmupOnASplitMove()
        run(flow, until: { flow.warmup.stage == .switchPause })
        flow.freezeForPositionTechnique()
        clock += 120
        signals.primes = 0

        flow.resumePositionCountdown()
        XCTAssertEqual(signals.primes, 0, "the switch pause sounds no 3-2-1")
    }

    func testATransitionPausedInItsLastSecondsIsPrimedWhenItResumes() {
        let flow = warmupOnItsSecondTransition()
        run(flow, until: { flow.warmup.clock.remaining == 2 })
        flow.toggleBlockPause()
        clock += 120
        signals.primes = 0
        signals.events.removeAll()

        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "the premise: a transition is its own way back in")
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { flow.warmup.stage != .getReady })
        XCTAssertEqual(signals.tones.last, .go)
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testATransitionPausedASecondAboveItsFourIsPrimedOnlyThere() {
        let flow = warmupOnItsSecondTransition()
        run(flow, until: { flow.warmup.clock.remaining == primedAt + 1 })
        flow.toggleBlockPause()
        clock += 120
        signals.primes = 0

        flow.toggleBlockPause()
        XCTAssertEqual(signals.primes, 0, "its four is still ahead, and its tick primes it")
        run(flow, until: { flow.warmup.stage != .getReady })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testACoolDownTransitionPausedInItsLastSecondsIsPrimedWhenItResumes() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow, until: { flow.cooldown.clock.remaining == 2 })
        flow.toggleBlockPause()
        clock += 120
        signals.primes = 0

        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "the premise: a transition is its own way back in")
        XCTAssertEqual(signals.primes, 1)
    }

    // MARK: - Back from the background

    func testAReturnIntoTheLastSecondsOfARestIsPrimed() {
        let flow = restLeftAtThirty(makeStore())
        clock += 28
        signals.primes = 0
        signals.events.removeAll()

        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 1, "the time away let the engine go cold, and the next tick is inside the 3-2-1")
        flow.tick()   // the next tick, a return between two of them
        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(signals.tones, [.tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testTicksHeldBackPastTheFourArePrimedBeforeTheyResume() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.completeSet()
        run(flow, until: { flow.restClock.remaining == 10 })
        // Behind the exit alert no tick runs, while the rest runs on; the
        // timer's beat there asks for the prime instead.
        clock += TimeInterval(10 - primedAt)
        signals.primes = 0
        signals.events.removeAll()

        flow.primeComingBack()
        XCTAssertEqual(signals.primes, 1, "on its four, and the first tick back may already be past it")
        clock += 0.9
        flow.tick()
        XCTAssertEqual(signals.tones, [.tick], "the timer kept its own beat: its next tick lands on the 3")
        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testAReturnASecondAboveTheFourIsPrimedOnlyByItsTick() {
        let flow = restLeftAtThirty(makeStore())
        clock += TimeInterval(30 - primedAt - 1)
        signals.primes = 0

        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 0, "its four is still ahead, and its tick primes it")
        run(flow, until: { flow.restClock.remaining == primedAt })
        XCTAssertEqual(signals.primes, 1)
        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testAGlanceAtControlCenterPrimesNothing() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.completeSet()
        run(flow, until: { flow.restClock.remaining == primedAt - 1 })
        signals.primes = 0
        // Control Center turns the scene inactive and active again without
        // it ever leaving: the rest went on ticking, and its ticks primed it.
        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 0)
    }

    func testAReturnIntoAHoldsLastSecondsIsPrimed() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, until: { flow.holding })
        run(flow, until: { flow.holdClock.remaining == 10 })
        flow.sceneLeft()
        clock += 8
        signals.primes = 0

        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 1)
    }

    func testAReturnIntoACountInIsPrimed() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        flow.sceneLeft()
        clock += 2
        signals.primes = 0

        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 1)
    }

    func testAReturnAfterACountInRanOutPrimesItOnceWhenItStartsOver() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        flow.sceneLeft()
        clock += 30
        signals.primes = 0

        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 0, "it ran out unheard: none of its 3-2-1 is left")
        flow.tick()
        XCTAssertTrue(flow.holdCountingIn, "the premise: a go nobody heard starts it over")
        XCTAssertEqual(signals.primes, 1)
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testAReturnWithTheSoundsOffPrimesNothing() {
        let store = makeStore()
        store.update(refreshWidget: false) { $0.settings.soundsEnabled = false }
        let flow = restLeftAtThirty(store)
        clock += 28

        flow.sceneCameBack()
        XCTAssertEqual(signals.primes, 0, "the haptic is half of a signal the switch has turned off")
    }
}
