//
//  The screens of a workout: warm-up > work > rest > … > cool-down > rating.
//  Port of ios/Dredfit/Views/Workout/WorkoutFlowView.swift. What happens on
//  them is `WorkoutSession`'s; this view renders it, forwards taps, ticks the
//  clocks once a second while the app is in front, and keeps the screen on.
//
//  The screens are split across sibling files the way the flow is:
//  WorkoutFlowViewWarmup/Cooldown (the guided blocks), WorkoutFlowViewWork
//  (the screen a set is performed on), WorkoutFlowViewSummary (a finished
//  hold) and WorkoutFlowViewSkips (the escapes of the work screen).
//
//  BACK. iOS presents the workout as a full-screen cover, which has no back
//  gesture at all — the way out is the header's Exit. On Android the system
//  back is always there, so it IS Exit: the same question when there is
//  progress to lose, the same quiet discard when there is none. Swallowing it
//  would leave a person who is used to back with no way out they recognise;
//  letting it close the flow silently would drop the question that keeps
//  "Finish later" from losing a workout.
//

package com.dredfit.ui.workout

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.dredfit.core.Session
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.signals.DeviceSignals
import com.dredfit.store.AppStore
import com.dredfit.store.currentPositions
import com.dredfit.store.lastRecord
import com.dredfit.store.progressCurve
import com.dredfit.store.recordsSinceReset
import com.dredfit.ui.Observed
import com.dredfit.ui.SaveFailureBanner
import com.dredfit.ui.technique.TechniqueSheet
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.tr
import com.dredfit.workout.ActivityState
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.Retrospective
import com.dredfit.workout.TechniqueTarget
import com.dredfit.workout.WorkoutActivityDriving
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.canExtendRest
import com.dredfit.workout.discard
import com.dredfit.workout.extendRest
import com.dredfit.workout.finishNow
import com.dredfit.workout.nextLabel
import com.dredfit.workout.restStartsTheNextSet
import com.dredfit.workout.skipRest
import com.dredfit.workout.toggleBlockPause
import com.dredfit.workout.freezeForPositionTechnique
import com.dredfit.workout.freezeRestForTechnique
import com.dredfit.workout.hasProgress
import com.dredfit.workout.isWarmingUp
import com.dredfit.workout.minutesLeft
import com.dredfit.workout.reentering
import com.dredfit.workout.restTechniqueTarget
import com.dredfit.workout.resumePositionCountdown
import com.dredfit.workout.resumeRestCountdown
import com.dredfit.workout.sceneCameBack
import com.dredfit.workout.sceneLeft
import java.time.Instant

/**
 * The workout in flight: the session snapshotted at the tap (a live read
 * would flip the rating screen to the NEXT session once the rating lands)
 * and its flow. Held by the process, not by the screen, so a recreated
 * activity (a theme or language change) finds the same flow; a process death
 * loses it, and Today's "Continue the workout?" picks the snapshot up.
 */
class ActiveWorkout(val session: Session, val flow: Observed<WorkoutSession>, val signals: DeviceSignals) {
    companion object {
        fun start(session: Session, store: AppStore, signals: DeviceSignals, resume: WorkoutSnapshot? = null,
                  settleImmediately: Boolean = false): ActiveWorkout =
            ActiveWorkout(session, Observed(WorkoutSession(
                session = session, store = store, resume = resume, settleImmediately = settleImmediately,
                liveActivity = NoOngoingNotification, signals = signals, now = Instant::now)), signals)
    }
}

/** The ongoing notification (iOS's Live Activity) arrives with phase 3; until
 *  then the flow drives nothing. */
private object NoOngoingNotification : WorkoutActivityDriving {
    override fun start(sessionNumber: Int, state: ActivityState) = Unit
    override fun update(state: ActivityState) = Unit
    override fun end() = Unit
}

