//
//  warm-up > work > rest > … > cool-down > feedback. Every countdown is
//  wall-clock based (an end Date, not a tick count) so locking the phone
//  loses nothing; the screen stays awake for the whole session.
//

import Combine
import SwiftUI
import StoreKit
import UIKit
import DredfitCore

// The type is split across seven sibling files: the two guided blocks
// (+Warmup, +Cooldown), the screen a set is performed on (+Work), the holds
// and session persistence (+Session), the pause of a guided block
// (+BlockPause), the summary of a finished hold (+Summary) and the skips
// made during the workout (+Skips). The reason is a CI error rather than a
// style opinion — the lint's hard ceiling on a file is 1200 lines, and this
// file stood at 1101 when the hands-free hold wave arrived with a phase to
// add, and at 1159 after §41.13.
//
// Swift's `private` is FILE-scoped, so the state and helpers those siblings
// reach for are declared without it. They are internal to the module and to
// this type, not API: nothing outside these eight files touches them.
//
// The extension at the bottom of THIS file is a different matter. It is here
// rather than in a sibling because the second ceiling — 600 lines for the
// type's own body — does not follow an extension anywhere, so a body only
// shrinks by moving members out of it, and moving them across a file boundary
// as well would have cost visibility for nothing.
struct WorkoutFlowView: View {
    let session: Session
    var resume: WorkoutSnapshot?
    /// Open straight on the rating, cataloguing whatever is unfinished — the
    /// answer to "keep this workout?" on Today. The athlete says how it went
    /// themselves; nothing is rated on their behalf inside the day
    /// (owner, 06.09.2026).
    var settleImmediately = false
    @Environment(\.dismiss) var dismiss
    @Environment(AppStore.self) var store
    @Environment(\.requestReview) private var requestReview
    /// Reduce Motion, and it is not a question of taste on these screens:
    /// seven tick handlers roll their digits on a 0.3 s linear animation and
    /// the rest ring's arc sweeps under them, which is the movement the
    /// setting is turned on to stop (UX review 05.09.2026). Declared without
    /// `private` because Swift's `private` is file-scoped and six of those
    /// seven ticks live in the sibling files.
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    enum Phase: Equatable {
        /// The warm-up no longer starts itself either. Being dropped straight
        /// into a countdown nobody agreed to is how a block gets skipped by
        /// walking away rather than by saying so — and the answer "I am
        /// already warm" is a real one. Offered, never required; the same two
        /// answers as the cool-down.
        case warmupIntro
        case warmup
        case work
        case rest(seconds: Int)
        /// Every set of a hold movement on one screen, with any number one
        /// tap from being corrected. It REPLACES the settled hold that stood
        /// on the work screen: that showed one number, the last one, and the
        /// sets before it had never been correctable at all — a number
        /// entered on the work screen writes the set under way and truncates
        /// what follows, so there was no writer that could touch set one.
        ///
        /// Only after a hold, and only when the movement is behind. Sets of
        /// reps are logged by the tap that ends them and nothing about that
        /// screen changed.
        case exerciseSummary
        /// The cool-down no longer starts itself. The work is behind, and
        /// being dropped straight into a stretch nobody asked for is how a
        /// block gets skipped by walking away instead of by saying so. One
        /// screen, two answers, and both are fine.
        case cooldownIntro
        case cooldown                 // between the last exercise and the rating
        case feedback
        case milestone([Milestone])   // only when the workout earned one
    }

