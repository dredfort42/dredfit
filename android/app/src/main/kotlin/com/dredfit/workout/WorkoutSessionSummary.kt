//
//  The exercise summary a hold movement ends on: which card the adjuster
//  edits, what the panel's line and a card's "≈" say, the ceiling of a
//  correction, the steps added "for next time" — and the probe's caption.
//  Port of ios/Dredfit/WorkoutSession+Summary.swift.
//

package com.dredfit.workout

import com.dredfit.core.EngineConfig
import com.dredfit.core.SessionExercise
import com.dredfit.store.markOwnNumberReported
import com.dredfit.store.previewPlan
import com.dredfit.workout.WorkoutSession.EditTarget

/** One set of the movement as the summary prints it. */
data class HeldSet(
    /** 0-based, the set's own — the card after a skipped set says "set 3". */
    val index: Int,
    val seconds: Int,
    val planned: Int,
    /** An ESTIMATE: the set ended under a thumb. Printed as "≈". */
    val approximate: Boolean,
    /** Only the last working set — decided by the set's index. */
    val correctable: Boolean,
) {
    val id: Int get() = index
}

/** The sets of the exercise in front of us skipped with no number of their own. */
val WorkoutSession.leftOutHere: Set<Int> get() = leftOutSets[exercise.pattern] ?: emptySet()

/** Every set of the movement that was DONE, in set order — a set skipped
 *  with no number has no card. `allSets` underneath, so the summary and the
 *  flow cannot disagree about a number. */
val WorkoutSession.heldSets: List<HeldSet>
    get() = SetFacts.performed(actuals, exercise, leftOutHere).map { (set, value) ->
        HeldSet(index = set, seconds = value, planned = exercise.plannedLoad(set = set),
                approximate = summaryCardIsApproximate(set), correctable = isLastSummarySet(set))
    }

/** Opens the entry on the card that was tapped — only the correctable one. */
fun WorkoutSession.startSummaryAdjusting(set: Int) {
    if (!isLastSummarySet(set)) return
    adjustValue = SetFacts.inForce(actuals, exercise, set = set)
    editing = EditTarget.SummaryCard(set)
}

/** OK on the summary's panel: the correction lands on the card tapped. */
fun WorkoutSession.commitSummaryEdit(set: Int) {
    actuals = SetFacts.recordingSet(adjustValue, actuals, exercise, set = set)
    // The correction can move the base under an addition already made.
    trimRaiseToWhatStillMoves()
    // The second door of the same channel spends the same flag.
    store.markOwnNumberReported()
    editing = null
    persistProgress()
}

/** What the clock counted for a set — before any correction. */
fun WorkoutSession.summaryMeasured(set: Int): Int = holdMeasured[set] ?: SetFacts.inForce(actuals, exercise, set = set)

/** The line above the panel, chosen by the mark, not by the card's "≈". */
fun WorkoutSession.summaryPanelLine(set: Int): Words {
    val measured = summaryMeasured(set)
    return if (set in holdApproxSets) Words.of("set %lld · stopped by hand at about %lld s", set + 1, measured)
    else Words.of("set %lld · the clock saw %lld s", set + 1, measured)
}

/** The card's "≈": a set a thumb ended, still carrying the thumb's number. */
fun WorkoutSession.summaryCardIsApproximate(set: Int): Boolean =
    set in holdApproxSets && SetFacts.inForce(actuals, exercise, set = set) == summaryMeasured(set)

/** The last WORKING set — the probe has no card here. */
fun WorkoutSession.isLastSummarySet(index: Int): Boolean = index == exercise.sets - 1

/** The rule is `SetFacts.correctionRange`; what is measured is the CLOCK's
 *  number, and what ended the set is its last side. */
fun WorkoutSession.summaryRange(set: Int): IntRange =
    SetFacts.correctionRange(measured = summaryMeasured(set), isLastSet = isLastSummarySet(set),
                             restFollowed = set < totalSets - 1, endedByTap = set in holdTapEndedSets)

/** The plan this movement will get with `steps` additions — the engine's own
 *  answer, dry-run through the store. */
fun WorkoutSession.nextPlan(withAdditions: Int): SessionExercise? {
    val raised = LinkedHashMap(raisedSteps)
    if (withAdditions > 0) raised[exercise.pattern] = withAdditions else raised.remove(exercise.pattern)
    return store.previewPlan(after = session, pattern = exercise.pattern,
                             overrides = SetFacts.overrides(actuals, skipping = leftOutSets, exercises = exercises),
                             skipped = skippedPatterns, setsSkipped = setsSkipped,
                             probes = probeActuals, raised = raised)
}

/** The stepper's write: a DECISION, persisted like the facts. */
fun WorkoutSession.setRaise(steps: Int) {
    val clamped = minOf(maxOf(steps, 0), EngineConfig.raiseStepsMax)
    raisedSteps = if (clamped > 0) raisedSteps + (exercise.pattern to clamped) else raisedSteps - exercise.pattern
    persistProgress()
}

/** The count after a correction — `NextTimeBlock`'s rule. Persisted by the
 *  caller with the correction it follows. */
fun WorkoutSession.trimRaiseToWhatStillMoves() {
    val steps = raisedSteps[exercise.pattern] ?: 0
    val live = NextTimeBlock.stepsThatStillMove(steps) { nextPlan(withAdditions = it) }
    if (live != steps) {
        raisedSteps = if (live > 0) raisedSteps + (exercise.pattern to live) else raisedSteps - exercise.pattern
    }
}

// MARK: - The probe's caption

/** What the probe set says under its number once one is in. */
sealed interface ProbeOutcome {
    /** Passed: next time is the probe's own movement. */
    data class Passed(val name: String) : ProbeOutcome
    /** The working sets fell short: the plan moves onto the movement named. */
    data class PlanMoves(val name: String) : ProbeOutcome
    /** The probe fell short after working sets that met the plan. */
    data object Stays : ProbeOutcome
}

/** A promise about the next plan, decided here; null until a number is in.
 *  Working sets that fell short speak first. */
val WorkoutSession.probeOutcome: ProbeOutcome?
    get() {
        val entered = probeActuals[exercise.pattern] ?: return null
        if (SetFacts.foldFallsShort(actuals, of = exercise, skipping = leftOutHere)) {
            return ProbeOutcome.PlanMoves(nextPlan(withAdditions = 0)?.name ?: exercise.name)
        }
        return if (entered >= current.planned) ProbeOutcome.Passed(current.name) else ProbeOutcome.Stays
    }
