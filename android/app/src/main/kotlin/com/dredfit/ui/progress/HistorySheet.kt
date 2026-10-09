//
//  A completed workout viewed from the calendar, the chart or Today. Port of
//  ios/Dredfit/Views/Progress/HistorySheet.swift. The rules it reads a record
//  by — the facts, the probe, the skips, where a movement stood after — are
//  the plain object below (no Compose in them), so a JVM unit test reaches
//  them; what they SAY is `Words`, resolved by the sheet. HistorySheet.swift
//  says why each step is the way it is.
//

package com.dredfit.ui.progress

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.canChangeLastRating
import com.dredfit.store.easedByHand
import com.dredfit.store.easedByRating
import com.dredfit.ui.Observed
import com.dredfit.ui.listFormatted
import com.dredfit.ui.screenDateText
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.ChevronGlyph
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PairedSecondary
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.today.didFullPlan
import com.dredfit.ui.tr
import com.dredfit.workout.EnergyEstimate
import com.dredfit.workout.RaiseLabel
import com.dredfit.workout.SetFacts
import com.dredfit.workout.Words
import com.dredfit.workout.asPlanned

object HistorySheet {

    /** The numbers of `ex`'s sets in `record`, and the one the rating
     *  reported — null when the record says nothing beyond the plan. A record
     *  naming its skipped sets leaves out the ones with no number of their
     *  own and cuts the sets a workout ended before reaching; an older one is
     *  cut to the sets that ran, never below what was recorded. */
    fun setFacts(ex: SessionExercise, record: WorkoutRecord): Pair<List<Int>, Int>? {
        val reported = record.actuals?.get(ex.pattern)
        val facts = record.setActuals
        val known = facts?.get(ex.pattern)?.size
        val named = record.skippedSets[ex.pattern]
        if (facts != null && known != null && named != null) {
            val unreached = maxOf(setsSkipped(ex, record) - named.size, 0)
            val ran = maxOf(ex.sets - unreached, known)
            val done = SetFacts.performed(facts, ex, skipping = record.leftOutSets[ex.pattern] ?: emptySet())
                .filter { it.first < ran }
            val first = done.firstOrNull()?.second ?: return null
            if (done.none { it.second != ex.plannedLoad(set = it.first) }) return null
            return done.map { it.second } to (reported ?: first)
        }
        val values = when {
            facts != null && known != null -> {
                val performed = maxOf(ex.sets - setsSkipped(ex, record), 0)
                SetFacts.allSets(facts, ex).take(maxOf(performed, known))
            }
            reported != null -> listOf(reported)
            else -> return null
        }
        val first = values.firstOrNull() ?: return null
        if (!SetFacts.differs(values, from = ex)) return null
        return values to (reported ?: first)
    }

    /** What the last set was, when it was not a working set. The verdict is
     *  read off where the session ENDED, never a second copy of the pass
     *  rule; a missing number is not read as "skipped". */
    fun probeLine(ex: SessionExercise, record: WorkoutRecord): Words? {
        val probe = ex.probe ?: return null
        val after = record.positionsAfter?.get(ex.pattern) ?: return null
        val name = Words.name(if (probe.variation in 1..Library.count(ex.pattern)) Library.name(ex.pattern, probe.variation)
                              else probe.name)
        val landed = after.variation >= probe.variation
        val reported = record.probes?.get(ex.pattern)
            ?: return if (landed) Words.keyed("history.probePassedPlain", "Probe: %@ — passed", name)
            else Words.keyed("history.probeUnresolved", "Probe: %@ — not this time", name)
        // The probe's own unit, which is not always the exercise's.
        val did = Words.display(SessionProbe(variation = probe.variation, name = probe.name, unit = probe.unit,
                                             load = reported, perSide = probe.perSide))
        return if (landed) Words.keyed("history.probePassed", "Probe: %1\$@ · %2\$@ — passed", name, did)
        else Words.keyed("history.probeShort", "Probe: %1\$@ · %2\$@ — not this time", name, did)
    }

    /** How much of a movement's plan was dropped mid-workout, when any was —
     *  "N of M", with no plural to inflect. */
    fun setsSkippedLine(ex: SessionExercise, record: WorkoutRecord): Words? {
        val lost = setsSkipped(ex, record)
        if (lost <= 0) return null
        return Words.keyed("history.setsSkipped", "Sets skipped: %1\$lld of %2\$lld", lost, ex.sets)
    }

    /** Sets dropped from a movement that WAS trained; a movement nobody
     *  reached is skipped whole and counts none here. */
    fun setsSkipped(ex: SessionExercise, record: WorkoutRecord): Int {
        if (record.skipped?.contains(ex.pattern) == true) return 0
        return maxOf(record.setsSkipped?.get(ex.pattern) ?: 0, 0)
    }

    /** The movement a workout was cut short ON is "not finished" — the
     *  rating screen's own key — and only the others "skipped". */
    fun skipWord(ex: SessionExercise, record: WorkoutRecord): Words =
        if (record.interrupted == ex.pattern) Words.of("not finished") else Words.of("skipped")

