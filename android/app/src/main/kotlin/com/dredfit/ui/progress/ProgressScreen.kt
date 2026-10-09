//
//  One data colour (accent) — one metric in several projections. Port of
//  ios/Dredfit/Views/Progress/ProgressScreen.swift: the total and its share
//  card, the chart (total or one movement) with its break bands and the one
//  line under it, and a row per movement that selects the projection. The
//  rules that choose what the chart draws are plain Kotlin below.
//

package com.dredfit.ui.progress

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Position
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.progressCurve
import com.dredfit.store.record
import com.dredfit.store.recordsSinceReset
import com.dredfit.store.totalProgress
import com.dredfit.ui.Observed
import com.dredfit.ui.currentLocale
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.theme.isAccessibilitySize
import com.dredfit.ui.tr
import com.dredfit.workout.Words
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

object ProgressScreen {

    /** If the bar was turned off while its row was selected, the total view
     *  rather than an empty, unselectable chart. */
    fun effectivePattern(store: AppStore, chartPattern: Pattern?): Pattern? =
        if (chartPattern == Pattern.pullBar && !barBranchExists(store)) null else chartPattern

    fun barBranchExists(store: AppStore): Boolean =
        store.engineState.hasBar || Engine.progress(store.engineState, Pattern.pullBar) > 0

    /** Records without a position snapshot are skipped, and so are the ones
     *  from before v3: the line starts where the measured ladder does. */
    fun chartPoints(store: AppStore, pattern: Pattern?): List<StepsChart.StepPoint> =
        store.recordsSinceReset.mapNotNull { if (pattern != null) plot(it, pattern) else plotTotal(it) }
            .mapIndexed { i, pt -> pt.copy(id = i) }

    /** All five recorded coordinates — replotted without `sub` and `cut` a
     *  snapshot would sit off the number beside the row. */
    fun plot(record: WorkoutRecord, p: Pattern): StepsChart.StepPoint? {
        val position = record.positionsAfter?.get(p) ?: return null
        val value = Engine.progress(p, Position(variation = position.variation, sets = position.sets, dose = position.dose,
                                                sub = position.sub ?: 0, cut = position.cut ?: 0))
        return StepsChart.StepPoint(id = 0, date = record.date, value = value, result = record.result,
                                    ownNumber = record.actuals?.get(p) != null,
                                    ownSkips = record.setsSkipped?.get(p) != null)
    }

    fun plotTotal(record: WorkoutRecord): StepsChart.StepPoint? {
        val steps = record.totalProgressAfter ?: return null
        return StepsChart.StepPoint(id = 0, date = record.date, value = steps, result = record.result,
                                    ownNumber = !record.actuals.isNullOrEmpty(),
                                    ownSkips = !record.setsSkipped.isNullOrEmpty())
    }

    /** A gap of calendar days wide enough for the silent decay. The break
     *  claims a drop only when the returning session cannot explain it —
     *  "tough", a number of its own, or sets skipped. */
    fun breakBands(points: List<StepsChart.StepPoint>, zone: ZoneId): List<StepsChart.BreakBand> =
        points.zipWithNext().withIndex().mapNotNull { (index, pair) ->
            val (before, after) = pair
            val days = ChronoUnit.DAYS.between(before.date.atZone(zone).toLocalDate(), after.date.atZone(zone).toLocalDate()).toInt()
            if (days < EngineConfig.silentDecayGapDays) return@mapNotNull null
            val ownDoing = after.result == FeedbackResult.less || after.ownNumber || after.ownSkips
            StepsChart.BreakBand(id = index, from = before.date, to = after.date, days = days,
                                 costSteps = after.value < before.value && !ownDoing)
        }

    /** The freshest band that actually COST steps, failing that the longest:
     *  by length alone the explanation would sit on a harmless gap. */
    fun explainedBand(bands: List<StepsChart.BreakBand>): StepsChart.BreakBand? =
        bands.lastOrNull { it.costSteps } ?: bands.maxByOrNull { it.days }

    /** One line, claiming no more than happened. */
    fun breakFact(band: StepsChart.BreakBand, count: Int): List<Words> = buildList {
        add(Words.of("A break of %lld days.", band.days))
        if (band.costSteps) add(Words.of("The plan met you lower."))
        if (count > 1) add(Words.of("Others are marked too."))
    }

    /** The variation alone: behind "Squat — " the kicker would truncate its
     *  tail, and the tail is the differentiator. */
    fun chartTitle(store: AppStore, pattern: Pattern?): Words =
        if (pattern == null) Words.of("total steps") else Words.name(Library.name(pattern, store.engineState.position(pattern).variation))

    /** Everything the card DRAWS — its numbers, its day and its curve — so
     *  the render runs exactly when the picture would change. */
    fun cardKey(store: AppStore): List<Any> =
        listOf(store.records.size, store.totalProgress, store.today.atZone(store.zone).toLocalDate()) + store.progressCurve()
}

