//
//  The screens of a workout: warm-up > work > rest > … > cool-down > rating.
//  What happens on them is `WorkoutSession`'s; this view renders it, forwards
//  taps, and keeps the screen awake for the whole session.
//
//  The screens are split across sibling files the way the flow is: the two
//  guided blocks (+Warmup, +Cooldown), the screen a set is performed on
//  (+Work), the summary of a finished hold (+Summary) and the escapes of the
//  work screen (+Skips).
//

import Combine
import SwiftUI
import StoreKit
import UIKit
import DredfitCore

struct WorkoutFlowView: View {
    let session: Session
    @State var flow: WorkoutSession
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) var store
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Captured at tap time (not a bool): an ordinary rest keeps ticking while
    // the sheet is open and may flip the phase underneath. The rest of a
    // hands-free run does NOT — it would start the next set under the sheet,
    // so `openRestTechnique` freezes that one.
    @State var techniqueTarget: TechniqueTarget?
    // Unlike techniqueTarget, presenting this freezes the countdown.
    @State private var positionTechnique: PositionTechnique?
    @State private var lastResult: FeedbackResult?   // gates the review ask
    @State private var exitConfirmShown = false

    /// The skip a thumb has asked for and not confirmed yet — see
    /// SkipConfirmation.swift for why one is asked for at all.
    @State var pendingSkip: SkipConfirmation?

    @ScaledMetric(relativeTo: .largeTitle) private var restRingSize: CGFloat = 240
    /// The set dots of the work screen. A dot is the size of the caption it
    /// stands over, so it follows the same setting.
    @ScaledMetric(relativeTo: .caption) var setDotSize: CGFloat = 10

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// `settleImmediately` opens straight on the rating — see `WorkoutSession`.
    init(session: Session, resume: WorkoutSnapshot?, settleImmediately: Bool, store: AppStore) {
        self.session = session
        _flow = State(initialValue: WorkoutSession(
            session: session, store: store,
            resume: resume, settleImmediately: settleImmediately,
            liveActivity: WorkoutActivityController(),
            signals: DeviceSignals(),
            now: { .now }))
    }

    private var isMilestone: Bool { if case .milestone = flow.phase { return true }; return false }

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

            switch flow.phase {
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
                FeedbackView(session: session, facts: flow.actuals,
                             setsSkipped: flow.setsSkipped,
                             skipped: flow.skippedPatterns,
                             raised: flow.raisedSteps,
                             interrupted: flow.interruptedPattern) { result, overrides in
                    let earned = flow.rate(result, overrides: overrides)
                    if earned.isEmpty {
                        dismiss()
                    } else {
                        lastResult = result
                        flow.showMilestones(earned)
                    }
                }
            case .milestone(let earned):
                MilestoneView(milestones: earned,
                              steps: store.progressCurve(through: store.lastRecord?.date),
                              // The current run, as the curve beside it: after
                              // a fresh start "then" is the new run's first.
                              retrospective: Retrospective.make(
                                  records: store.recordsSinceReset,
                                  current: store.currentPositions)) {
                    askForReviewIfEarned()
                    dismiss()
                }
            }
        }
        .settleWindow(after: screen)
        .padding(.horizontal, 24)
        .background(Theme.bg.ignoresSafeArea())
        .saveFailureBanner(store)
        .onReceive(timer) { _ in
            // Nothing the clocks drive happens behind "Leave the workout?":
            // otherwise a hands-free rest could run out under it, start the
            // next hold on its go and log it as held. Every countdown is an
            // end DATE, so a skipped tick loses nothing — after "Keep
            // training" the next tick meets whatever ran out, under the rules
            // a backgrounded app already lives by.
            guard !exitConfirmShown else { return }
            flow.tick()
        }
        .onAppear {
            // Claims the snapshot for as long as this flow is up, so a
            // foreground three hours into an idle session cannot settle the
            // workout out from under the athlete still in it.
            store.workoutFlowAppeared()
            UIApplication.shared.isIdleTimerDisabled = true
            flow.animator = { motion, change in withAnimation(motion?.animation, change) }
            flow.appear()
        }
        .onDisappear {
            store.workoutFlowDisappeared()
            UIApplication.shared.isIdleTimerDisabled = false
            flow.disappear()
        }
        .onChange(of: reduceMotion, initial: true) { _, reduce in flow.reduceMotion = reduce }
        // A held block is the one state where the app knows nobody is
        // training, so it stops holding the screen open. One place rather
        // than one per path: every way in and out of a pause runs through it.
        .onChange(of: flow.blockPause.isHeld) { _, held in
            UIApplication.shared.isIdleTimerDisabled = !held
        }
        // Only `.background` is leaving: Control Center or a pulled-down
        // notification is `.inactive`, and the person is still here.
        .onChange(of: scenePhase) { _, scene in
            switch scene {
            case .background: flow.sceneLeft()
            case .active: flow.sceneCameBack()
            default: break
            }
        }
        // WITHOUT `planned:` — the step-below block belongs to the screen that
        // shows the UPCOMING workout, never to one that is running. The
        // session is snapshotted at Start, so a switch taken here would move
        // the state under a plan already in flight, and the rating lands on
        // the pair: measured, squat v6 3×15 switched to v5 and
        // rated "on plan" writes 15 into the journal of v5, where the person
        // had shown 4 — and a probe passed later in the same session promotes
        // straight past the rung they just chose, undoing the decision without
        // saying so. The engine is right; the two states simply must not move
        // at once.
        .sheet(item: $techniqueTarget, onDismiss: flow.resumeRestCountdown) { target in
            TechniqueSheet(target: target)
        }
        .sheet(item: $positionTechnique, onDismiss: flow.resumePositionCountdown) { technique in
            PositionTechniqueSheet(technique: technique)
        }
        .alert(String(localized: "Leave the workout?"),
               isPresented: $exitConfirmShown) {
            // An ALERT, not a confirmationDialog: iOS 26 presents the latter
            // as an anchored popover, so the same question would draw a centred
            // card in the workout and a tailed bubble pointing at a settings
            // row.
            // An alert has no anchor — every one of these is the same window,
            // centred, whatever it was raised from.
            //
            // A popover suppresses its cancel action, because tapping outside
            // IS the cancel, so it needs a SECOND, role-less button as the
            // escape. An alert does not: measured on iPhone 17 Pro / iOS 26.5,
            // the node is `Alert` with no `Popover` beside it, and all four
            // buttons stand in the accessibility tree — the `.cancel` one
            // included. So the escape is one button, carrying the role AND the
            // name that says what it does. "Cancel" answers "cancel what?";
            // this one does not.
            Button(String(localized: "Keep training"), role: .cancel) { }
            Button(String(localized: "Finish now")) { flow.finishNow() }
            // Every number here is persisted at every transition
            // (`persistProgress`), so stepping out keeps the workout and Today
            // offers to pick it up — without this button the choice would be
            // to rate an unfinished session as if it were over, or to throw it
            // away. Past the resume window what was done is settled on plan
            // rather than lost (`settleAbandonedWorkout`), so neither ending
            // drops the work.
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

    /// The screens a settle window is keyed by: the phase without its payload.
    /// Three things the phase alone does not show also change the button under
    /// the finger: a guided block's transition giving way to its position, the
    /// next position's transition after a skip, and a probe hold's Stop
    /// turning into Done when its clock runs out.
    private enum Screen: Hashable {
        case warmupIntro, rest, exerciseSummary, cooldownIntro, feedback, milestone
        case warmupTransition(Int), warmupPosition(Int), cooldownTransition(Int), cooldownPosition(Int)
        case work(settled: Bool)
    }

    private var screen: Screen {
        switch flow.phase {
        case .warmupIntro: return .warmupIntro
        case .warmup:
            return flow.reentering || flow.warmup.stage == .getReady
                ? .warmupTransition(flow.warmup.index) : .warmupPosition(flow.warmup.index)
        case .work: return .work(settled: flow.holdSettled)
        case .rest: return .rest
        case .exerciseSummary: return .exerciseSummary
        case .cooldownIntro: return .cooldownIntro
        case .cooldown:
            return flow.reentering || flow.cooldown.stage == .getReady
                ? .cooldownTransition(flow.cooldown.index) : .cooldownPosition(flow.cooldown.index)
        case .feedback: return .feedback
        case .milestone: return .milestone
        }
    }

    private func discardWorkout() {
        flow.discard()
        dismiss()
    }

    // MARK: - Header with progress segments

    @ViewBuilder
    private var header: some View {
        if flow.phase != .feedback, !isMilestone {
            FlowHeader(title: headerTitle,
                       steps: flow.isWarmingUp ? 0 : flow.exercises.count,
                       // The cool-down is past the LAST exercise, not on it:
                       // `exIndex` stops at count - 1, so the final capsule
                       // would stay "under way" for the whole block and the
                       // bar could never say the work was done.
                       doneIndex: flow.phase == .cooldown || flow.phase == .cooldownIntro
                           ? flow.exercises.count : flow.exIndex,
                       minutesLeft: flow.minutesLeft) {
                if flow.hasProgress {
                    exitConfirmShown = true
                } else {
                    discardWorkout()
                }
            }
        }
    }

    private var headerTitle: String {
        switch flow.phase {
        case .work, .exerciseSummary:
            return String(localized: "\(flow.exIndex + 1) / \(flow.exercises.count)")
        case .warmup, .warmupIntro: return String(localized: "WARM-UP")
        case .cooldownIntro, .cooldown: return String(localized: "COOL-DOWN")
        default:        return String(localized: "REST")
        }
    }

    // MARK: - The technique sheet (shared by both guided blocks)

    func openPositionTechnique(_ technique: PositionTechnique) {
        positionTechnique = technique
        flow.freezeForPositionTechnique()
    }

    func countdownIdentifier(reentering: Bool) -> String {
        reentering ? "reentry-countdown" : "getready-countdown"
    }

    // MARK: - Rest

    private func openRestTechnique() {
        flow.freezeRestForTechnique()
        techniqueTarget = flow.restTechniqueTarget
    }

    private var restView: some View {
        RestRing(remaining: flow.restClock.remaining,
                 fraction: progressFraction,
                 ringSize: restRingSize,
                 nextLabel: flow.nextLabel,
                 extensionSeconds: WorkoutSession.restExtensionSeconds,
                 // Frozen, "+N s" would add to a clock that is not moving:
                 // the same reason "I'm ready" hides on a paused transition.
                 // Skip stays live — an escape must always be reachable.
                 canExtend: flow.canExtendRest && !flow.blockPause.isHeld,
                 paused: flow.blockPause.isHeld,
                 // Offered only where the clock acts on its own. On every
                 // other rest nothing happens without the person, and a
                 // control that promises to stop something that is not moving
                 // is worse than no control.
                 onPauseToggle: flow.restStartsTheNextSet ? { flow.toggleBlockPause() } : nil,
                 onTechnique: { openRestTechnique() },
                 onExtend: flow.extendRest,
                 onSkip: flow.skipRest)
    }

    private var progressFraction: CGFloat {
        guard case .rest(let total) = flow.phase, total > 0 else { return 0 }
        return CGFloat(flow.restClock.remaining) / CGFloat(total)
    }
}

extension WorkoutSession.Motion {
    /// The digit roll every countdown in the flow shares — one definition, so
    /// Reduce Motion is honoured by all of them or none.
    var animation: Animation {
        switch self {
        case .countdown: return .linear(duration: 0.3)
        case .note: return .easeOut(duration: 0.25)
        }
    }
}
