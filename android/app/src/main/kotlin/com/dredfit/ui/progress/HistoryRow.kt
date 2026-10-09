//
//  One movement of a workout as the history sheet reads it back. Port of
//  ios/Dredfit/Views/Progress/HistoryRow.swift: the movement, its plan, and
//  under both, at full width, the lines that say how it differed — the fact,
//  the probe, the skipped sets, an easier variation chosen by hand, and where
//  it stood after. Each line carries the iOS identifier.
//

package com.dredfit.ui.progress

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.journal.WorkoutRecord
import com.dredfit.ui.displayOf
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun HistoryRow(ex: SessionExercise, shown: WorkoutRecord, easedByHand: List<Pattern>, modifier: Modifier = Modifier) {
    val c = Theme.colors
    val p = ex.pattern.rawValue
    val hurt = shown.discomfort?.contains(ex.pattern) == true
    val skipped = shown.skipped?.contains(ex.pattern) == true
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Text(tr(currentName(ex)), style = dredfitFont(16f, Weight.medium), color = c.ink, modifier = Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // NAMED: three rows of numbers can stand under one movement,
                // and each carries a word.
                Text(tr("plan %@", displayOf(ex)), style = dredfitFont(15f, monospacedDigit = true), color = c.ink2)
                when {
                    // Only a record from a build that had the pain report.
                    hurt -> Text(tr("hurt"), style = dredfitFont(12.5f), color = c.accentText)
                    skipped -> Text(tr(HistorySheet.skipWord(ex, shown)), style = dredfitFont(12.5f), color = c.ink2,
                                    modifier = Modifier.testTag("history-skipword-$p"))
                }
            }
        }
        // The one line that says the session went differently from the plan:
        // accented, in the plan's own spelling.
        if (!skipped && !hurt) {
            HistorySheet.factLine(ex, shown)?.let {
                Line(tr(it), "history-actual-$p", dredfitFont(12.5f, Weight.semibold, monospacedDigit = true), c.accentText)
            }
        }
        HistorySheet.probeLine(ex, shown)?.let { Line(tr(it), "history-probe-$p") }
        HistorySheet.setsSkippedLine(ex, shown)?.let { Line(tr(it), "history-setsskipped-$p") }
        // The one cause of a drop with no break to explain it: the athlete
        // moved the movement down themselves.
        if (ex.pattern in easedByHand) Line(tr("history.easedByHand"), "history-easedbyhand-$p")
        HistorySheet.afterLine(ex, shown)?.let { Line(tr(it), "history-after-$p") }
    }
}

@Composable
private fun Line(text: String, tag: String, style: TextStyle = dredfitFont(12.5f), color: Color = Theme.colors.ink2) {
    Text(text, style = style, color = color, modifier = Modifier.fillMaxWidth().testTag(tag))
}

/** The snapshot froze `name` in the language of its day; resolved again so
 *  history follows a language switch. The stored name stays for a variation
 *  the library no longer has, and for a record from before v3. */
private fun currentName(ex: SessionExercise): String =
    if (ex.variation in 1..Library.count(ex.pattern)) Library.name(ex.pattern, ex.variation) else ex.name
