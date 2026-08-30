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

// The type is split across four sibling files: the two guided blocks
// (+Warmup, +Cooldown), the holds and session persistence (+Session), and the
// pause of a guided block (+BlockPause). The reason is a CI error rather than
// a style opinion — the lint's hard ceiling on a file is 1200 lines.
//
// Swift's `private` is FILE-scoped, so the state and helpers those siblings
// reach for are declared without it. They are internal to the module and to
// this type, not API: nothing outside these five files touches them.
//
// The extension at the bottom of THIS file is a different matter. It is here
// rather than in a sibling because the second ceiling — 600 lines for the
// type's own body — does not follow an extension anywhere, so a body only
// shrinks by moving members out of it, and moving them across a file boundary
// as well would have cost visibility for nothing.
struct WorkoutFlowView: View {
    let session: Session
    var resume: WorkoutSnapshot?
    @Environment(\.dismiss) var dismiss
    @Environment(AppStore.self) var store
    @Environment(\.requestReview) private var requestReview

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
    // Captured at tap time (not a bool): the rest countdown keeps ticking
    // while the sheet is open and may flip the phase underneath.
    @State private var techniqueTarget: TechniqueTarget?
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
    @State var skippedPatterns: Set<Pattern> = []
    /// Kept apart from `skippedPatterns`: the engine treats both as skips for
    /// the session, but the rating and the history say different things.
    @State var adjusting = false
    /// Movements this session has already been warned about. Once per exercise
    /// — a second copy of the same advice is nagging.
    @State private var maximumNoted: Set<Pattern> = []
    @State var maximumWarning: String?
    @State private var adjustValue = 0
    @State var workoutStart: Date?   // actual duration for Health
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
    /// The hold is over and its seconds are recorded, but the set is NOT
    /// closed yet — `finishHold` stops here and the primary button finishes
    /// the job. A hold ends itself, so before this flag the number it produced
    /// left the screen in the same frame it was produced in, and "Went
    /// differently" never got a moment to exist: on the last set of a movement
    /// nothing about it ever came back.
    @State var holdSettled = false
    /// The skip a thumb has asked for and not confirmed yet — see
    /// SkipConfirmation.swift for why one is asked for at all.
    @State private var pendingSkip: SkipConfirmation?