    /** Where the movement stood once the answer had been applied — silent
     *  when that is what the row above already prints. */
    fun afterLine(ex: SessionExercise, record: WorkoutRecord): Words? {
        val after = record.positionsAfter?.get(ex.pattern) ?: return null
        if (after.variation !in 1..Library.count(ex.pattern)) return null
        // Where the position stood, not the next appearance.
        val stood = after.asPlanned(ex.pattern, probe = null)
        val line = if (after.variation == ex.variation) {
            if (stood.display == ex.display || onlyMoreSets(stood, ex)) return null
            Words.keyed("history.after", "After: %@", Words.display(stood))
        } else {
            // A changed variation says which one: the dose alone reads like a
            // collapse where it is the grid floor of a harder movement.
            Words.keyed("history.afterVariation", "After: %1\$@ · %2\$@",
                        Words.name(Library.name(ex.pattern, after.variation)), Words.display(stood))
        }
        // The share that LANDED, not the taps.
        val steps = record.raisedShare(ex.pattern)
        if (steps <= 0) return line
        val unit = Library.unit(ex.pattern, after.variation)
        return Words.keyed("history.afterRaised", "%1\$@ · %2\$@ of it is your addition",
                           line, RaiseLabel.text(steps, unit))
    }

    /** What was actually done, in the plan's own spelling — or null when it
     *  ran to plan, exactly as `setFacts` decides. */
    fun factLine(ex: SessionExercise, record: WorkoutRecord): Words? {
        val (values, _) = setFacts(ex, record) ?: return null
        val uniform = values.all { it == values[0] }
        val perSet = record.setActuals?.get(ex.pattern) != null
        val done = SessionExercise(pattern = ex.pattern, name = ex.name, variation = ex.variation, unit = ex.unit,
                                   load = if (uniform) values[0] else ex.load, perSide = ex.perSide,
                                   sets = if (perSet) values.size else maxOf(ex.sets, 1),
                                   restSetSec = 0, restExerciseSec = 0,
                                   loads = if (uniform) null else values, probe = null)
        return if (ex.unit == LoadUnit.hold) Words.keyed("history.held", "Held: %@", Words.display(done))
        else Words.keyed("history.actual", "Actual: %@", Words.display(done))
    }

    /** The plan's set count is not the position's (the probe takes one, the
     *  pull slot caps the push): MORE sets than the row is the row's own
     *  arithmetic, not news. */
    private fun onlyMoreSets(stood: SessionExercise, plan: SessionExercise): Boolean =
        stood.load == plan.load && stood.sets > plan.sets && subSteps(stood) == subSteps(plan)

    private fun subSteps(ex: SessionExercise): Int = ex.loads?.count { it > ex.load } ?: 0

    /** The wall clock the workout occupied, while it can still be about the
     *  workout: stands down past twice the plan, and for a record with no
     *  plan to hold it against. Skips and legacy pain reports were "not
     *  performed" and are charged no minutes. */
    fun clockMinutes(record: WorkoutRecord): Int? {
        val seconds = record.durationSec ?: return null
        if (seconds <= 0) return null
        val exercises = record.exercises ?: return null
        val plan = EnergyEstimate.segments(exercises, skipped = (record.skipped ?: emptySet()) + (record.discomfort ?: emptySet()),
                                           warmupSec = record.warmupSec, cooldownSec = record.cooldownSec) ?: return null
        if (!plan.isPlausible || seconds.toDouble() > 2 * plan.totalSec) return null
        return maxOf(1, roundedAwayFromZero(seconds.toDouble() / 60).toInt())
    }

    /** The entries either side of the one being read; the journal is
     *  oldest-first. */
    fun neighbours(records: List<WorkoutRecord>, shown: WorkoutRecord): Pair<WorkoutRecord?, WorkoutRecord?> {
        val here = records.indexOfFirst { it.id == shown.id }
        if (here < 0) return null to null
        return records.getOrNull(here - 1) to records.getOrNull(here + 1)
    }

    /** The store's guard, plus: the record on screen has to BE the last one —
     *  the walk can stand on any entry. */
    fun canChangeRating(store: AppStore, shown: WorkoutRecord): Boolean =
        store.canChangeLastRating && store.records.lastOrNull()?.id == shown.id

    /** The answers the change alert offers: never the one already given, and
     *  "easy" gated exactly as the rating screen gates it. */
    fun ratingChoices(shown: WorkoutRecord): List<FeedbackResult> = buildList {
        if (shown.result != FeedbackResult.less) add(FeedbackResult.less)
        if (shown.result != FeedbackResult.plan) add(FeedbackResult.plan)
        if (shown.result != FeedbackResult.more && shown.didFullPlan) add(FeedbackResult.more)
    }
}

/** The sheet itself. Opened with ONE record from three screens; the walk to
 *  its neighbours is state here, so every call site passes the record alone. */
