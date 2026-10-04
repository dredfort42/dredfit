//
//  The workout flow apart from its screens: warm-up > work > rest > … >
//  cool-down > rating. Every countdown is wall-clock based (an end date, not a
//  tick count), so locking the phone loses nothing.
//
//  The view renders this and forwards taps. Nothing here imports SwiftUI, so
//  what a tap, a tick or a process death does can be driven from a unit test;
//  what the flow needs from the device — the clock, the tones, the
//  lock-screen tile, motion — is handed in. What the screens make of it
//  (which escape is offered, which number is the big one) stays in the view.
//
//  Split by what each part of the flow does: +Sets, +Rest, +Holds, +Summary,
//  +Skips, +Warmup, +Cooldown, +Blocks, +BlockPause, +Snapshot. Swift's
//  `private` is file-scoped, so the state those files share is internal; only
//  this type writes it. The view writes `adjustValue` through the panel and
//  hands in `animator` and `reduceMotion`, nothing else.
//

import Foundation
import Observation
import DredfitCore

@MainActor
@Observable
final class WorkoutSession {
    let session: Session
    let store: AppStore
    let liveActivity: any WorkoutActivityDriving
    let signals: any WorkoutSignalling
    let now: () -> Date
    /// The snapshot this flow picks up from, read once by `appear`.
    private let resume: WorkoutSnapshot?
    /// Open straight on the rating, cataloguing whatever is unfinished — the
    /// answer to "keep this workout?" on Today. The athlete says how it went
    /// themselves; nothing is rated on their behalf inside the day.
    private let settleImmediately: Bool

    /// The motions the flow asks for. The view turns them into animations;
    /// with Reduce Motion on, none is asked for at all.
    enum Motion {
        /// The digit roll every countdown shares, and the rest ring's sweep.
        case countdown
        /// The note about an all-out set sliding up.
        case note
    }

    /// SwiftUI's `withAnimation`, handed in by the view; nil means no motion.
    /// A plain call by default, which is what a test needs.
    @ObservationIgnored var animator: (Motion?, () -> Void) -> Void = { _, change in change() }
    /// Reduce Motion as the view reads it from its environment. Not a question
    /// of taste on these screens: the countdowns roll their digits and the rest
    /// ring sweeps under them, which is the movement the setting stops.
    @ObservationIgnored var reduceMotion = false

    init(session: Session,
         store: AppStore,
         resume: WorkoutSnapshot?,
         settleImmediately: Bool,
         liveActivity: any WorkoutActivityDriving,
         signals: any WorkoutSignalling,
         now: @escaping () -> Date) {
        self.session = session
        self.store = store
        self.resume = resume
        self.settleImmediately = settleImmediately
        self.liveActivity = liveActivity
        self.signals = signals
        self.now = now
    }

    enum Phase: Equatable {
        /// The warm-up does not start itself. Being dropped straight into a
        /// countdown nobody agreed to is how a block gets skipped by walking
        /// away rather than by saying so — and the answer "I am already warm"
        /// is a real one. Offered, never required; the same two answers as the
        /// cool-down.
        case warmupIntro
        case warmup
        case work
        case rest(seconds: Int)
        /// Every set of a hold movement on one screen, the last one a tap from
        /// being corrected — a hold ends itself, and nothing about the
        /// movement comes back after its last set (`finishHold`).
        ///
        /// Only after a hold movement, and only when it is behind — its probe
        /// set, when it has one, comes first on a screen of its own. Sets of
        /// reps are logged by the tap that ends them.
        case exerciseSummary
        /// The cool-down does not start itself. The work is behind, and being
        /// dropped straight into a stretch nobody asked for is how a block
        /// gets skipped by walking away instead of by saying so. One screen,
        /// two answers, and both are fine.
        case cooldownIntro
        case cooldown                 // between the last exercise and the rating
        case feedback
        case milestone([Milestone])   // only when the workout earned one
    }

    /// What the adjuster panel is open on. One value, set by whoever opens
    /// the panel and cleared with it, so what OK writes depends neither on
    /// what the screen looks like when it is tapped nor on a mode an earlier
    /// panel left behind.
    enum EditTarget: Equatable {
        /// The set under way: its record, or the probe's number.
        case set
        /// How long this hold exercise will run — a target, not a record.
        case holdTime
        /// A card of the exercise summary: the set that was tapped, not the
        /// set the flow is on.
        case summaryCard(Int)
    }

    var exIndex = 0

    var setIndex = 0          // 0-based

    var phase: Phase = .warmupIntro

