//
//  The workout flow apart from its screens: warm-up > work > rest > … >
//  cool-down > rating. Port of ios/Dredfit/WorkoutSession.swift.
//
//  Every countdown is wall-clock based (an end date, not a tick count), so a
//  backgrounded app loses nothing, and the snapshot written on every phase
//  transition (WorkoutSessionSnapshot.kt) is what survives Android killing
//  the process. Nothing here imports Android: the clock, the tones and the
//  tile are handed in, so a tap, a tick or a process death runs in a JVM test.
//
//  Split by what each part of the flow does, one file per Swift extension:
//  WorkoutSessionSets/Rest/Holds/Summary/Skips/Warmup/Cooldown/Blocks/
//  BlockPause/Snapshot.kt. The state those files share is public, as Swift's
//  is internal; only the flow writes it (and a test, as on iOS).
//
//  Swift structs held here (Countdown, GuidedBlockRun, BlockPause.State,
//  Absence) are mutable classes, each owned by this flow alone and never
//  shared; the maps and sets are immutable values reassigned whole.
//

package com.dredfit.workout

import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.totalSets
import java.time.Instant

class WorkoutSession(
    val session: Session,
    val store: AppStore,
    /** The snapshot this flow picks up from, read once by `appear`. */
    private val resume: WorkoutSnapshot?,
    /** Open straight on the rating, cataloguing whatever is unfinished — the
     *  answer to "keep this workout?" on Today. */
    private val settleImmediately: Boolean,
    val liveActivity: WorkoutActivityDriving,
    val signals: WorkoutSignalling,
    val now: () -> Instant,
) {
    /** The motions the flow asks for; with reduced motion, none at all. */
    @Suppress("EnumEntryName")
    enum class Motion { countdown, note }

    /** The screen's animation wrapper, handed in; a plain call by default,
     *  which is what a test needs. */
    var animator: (Motion?, () -> Unit) -> Unit = { _, change -> change() }

    /** The system's "remove animations" as the screen reads it. */
    var reduceMotion: Boolean = false

    sealed interface Phase {
        /** The warm-up does not start itself — offered, never required. */
        data object WarmupIntro : Phase
        data object Warmup : Phase
        data object Work : Phase
        data class Rest(val seconds: Int) : Phase
        /** Every done set of a hold movement on one screen, the last one a
         *  tap from being corrected. */
        data object ExerciseSummary : Phase
        /** The cool-down does not start itself either. */
        data object CooldownIntro : Phase
        data object Cooldown : Phase
        data object Feedback : Phase
        /** Only when the workout earned one. */
        data class Milestone(val earned: List<com.dredfit.workout.Milestone>) : Phase
    }

    /** What the adjuster panel is open on — set by whoever opens it, so OK
     *  never depends on what the screen shows when it is tapped. */
    sealed interface EditTarget {
        /** The set under way: its record, or the probe's number. */
        data object Set : EditTarget
        /** How long this hold exercise will run — a target, not a record. */
        data object HoldTime : EditTarget
        /** A card of the exercise summary: the set that was tapped. */
        data class SummaryCard(val index: Int) : EditTarget
    }

    var exIndex: Int = 0
    var setIndex: Int = 0          // 0-based
    var phase: Phase = Phase.WarmupIntro

    /** Where each guided block stands — one clock for every stage. */
    var warmup: GuidedBlockRun = GuidedBlockRun()
    var cooldown: GuidedBlockRun = GuidedBlockRun()

    /** Drawn on entry, recomposed only when a position is set aside or back. */
    var cooldownPositions: List<CooldownPosition> = emptyList()

    /** The pause of the guided blocks (#61) and of a hands-free rest. */
    var blockPause: BlockPause.State = BlockPause.State()

    var restClock: Countdown = Countdown()

    /** What this transition planned — the extension cap is twice it. */
    var restPlanned: Int = 0

    /** A fact belongs to the set it happened on (SetFacts). */
    var actuals: Map<Pattern, List<Int>> = emptyMap()

    /** Sets skipped along the way — handed to the engine only when the
     *  rating lands: the cut belongs on the RESULT of the feedback. */
    var setsSkipped: Map<Pattern, Int> = emptyMap()

    /** Which of those the person skipped, by index. */
    var skippedSetIndices: Map<Pattern, Set<Int>> = emptyMap()

    /** The ones among those that carry a number entered before the skip. */
    var skippedWithNumber: Map<Pattern, Set<Int>> = emptyMap()

    /** Sets the person entered a number for, by index — in the session only. */
    var numbersEntered: Map<Pattern, Set<Int>> = emptyMap()

    /** What the PROBE set showed — its own channel, never folded. */
    var probeActuals: Map<Pattern, Int> = emptyMap()

    /** Steps added "for next time" — a DECISION, landed after the rating. */
    var raisedSteps: Map<Pattern, Int> = emptyMap()

    var skippedPatterns: Set<Pattern> = emptySet()

    var editing: EditTarget? = null

    /** Movements already warned about — once per exercise. */
    var maximumNoted: Set<Pattern> = emptySet()

    var maximumWarning: Words? = null

    var adjustValue: Int = 0

    var workoutStart: Instant? = null

    /** Seconds spent away across resumes, subtracted from the duration. */
    var awaySec: Int = 0

    /** The moment the flow left, while the process lives on (`sceneLeft`). */
    var absence: Absence = Absence()

    /** The two guided blocks, measured rather than assumed: a declined block
     *  never gets a `BeganAt` and resolves to ZERO. */
    var warmupBeganAt: Instant? = null
    var warmupSec: Int? = null
    var cooldownBeganAt: Instant? = null
    var cooldownSec: Int? = null

    /** Seconds a guided block STOOD STILL — subtracted from its wall clock. */
    var blockPausedSec: Int = 0
    var blockFrozenAt: Instant? = null

    /** "not finished" on the rating; a skip like any other to the engine. */
    var interruptedPattern: Pattern? = null

    /** One-shot guard for `appear`. */
    var didStart: Boolean = false

    /** Per-side holds run the clock twice; the actual is the smaller side. */
    var holdClock: Countdown = Countdown()
    var holdTotal: Int = 0
    var holdSecondSide: Boolean = false
    var firstSideHeld: Int? = null

    /** The second side starts itself — no tap, with hands busy in a plank. */
    var holdSwitchClock: Countdown = Countdown()

    /** The count-in "Start hold" earns before the clock runs. */
    var holdCountInClock: Countdown = Countdown()

    /** The PROBE of a hold is over and recorded, the set not closed yet. */
    var holdSettled: Boolean = false

    /** How long the athlete SAID this hold would run — a target, per
     *  exercise, carried across a process death. */
    var holdDeclared: Int? = null

    /** Sets of this exercise a thumb ended: their numbers are ESTIMATES. */
    var holdApproxSets: Set<Int> = emptySet()

    /** What the CLOCK wrote for each set, before any correction. */
    var holdMeasured: Map<Int, Int> = emptyMap()

    /** Sets whose LAST side a thumb ended. */
    var holdTapEndedSets: Set<Int> = emptySet()

    /** One tap started the exercise and it continues itself. NOT in the
     *  snapshot, by decision: after a process death the work screen comes
     *  back with its own start button — a restored flag would arm a countdown
     *  for someone holding a cold phone. */
    var holdAutoRun: Boolean = false

    val exercises: List<SessionExercise> get() = session.exercises

    val exercise: SessionExercise get() = exercises[exIndex]

    /** The exercise in front of us, its probe's set included. */
    val totalSets: Int get() = exercise.totalSets

    /** The set under way is the probe. */
    val onProbeSet: Boolean get() = exercise.probe != null && setIndex >= exercise.sets

    val isLastSet: Boolean get() = setIndex == totalSets - 1

    val isLastExercise: Boolean get() = exIndex == exercises.size - 1

    /** What the screen shows right now: the planned exercise, or — on the
     *  probe set — the movement the probe offers. */
    data class CurrentMovement(
        val name: String,
        val unit: LoadUnit,
        val perSide: Boolean,
        val planned: Int,
        val isProbe: Boolean,
        val target: TechniqueTarget,
    )

    val current: CurrentMovement
        get() {
            val probe = exercise.probe
            if (probe != null && onProbeSet) {
                return CurrentMovement(probe.name, probe.unit, probe.perSide, planned = probe.load, isProbe = true,
                                       target = TechniqueTarget(probe, of = exercise.pattern))
            }
            return CurrentMovement(exercise.name, exercise.unit, exercise.perSide,
                                   planned = exercise.plannedLoad(set = setIndex), isProbe = false,
                                   target = TechniqueTarget(exercise))
        }

    val holding: Boolean get() = holdClock.isRunning
    val holdSwitchPausing: Boolean get() = holdSwitchClock.isRunning
    val holdCountingIn: Boolean get() = holdCountInClock.isRunning

    fun animate(motion: Motion, change: () -> Unit) {
        animator(if (reduceMotion) null else motion, change)
    }

    // MARK: - The prime before the ticks come back

    /** Primes a countdown its ticks have not been following — one that stood
     *  still, ran on while the app was away, or ran behind the exit alert —
     *  when it is on its four or inside its 3-2-1. */
    fun primeComingBack() {
        if (!store.settings.soundsEnabled) return
        val clock = signallingCountdown ?: return
        val showing = when (val reading = clock.read(now())) {
            Countdown.Reading.Unchanged -> clock.remaining
            is Countdown.Reading.Second -> reading.second
            // Ran out while it stood: no 3-2-1 left to prime for.
            is Countdown.Reading.Ended -> return
        }
        if (showing <= countdownSignalSeconds + 1) signals.prime()
    }

    /** The countdown on screen that ends on a 3-2-1, while running. Never a
     *  side-switch pause: it has no 3-2-1. */
    private val signallingCountdown: Countdown?
        get() {
            val clock = when (phase) {
                Phase.Warmup, Phase.Cooldown -> {
                    val run = if (phase == Phase.Warmup) warmup else cooldown
                    when {
                        blockPause.isPaused -> blockPause.reentry
                        run.stage == GuidedStage.switchPause -> return null
                        else -> run.clock
                    }
                }
                is Phase.Rest -> restClock
                Phase.Work -> if (holdCountingIn) holdCountInClock else holdClock
                else -> return null
            }
            return if (clock.isRunning) clock else null
        }

    // MARK: - What the view forwards

    /** One second of the flow: whichever countdown the phase is running. */
    fun tick() {
        when (phase) {
            Phase.Warmup -> if (blockPause.isPaused) tickBlockPause() else tick(GuidedBlock.warmup)
            // Paused, the rest has no end date to run out.
            is Phase.Rest -> if (blockPause.isPaused) tickBlockPause() else tickRest()
            Phase.Cooldown -> if (blockPause.isPaused) tickBlockPause() else tick(GuidedBlock.cooldown)
            Phase.Work -> when {
                holdCountingIn -> tickHoldCountIn()
                holdSwitchPausing -> tickHoldSwitchPause()
                holding -> tickHold()
            }
            else -> Unit
        }
    }

    /** The flow is on screen. Once: sheets over the flow can make the screen
     *  appear again. */
    fun appear() {
        if (didStart) return
        didStart = true
        // BOTH halves of the pair, here and not on the first tick.
        if (store.settings.soundsEnabled) {
            signals.primeSounds()
            signals.prime()
        }
        resume?.let { restore(it) }
        if (workoutStart == null) workoutStart = now()
        // After the restore, so it catalogues the real position.
        if (settleImmediately && phase != Phase.Feedback) finishNow()
        // Nothing for the tile to describe on the rating.
        if (phase != Phase.Feedback) {
            liveActivity.start(sessionNumber = session.sessionNumber, state = currentActivityState())
        }
    }

    fun disappear() {
        liveActivity.end()
    }

    /** The skipped sets every fold and display leaves out. */
    val leftOutSets: Map<Pattern, Set<Int>> get() = SetFacts.leftOut(skippedSetIndices, keeping = skippedWithNumber)

    /** The number each movement with a fact hands the engine — computed here,
     *  so the rating screen and the engine cannot be shown different
     *  arithmetic. */
    val overrides: Map<Pattern, Double> get() = SetFacts.overrides(actuals, skipping = leftOutSets, exercises = exercises)

    /** Each such movement's sets as the rating screen prints its "actual". */
    val actualSets: Map<Pattern, List<Int>>
        get() {
            val leftOut = leftOutSets
            val out = LinkedHashMap<Pattern, List<Int>>()
            for (ex in exercises) {
                if (actuals[ex.pattern] == null) continue
                out[ex.pattern] = SetFacts.performed(actuals, ex, leftOut[ex.pattern] ?: emptySet()).map { it.second }
            }
            return out
        }

    /** The rating lands: the workout goes to the engine with everything it
     *  recorded, and what it earned comes back. */
    fun rate(result: FeedbackResult): List<com.dredfit.workout.Milestone> {
        val start = workoutStart
        return store.completeWorkout(
            session = session, result = result,
            overrides = overrides,
            setActuals = actuals,
            skipped = skippedPatterns,
            setsSkipped = setsSkipped,
            skippedSets = skippedSetIndices,
            skippedWithNumber = skippedWithNumber,
            probes = probeActuals,
            // max: the wall clock can move backwards mid-workout. Minus the
            // measured absence.
            durationSec = start?.let { maxOf(0, Countdown.seconds(it, now()).toInt() - awaySec) },
            warmupSec = warmupSec, cooldownSec = cooldownSec,
            interrupted = interruptedPattern,
            raised = raisedSteps,
            date = now())
    }

    /** At the transition, not when the milestone screen appears — this
     *  cannot double-play. */
    fun showMilestones(earned: List<com.dredfit.workout.Milestone>) {
        playMilestone()
        phase = Phase.Milestone(earned)
    }

    companion object {
        const val countdownSignalSeconds = 3
        const val holdMistapSeconds = 3.0
        /** One tap of extra rest; the cap on repeats is twice the plan. */
        const val restExtensionSeconds = 15
    }
}