@Composable
fun ProgressScreen(observedStore: Observed<AppStore>, modifier: Modifier = Modifier) {
    val store by observedStore
    val c = Theme.colors
    val context = LocalContext.current
    var chartPattern by rememberSaveable { mutableStateOf<Pattern?>(null) }
    var history by remember { mutableStateOf<WorkoutRecord?>(null) }
    var card by remember { mutableStateOf<ShareCardFactory.Card?>(null) }
    val canShare = store.records.isNotEmpty()
    val headline = tr(ShareCardFactory.summaryHeadline(store.records.size, store.totalProgress))
    val locale = currentLocale()
    val cardDate = DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale, "dMMMMy"), locale)
        .format(store.today.atZone(store.zone))
    // `progressCurve()`: cut at the reset, so the milestone card and this one
    // draw the same line.
    val curve = store.progressCurve()
    val key = ProgressScreen.cardKey(store) + headline + cardDate
    LaunchedEffect(key, canShare) {
        card = if (!canShare) null
        else withContext(Dispatchers.Default) {
            ShareCardFactory.card(context, headline, ShareCardFactory.Slot.progress, cardDate, steps = curve)
        }
    }

    Column(modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 24.dp)) {
            Kicker(tr("Progress"), Modifier.padding(top = 18.dp))
            StatRow(store.totalProgress, store.records.size, card, headline, Modifier.padding(top = 12.dp))
        }
        val effective = ProgressScreen.effectivePattern(store, chartPattern)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 12.dp)) {
            // The row must not move when a pattern is picked: the title stays
            // on one line and "Show all" keeps its space when idle.
            Row(Modifier.fillMaxWidth().padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Kicker(tr(ProgressScreen.chartTitle(store, effective)), Modifier.weight(1f), maxLines = 1)
                Spacer(Modifier.width(8.dp))
                Text(tr("Show all"), style = dredfitFont(13f, Weight.semibold), color = c.accentText, maxLines = 1,
                     modifier = Modifier.alpha(if (effective != null) 1f else 0f)
                         .clickable(enabled = effective != null, role = Role.Button) { chartPattern = null }
                         .semantics { if (effective == null) hideFromAccessibility() }
                         .heightIn(min = 32.dp).padding(vertical = 6.dp).testTag("show-all"))
            }
            val points = ProgressScreen.chartPoints(store, effective)
            val bands = ProgressScreen.breakBands(points, store.zone)
            // 120 of chart plus room for the date axis — text, so it grows.
            val chartHeight = 134.dp * LocalDensity.current.fontScale.coerceAtLeast(1f)
            StepsChart(points, bands, store.zone, Modifier.padding(top = 8.dp).height(chartHeight)) { date ->
                history = store.record(date)
            }
            ProgressScreen.explainedBand(bands)?.let { band ->
                Text(ProgressScreen.breakFact(band, bands.size).map { tr(it) }.joinToString(" "),
                     style = dredfitFont(12.5f), color = c.ink2, modifier = Modifier.padding(top = 6.dp))
            }
            Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val rows = Pattern.ordered + if (ProgressScreen.barBranchExists(store)) listOf(Pattern.pullBar) else emptyList()
                for (p in rows) {
                    val selected = effective == p
                    PatternProgressRow(observedStore, p, selected) { chartPattern = if (selected) null else p }
                }
            }
        }
    }
    history?.let { HistorySheet(observedStore, it) { history = null } }
}

/** Plain values, never the store: a composable handed the store object is
 *  SKIPPED under strong skipping (same instance) and keeps old numbers after
 *  an import or the decay (skeptic finding; android/CLAUDE.md, SetDots).
 *
 *  Number and caption keep their intrinsic width — a four-digit total must
 *  not break mid-digit; the share button yields instead. At accessibility
 *  sizes the caption moves under the number. */
@Composable
private fun StatRow(total: Int, workouts: Int, card: ShareCardFactory.Card?, headline: String, modifier: Modifier) {
    val share = @Composable { ShareButton(if (workouts > 0) card else null, headline) }
    if (isAccessibilitySize()) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TotalNumber(total)
                Spacer(Modifier.weight(1f))
                share()
            }
            StepsCaption(workouts, oneLine = false)
        }
    } else {
        Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            // Only the button is centred: the pair measures as one block and
            // the caption keeps the number's baseline.
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TotalNumber(total, Modifier.alignBy(LastBaseline))
                StepsCaption(workouts, oneLine = true, Modifier.alignBy(LastBaseline))
            }
            Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
            share()
        }
    }
}

@Composable
private fun TotalNumber(total: Int, modifier: Modifier = Modifier) {
    Text("$total", style = dredfitFont(56f, Weight.heavy, cap = 84f, tracking = -2f, monospacedDigit = true),
         color = Theme.colors.ink, maxLines = 1, softWrap = false, modifier = modifier.testTag("total-steps"))
}

/** One word, in every language — that keeps a four-digit total and a
 *  Russian caption on one row. */
@Composable
private fun StepsCaption(workouts: Int, oneLine: Boolean, modifier: Modifier = Modifier) {
    val c = Theme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        val lines = if (oneLine) 1 else Int.MAX_VALUE
        Text(tr("progress.stepsLabel"), style = dredfitFont(14.5f), color = c.ink2, maxLines = lines,
             softWrap = !oneLine, overflow = TextOverflow.Visible)
        Text(tr("%lld workouts", workouts), style = dredfitFont(14.5f), color = c.ink2, maxLines = lines,
             softWrap = !oneLine, overflow = TextOverflow.Visible)
    }
}