@Composable
fun WorkoutFlowView(active: ActiveWorkout, observedStore: Observed<AppStore>, onClose: () -> Unit) {
    val observed = active.flow
    val flow by observed
    val store by observedStore
    var techniqueTarget by remember { mutableStateOf<TechniqueTarget?>(null) }
    var positionTechnique by remember { mutableStateOf<PositionTechnique?>(null) }
    var exitConfirmShown by remember { mutableStateOf(false) }
    var pendingSkip by remember { mutableStateOf<SkipConfirmation?>(null) }
    val exitShown by rememberUpdatedState(exitConfirmShown)
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    // On screen: the flow primes the signals and starts. Once — `appear` is
    // guarded — so a recreated activity picks the same flow up where it was.
    // The CLAIM on the snapshot is not taken here but where the flow is
    // started and closed (RootScreen): a recreated activity disposes this
    // composition, and its onResume would run the settlement of a forgotten
    // workout before the new composition could claim the snapshot back.
    LaunchedEffect(observed) {
        observed.act { appear() }
    }

    // One second of the flow, while the app is in front — a backgrounded iOS
    // app runs no timer either, and every countdown is an end date, so a
    // skipped tick loses nothing. Nothing the clocks drive happens behind
    // "Leave the workout?": the clocks run on and are only primed.
    //
    // A main-looper timer, like iOS's `Timer.publish(every: 1)`, rather than
    // a coroutine `delay`: the flow's clocks are wall-clock end dates, and a
    // composition's coroutines run on the frame clock a UI test drives in
    // virtual time — a tick has to stay a real second everywhere.
    //
    // Only leaving is leaving: a pulled-down shade keeps the app started.
    DisposableEffect(lifecycle, observed) {
        val main = Handler(Looper.getMainLooper())
        // Re-armed on its SCHEDULE, like `Timer.publish`, not a second after
        // the beat's own work (tones, vibration): a drifting beat crosses a
        // countdown's second boundary, `read` jumps two seconds, and a 3-2-1
        // loses its tick.
        var next = 0L
        val beat = object : Runnable {
            override fun run() {
                observed.act { if (exitShown) primeComingBack() else tick() }
                next += 1000
                main.postAtTime(this, next)
            }
        }
        val watcher = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> {
                    observed.act { sceneCameBack() }
                    next = SystemClock.uptimeMillis() + 1000
                    main.postAtTime(beat, next)
                }
                Lifecycle.Event.ON_STOP -> {
                    main.removeCallbacks(beat)
                    observed.act { sceneLeft() }
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(watcher)
        onDispose {
            lifecycle.removeObserver(watcher)
            main.removeCallbacks(beat)
        }
    }

    // The screen stays on for the whole session — except while a block is
    // held, the one state where the app knows nobody is training.
    val held = flow.blockPause.isHeld
    val view = LocalView.current
    DisposableEffect(held) {
        view.keepScreenOn = !held
        onDispose { view.keepScreenOn = false }
    }

    fun discardWorkout() {
        observed.act { discard() }
        onClose()
    }

    fun exit() {
        if (flow.hasProgress) exitConfirmShown = true else discardWorkout()
    }

    // On the rating and the milestone iOS offers no way out but the answer —
    // the header with Exit is not there — and "Finish now" or "Discard" over
    // a finished workout would damage its record. So Back is Exit on every
    // screen that shows Exit, waits for the rating on the rating, and is the
    // milestone's own Done there.
    BackHandler {
        when (flow.phase) {
            Phase.Feedback -> Unit
            is Phase.Milestone -> onClose()
            else -> exit()
        }
    }

    val c = Theme.colors
    Column(Modifier.fillMaxSize().background(c.bg).safeDrawingPadding()) {
        SaveFailureBanner(observedStore, trailingClearance = 0.dp)
        Column(Modifier.weight(1f).padding(horizontal = 24.dp).settleWindow(settleScreen(flow))) {
            val phase = flow.phase
            if (phase != Phase.Feedback && phase !is Phase.Milestone) {
                FlowHeader(title = headerTitle(flow), steps = if (flow.isWarmingUp) 0 else flow.exercises.size,
                           // The cool-down is past the LAST exercise, not on it.
                           doneIndex = if (phase == Phase.Cooldown || phase == Phase.CooldownIntro) flow.exercises.size
                                       else flow.exIndex,
                           minutesLeft = flow.minutesLeft, onExit = ::exit)
            }
            Box(Modifier.weight(1f)) {
                when (phase) {
                    Phase.WarmupIntro -> WarmupIntroView(observed)
                    Phase.Warmup -> WarmupView(observed) { positionTechnique = it; observed.act { freezeForPositionTechnique() } }
                    Phase.Work -> WorkView(observed, observedStore, { techniqueTarget = it }, { pendingSkip = it })
                    Phase.ExerciseSummary -> ExerciseSummaryView(observed)
                    is Phase.Rest -> FlowRestView(observed, phase) {
                        observed.act { freezeRestForTechnique() }
                        techniqueTarget = flow.restTechniqueTarget
                    }
                    Phase.CooldownIntro -> CooldownIntroView(observed)
                    Phase.Cooldown -> CooldownView(observed, observedStore) {
                        positionTechnique = it
                        observed.act { freezeForPositionTechnique() }
                    }
                    Phase.Feedback -> FeedbackView(
                        session = active.session, facts = flow.actuals, overrides = flow.overrides,
                        actualSets = flow.actualSets, setsSkipped = flow.setsSkipped, skipped = flow.skippedPatterns,
                        raised = flow.raisedSteps, interrupted = flow.interruptedPattern,
                    ) { result ->
                        val earned = flow.rate(result)
                        if (earned.isEmpty()) onClose() else observed.act { showMilestones(earned) }
                    }
                    is Phase.Milestone -> MilestoneView(
                        milestones = phase.earned,
                        // Up to the workout that earned these.
                        steps = store.progressCurve(through = store.lastRecord?.date),
                        // The current run, as the curve beside it: after a
                        // fresh start "then" is the new run's first.
                        retrospective = Retrospective.make(store.recordsSinceReset, store.currentPositions),
                        onDone = onClose)
                }
            }
        }
        Announcer(active.signals.announcement.value?.let { tr(it) })
    }

    // WITHOUT `planned`: the step-below block belongs to the screen that shows
    // the UPCOMING workout, never to one that is running.
    techniqueTarget?.let { target ->
        TechniqueSheet(target, planned = false, observedStore = observedStore) {
            techniqueTarget = null
            observed.act { resumeRestCountdown() }
        }
    }
    positionTechnique?.let { technique ->
        PositionTechniqueSheet(technique, observedStore) {
            positionTechnique = null
            observed.act { resumePositionCountdown() }
        }
    }
    if (exitConfirmShown) {
        DredfitAlert(
            title = tr("Leave the workout?"),
            message = tr("“Finish now” goes to the rating and marks the rest as skipped. “Finish later” keeps your place — Today offers to pick it up."),
            actions = listOf(
                // Nothing ticked while the question was up, so staying
                // catches the clocks up at once rather than on the next beat.
                AlertAction(tr("Keep training"), tag = "exit-keep-training", cancel = true) { observed.act { tick() } },
                AlertAction(tr("Finish now"), tag = "exit-finish-now") { observed.act { finishNow() } },
                // Every number is persisted at every transition, so stepping
                // out keeps the workout and Today offers to pick it up.
                AlertAction(tr("Finish later"), tag = "exit-finish-later") { onClose() },
                AlertAction(tr("Discard workout"), tag = "exit-discard", destructive = true) { discardWorkout() },
            ),
            onClose = { exitConfirmShown = false },
        )
    }
    // Beside the exit alert rather than on the work screen: a confirmed skip
    // can retire that screen, and an alert dismissed with its view is how a
    // presentation gets stuck.
    pendingSkip?.let { skip ->
        SkipConfirmationAlert(skip) { pendingSkip = null }
    }
}

/** The screens a settle window is keyed by: the phase without its payload,
 *  plus the three changes the phase alone does not show (FlowSettleTest). */
sealed interface SettleScreen {
    data object WarmupIntro : SettleScreen
    data object Rest : SettleScreen
    data object ExerciseSummary : SettleScreen
    data object CooldownIntro : SettleScreen
    data object Feedback : SettleScreen
    data object Milestone : SettleScreen
    data class WarmupTransition(val index: Int) : SettleScreen
    data class WarmupPosition(val index: Int) : SettleScreen
    data class CooldownTransition(val index: Int) : SettleScreen
    data class CooldownPosition(val index: Int) : SettleScreen
    data class Work(val settled: Boolean) : SettleScreen
}

fun settleScreen(flow: WorkoutSession): SettleScreen = when (flow.phase) {
    Phase.WarmupIntro -> SettleScreen.WarmupIntro
    Phase.Warmup -> if (flow.reentering || flow.warmup.stage == GuidedStage.getReady)
        SettleScreen.WarmupTransition(flow.warmup.index) else SettleScreen.WarmupPosition(flow.warmup.index)
    Phase.Work -> SettleScreen.Work(flow.holdSettled)
    is Phase.Rest -> SettleScreen.Rest
    Phase.ExerciseSummary -> SettleScreen.ExerciseSummary
    Phase.CooldownIntro -> SettleScreen.CooldownIntro
    Phase.Cooldown -> if (flow.reentering || flow.cooldown.stage == GuidedStage.getReady)
        SettleScreen.CooldownTransition(flow.cooldown.index) else SettleScreen.CooldownPosition(flow.cooldown.index)
    Phase.Feedback -> SettleScreen.Feedback
    is Phase.Milestone -> SettleScreen.Milestone
}

/** The rest. Frozen, "+N s" would add to a clock that is not moving; Skip
 *  stays live — an escape must always be reachable. Pause is offered only
 *  where the clock acts on its own: the rest that starts the next set. */
@Composable
private fun FlowRestView(observed: Observed<WorkoutSession>, rest: Phase.Rest, openTechnique: () -> Unit) {
    val flow by observed
    val held = flow.blockPause.isHeld
    val remaining = flow.restClock.remaining
    RestRing(
        remaining = remaining,
        fraction = if (rest.seconds > 0) remaining.toFloat() / rest.seconds else 0f,
        nextLabel = tr(flow.nextLabel),
        canExtend = flow.canExtendRest && !held,
        paused = held,
        onPauseToggle = if (flow.restStartsTheNextSet) ({ observed.act { toggleBlockPause() } }) else null,
        onTechnique = openTechnique,
        onExtend = { observed.act { extendRest() } },
        onSkip = { observed.act { skipRest() } },
    )
}

@Composable
private fun headerTitle(flow: WorkoutSession): String = when (flow.phase) {
    Phase.Work, Phase.ExerciseSummary -> tr("%lld / %lld", flow.exIndex + 1, flow.exercises.size)
    Phase.Warmup, Phase.WarmupIntro -> tr("WARM-UP")
    Phase.CooldownIntro, Phase.Cooldown -> tr("COOL-DOWN")
    else -> tr("REST")
}