    @State var exIndex = 0
    @State var setIndex = 0          // 0-based
    @State var phase: Phase = .warmupIntro
    @State var warmupIndex = 0
    @State var warmupRemaining = 0
    @State var warmupEndDate: Date?
    // Shares the block's countdown state — one timer, two stages — so
    // nothing new has to survive backgrounding.
    @State var warmupStage: Warmup.Stage = .getReady
    // Computed once on entry: the composition depends on what was performed.
    @State var cooldownPositions: [CooldownPosition] = []
    @State var cooldownIndex = 0
    @State var cooldownRemaining = 0
    @State var cooldownEndDate: Date?
    @State var cooldownStage: Cooldown.Stage = Cooldown.openingStage
    // The pause of the guided blocks (issue #61). One for both, like the
    // stage/remaining pairs above: the two blocks never run at once. Held, the
    // frozen seconds sit in warmupRemaining / cooldownRemaining and no end
    // date exists anywhere; re-entering, only this moves.
    @State var blockPause = BlockPause.State()
    @State var restRemaining = 0
    @State var restEndDate: Date?
    /// What this transition planned, kept because the phase carries the
    /// current total and the extension cap is twice the PLANNED one.
    @State var restPlanned = 0
    // Captured at tap time (not a bool): an ordinary rest keeps ticking while
    // the sheet is open and may flip the phase underneath. The rest of a
    // hands-free run does NOT — it would start the next set under the sheet,
    // so `openRestTechnique` freezes that one (UX review 05.09.2026).
    @State var techniqueTarget: TechniqueTarget?
    // Unlike techniqueTarget, presenting this freezes the countdown.
    @State private var positionTechnique: PositionTechnique?
    /// A fact belongs to the set it happened on — see SetFacts for the shape
    /// and for what a set of them collapses to.
    @State var actuals: SetFacts.PerSet = [:]
    /// Sets skipped along the way, per movement. Accumulated here, beside the
    /// per-set facts and for the same length of time — the session — and
    /// handed to the engine only when the rating lands: the cut belongs on the
    /// RESULT of the feedback, never on its input.
    @State var setsSkipped: SetFacts.Skips = [:]
    /// What the PROBE set showed, per movement (§40.4). Kept apart from
    /// `actuals` on purpose and for the same reason the engine keeps `probes`
    /// apart from `overrides`: the probe is a different exercise, and folding
    /// its number into the mean of the working sets would average two
    /// variations. It reaches the engine through its own argument.
    @State var probeActuals: [Pattern: Int] = [:]
    /// Steps added "for next time" on the summary of a finished hold, per
    /// movement (§41.13). A DECISION, not a fact: it never touches `actuals`
    /// and reaches the engine through its own argument, landed after the
    /// rating. Kept for the session like the facts are, and carried across a
    /// process death for the same reason the declared time is — coming back
    /// without it would undo a choice already made on screen.
    @State var raisedSteps: [Pattern: Int] = [:]
    @State var skippedPatterns: Set<Pattern> = []
    /// Kept apart from `skippedPatterns`: the engine treats both as skips for
    /// the session, but the rating and the history say different things.
    @State var adjusting = false
    /// Movements this session has already been warned about. Once per exercise
    /// — a second copy of the same advice is nagging.
    @State private var maximumNoted: Set<Pattern> = []
    @State var maximumWarning: String?
    @State var adjustValue = 0
    @State var workoutStart: Date?   // actual duration for Health
    /// Seconds spent away across resumes, subtracted from the duration
    /// Health is told about. Wall clock alone charged the break to the
    /// workout (UX review 05.09.2026).
    @State var awaySec = 0
    /// The two guided blocks, measured rather than assumed. `*BeganAt` is the
    /// moment the person said yes; `*Sec` is what the block cost once it
    /// ended, and it stays nil only while the block has not ended yet. A
    /// declined block never gets a `BeganAt` and resolves to ZERO — which is
    /// the whole point: its planned minutes used to be billed to Health
    /// whether or not anybody stretched.
    @State var warmupBeganAt: Date?
    @State var warmupSec: Int?
    @State var cooldownBeganAt: Date?
    @State var cooldownSec: Int?
    /// Seconds a guided block STOOD STILL — a pause, an open technique sheet,
    /// or the absence a tick found on its way into one. `warmupSec` and
    /// `cooldownSec` are wall clock (`BlockRun.seconds`), so without this a
    /// warm-up paused for a phone call billed the call to the warm-up and
    /// Health was told the person stretched for eleven minutes (UX review
    /// 05.09.2026). One pair for both blocks, like every other pair above:
    /// they never run at once, and each block resets them when it begins.
    @State var blockPausedSec = 0
    @State var blockFrozenAt: Date?
    @State private var lastResult: FeedbackResult?   // gates the review ask
    @State var liveActivity = WorkoutActivityController()
    @State private var exitConfirmShown = false
    /// Labelled "not finished" on the rating screen; to the engine it is a
    /// skip like any other.
    @State var interruptedPattern: Pattern?
    /// One-shot guard: sheets presented over the flow can make onAppear fire
    /// more than once.
    @State private var didStart = false

    // Per-side holds run the countdown twice; the actual is the smaller of
    // the two — the honest bottleneck.
    @State var holdEndDate: Date?
    @State var holdRemaining = 0
    @State var holdTotal = 0
    @State var holdSecondSide = false
    @State var firstSideHeld: Int?
    // The second side starts itself — no tap, with hands busy in a plank.
    @State var holdPauseEndDate: Date?
    @State var holdPauseRemaining = 0
    // The count-in "Start hold" earns before the clock runs
    // (GetReady.countInSeconds). Its own pair rather than a stage flag on the
    // hold's: the hold's total must already stand while this counts, so that
    // the go can start it without recomputing anything.
    @State var holdCountInEndDate: Date?
    @State var holdCountInRemaining = 0
    /// The LAST hold of a movement is over and its seconds are recorded, but
    /// the set is not closed yet — `finishHold` stops there and the primary
    /// button finishes the job. A hold ends itself, so before this flag the
    /// number it produced left the screen in the same frame it was produced
    /// in, and "Went differently" never got a moment to exist.
    ///
    /// Only the last set: every earlier one still flows into its rest by
    /// itself, because the movement comes back and a tap between the effort
    /// and the recovery would be pure friction. After the last set nothing
    /// about the movement returns, so its seconds would stand uncorrectable.
    /// The PROBE set of a hold movement is over and its seconds are
    /// recorded, but the set is not closed yet — the probe's own caption
    /// states its outcome ("Next time: …"), and that sentence has to survive
    /// the moment the clock stops. Narrowed to the probe by this wave: every
    /// other last set of a hold now lands on `exerciseSummary`, which is a
    /// better version of the same idea and speaks about the whole movement.
    @State var holdSettled = false
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
    @State var holdDeclared: Int?
    /// The adjuster is open on the DECLARATION rather than on a set's record.
    /// A flag rather than a condition derived from the screen, for the same
    /// reason `summarySet` is one: what the panel writes must not depend on
    /// what the screen happens to look like when OK is tapped.
    @State var holdDeclaring = false
    /// Sets of the exercise in front of us whose number is an ESTIMATE rather
    /// than a measurement: the set ended under a thumb, which pays a guessed
    /// three-second reach allowance. Indices, because that is what the summary
    /// prints beside; cleared with the exercise it describes.
    @State var holdApproxSets: Set<Int> = []
    /// What the CLOCK wrote for each set of the exercise in front of us, by
    /// set index — the number `recordHoldActual` produced, before any
    /// correction by hand. The summary reads its ceiling off this rather
    /// than off the number in force: a set corrected from 7 down to 5 kept
    /// re-opening under "the clock saw 5 s", naming a number the person had
    /// typed as the clock's, and could never be put back up to the 7 the
    /// clock actually counted (owner, 12.09.2026). Per exercise, like the
    /// estimate marks, and carried across a process death with them.
    @State var holdMeasured: [Int: Int] = [:]
    /// Which card of the summary the adjuster is editing, so the panel writes
    /// to the set that was tapped rather than to the set the flow is on.
    @State var summarySet: Int?
    /// The exercise was started by ONE tap and continues itself: the rest
    /// after each set opens the next set's count-in with nobody touching the
    /// phone (R23). It belongs to the exercise it was started for, so it is
    /// cleared on the way out of one — `resetHoldSides` for every skip,
    /// `advanceAfterRest` for the ordinary advance, `finishNow` for the exit.
    ///
    /// A PAUSED guided block deliberately does not clear it: the pause is a
    /// block's own control, it cannot be reached from a work screen at all,
    /// and Resume has to come back to the run the person started.
    ///
    /// Not in the snapshot, and that is a decision rather than an omission:
    /// process death drops the run, the work screen comes back with its own
    /// start button, and one tap buys the sets that are left. A restored flag
    /// would arm a countdown for someone who is holding a cold phone.
    @State var holdAutoRun = false
    /// The skip a thumb has asked for and not confirmed yet — see
    /// SkipConfirmation.swift for why one is asked for at all.
    @State var pendingSkip: SkipConfirmation?