    /// Where each guided block stands: its position, the stage of it, and one
    /// clock for every stage — so nothing new has to survive backgrounding.
    var warmup = GuidedBlockRun()
    var cooldown = GuidedBlockRun()

    // Computed on entry — the composition depends on what was performed — and
    // recomposed only when the athlete sets a position aside or brings one
    // back (`rebaseCooldownOnComposition`).
    var cooldownPositions: [CooldownPosition] = []

    // The pause of the guided blocks (issue #61) and of a hands-free rest.
    // One for all three: they never run at once. Held, the frozen seconds
    // stand in the stage's own clock and no end date exists anywhere;
    // re-entering, only this moves.
    var blockPause = BlockPause.State()

    var restClock = Countdown()

    /// What this transition planned, kept because the phase carries the
    /// current total and the extension cap is twice the PLANNED one.
    var restPlanned = 0

    /// A fact belongs to the set it happened on — see SetFacts for the shape
    /// and for what a set of them collapses to.
    var actuals: SetFacts.PerSet = [:]

    /// Sets skipped along the way, per movement. Accumulated here, beside the
    /// per-set facts and for the same length of time — the session — and
    /// handed to the engine only when the rating lands: the cut belongs on the
    /// RESULT of the feedback, never on its input.
    var setsSkipped: SetFacts.Skips = [:]

    /// What the PROBE set showed, per movement. Kept apart from
    /// `actuals` on purpose and for the same reason the engine keeps `probes`
    /// apart from `overrides`: the probe is a different exercise, and folding
    /// its number into the mean of the working sets would average two
    /// variations. It reaches the engine through its own argument.
    var probeActuals: [Pattern: Int] = [:]

    /// Steps added "for next time" on the summary of a finished hold, per
    /// movement. A DECISION, not a fact: it never touches `actuals` and
    /// reaches the engine through its own argument, landed after the rating.
    /// Kept for the session like the facts are, and carried across a process
    /// death for the same reason the declared time is — coming back without
    /// it would undo a choice already made on screen.
    var raisedSteps: [Pattern: Int] = [:]

    var skippedPatterns: Set<Pattern> = []

    var editing: EditTarget?

    /// Movements this session has already been warned about. Once per exercise
    /// — a second copy of the same advice is nagging.
    var maximumNoted: Set<Pattern> = []

    var maximumWarning: String?

    var adjustValue = 0

    var workoutStart: Date?   // actual duration for Health

    /// Seconds spent away across resumes, subtracted from the duration
    /// Health is told about. Wall clock alone would charge the break to the
    /// workout.
    var awaySec = 0

    /// The moment the scene left, while the process lives on (`sceneLeft`).
    var absence = SetFacts.Absence()

    /// The two guided blocks, measured rather than assumed. `*BeganAt` is the
    /// moment the person said yes; `*Sec` is what the block cost once it
    /// ended, and it stays nil only while the block has not ended yet. A
    /// declined block never gets a `BeganAt` and resolves to ZERO — which is
    /// the whole point: its planned minutes must not be billed to Health when
    /// nobody stretched.
    var warmupBeganAt: Date?

    var warmupSec: Int?

    var cooldownBeganAt: Date?

    var cooldownSec: Int?

    /// Seconds a guided block STOOD STILL — a pause, an open technique sheet,
    /// or the absence a tick found on its way into one. `warmupSec` and
    /// `cooldownSec` are wall clock (`BlockRun.seconds`), so without this a
    /// warm-up paused for a phone call would bill the call to the warm-up and
    /// tell Health the person stretched through it. One pair for both blocks:
    /// they never run at once, and each block resets the pair when it begins.
    var blockPausedSec = 0

    var blockFrozenAt: Date?

    /// Labelled "not finished" on the rating screen; to the engine it is a
    /// skip like any other. Kept apart from `skippedPatterns`: the engine
    /// treats both as skips for the session, but the rating and the history
    /// say different things.
    var interruptedPattern: Pattern?

    /// One-shot guard: sheets presented over the flow can make onAppear fire
    /// more than once.
    var didStart = false

    // Per-side holds run the countdown twice; the actual is the smaller of
    // the two — the honest bottleneck.
    var holdClock = Countdown()

    var holdTotal = 0

    var holdSecondSide = false

    var firstSideHeld: Int?

    // The second side starts itself — no tap, with hands busy in a plank.
    var holdSwitchClock = Countdown()

    // The count-in "Start hold" earns before the clock runs
    // (GetReady.countInSeconds). Its own clock rather than a stage flag on the
    // hold's: the hold's total must already stand while this counts, so that
    // the go can start it without recomputing anything.
    var holdCountInClock = Countdown()

