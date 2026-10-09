//
//  Single source of truth: engine state + workout journal.
//  Persistence — one JSON file. Port of ios/Dredfit/AppStore.swift.
//
//  No Android import, on purpose: the store and every rule it keeps run in a
//  plain JVM unit test. The UI observes it through `observe`.
//
//  The iOS rule "an extension reads, every decision that moves the engine
//  stays in AppStore.swift" is a compiler rule here: the AppStore*.kt files
//  are extension functions, and an extension function cannot set a
//  `private set` property — it goes through `update`, like the Swift ones.
//
//  EngineState is a mutable class standing in for a Swift struct: this file
//  never mutates one in place. Every new state comes out of an engine entry
//  point (a fresh instance) or out of an explicit `copy()`.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SwiftJson
import com.dredfit.core.applyComeback
import com.dredfit.core.applyFeedback
import com.dredfit.core.applySilentDecay
import com.dredfit.core.easierVariation
import com.dredfit.core.generateSession
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.journal.WorkoutRecord
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.workout.Milestone
import com.dredfit.workout.MilestoneDetector
import com.dredfit.workout.SetFacts
import java.io.IOException
import java.nio.file.Path
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.util.logging.Logger

class AppStore(
    storagePath: Path,
    /** A test's clock; null in the app, which reads the system's afresh. */
    private val fixedClock: Clock? = null,
) {
    /** Its ZONE is the trainee's — iOS's `Calendar.current` — and every
     *  calendar question (rest weekdays, training days, the ISO week) is asked
     *  in it. Read on every call, so a zone changed while the app lives is the
     *  zone the next question is asked in, as `Calendar.current` is on iOS. */
    val clock: Clock get() = fixedClock ?: Clock.systemDefaultZone()

    var engineState: EngineState = EngineState.initial
        private set
    var records: List<WorkoutRecord> = emptyList()
        private set
    var settings: AppSettings = AppSettings()
        private set
    /** Read through `resumableWorkout`, which applies the validity checks. */
    var pendingWorkout: WorkoutSnapshot? = null
        private set

    /** Whether the workout flow is on screen RIGHT NOW, in this process. Not
     *  persisted: after a process death nothing owns the snapshot. */
    var workoutIsOnScreen: Boolean = false
        private set

    fun workoutFlowAppeared() { workoutIsOnScreen = true }
    fun workoutFlowDisappeared() { workoutIsOnScreen = false }

    /** Views derive "today" from this rather than the clock, so crossing
     *  midnight while in the background re-renders them. */
    var today: Instant = clock.instant()
        private set

    val zone: ZoneId get() = clock.zone

    private val stateFile = StateFile(storagePath)

    /**
     * The state file existed but could not be read, or was read and could not
     * be put aside before a write would replace it. While set, persist() is a
     * no-op: the file on disk is the only copy of the journal and must never
     * be overwritten from the empty in-memory state. Everything that publishes
     * state outward — backup export among it — checks this too.
     */
    var journalFrozen: Boolean = false
        private set

    /** A store that has been used stays frozen until relaunch: a reload would
     *  replace the person's changes with the file's state silently. */
    private var mutatedWhileFrozen = false

    /** Why the last write failed, until a write succeeds — the only sign that
     *  changes since the last save are at risk. */
    var lastPersistError: IOException? = null
        private set

    private val listeners = mutableListOf<() -> Unit>()

    /** The UI's way in: called after every change the store makes. Swift's
     *  `@Observable` without a framework — the store stays plain Kotlin. */
    fun observe(listener: () -> Unit): AutoCloseable {
        listeners += listener
        return AutoCloseable { listeners -= listener }
    }

    private fun changed() = listeners.toList().forEach { it() }

    init {
        when (val read = stateFile.read(reload = false)) {
            StateFile.Read.Absent, StateFile.Read.Undecodable -> adopt(null)
            StateFile.Read.Unreadable -> {
                // The journal may be perfectly fine, or damaged with nowhere
                // to put a copy. Either way the file is the only copy: freeze
                // rather than start over on top of it; reloadIfNeeded() lifts it.
                journalFrozen = true
                log.severe("state file could not be read or put aside — persistence frozen")
                adopt(null)
            }
            is StateFile.Read.Loaded -> {
                adopt(read.data)
                if (read.data.engineStateMigrated) {
                    log.info("engine state migrated from v2 — journal, bar and counter carried over")
                }
            }
        }
    }

    /** Second chance for a launch whose state file could not be read or put
     *  aside — called when the app comes to the foreground. */
    fun reloadIfNeeded() {
        if (!journalFrozen || mutatedWhileFrozen) return
        when (val read = stateFile.read(reload = true)) {
            StateFile.Read.Absent, StateFile.Read.Unreadable -> return
            StateFile.Read.Undecodable -> Unit
            is StateFile.Read.Loaded -> adopt(read.data)
        }
        journalFrozen = false
        changed()
    }

    /** What a read hands the store, at launch and on a reload alike. */
    private fun adopt(data: AppData?) {
        var state = PersistedState(
            engineState = data?.engineState ?: EngineState.initial,
            records = data?.records ?: emptyList(),
            settings = data?.settings ?: AppSettings(),
            pendingWorkout = data?.pendingWorkout)
        // Stamped in the settings, which is what carries it: the card must
        // survive a launch that ends before anyone reads it.
        if (data?.engineStateMigrated == true) {
            state = state.copy(settings = state.settings.copy(migrationNoticePending = true))
        }
        assign(state.migratingHealthMarkToFlags())
    }

    /** The date half of `refreshDay` and nothing else, for a midnight that
     *  passes inside a live screen. Never the decay. */
    fun reanchorToday(now: Instant = clock.instant()) {
        if (!sameDay(today, now)) {
            today = now
            changed()
        }
    }

    // MARK: - The only mutation

    /**
     * Records a finished workout. The defaults are Swift's; every optional is
     * passed to the engine explicitly, so none can fall back unnoticed.
     *
     * @return the milestones this workout earned — derived here because this
     *   is the only place still holding the pre-feedback state.
     */
    @Suppress("LongParameterList")
    fun completeWorkout(
        session: Session,
        result: FeedbackResult,
        overrides: Map<Pattern, Double> = emptyMap(),
        /** The sets behind each override, for the journal. */
        setActuals: Map<Pattern, List<Int>> = emptyMap(),
        skipped: Set<Pattern> = emptySet(),
        /** Sets skipped DURING the session — the engine settles them AFTER the rating. */
        setsSkipped: Map<Pattern, Int> = emptyMap(),
        skippedSets: Map<Pattern, Set<Int>> = emptyMap(),
        skippedWithNumber: Map<Pattern, Set<Int>> = emptyMap(),
        /** What the PROBE set showed — never folded into `overrides`. */
        probes: Map<Pattern, Int> = emptyMap(),
        durationSec: Int? = null,
        warmupSec: Int? = null,
        cooldownSec: Int? = null,
        interrupted: Pattern? = null,
        /** Steps added "for next time" — landed by the engine last. */
        raised: Map<Pattern, Int> = emptyMap(),
        date: Instant = clock.instant(),
    ): List<Milestone> {
        // Mirror of the engine's replay guard: a session that does not belong
        // to this state must not append a duplicate journal entry either.
        if (session.sessionNumber != engineState.counter + 1) return emptyList()
        pendingWorkout = null   // the workout is over — nothing to resume
        val before = engineState
        // The gap as a FRACTION of a day: floored, a second workout on the
        // same day would report zero and the weekly window would stop ageing.
        // Stored as Swift stores it, so this record equals itself read back.
        val stamped = SwiftJson.swiftDate(date)
        val gap = gapFraction(now = stamped)
        engineState = Engine.applyFeedback(
            state = before, session = session, result = result, overrides = overrides,
            skipped = skipped, setsSkipped = setsSkipped, gapDays = gap,
            probes = probes, raised = raised)
        // The share of the raise that MOVED the position: the same call once
        // more without it, and the raise replayed over that state step by step.
        var landed: Map<Pattern, Int> = emptyMap()
        if (raised.isNotEmpty()) {
            val unraised = Engine.applyFeedback(
                state = before, session = session, result = result, overrides = overrides,
                skipped = skipped, setsSkipped = setsSkipped, gapDays = gap, probes = probes)
            landed = landed(raised, unraised)
        }
        // Facts of THIS moment and of no other: the state before the rating
        // cannot be reconstructed from the journal afterwards.
        settings = settings.copy(lastRatingUndo = RatingUndo(state = before, session = session))
        noteRatingLanded(session, before)
        records = records + WorkoutRecord(
            sessionNumber = session.sessionNumber,
            date = stamped,
            result = result,
            totalProgressAfter = totalProgress,
            exercises = session.exercises,
            // Which push cards the pulls held back, read off `before`.
            heldBack = pushesHeldBack(session, builtFrom = before),
            // The journal keeps INTEGERS; the fraction is the engine's judge.
            actuals = if (overrides.isEmpty()) null else overrides.mapValues { roundedAwayFromZero(it.value).toInt() },
            setActuals = setActuals.ifEmpty { null },
            probes = probes.ifEmpty { null },
            setsSkipped = setsSkipped.ifEmpty { null },
            skippedSetIndices = SetFacts.stored(skippedSets),
            skippedWithNumberIndices = SetFacts.stored(skippedWithNumber),
            skipped = skipped.ifEmpty { null },
            positionsAfter = currentPositions,
            durationSec = durationSec,
            warmupSec = warmupSec,
            cooldownSec = cooldownSec,
            interrupted = interrupted,
            raisedSteps = raised.ifEmpty { null },
            raisedLanded = if (raised.isEmpty()) null else landed)
        persist()
        // Reminders and the Health export follow a finished workout on iOS;
        // they arrive here with reminders/ and health/.
        return MilestoneDetector.detect(before = before, after = engineState, session = session, skipped = skipped)
    }

    /** Which movements of the session the rating actually made easier, by the
     *  engine's own ordinal before and after. */
    private fun noteRatingLanded(session: Session, before: EngineState) {
        val eased = session.exercises.map { it.pattern }.filter {
            Engine.progress(engineState, it) < Engine.progress(before, it)
        }
        val moves = ratingMoves(session.sessionNumber)
            ?: planMoves(session.sessionNumber)
            ?: PlanMoves(session = session.sessionNumber)
        settings = settings.copy(
            ratingMoves = moves.copy(byRating = eased),
            // Leave the handle's slot empty rather than stale: it names the
            // plan AHEAD, which is now a session this record knows nothing about.
            planMoves = if (settings.planMoves?.session == session.sessionNumber) null else settings.planMoves)
    }

    /** The plan a handle moves is the one AHEAD — `counter + 1`. A tap against
     *  an older stamp starts the list over. */
    private fun noteEasedByHand(pattern: Pattern) {
        val session = engineState.counter + 1
        val moves = planMoves(session) ?: PlanMoves(session = session)
        settings = settings.copy(
            planMoves = if (pattern in moves.byHand) moves else moves.copy(byHand = moves.byHand + pattern))
    }

    // MARK: - The shown plan

    /**
     * The plan is on screen — the engine remembers it, so "a descent never
     * adds load" holds against plans SEEN, not only against plans trained.
     * ONE WRITE PER SHOWING, not one per render: writing down a plan already
     * written down changes nothing, so every render after the first returns
     * without a write. Never on a frozen journal: that plan was drawn from an
     * empty state, and writing it would pin the freeze.
     */
    fun recordPlanShown(session: Session) {
        if (journalFrozen || session != Engine.generateSession(engineState)) return
        val recorded = Engine.recordShown(state = engineState, session = session)
        if (recorded == engineState) return
        engineState = recorded
        persist()
    }

    // MARK: - Settings

    /** Turning it off freezes the vertical branch; its level is kept. */
    fun setHasBar(on: Boolean) {
        engineState = engineState.copy().also { it.hasBar = on }
        persist()
    }

    // MARK: - Silent decay for the 7–13 day blind zone (issue #37)

    /**
     * Quiet −1 to every pattern in the 7–13 day gap the comeback does not
     * reach. NOT idempotent in the engine, so applied at most once per break:
     * the stamp is keyed to the last workout's date and goes stale by itself.
     * A rhythm break leaves no stamp on purpose — re-evaluated on every open.
     */
    fun applySilentDecayIfNeeded(now: Instant = clock.instant()) {
        val last = records.lastOrNull() ?: return
        val gap = gapDays(now) ?: return
        if (gap < EngineConfig.silentDecayGapDays || gap >= EngineConfig.comebackMinGapDays || isRhythmBreak(gap)) return
        if (silentDecayAppliedForCurrentBreak) return
        engineState = Engine.applySilentDecay(state = engineState, gapDays = gap)
        settings = settings.copy(silentDecayAppliedFor = last.date)
        persist()
    }

    /**
     * Guarded (#128): `applyComeback` is "at most once per break" and deepens
     * repeated returns, so card visibility must not be the only gate. A
     * double tap re-enters with the question closed and leaves silently.
     */
    fun acceptComeback(now: Instant = clock.instant()) {
        if (!shouldOfferComeback(now)) return
        val gap = gapDays(now) ?: return
        engineState = Engine.applyComeback(state = engineState, gapDays = gap,
                                           alreadyDecayed = silentDecayAppliedForCurrentBreak)
        closeComebackQuestion(now)
    }

    // MARK: - The handles

    /** The handle goes through the ENGINE: a level written here would skip
     *  the floor, the sanitizer and the measure the repair reads. */
    fun makeEasier(pattern: Pattern) {
        if (!canMakeEasier(pattern)) return
        engineState = Engine.easierVariation(state = engineState, pattern = pattern)
        // The only moment that knows the step down was taken by hand.
        noteEasedByHand(pattern)
        persist()
    }

    /** Only the engine resets; the journal and settings survive, and the bar
     *  did not disappear from the doorway. */
    fun resetProgress() {
        val hadBar = engineState.hasBar
        engineState = EngineState.initial.also { it.hasBar = hadBar }
        // Session numbers restart: a pre-reset snapshot would resume into the
        // wrong workout, and the undo holds a whole PRE-RESET state.
        pendingWorkout = null
        settings = settings.copy(lastRatingUndo = null, planMoves = null, ratingMoves = null)
        closeComebackQuestion()
    }

    // MARK: - The weak-link prompt (#135)

    /** Yes, it is this movement: it drops to an easier variation, through the
     *  engine, and stays in the plan. */
    fun makeSuspectEasier(pattern: Pattern) {
        settings = settings.copy(weakLinkPromptAnsweredFor = records.lastOrNull()?.sessionNumber)
        engineState = Engine.easierVariation(state = engineState, pattern = pattern)
        noteEasedByHand(pattern)
        persist()
    }

    // MARK: - Taking a rating back

    /**
     * Re-applies another rating to the state the first one was applied to —
     * a clean rollback, nothing carried across (AppStore.swift says why).
     * @return the milestones the NEW rating earns; empty when nothing changes.
     */
    fun changeLastRating(to: FeedbackResult): List<Milestone> {
        val redo = ratingRedo() ?: return emptyList()
        if (redo.record.result == to) return emptyList()
        engineState = redo.undo.state
        records = records.dropLast(1)
        val facts = redo.record.setActuals ?: emptyMap()
        val milestones = completeWorkout(
            session = redo.undo.session,
            result = to,
            overrides = SetFacts.overrides(facts, skipping = redo.record.leftOutSets,
                                           exercises = redo.undo.session.exercises),
            setActuals = facts,
            skipped = redo.record.skipped ?: emptySet(),
            setsSkipped = redo.record.setsSkipped ?: emptyMap(),
            skippedSets = redo.record.skippedSets,
            skippedWithNumber = redo.record.skippedWithNumber,
            probes = redo.record.probes ?: emptyMap(),
            durationSec = redo.record.durationSec,
            warmupSec = redo.record.warmupSec,
            cooldownSec = redo.record.cooldownSec,
            interrupted = redo.record.interrupted,
            // The addition was a decision about the movement, not the rating.
            raised = redo.record.raisedSteps ?: emptyMap(),
            date = redo.record.date)
        // Health already holds this workout and nothing about it changed:
        // carrying the mark over stops a second copy being written.
        records.lastOrNull()?.let { last ->
            records = records.dropLast(1) + last.copy(healthExported = redo.record.healthExported)
        }
        persist()
        return milestones
    }

    // MARK: - Persistence

    /** The way into the persisted state from outside this file: the change
     *  and its write are one call, so no caller can make one without the other. */
    fun update(change: (PersistedState) -> PersistedState) {
        assign(change(persisted))
        persist()
    }

    private val persisted: PersistedState
        get() = PersistedState(engineState = engineState, records = records,
                               settings = settings, pendingWorkout = pendingWorkout)

    private fun assign(state: PersistedState) {
        engineState = state.engineState
        records = state.records
        settings = state.settings
        pendingWorkout = state.pendingWorkout
    }

    private fun persist() {
        // A journal that could not be read must never be overwritten by the
        // empty state that replaced it. The change stays in memory for this
        // launch and pins the freeze.
        if (journalFrozen) {
            if (!mutatedWhileFrozen) {
                mutatedWhileFrozen = true
                log.warning("state changed while the journal is frozen — kept in memory only")
            }
            changed()
            return
        }
        try {
            stateFile.write(AppData(engineState, records, settings, pendingWorkout))
            lastPersistError = null
        } catch (e: IOException) {
            // The next mutation retries the full write, but this is the only
            // durability path — a failure must leave a trace.
            log.severe("persist failed: ${e.message}")
            lastPersistError = e
        }
        changed()
    }

    companion object {
        internal val log: Logger = Logger.getLogger("com.dredfit.store")

        /** The one file, in the app's private files directory — the
         *  counterpart of Application Support. */
        const val STATE_FILE_NAME = "dredfit-state.json"
    }
}