    @ScaledMetric(relativeTo: .largeTitle) private var restRingSize: CGFloat = 240
    /// The set dots of the work screen. A dot is the size of the caption it
    /// stands over, so it follows the same setting (UX review 05.09.2026).
    @ScaledMetric(relativeTo: .caption) var setDotSize: CGFloat = 10

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// The session's own list. It used to be a SUBSET of it — the short
    /// version ran three movements of six and recorded the rest as skips — and
    /// every position in the flow (indices, "N / M", the capsules, restore
    /// clamping) counts in this, which is why the name stayed.
    var exercises: [SessionExercise] { session.exercises }
    var exercise: SessionExercise { exercises[exIndex] }

    /// Working sets plus the probe, when the plan carries one (§40.4). The
    /// probe REPLACED a working set upstream — the engine handed back one set
    /// fewer — so the session's volume is unchanged and this count is what the
    /// person actually walks through.
    var totalSets: Int { exercise.sets + (exercise.probe == nil ? 0 : 1) }
    /// The set under way is the probe: one set of the NEXT variation, offered
    /// instead of the last set of the current one.
    var onProbeSet: Bool { exercise.probe != nil && setIndex >= exercise.sets }
    var isLastSet: Bool { setIndex == totalSets - 1 }
    var isLastExercise: Bool { exIndex == exercises.count - 1 }

    /// What the screen is showing right now: the planned exercise, or — on the
    /// probe set — the movement the probe offers. Everything the work screen
    /// reads goes through this, which is why the probe needs no second screen
    /// and no new question (§40.4).
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
    var holding: Bool { holdEndDate != nil }
    var holdSwitchPausing: Bool { holdPauseEndDate != nil }
    var holdCountingIn: Bool { holdCountInEndDate != nil }

    /// The digit roll every countdown in the flow shares, and nothing at all
    /// under Reduce Motion — `withAnimation(nil)` is how a transaction is told
    /// to make no movement. One definition rather than seven literals: each
    /// tick handler spelled `.linear(duration: 0.3)` out by hand, which is how
    /// a setting comes to be honoured on some of them and not the rest.
    var countdownAnimation: Animation? { reduceMotion ? nil : .linear(duration: 0.3) }
    private var isMilestone: Bool { if case .milestone = phase { return true }; return false }