    /// The PROBE set of a hold movement is over and its seconds are
    /// recorded, but the set is not closed yet — `finishHold` stops there and
    /// the primary button finishes the job. A hold ends itself, so without
    /// this the number would leave the screen in the same frame it was
    /// produced in, and the probe's own caption states its outcome ("Next
    /// time: …"): that sentence has to survive the moment the clock stops.
    ///
    /// Only the probe: every earlier set flows into its rest by itself,
    /// because the movement comes back and a tap between the effort and the
    /// recovery would be pure friction, and every other last set of a hold
    /// lands on `exerciseSummary`, which speaks about the whole movement.
    var holdSettled = false

    /// How long the athlete SAID this hold would run, before doing it.
    ///
    /// A target, not a report, and the difference is the whole reason it may
    /// be entered before the effort at all: nothing here claims a set was
    /// performed. It stands in for the plan while the exercise lasts — the
    /// clock counts down from it and Stop cuts it short — so what the engine
    /// finally reads is still measured, never declared.
    ///
    /// Per exercise, not per set: one tap buys the whole movement, and the
    /// sets after the first run with nobody at the phone. Cleared with the
    /// exercise, and carried across a process death, because coming back to
    /// the plan's number after declaring more would silently undo the
    /// decision.
    var holdDeclared: Int?

    /// Sets of the exercise in front of us whose number is an ESTIMATE rather
    /// than a measurement: the set ended under a thumb, which pays a guessed
    /// three-second reach allowance. Indices, because that is what the summary
    /// prints beside; cleared with the exercise it describes.
    var holdApproxSets: Set<Int> = []

    /// What the CLOCK wrote for each set of the exercise in front of us, by
    /// set index — the number `recordHoldActual` produced, before any
    /// correction by hand. The summary reads the clock's word off this
    /// rather than off the number in force (`summaryMeasured`): a set
    /// corrected from 7 down to 5 re-opens under "the clock saw 7 s", never
    /// under the 5 the person typed. Per exercise, like the estimate marks,
    /// and carried across a process death with them.
    var holdMeasured: [Int: Int] = [:]

    /// The exercise was started by ONE tap and continues itself: the rest
    /// after each set opens the next set with nobody touching the phone. It
    /// belongs to the exercise it was started for, so it is cleared on the
    /// way out of one — `resetHoldSides` for every skip, `advanceAfterRest`
    /// for the ordinary advance, `finishNow` for the exit.
    ///
    /// The pause of a hands-free rest deliberately does not clear it: the
    /// pause cannot be reached from a work screen at all, and Resume has to
    /// come back to the run the person started.
    ///
    /// Not in the snapshot, and that is a decision rather than an omission:
    /// process death drops the run, the work screen comes back with its own
    /// start button, and one tap buys the sets that are left. A restored flag
    /// would arm a countdown for someone who is holding a cold phone.
    var holdAutoRun = false

    /// The session's own list: every position in the flow (indices, "N / M",
    /// the capsules, restore clamping) counts in this.
    var exercises: [SessionExercise] { session.exercises }

    var exercise: SessionExercise { exercises[exIndex] }

    /// Working sets plus the probe, when the plan carries one. The probe
    /// REPLACES a working set upstream — the engine hands back one set fewer —
    /// so the session's volume is unchanged and this count is what the person
    /// actually walks through.
    var totalSets: Int { exercise.sets + (exercise.probe == nil ? 0 : 1) }

    /// The set under way is the probe: one set of the NEXT variation, offered
    /// instead of the last set of the current one.
    var onProbeSet: Bool { exercise.probe != nil && setIndex >= exercise.sets }

    var isLastSet: Bool { setIndex == totalSets - 1 }

    var isLastExercise: Bool { exIndex == exercises.count - 1 }

    /// What the screen is showing right now: the planned exercise, or — on the
    /// probe set — the movement the probe offers. Everything the work screen
    /// reads goes through this, which is why the probe needs no second screen
    /// and no new question.
    struct CurrentMovement {
        let name: String
        let unit: LoadUnit
        let perSide: Bool
        let planned: Int
        let isProbe: Bool
        let target: TechniqueTarget
    }