    @ScaledMetric(relativeTo: .largeTitle) private var restRingSize: CGFloat = 240

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
    private var holding: Bool { holdEndDate != nil }
    private var holdSwitchPausing: Bool { holdPauseEndDate != nil }
    private var holdCountingIn: Bool { holdCountInEndDate != nil }
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
                            // max: the wall clock can move backwards mid-workout
                            max(0, Int(Date.now.timeIntervalSince($0)))
                        },
                        warmupSec: warmupSec, cooldownSec: cooldownSec)
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
                tickRest()
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
            UIApplication.shared.isIdleTimerDisabled = true
            guard !didStart else { return }
            didStart = true
            // Pay the audio-session setup here, not on the first tick.
            if store.settings.soundsEnabled { CountdownSounds.shared.prime() }
            if let resume { restore(from: resume) }
            if workoutStart == nil { workoutStart = .now }
            // Nothing for the lock screen to describe on the rating.
            if phase != .feedback {
                liveActivity.start(sessionNumber: session.sessionNumber,
                                   state: currentActivityState())
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            liveActivity.end()
        }
        // A held block is the one state where the app knows nobody is
        // training, so it stops holding the screen open. One place rather
        // than one per path: every way in and out of a pause runs through it.
        .onChange(of: blockPause.isHeld) { _, held in
            UIApplication.shared.isIdleTimerDisabled = !held
        }
        .sheet(item: $techniqueTarget) { target in
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
            Button(String(localized: "Discard workout"), role: .destructive) {
                discardWorkout()
            }
        } message: {
            Text("“Finish now” keeps what you've done and goes to the rating — the remaining exercises are marked as skipped.")
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
                       doneIndex: exIndex,
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
    /// Offered on the work and rest screens only. The guided blocks carry a
    /// countdown of their own and nothing on them shortens the session, and
    /// the rating is past the question entirely.
    private var minutesLeft: Int? {
        var index = exIndex
        var behind = setIndex
        switch phase {
        case .work:
            break
        case .rest:
            // The set the rest FOLLOWS is done — the flow advances after it.
            behind += 1
            if behind >= exercise.sets { index += 1; behind = 0 }
        default:
            return nil
        }
        // The cool-down is the only fixed block still ahead; the warm-up is
        // behind by the time the work screen is up.
        return SessionAhead.minutes(exercises, exIndex: index, setsBehind: behind,
                                    ends: session.cooldownMin)
    }

    private var headerTitle: String {
        switch phase {
        case .work:     return String(localized: "\(exIndex + 1) / \(exercises.count)")
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
    }

    private func resumePositionCountdown() {
        // Whatever the sheet froze is what it hands back. A way back in
        // outlives it; a pause outranks it — closing the sheet must never
        // restart a block the user stopped (issue #34 vs #61).
        blockPause.thawAfterSheet(now: .now)
        guard !blockPause.isPaused else { return }
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

    // MARK: - Work

    private var workView: some View {
        VStack(spacing: 0) {
            Spacer()
            if current.isProbe {
                // The badge is the whole announcement: one set of a movement
                // that is not yet yours, to find out whether it is. It is not
                // a question and there is nothing to answer — the number goes
                // in through the same per-set control as every other set.
                Text("Probe")
                    .dredfitFont(11, weight: .heavy)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("probe-badge")
            }
            Text(current.name)
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .accessibilityLabel(Text(verbatim: current.name))

            // On the probe set this opens the technique of the NEW movement:
            // nobody should be asked to try something they cannot read up on
            // first.
            TechniqueButton { techniqueTarget = current.target }
                .padding(.top, 10)

            VStack(spacing: 4) {
                Text("\(workNumber)")
                    .dredfitFont(112, weight: .heavy, cap: 150)
                    .tracking(-4)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(loadCaption)
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 20)
            // One element, like the rest ring below: two made VoiceOver read
            // "8" and then "reps per side" as if they were separate facts, and
            // the number alone is meaningless. Both halves are recomputed on
            // every body pass, so the label follows a hold's countdown down.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(workNumber) ") + Text(verbatim: loadCaption))

            HStack(spacing: 10) {
                ForEach(0..<totalSets, id: \.self) { i in
                    // The probe's dot is hollow: it is the same session and
                    // the same count of sets, but not the same movement.
                    Circle()
                        .strokeBorder(Theme.accent,
                                      lineWidth: exercise.probe != nil && i == exercise.sets ? 2 : 0)
                        .background(Circle().fill(
                            exercise.probe != nil && i == exercise.sets
                                ? Color.clear
                                : (i < setIndex ? Theme.ink
                                   : (i == setIndex ? Theme.accent : Theme.hairline))))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 30)

            // The count-in outranks the probe's own caption: the big number
            // above is five seconds of getting into position, and nothing else
            // on the screen would say so.
            if current.isProbe && !holdCountingIn {
                probeCaption
                    .padding(.top, 10)
            } else {
                WorkStatusCaption(countingIn: holdCountingIn,
                                  switchingSides: holdSwitchPausing,
                                  secondSide: holdSecondSide,
                                  settled: holdSettled,
                                  actual: setActual,
                                  setIndex: setIndex, sets: exercise.sets,
                                  planned: exercise.plannedLoad(set: setIndex),
                                  uneven: exercise.loads != nil)
                    .padding(.top, 10)
            }

            Spacer()

            // The messages stand down while a number is being entered: one
            // thing to read at a time.
            //
            // The hint FIRST, the note second. Both are reserved height when
            // hidden, and the order is what keeps that height from sitting
            // between the note and the button below: the note has to stand the
            // same 18 pt above the pair that the escapes stand below it, and
            // that the rest offer stands above Start on Today (owner,
            // 27.08.2026).
            if !adjusting {
                // Opacity, not `if`: the reserved height keeps the layout still
                // when the hint's job is done mid-exercise.
                if store.records.isEmpty {
                    Text("Did far more than planned? Tap “Went differently” and enter what you actually did — the next plan starts from what you showed.")
                        .dredfitFont(14)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                        .opacity(holding || holdSwitchPausing || holdCountingIn
                                 || actuals[exercise.pattern] != nil ? 0 : 1)
                }

                // Once per exercise per session, and it never blocks the entry
                // — the number stands either way. It used to be grey 13 pt in
                // the fine-print slot directly above the black primary button,
                // which is the one place on the screen nobody reads (owner,
                // 27.08.2026). accentText on accentSoft, not accent: accent
                // itself is 2.91:1 on that fill (see the badge pill on Today).
                if let warning = maximumWarning {
                    Text(warning)
                        .dredfitFont(14, weight: .medium)
                        .foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("maximum-note")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            // The entry opens IN THE SLOT OF THE BUTTON THAT OPENS IT, directly
            // over the primary one it will hand back to. Nothing below moves:
            // the block after the Spacer is bottom-aligned as a group, so what
            // is added or removed above the button changes where the group
            // starts, never where the button sits.
            if adjusting {
                AdjustPanel(value: $adjustValue, unit: current.unit) {
                    if current.isProbe {
                        // The probe's own channel: one number about one set of
                        // another movement, never folded into the mean of the
                        // working sets.
                        probeActuals[exercise.pattern] = adjustValue
                    } else {
                        // This set only — the ones behind keep what they ran at.
                        actuals = SetFacts.recording(adjustValue, in: actuals,
                                                     exercise, set: setIndex)
                        noteMaximumOutOfOrder()
                    }
                    adjusting = false
                    persistProgress()   // an entered actual is worth keeping
                }
                .padding(.bottom, 18)
            } else {
                WentDifferentlyButton { startAdjusting() }
                    .padding(.bottom, 18)
                    // no adjusting mid-hold, mid-count-in or mid-pause
                    .opacity(holding || holdSwitchPausing || holdCountingIn ? 0 : 1)
                    .disabled(holding || holdSwitchPausing || holdCountingIn)
            }

            if current.unit == .hold {
                if holding {
                    PrimaryButton(title: String(localized: "Stop")) { stopHoldEarly() }
                        .accessibilityIdentifier("hold-stop")
                } else if holdSwitchPausing || holdCountingIn {
                    // hidden, not opacity: the button must leave the
                    // accessibility tree while keeping its reserved space.
                    // A count-in is armed already — a second tap on the slot
                    // it left must not land on anything.
                    //
                    // Its own identifier, not the live one's: should `.hidden()`
                    // ever stop pruning the tree, a query for the real control
                    // must not resolve to this placeholder.
                    PrimaryButton(title: String(localized: "Start hold")) { }.hidden()
                        .accessibilityIdentifier("hold-start-spacer")
                } else if holdSettled {
                    // The hold is behind; this tap only logs it. Same title
                    // and same identifier as the reps button, because it is
                    // the same act — the set ends when the person says the
                    // number is right, not when a clock says the effort is
                    // over.
                    PrimaryButton(title: String(localized: "Done")) { completeSet() }
                        .accessibilityIdentifier("exercise-done")
                } else {
                    PrimaryButton(title: String(localized: "Start hold")) { startHold() }
                        .accessibilityIdentifier("hold-start")
                }
            } else {
                PrimaryButton(title: String(localized: "Done")) { completeSet() }
                    .accessibilityIdentifier("exercise-done")
            }

            ExerciseActionsRow(onSkipSet: setSkipAction,
                               skipsProbe: onProbeSet,
                               escape: exerciseEscape)
            // 18, the measure of this whole stack: the same gap stands between
            // the note and "Went differently", between it and the button, and
            // here between the button and the escapes. It was 18 to begin with
            // for a reason that still holds — the button between them LOGS THE
            // SET, and a thumb that lands a few points off does not miss, it
            // finishes the set at plan.
            .padding(.top, 18)
            .padding(.bottom, 10)
            // No adjusting/skipping mid-hold, mid-count-in or mid-pause —
            // and none once the hold is behind either: the set was performed
            // and its number is on the screen, so a skip there would contradict
            // the very fact the person is being shown.
            .opacity(holding || holdSwitchPausing || holdCountingIn || holdSettled ? 0 : 1)
            .disabled(holding || holdSwitchPausing || holdCountingIn || holdSettled)

        }
    }

    /// In order of precedence.
    private var workNumber: Int {
        if holdCountingIn { return holdCountInRemaining }
        if holdSwitchPausing { return holdPauseRemaining }
        if holding { return holdRemaining }
        if current.isProbe { return probeActuals[exercise.pattern] ?? current.planned }
        return SetFacts.inForce(actuals, exercise, set: setIndex)
    }

    /// The caption's: this set's own number, nothing when it is the plan.
    /// The plan of THIS SET — against the flat base an untouched top set of
    /// an uneven plan read as an entered fact (UI-truth audit, 27.08.2026).
    private var setActual: Int? {
        SetFacts.offPlan(actuals, exercise, set: setIndex)
    }

    // MARK: - Inline actual adjuster (the panel itself is AdjustPanel.swift)

    private func startAdjusting() {
        adjustValue = current.isProbe
            ? (probeActuals[exercise.pattern] ?? current.planned)
            : SetFacts.inForce(actuals, exercise, set: setIndex)
        adjusting = true
    }

    /// What the probe set says under its number. Before a number is entered it
    /// states the target; afterwards it states the outcome — and the failing
    /// outcome is NEUTRAL, because honesty is never punished (§40.4): staying
    /// on a movement you can already do is not a failure, and the copy must
    /// not read like one.
    ///
    /// The failing line used to read "We'll stay with the current variation",
    /// and it needed explaining for two reasons (owner, 27.08.2026). It said
    /// "variation", a word this app's own vocabulary does not use anywhere
    /// else on screen. And it pointed at something NOT ON SCREEN: at that
    /// moment the title is the NEXT movement with a "Probe" badge over it, so
    /// "the current one" is a name the reader has to reconstruct — where the
    /// passing line names its movement outright. What replaced it states the
    /// consequence instead, which is the thing the reader will actually see
    /// tomorrow, and deliberately does NOT promise the probe comes back next
    /// time: a session later rated "hard" on this pattern suppresses it.
    @ViewBuilder
    private var probeCaption: some View {
        if let entered = probeActuals[exercise.pattern] {
            if entered >= current.planned && !workingSetsFellShort {
                Text("Next time: \(current.name)")
                    .accessibilityIdentifier("probe-passed")
            } else {
                // Also the answer for a probe done at target AFTER working
                // sets that fell short: the engine reads that session as
                // "hard" for the pattern, and a hard pattern's probe does not
                // count (§40.4) — a promise here would be broken by numbers
                // already entered (UI-truth audit, 27.08.2026).
                Text("Not this time — the plan stays as it is.")
                    .accessibilityIdentifier("probe-stays")
            }
        } else {
            // No number here: the big one above IS this number, and the
            // caption repeated it (owner, 27.08.2026). On a hold probe the
            // big number starts counting down once the timer runs, and the
            // target then shows nowhere — which is exactly what an ORDINARY
            // hold does too, so the probe simply stops being the exception.
            Text("One set to try it.")
        }
    }

    /// The knowable half of the §40.4 gate — see `SetFacts.foldFallsShort`.
    private var workingSetsFellShort: Bool {
        SetFacts.foldFallsShort(actuals, of: exercise)
    }

    private var loadCaption: String {
        // During the switch pause and the count-in the big number is a
        // countdown, not the load.
        if holdSwitchPausing || holdCountingIn { return String(localized: "sec") }
        // The unit only: the 112 pt number above already says how many, and
        // printing it twice is the kind of noise that makes a screen feel
        // busy. Because the caption no longer agrees with a number, these
        // keys need no ICU plurals — one form per language.
        switch (current.unit, current.perSide) {
        case (.reps, false): return String(localized: "reps")
        case (.reps, true):  return String(localized: "reps per side")
        case (.hold, false): return String(localized: "seconds")
        case (.hold, true):  return String(localized: "seconds per side")
        }
    }

    // MARK: - Rest

    private var restView: some View {
        RestRing(remaining: restRemaining,
                 fraction: progressFraction,
                 ringSize: restRingSize,
                 nextLabel: nextLabel,
                 extensionSeconds: Self.restExtensionSeconds,
                 canExtend: canExtendRest,
                 onTechnique: { techniqueTarget = restTechniqueTarget },
                 onExtend: extendRest,
                 onSkip: {
                     restEndDate = nil
                     restRemaining = 0
                     advanceAfterRest()
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
                                  detail: String(localized: "Next up"),
                                  restEndDate: newEnd))
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
        // A hold has already sounded its own ending, at the moment the effort
        // actually stopped (see `finishHold`). The tap that lands here after
        // one confirms a number; sounding "done" again would announce an end
        // that happened seconds ago.
        if !holdSettled { playDone() }
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
    private func noteMaximumOutOfOrder() {
        let pattern = exercise.pattern
        guard !maximumNoted.contains(pattern) else { return }
        // The rule itself is `SetFacts.maximumOutOfOrder`, where a test can
        // reach it — and where the reason it is NOT about the order of sets
        // is written down.
        guard SetFacts.maximumOutOfOrder(adjustValue, exercise, set: setIndex) else { return }
        maximumNoted.insert(pattern)
        withAnimation(.easeOut(duration: 0.25)) {
            maximumWarning = String(localized: """
                A maximum now takes the strength out of the sets after it. \
                What counts is the whole exercise, not one set.
                """)
        }
    }

    /// Leaving an exercise early. There used to be two ways — a skip and a
    /// pain report — and the report is gone. A person who finds the movement
    /// too hard now reaches for a handle instead, which keeps the movement in
    /// the plan rather than taking it out for weeks.
    private func leaveExercise() {
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
        // The settled hold belongs to the set it was held in for exactly the
        // same reason and for exactly as long: carried into the next set it
        // would offer "Done" for an effort nobody made.
        holdSettled = false
    }

    /// Past the exercise in front of us, however it ended — into the next one,
    /// or into the cool-down when there is none. `startCooldown` degrades to
    /// the rating when nothing was performed.
    private func advancePastExercise() {
        resetHoldSides()
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

    // MARK: - The skip that happens DURING the workout

    /// Whether a skip still leaves a trained movement behind, asked of the
    /// plan in front of us — the arithmetic itself is `SetFacts.skipFits`,
    /// where it can be tested without a screen.
    private func skipsLeaveAMovement(_ count: Int) -> Bool {
        SetFacts.skipFits(count, of: exercise.sets,
                          alreadySkipped: setsSkipped[exercise.pattern] ?? 0)
    }

    /// Sets of this exercise already behind and actually performed.
    private var setsPerformedHere: Int {
        setIndex - (setsSkipped[exercise.pattern] ?? 0)
    }

    /// "Skip this set": the set is not performed and the next one is up.
    ///
    /// No rest on the way out — there is nothing to recover from, and the
    /// minutes are the whole point of the tap.
    private func skipSet() {
        // Skipping the PROBE takes no volume off anything: it was never a set
        // of the planned movement. The outcome is "unresolved" (§40.4) — the
        // probe simply comes back next time — and the appearance is spent
        // exactly as it would have been.
        if onProbeSet {
            adjusting = false
            probeActuals.removeValue(forKey: exercise.pattern)
            advancePastExercise()
            return
        }
        guard skipsLeaveAMovement(1) else { leaveExercise(); return }
        adjusting = false
        setsSkipped[exercise.pattern, default: 0] += 1
        if isLastSet {
            advancePastExercise()
        } else {
            resetHoldSides()   // see `resetHoldSides`: this path skips it otherwise
            setIndex += 1
            phase = .work
            liveActivity.update(activityWorkState())
            persistProgress()
        }
    }

    /// "Skip the remaining sets": one tap for the whole movement. Sixteen
    /// separate taps to fit a session into 45 minutes is a thing nobody does;
    /// three to six is.
    private func skipRestOfExercise() {
        // Only the WORKING sets can be taken off; on the probe set there are
        // none left, and the probe itself is not volume.
        let left = max(0, exercise.sets - setIndex)
        guard skipsLeaveAMovement(left) else { leaveExercise(); return }
        adjusting = false
        setsSkipped[exercise.pattern, default: 0] += left
        advancePastExercise()
    }

    /// The set-level skip, or nil when it would take the movement with it —
    /// then the escape beside it says so in its own label instead of doing it
    /// quietly under a word that promises less.
    private var setSkipAction: (() -> Void)? {
        // The probe can ALWAYS be skipped (§40.4): it is not a set of the
        // planned movement, so skipping it takes no volume off anything and
        // cannot leave the movement untrained. The outcome is "unresolved",
        // and the probe comes back on the next appearance.
        if onProbeSet {
            return { pendingSkip = SkipConfirmation(kind: .probeSet) { skipSet() } }
        }
        guard skipsLeaveAMovement(1) else { return nil }
        return { pendingSkip = SkipConfirmation(kind: .workingSet) { skipSet() } }
    }

    /// The exercise-level escape, and the landing its label names. The two
    /// controls collapse into one whenever they would do the same thing: on
    /// the floor both take the movement, and on the last set "the remaining
    /// sets" ARE this set.
    private var exerciseEscape: ExerciseActionsRow.Escape? {
        // On the probe set the working sets are already behind: "skip the
        // exercise" would throw away a movement that was in fact trained.
        // Skipping the probe is the set-level control beside this one.
        guard !onProbeSet else { return nil }
        let leave = ExerciseActionsRow.Escape(
            title: String(localized: "Skip exercise"),
            identifier: "exercise-skip",
            action: { pendingSkip = SkipConfirmation(kind: .exercise) { leaveExercise() } })
        guard skipsLeaveAMovement(1) else { return leave }
        guard !isLastSet else { return nil }
        guard setsPerformedHere >= EngineConfig.setsFloor else { return leave }
        return ExerciseActionsRow.Escape(
            title: String(localized: "Skip remaining sets"),
            identifier: "exercise-skip-rest",
            action: { pendingSkip = SkipConfirmation(kind: .restOfSets) { skipRestOfExercise() } })
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
                                  detail: String(localized: "Next up"),
                                  restEndDate: restEndDate))
        persistProgress()
    }

    private func tickRest() {
        guard let end = restEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != restRemaining else { return }
        if newRemaining == 0 {
            restEndDate = nil
            restRemaining = 0
            playGo()
            advanceAfterRest()
        } else {
            // no tick spam after backgrounding
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < restRemaining {
                playTick()
            }
            withAnimation(.linear(duration: 0.3)) { restRemaining = newRemaining }
        }
    }
}