    /// The stamp is written whether or not iOS shows the prompt — Apple
    /// rate-limits invisibly, and an unseen request still counts against our
    /// own floor. The delay waits out the cover's dismissal: StoreKit
    /// silently drops a prompt asked for mid-transition.
    private func askForReviewIfEarned() {
        guard store.shouldRequestReview(lastResult: lastResult) else { return }
        let store = self.store
        let requestReview = self.requestReview
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            store.recordReviewRequest()
            requestReview()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            switch phase {
            case .warmupIntro:
                warmupIntroView
            case .warmup:
                warmupView
            case .work:
                workView
            case .exerciseSummary:
                exerciseSummaryView
            case .rest:
                restView
            case .cooldownIntro:
                cooldownIntroView
            case .cooldown:
                cooldownView
            case .feedback:
                FeedbackView(session: session, facts: actuals,
                             setsSkipped: setsSkipped,
                             skipped: skippedPatterns,
                             raised: raisedSteps,
                             interrupted: interruptedPattern) { result, overrides in
                    let earned = store.completeWorkout(
                        session: session, result: result,
                        overrides: overrides,
                        setActuals: actuals,
                        // Skips like any other: levels frozen, counter and
                        // rotation still advance.
                        skipped: skippedPatterns,
                        // The sets skipped along the way. The engine settles
                        // them against the rating — after it, never before.
                        setsSkipped: setsSkipped,
                        // The probe's own channel (§40.4): a number about one
                        // set of a movement that is not in the plan yet.
                        probes: probeActuals,
                        durationSec: workoutStart.map {
                            // max: the wall clock can move backwards mid-workout.
                            // Minus the measured absence: a workout picked up
                            // two hours later is not a two-hour workout, and
                            // duration is what a person reads in Health.
                            max(0, Int(Date.now.timeIntervalSince($0)) - awaySec)
                        },
                        warmupSec: warmupSec, cooldownSec: cooldownSec,
                        // Named in the journal, not just on this screen: the
                        // history says "not finished" about a movement that
                        // was started, and "skipped" about one that was not.
                        interrupted: interruptedPattern,
                        // The additions, landed by the engine over the rating
                        // — never applied here (§41.13).
                        raised: raisedSteps)
                    if earned.isEmpty {
                        dismiss()
                    } else {
                        lastResult = result
                        // At the transition, not in MilestoneView.onAppear:
                        // onAppear can refire behind sheets, and a restore
                        // lands on the rating — so this cannot double-play.
                        playMilestone()
                        phase = .milestone(earned)
                    }
                }
            case .milestone(let earned):
                MilestoneView(milestones: earned,
                              steps: store.progressCurve(through: store.lastRecord?.date),
                              retrospective: Retrospective.make(
                                  records: store.records,
                                  current: store.currentPositions)) {
                    askForReviewIfEarned()
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 24)
        .background(Theme.bg.ignoresSafeArea())
        .onReceive(timer) { _ in
            switch phase {
            case .warmup:
                if blockPause.isPaused { tickBlockPause() } else { tickWarmup() }
            case .rest:
                // Paused, the rest has no end date to run out — the way back
                // in owns the clock, exactly as it does in the two blocks.
                if blockPause.isPaused { tickBlockPause() } else { tickRest() }
            case .cooldown:
                if blockPause.isPaused { tickBlockPause() } else { tickCooldown() }
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
        .onAppear {
            // Claims the snapshot for as long as this flow is up, so a
            // foreground three hours into an idle session cannot settle the
            // workout out from under the athlete still in it.
            store.workoutFlowAppeared()
            UIApplication.shared.isIdleTimerDisabled = true
            guard !didStart else { return }
            didStart = true
            // Pay the audio-session setup here, not on the first tick.
            // BOTH halves of the pair, not just the tone. The Taptic Engine
            // idles between countdowns and pays its wake-up on the first
            // impulse, so the first tick of a 3-2-1 landed after the second —
            // and with the ring switch flipped the haptic is the whole channel
            // (UX review 05.09.2026). `prepare()` holds for a few seconds
            // only, which is why `tickRest` primes again on its way in.
            if store.settings.soundsEnabled {
                CountdownSounds.shared.prime()
                WorkoutSignals.prime()
            }
            if let resume { restore(from: resume) }
            if workoutStart == nil { workoutStart = .now }
            // After the restore, so it catalogues the real position: the same
            // call the in-flow "Finish now" makes, which is why the card
            // beside it says the same words.
            if settleImmediately, phase != .feedback { finishNow() }
            // Nothing for the lock screen to describe on the rating.
            if phase != .feedback {
                liveActivity.start(sessionNumber: session.sessionNumber,
                                   state: currentActivityState())
            }
        }
        .onDisappear {
            store.workoutFlowDisappeared()
            UIApplication.shared.isIdleTimerDisabled = false
            liveActivity.end()
        }
        // A held block is the one state where the app knows nobody is
        // training, so it stops holding the screen open. One place rather
        // than one per path: every way in and out of a pause runs through it.
        .onChange(of: blockPause.isHeld) { _, held in
            UIApplication.shared.isIdleTimerDisabled = !held
        }
        // WITHOUT `planned:` — the step-below block belongs to the screen that
        // shows the UPCOMING workout, never to one that is running (owner,
        // 01.09.2026). The session is snapshotted at Start, so a switch taken
        // here would move the state under a plan already in flight, and the
        // rating lands on the pair: measured, squat v6 3×15 switched to v5 and
        // rated "on plan" writes 15 into the journal of v5, where the person
        // had shown 4 — and a probe passed later in the same session promotes
        // straight past the rung they just chose, undoing the decision without
        // saying so. The engine is right; the two states simply must not move
        // at once.
        .sheet(item: $techniqueTarget, onDismiss: resumeRestCountdown) { target in
            TechniqueSheet(target: target)
        }
        .sheet(item: $positionTechnique, onDismiss: resumePositionCountdown) { technique in
            PositionTechniqueSheet(technique: technique)
        }
        .alert(String(localized: "Leave the workout?"),
               isPresented: $exitConfirmShown) {
            // An ALERT, not a confirmationDialog: iOS 26 presents the latter
            // as an anchored popover, so the same question drew a centred card
            // in the workout and a tailed bubble pointing at a settings row.
            // An alert has no anchor — every one of these is the same window,
            // centred, whatever it was raised from.
            //
            // And the workaround the popover forced is gone with it. A popover
            // suppresses its cancel action, because tapping outside IS the
            // cancel, so the escape had to be a SECOND, role-less button. An
            // alert does not: measured on iPhone 17 Pro / iOS 26.5, the node is
            // `Alert` with no `Popover` beside it, and all four buttons stood in
            // the accessibility tree — the `.cancel` one included. So the escape
            // is one button again, carrying the role AND the name that says what
            // it does. "Cancel" answers "cancel what?"; this one does not.
            Button(String(localized: "Keep training"), role: .cancel) { }
            Button(String(localized: "Finish now")) { finishNow() }
            // The answer the flow could always give and never offered. Every
            // number here is persisted at every transition (`persistProgress`),
            // so stepping out keeps the workout and Today offers to pick it up
            // — while the two buttons around it were the whole choice: rate an
            // unfinished session as if it were over, or throw it away (UX
            // review 05.09.2026). Past the resume window what was done is
            // settled on plan rather than lost (`settleAbandonedWorkout`), so
            // neither ending drops the work.
            Button(String(localized: "Finish later")) { dismiss() }
            Button(String(localized: "Discard workout"), role: .destructive) {
                discardWorkout()
            }
        } message: {
            // One literal, because the literal is the catalog key.
            // swiftlint:disable:next line_length
            Text("“Finish now” goes to the rating and marks the rest as skipped. “Finish later” keeps your place — Today offers to pick it up.")
        }
        // Beside the exit alert rather than on the work screen itself: a
        // confirmed skip can retire that screen (into the next exercise, or
        // into the cool-down), and an alert dismissing together with the view
        // it hangs on is how a presentation gets stuck.
        .skipConfirmation($pendingSkip)
    }

    // MARK: - Header with progress segments

    @ViewBuilder
    private var header: some View {
        if phase != .feedback, !isMilestone {
            FlowHeader(title: headerTitle,
                       steps: isWarmingUp ? 0 : exercises.count,
                       // The cool-down is past the LAST exercise, not on it:
                       // `exIndex` stops at count - 1 and the final capsule
                       // stayed "under way" for the whole block, so the bar
                       // could never say the work was done (review 06.09.2026).
                       doneIndex: phase == .cooldown || phase == .cooldownIntro
                           ? exercises.count : exIndex,
                       minutesLeft: minutesLeft) {
                if hasProgress {
                    exitConfirmShown = true
                } else {
                    discardWorkout()
                }
            }
        }
    }

    /// What is left of the session, in minutes — recomputed on every
    /// body pass, so a skipped set takes its minutes off at the moment it is
    /// skipped rather than at the next screen.
    ///
    /// Offered on the work and rest screens and inside the cool-down — the
    /// three screens where "how much longer" is a live question. The warm-up
    /// is left out: it stands before the work it cannot shorten, and its own
    /// offer screen already states its length. The rating is past the question
    /// entirely.
    private var minutesLeft: Int? {
        var index = exIndex
        var behind = setIndex
        switch phase {
        case .work:
            break
        case .rest, .exerciseSummary:
            // The set the rest FOLLOWS is done — the flow advances after it.
            // The summary stands past a finished set for the same reason, so
            // counting its set as still ahead would quietly add a set's worth
            // of minutes to a movement that is over.
            behind += 1
            // `totalSets`, not `exercise.sets`: the probe is a set of this
            // exercise too. Counted by the working sets alone, the exercise
            // left the list on the rest that ANNOUNCES the probe by name, so
            // the header dropped the probe's own minute and then grew by it
            // when the probe's screen opened — a number moving without the
            // person having moved it (self-review 05.09.2026). Identical for
            // an exercise without one, where the two are equal.
            if behind >= totalSets { index += 1; behind = 0 }
        case .cooldown:
            // The block the header stopped answering for. The work screen
            // counts the cool-down into what is left (`ends:` below), and then
            // the number vanished on the one screen where the person is
            // actually waiting it out — so the block that was reserved four
            // minutes a moment ago reported nothing at all (UX review
            // 05.09.2026). Its own arithmetic, not the session's: what is left
            // here is stretches, and it is counted the way the offer counted
            // them. The intro screen is left out on purpose — it prints the
            // same number in its own body, and a header would say it twice.
            return cooldownMinutesLeft
        default:
            return nil
        }
        // The cool-down is the only fixed block still ahead; the warm-up is
        // behind by the time the work screen is up.
        //
        // WITH THE FACTS, not the plan alone. The clock on a hold runs from
        // `SetFacts.holdTarget` — the time the athlete declared, or the
        // shortfall a set cut short carries onto the sets after it — while
        // this number was built out of `plannedLoad`, so the header went on
        // promising 30 s a set to somebody who had just set the clock to 45,
        // and went on promising 40 to somebody whose remaining sets were now
        // 19 (UX review 05.09.2026). The two disagree exactly when the person
        // has deviated from the plan, which is when the question gets asked.
        //
        // The declaration is the CURRENT exercise's, so it travels only while
        // `index` still points at it: past the last set the flow is standing
        // in front of the next movement, and a time set for the plank says
        // nothing about the side plank (`resetHoldExercise`).
        return SessionAhead.minutes(exercises, exIndex: index, setsBehind: behind,
                                    ends: session.cooldownMin,
                                    facts: actuals,
                                    declared: index == exIndex ? holdDeclared : nil)
    }

    private var headerTitle: String {
        switch phase {
        case .work, .exerciseSummary:
            return String(localized: "\(exIndex + 1) / \(exercises.count)")
        case .warmup, .warmupIntro: return String(localized: "WARM-UP")
        case .cooldownIntro, .cooldown: return String(localized: "COOL-DOWN")
        default:        return String(localized: "REST")
        }
    }

    // MARK: - The technique sheet (shared by both guided blocks)

    /// Freezes the running countdown: the end date comes off (the tick
    /// guards go quiet) while the remaining seconds stay put and rebuild it.
    /// The way back in from a pause freezes with it — reading is not getting
    /// back into position either.
    func openPositionTechnique(_ technique: PositionTechnique) {
        positionTechnique = technique
        warmupEndDate = nil
        cooldownEndDate = nil
        blockPause.freezeForSheet()
        // And the block stops costing time while it is read: reading is not
        // stretching either, and the block's own length is wall clock
        // (UX review 05.09.2026, see `blockPausedSec`).
        beginBlockFreeze()
    }

    private func resumePositionCountdown() {
        // Whatever the sheet froze is what it hands back. A way back in
        // outlives it; a pause outranks it — closing the sheet must never
        // restart a block the user stopped (issue #34 vs #61).
        blockPause.thawAfterSheet(now: .now)
        guard !blockPause.isPaused else { return }
        // After the guard: a block the person had PAUSED goes on standing
        // still, and closing the interval here would stop counting a pause
        // that has not ended.
        endBlockFreeze()
        switch phase {
        case .warmup:
            warmupEndDate = Date.now.addingTimeInterval(TimeInterval(warmupRemaining))
        case .cooldown:
            cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
        default:
            break
        }
    }

    // MARK: - Live Activity

    /// Strings leave the app pre-localized — the extension renders verbatim.
    func activityWorkState() -> RestActivityAttributes.ContentState {
        if isWarmingUp {
            return .init(phase: .work, title: String(localized: "WARM-UP"),
                         detail: "", restEndDate: nil)
        }
        // The probe set is one set of the NEXT variation, and the in-app
        // screen says so — the lock screen and the Dynamic Island must not
        // call it by the old movement's name while the person is doing the
        // new one (UI-truth audit, 27.08.2026).
        if current.isProbe {
            return .init(phase: .work, title: current.name,
                         detail: String(localized: "Probe"), restEndDate: nil)
        }
        return .init(phase: .work, title: exercise.name,
                     detail: String(localized: "set \(setIndex + 1) of \(totalSets)"),
                     restEndDate: nil)
    }

    // MARK: - Rest

    /// What the lock screen calls the rest it is counting down. Two rests look
    /// identical and end differently — an ordinary one hands the screen back
    /// and waits for a tap, the rest inside a hands-free hold run STARTS the
    /// next set on its own go — and the tile said "Next up" about both, so the
    /// one rest that cannot be missed looked exactly like the one that can
    /// (UX review 05.09.2026). The words are the rest screen's own
    /// (FlowChrome+Rest), keyed off the same fact, so the two cannot drift.
    var restActivityDetail: String {
        restStartsTheNextSet
            ? String(localized: "Starts by itself")
            : String(localized: "Next up")
    }

    /// Reading about what comes next must not cost the set it describes.
    ///
    /// The sheet covers the screen while the rest keeps counting underneath
    /// it, and on a hands-free run the end of that rest is what STARTS the
    /// next hold — so the person came back from a technique page into a plank
    /// already under way. The guided blocks freeze their countdown for exactly
    /// this tap (`openPositionTechnique`); this is that tap on the one rest
    /// with something to lose (UX review 05.09.2026). An ordinary rest is left
    /// running: it hands the screen back and waits, and freezing it would only
    /// make the workout longer.
    private func openRestTechnique() {
        if restStartsTheNextSet {
            restEndDate = nil
            // The tile counts down to a DATE, so a frozen rest has to take the
            // date away — the same reason `pauseBlock` does.
            liveActivity.update(.init(phase: .rest, title: nextLabel,
                                      detail: restActivityDetail, restEndDate: nil))
            // A frozen rest is persisted as the rest it will be when the sheet
            // closes, for the reason `persistProgress` states about a paused
            // one: written with no date it reads back as "no rest was running".
            persistProgress()
        }
        techniqueTarget = restTechniqueTarget
    }

    /// …and hands back exactly what it froze. A rest held by the PAUSE stays
    /// held — the person's own stop outranks the sheet's, the same order
    /// `resumePositionCountdown` keeps.
    private func resumeRestCountdown() {
        guard case .rest = phase, restEndDate == nil, !blockPause.isPaused else { return }
        let end = Date.now.addingTimeInterval(TimeInterval(max(restRemaining, 1)))
        restEndDate = end
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: end))
        persistProgress()
    }

    private var restView: some View {
        RestRing(remaining: restRemaining,
                 fraction: progressFraction,
                 ringSize: restRingSize,
                 nextLabel: nextLabel,
                 extensionSeconds: Self.restExtensionSeconds,
                 // Frozen, "+N s" would add to a clock that is not moving:
                 // the same reason "I'm ready" hides on a paused transition.
                 // Skip stays live — an escape must always be reachable.
                 canExtend: canExtendRest && !blockPause.isHeld,
                 paused: blockPause.isHeld,
                 // Offered only where the clock acts on its own (R32). On
                 // every other rest nothing happens without the person, and a
                 // control that promises to stop something that is not moving
                 // is worse than no control.
                 onPauseToggle: restStartsTheNextSet ? { toggleBlockPause() } : nil,
                 onTechnique: { openRestTechnique() },
                 onExtend: extendRest,
                 onSkip: {
                     clearBlockPause()
                     restEndDate = nil
                     restRemaining = 0
                     advanceAfterRest(countIn: true)
                 })
    }

    /// The cap is twice the rest this transition planned, so the dial cannot
    /// turn a workout into an evening.
    private var canExtendRest: Bool {
        guard case .rest(let total) = phase, restPlanned > 0 else { return false }
        return total + Self.restExtensionSeconds <= restPlanned * 2
    }

    /// Moves the end date, not a counter: restRemaining keeps deriving from
    /// the date, so a backgrounded phone comes back to the right number. The
    /// new total goes into the phase because the ring divides by it —
    /// otherwise the arc would run past 100%.
    ///
    /// The last-seconds signal needs no "already played" flag to reset: it
    /// fires on `newRemaining < restRemaining`, and an extension raises
    /// restRemaining, so the new countdown signals again on its own way down.
    private func extendRest() {
        guard case .rest(let total) = phase, let end = restEndDate, canExtendRest else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(Self.restExtensionSeconds))
        restEndDate = newEnd
        restRemaining = max(0, Int(newEnd.timeIntervalSinceNow.rounded()))
        phase = .rest(seconds: total + Self.restExtensionSeconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: newEnd))
        persistProgress()
    }

    private var progressFraction: CGFloat {
        guard case .rest(let total) = phase, total > 0 else { return 0 }
        return CGFloat(restRemaining) / CGFloat(total)
    }

    var nextLabel: String {
        if isLastSet {
            if isLastExercise { return String(localized: "Workout rating") }
            let next = exercises[exIndex + 1]
            return "\(next.name) · \(next.display)"
        }
        if exercise.probe != nil && setIndex + 1 == exercise.sets, let probe = exercise.probe {
            return String(localized: "Probe: \(probe.name) · \(probe.display)")
        }
        return String(localized: "\(exercise.name) · set \(setIndex + 2) of \(totalSets)")
    }

    /// Rest is never entered on the final set of the last exercise (that goes
    /// straight to the cool-down), so the index is always in range.
    ///
    /// The technique offered during a rest is the technique of what comes
    /// NEXT, and after the last working set of a probing exercise that is the
    /// PROBE's movement — the one thing on this screen nobody has done before.
    private var restTechniqueTarget: TechniqueTarget {
        if isLastSet && !isLastExercise {
            return TechniqueTarget(exercises[exIndex + 1])
        }
        if let probe = exercise.probe, setIndex + 1 == exercise.sets {
            return TechniqueTarget(probe: probe, of: exercise.pattern)
        }
        return TechniqueTarget(exercise)
    }
}