    var current: CurrentMovement {
        if let probe = exercise.probe, onProbeSet {
            return CurrentMovement(name: probe.name, unit: probe.unit, perSide: probe.perSide,
                                   planned: probe.load, isProbe: true,
                                   target: TechniqueTarget(probe: probe, of: exercise.pattern))
        }
        return CurrentMovement(name: exercise.name, unit: exercise.unit,
                               perSide: exercise.perSide,
                               planned: exercise.plannedLoad(set: setIndex), isProbe: false,
                               target: TechniqueTarget(exercise))
    }

    var holding: Bool { holdClock.isRunning }

    var holdSwitchPausing: Bool { holdSwitchClock.isRunning }

    var holdCountingIn: Bool { holdCountInClock.isRunning }

    /// Nonisolated on purpose. Under the target's default MainActor isolation
    /// an implicit deinit is an isolated one, going through the back-deployed
    /// `swift_task_deinitOnExecutor`, and in the CI runs of #258 on the iOS
    /// 26.2 simulator that path crashed every time a store was freed. Nothing
    /// here needs the main actor to be torn down.
    nonisolated deinit {}

    func animate(_ motion: Motion, _ change: () -> Void) {
        animator(reduceMotion ? nil : motion, change)
    }

    // MARK: - What the view forwards

    /// One second of the flow: whichever countdown the phase is running.
    func tick() {
        switch phase {
        case .warmup:
            if blockPause.isPaused { tickBlockPause() } else { tick(.warmup) }
        case .rest:
            // Paused, the rest has no end date to run out — the way back
            // in owns the clock, exactly as it does in the two blocks.
            if blockPause.isPaused { tickBlockPause() } else { tickRest() }
        case .cooldown:
            if blockPause.isPaused { tickBlockPause() } else { tick(.cooldown) }
        case .work where holdCountingIn:
            tickHoldCountIn()
        case .work where holdSwitchPausing:
            tickHoldSwitchPause()
        case .work where holding:
            tickHold()
        default:
            break
        }
    }

    /// The flow is on screen. Once: sheets presented over the flow can make
    /// the view appear again.
    func appear() {
        guard !didStart else { return }
        didStart = true
        // Pay the audio-session setup here, not on the first tick — and BOTH
        // halves of the pair, not just the tone. The Taptic Engine idles
        // between countdowns and pays its wake-up on the first impulse, so
        // the first tick of a 3-2-1 would land after the second, and with the
        // ring switch flipped the haptic is the whole channel. `prepare()`
        // holds for a few seconds only, which is why `tickRest` primes again
        // a second before its 3-2-1.
        if store.settings.soundsEnabled {
            signals.primeSounds()
            signals.prime()
        }
        if let resume { restore(from: resume) }
        if workoutStart == nil { workoutStart = now() }
        // After the restore, so it catalogues the real position: the same
        // call the in-flow "Finish now" makes, which is why the card beside
        // it says the same words.
        if settleImmediately, phase != .feedback { finishNow() }
        // Nothing for the lock screen to describe on the rating.
        if phase != .feedback {
            liveActivity.start(sessionNumber: session.sessionNumber,
                               state: currentActivityState())
        }
    }

    func disappear() {
        liveActivity.end()
    }

    /// The rating lands: the workout goes to the engine with everything it
    /// recorded, and what it earned comes back.
    func rate(_ result: FeedbackResult, overrides: [Pattern: Double]) -> [Milestone] {
        store.completeWorkout(
            session: session, result: result,
            overrides: overrides,
            setActuals: actuals,
            // Skips like any other: the position stays put, counter and
            // rotation still advance.
            skipped: skippedPatterns,
            // The sets skipped along the way. The engine settles them
            // against the rating — after it, never before.
            setsSkipped: setsSkipped,
            // The probe's own channel: a number about one set of a movement
            // that is not in the plan yet.
            probes: probeActuals,
            durationSec: workoutStart.map {
                // max: the wall clock can move backwards mid-workout. Minus
                // the measured absence: a workout picked up two hours later is
                // not a two-hour workout, and duration is what a person reads
                // in Health.
                max(0, Int(now().timeIntervalSince($0)) - awaySec)
            },
            warmupSec: warmupSec, cooldownSec: cooldownSec,
            // Named in the journal, not just on this screen: the history says
            // "not finished" about a movement that was started, and "skipped"
            // about one that was not.
            interrupted: interruptedPattern,
            // The additions, landed by the engine over the rating — never
            // applied here.
            raised: raisedSteps,
            date: now())
    }

    /// At the transition, not when the milestone screen appears: that can
    /// refire behind sheets, and a restore lands on the rating — so this
    /// cannot double-play.
    func showMilestones(_ earned: [Milestone]) {
        playMilestone()
        phase = .milestone(earned)
    }
}