@Composable
fun HistorySheet(observedStore: Observed<AppStore>, record: WorkoutRecord, onDismiss: () -> Unit) {
    val store by observedStore
    val c = Theme.colors
    var walked by remember { mutableStateOf<WorkoutRecord?>(null) }
    var changeRatingShown by remember { mutableStateOf(false) }
    val shown = walked ?: record
    // The same answer for every row, and empty for every record but the last.
    val easedByHand = store.easedByHand(shown)
    DredfitSheet(onDismiss) {
        // `.large`: a record is opened to be read, all of it.
        Column(Modifier.fillMaxHeight()) {
            Column(Modifier.padding(horizontal = 24.dp).padding(top = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Kicker(screenDateText(shown.date, store.zone))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(tr("Workout %lld", shown.sessionNumber), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f),
                         color = c.ink, modifier = Modifier.weight(1f))
                    NeighbourControls(HistorySheet.neighbours(store.records, shown)) { walked = it }
                }
                Text(resultCaption(store, shown), style = dredfitFont(15f), color = c.ink2)
                HistorySheet.clockMinutes(shown)?.let { minutes ->
                    Text(tr("Took %lld min in the app, pauses included", minutes),
                         style = dredfitFont(13.5f, monospacedDigit = true), color = c.ink2,
                         modifier = Modifier.testTag("history-duration"))
                }
            }
            val exercises = shown.exercises
            if (!exercises.isNullOrEmpty()) {
                LazyColumn(Modifier.weight(1f).padding(horizontal = 24.dp).padding(top = 8.dp)) {
                    // By position, not pattern: a hand-edited record can carry one
                    // pattern twice, and a repeated key would crash the list.
                    itemsIndexed(exercises) { _, ex ->
                        HistoryRow(ex, shown, easedByHand, Modifier.padding(vertical = 11.dp))
                        HorizontalDivider(color = c.hairline)
                    }
                }
            } else {
                // Not every record carries an exercise snapshot.
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Text(tr("No details saved for this workout."), style = dredfitFont(15f), color = c.ink2)
                }
            }
            // A record from before v3 carries its number on the retired scale:
            // the line is absent rather than stated in the wrong unit.
            shown.totalProgressAfter?.let { steps ->
                Text(tr("Total steps after: %lld", steps), style = dredfitFont(13.5f, monospacedDigit = true),
                     color = c.ink2, modifier = Modifier.padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 10.dp))
            }
            if (HistorySheet.canChangeRating(store, shown)) {
                PairedSecondary(tr("history.changeRating"), tag = "history-change-rating",
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 10.dp)) {
                    changeRatingShown = true
                }
            }
            PrimaryButton(tr("Got it"), tag = "history-done",
                          modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 16.dp), onClick = onDismiss)
        }
    }
    if (changeRatingShown) {
        val actions = HistorySheet.ratingChoices(shown).map { result ->
            val title = when (result) {
                FeedbackResult.less -> tr("Tough, did less")
                FeedbackResult.plan -> tr("On plan")
                FeedbackResult.more -> tr("Easy, could do more")
            }
            AlertAction(title, tag = "history-change-rating-${result.rawValue}") {
                // The milestones a new answer earns are dropped on purpose.
                observedStore.act { changeLastRating(result) }
                // The entry was REPLACED: re-point at the record that now
                // holds this workout.
                walked = store.records.lastOrNull()
            }
        } + AlertAction(tr("history.changeRating.keep"), tag = null, cancel = true) {}
        DredfitAlert(tr("history.changeRating.title"), tr("history.changeRating.body"), actions) {
            changeRatingShown = false
        }
    }
}

/** The answer, and — while the app can still say so honestly — which
 *  movements it actually eased (the stamp of the LAST record only). */
@Composable
private fun resultCaption(store: AppStore, shown: WorkoutRecord): String = when (shown.result) {
    FeedbackResult.less -> {
        val eased = store.easedByRating(shown)
        if (eased.isEmpty()) tr("Rating: tough — the next one will be easier")
        else tr("history.toughEased", listFormatted(eased.map { tr(it.displayName) }))
    }
    FeedbackResult.plan -> tr("Rating: on plan — the next one adds a step to the movements that have room for one")
    FeedbackResult.more -> tr("Rating: easy — progressing as fast as each movement allows")
}

/** "‹ ›" in the calendar's 44 dp targets and ink2. Dimmed rather than
 *  removed at the ends, so the header keeps its shape; hidden from TalkBack
 *  there. */
@Composable
private fun NeighbourControls(neighbours: Pair<WorkoutRecord?, WorkoutRecord?>, walk: (WorkoutRecord) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        StepButton(neighbours.first, tr("history.earlier"), "history-earlier", pointsBack = true, walk)
        StepButton(neighbours.second, tr("history.later"), "history-later", pointsBack = false, walk)
    }
}

@Composable
private fun StepButton(target: WorkoutRecord?, label: String, tag: String, pointsBack: Boolean,
                       walk: (WorkoutRecord) -> Unit) {
    Box(Modifier.size(MinTarget).alpha(if (target == null) 0.25f else 1f)
            .clickable(enabled = target != null, role = Role.Button) { target?.let(walk) }
            .semantics { if (target == null) hideFromAccessibility() else contentDescription = label }
            .testTag(tag),
        contentAlignment = Alignment.Center) {
        ChevronGlyph(Theme.colors.ink2, 14.dp, Modifier.rotate(if (pointsBack) 180f else 0f))
    }
}