// What moves the flow forward — the transitions between sets, exercises and
// blocks, and the skip taken during a workout. In an extension rather than in
// the struct body because SwiftLint bounds that body at 600 lines as an ERROR
// and it had reached 509; an extension weighs nothing against it. Same file,
// so every private member above stays reachable and nothing had to widen —
// moving these to a FILE of their own would have cost visibility and bought
// the same nothing, since a body count does not follow an extension anywhere.
extension WorkoutFlowView {

    // MARK: - State machine transitions

    func completeSet() {
        // All three ways a set ends meet here (#186): the Done tap, the hold
        // reaching zero, an early stop past the mis-tap window. A per-side
        // hold's first side goes to the switch pause instead, not here.
        //
        // §41.2: finishing the PROBE set records its target. The rule and the
        // reason live in `SetFacts.recordingProbe` — it is called rather than
        // written out here because a policy inside a SwiftUI view body is a
        // policy no unit test can reach, and this one unfreezes eight ladders
        // out of ten.
        probeActuals = SetFacts.recordingProbe(probeActuals, exercise.pattern,
                                               isProbe: current.isProbe,
                                               target: current.planned)
        // A hold's LAST set gets its summary first, and the probe's Done is
        // the one tap that can arrive here still owing one: the probe keeps a
        // settled screen of its own, so the movement it belongs to has not
        // been shown yet. Guarded on the phase rather than on a flag, because
        // this is also the summary's own exit and that pass must fall through.
        if phase != .exerciseSummary && isLastSet && exercise.unit == .hold
            && !skippedPatterns.contains(exercise.pattern) {
            startExerciseSummary()
            return
        }
        // A hold has already sounded its own ending, at the moment the effort
        // actually stopped (see `finishHold`). The tap that lands here after
        // one confirms a number; sounding "done" again would announce an end
        // that happened seconds ago — and neither does the summary's exit,
        // which is a screen past the effort, not the end of one.
        if !holdSettled && phase != .exerciseSummary { playDone() }
        holdSettled = false
        adjusting = false
        if isLastSet && isLastExercise {
            // "Finish now" deliberately does not run the cool-down.
            startCooldown()
        } else if isLastSet {
            startRest(exercise.restExerciseSec)
        } else {
            startRest(exercise.restSetSec)
        }
    }

    /// A soft note when the person enters MORE than the plan on a set that
    /// is not the last one. Once per exercise per session, and the entry
    /// stands either way — it is advice about the workout, never a correction
    /// of the number.
    ///
    /// What it must NOT say is that the system measures the last set more
    /// accurately. Under a mean the ORDER OF SETS DOES NOT REACH THE ENGINE at
    /// all: 12, 8, 8 and 8, 8, 12 both collapse to 9. The advice is about
    /// training — a maximum attempt fatigues what follows it — and the wording
    /// says exactly that and nothing more.
    func noteMaximumOutOfOrder() {
        let pattern = exercise.pattern
        guard !maximumNoted.contains(pattern) else { return }
        // The rule itself is `SetFacts.maximumOutOfOrder`, where a test can
        // reach it — and where the reason it is NOT about the order of sets
        // is written down.
        guard SetFacts.maximumOutOfOrder(adjustValue, exercise, set: setIndex) else { return }
        maximumNoted.insert(pattern)
        // Reduce Motion covers this one too: the note slides up from the
        // bottom edge under a `.transition`, and with no animation running
        // that transition simply appears (UX review 05.09.2026).
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            // "A maximum" was a term this app defines nowhere, in a
            // twenty-one word paragraph on a screen read between sets. What
            // replaced it names the ACT — going all out on one set — and keeps
            // both thoughts, because the second one is not decoration: without
            // it the line reads as a correction of the number, which is the
            // one thing it must never be (UX review 05.09.2026).
            maximumWarning = String(localized:
                "Going all out on one set weakens the ones after it. What counts is the whole exercise.")
        }
    }

    /// Leaving an exercise early. There used to be two ways — a skip and a
    /// pain report — and the report is gone. A person who finds the movement
    /// too hard now reaches for a handle instead, which keeps the movement in
    /// the plan rather than taking it out for weeks.
    func leaveExercise() {
        adjusting = false
        holdSecondSide = false
        firstSideHeld = nil
        holdPauseEndDate = nil
        holdCountInEndDate = nil
        actuals.removeValue(forKey: exercise.pattern)   // a skip wins over an actual
        // …and over the probe: a movement that was not trained resolves nothing.
        probeActuals.removeValue(forKey: exercise.pattern)
        // …and over the sets skipped inside it: the movement was not trained,
        // so there is no volume to take off it next time.
        setsSkipped.removeValue(forKey: exercise.pattern)
        skippedPatterns.insert(exercise.pattern)
        advancePastExercise()
    }

    /// The pair that makes ONE set of a per-side hold. `finishHold` clears
    /// them when a set ends normally, and every OTHER way out of a set has to
    /// clear them too. They used to survive a skip: a Stop inside the mis-tap
    /// grace is the one moment the actions row is live with `holdSecondSide`
    /// still true, and skipping from there carried it into the next set —
    /// where `finishHold` took the second-side branch, so that set ended after
    /// ONE side, and the smaller-of-the-two-sides rule capped its record with
    /// a number from the set before. The `min` does not ask whether the
    /// movement is per-side, so a stale side plank could cap a plain plank.
    func resetHoldSides() {
        holdSecondSide = false
        firstSideHeld = nil
        summarySet = nil
        // The settled hold belongs to the set it was held in for exactly the
        // same reason and for exactly as long: carried into the next set it
        // would offer "Done" for an effort nobody made.
        holdSettled = false
        // And the auto-run belongs to the exercise. Both call sites of this
        // are a departure — a skipped set, or the walk past an exercise — and
        // a skip is a person saying they want the phone, which is the one
        // thing an auto-run takes away. Resetting it here rather than at the
        // four skip paths is deliberate: an omitted reset was the defect
        // class this function was written for.
        holdAutoRun = false
    }

    /// What belongs to the EXERCISE rather than to the set: the time its clock
    /// was set to, and which of its sets were ended by a thumb. Cleared where a
    /// movement is left behind, and only there.
    ///
    /// It was folded into `resetHoldSides` and that was wrong in both
    /// directions at once. A SET SKIP calls that reset — a stale second side
    /// must not cross into the next set — and took the declaration down with
    /// it: saying "hold 60" and then skipping one set silently put the sets
    /// after it back on the plan, and dropped the "≈" marks off numbers the
    /// app had guessed at. Meanwhile the ordinary way out of an exercise does
    /// NOT go through that reset at all — the last set rests and
    /// `advanceAfterRest` walks to the next movement — so a declaration made
    /// for the plank set the side plank's clock to 60 s, a movement whose own
    /// plan is 15. Two lifetimes, two functions.
    func resetHoldExercise() {
        holdDeclared = nil
        holdDeclaring = false
        holdApproxSets.removeAll()
        holdMeasured.removeAll()
    }

    /// Past the exercise in front of us, however it ended — into the next one,
    /// or into the cool-down when there is none. `startCooldown` degrades to
    /// the rating when nothing was performed.
    func advancePastExercise() {
        resetHoldSides()
        resetHoldExercise()
        if isLastExercise {
            startCooldown()
        } else {
            exIndex += 1
            maximumWarning = nil   // the note belongs to the exercise it was about
            setIndex = 0
            phase = .work
            liveActivity.update(activityWorkState())
            persistProgress()
        }
    }

    private func startRest(_ seconds: Int) {
        #if DEBUG
        // --uitest-fast: the full-flow driver must never depend on the runner
        // tapping Skip in time. Production untouched; DEBUG builds only.
        let seconds = CommandLine.arguments.contains("--uitest-fast") ? 1 : seconds
        #endif
        restRemaining = seconds
        restEndDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        restPlanned = seconds
        phase = .rest(seconds: seconds)
        liveActivity.update(.init(phase: .rest, title: nextLabel,
                                  detail: restActivityDetail, restEndDate: restEndDate))
        persistProgress()
    }

    private func tickRest() {
        guard let end = restEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != restRemaining else { return }
        if newRemaining == 0 {
            restEndDate = nil
            restRemaining = 0
            let overshoot = -end.timeIntervalSinceNow
            // A suspended app comes back to a rest that ended while it could
            // sound nothing; the beat is still owed then (R32).
            let countIn = SetFacts.restHandsOverWithCountIn(endedByTap: false,
                                                            overshootSec: overshoot)
            // THE RUN IS A PROMISE TO SOMEBODY WHO IS HERE. Past the absence
            // threshold the phone was somewhere else — a call, a pocket — and
            // starting the next hold five seconds after the app comes back
            // drops a plank on someone who is still walking to the mat. The
            // threshold is `BlockPause.absenceSeconds`, the same one the two
            // blocks freeze on, and it means the same thing here (UX review
            // 05.09.2026). The exercise is not over: the work screen comes
            // back with its own button and one tap buys the sets that are left.
            if restStartsTheNextSet, overshoot > Double(BlockPause.absenceSeconds) {
                holdAutoRun = false
            }
            // …and then the go, which marks the end of the rest — and on a
            // hands-free run is also the start of the hold, because the set
            // opens on it. When the rest hands over WITH a count-in instead,
            // that count-in ends on a go of its own five seconds later, so
            // this one announced the same beginning twice (UX review
            // 05.09.2026). Read AFTER the clearing above, so a dropped run
            // takes its count-in — and this suppression — with it.
            let countInFollows = countIn && restStartsTheNextSet
            if !countInFollows { playGo() }
            // Spoken as well as sounded, for the reason the two blocks state:
            // the subtree VoiceOver was in is replaced outright by the next
            // screen, so without this the end of a rest reaches nobody who
            // cannot see it — and the tone is behind the sounds switch.
            announce(nextLabel)
            advanceAfterRest(countIn: countIn)
        } else {
            // no tick spam after backgrounding
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < restRemaining {
                playTick()
            }
            // A second or two BEFORE the signalling window, which is what the
            // generator's `prepare()` is worth: primed at the top of a
            // two-minute rest it has long gone cold by the 3 (UX review
            // 05.09.2026).
            if newRemaining == Self.countdownSignalSeconds + 1 && store.settings.soundsEnabled {
                WorkoutSignals.prime()
            }
            withAnimation(countdownAnimation) { restRemaining = newRemaining }
        }
    }
}
