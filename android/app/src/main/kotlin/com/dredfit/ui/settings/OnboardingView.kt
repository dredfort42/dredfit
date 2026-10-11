//
//  First-run explainer: three cards. The thermostat idea is the one thing a
//  new user cannot infer from the UI. Port of
//  ios/Dredfit/Views/Settings/OnboardingView.swift.
//
//  Finishing is reached only through the care card's explicit button (#101):
//  Skip jumps TO that card, never past it, so finishing always means the
//  checklist was on screen and acknowledged.
//

package com.dredfit.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dredfit.ui.theme.ArrowRightGlyph
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import kotlinx.coroutines.launch

private const val PAGE_COUNT = 3

@Composable
fun OnboardingView(onFinish: () -> Unit) {
    val c = Theme.colors
    val pager = rememberPagerState { PAGE_COUNT }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == PAGE_COUNT - 1
    // A full-screen cover on iOS has no back gesture; here back steps to the
    // card before, and on the first card does nothing — the cover is left
    // only through the care card.
    BackHandler { if (pager.currentPage > 0) scope.launch { pager.animateScrollToPage(pager.currentPage - 1) } }
    Column(Modifier.fillMaxSize().background(c.bg).safeDrawingPadding()) {
        // Faded rather than removed on the last card, so the cards do not
        // jump. ink2: an interactive control needs 3:1.
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 12.dp), horizontalArrangement = Arrangement.End) {
            val hint = tr("Skips ahead to the care note")
            Box(Modifier.heightIn(min = MinTarget).alpha(if (last) 0f else 1f)
                    // The hint rides on the action's label, TalkBack's
                    // "double-tap to …".
                    .clickable(enabled = !last, onClickLabel = hint, role = Role.Button) {
                        scope.launch { pager.animateScrollToPage(PAGE_COUNT - 1) }
                    }
                    .semantics { if (last) hideFromAccessibility() }
                    .testTag("onboarding-skip"),
                contentAlignment = Alignment.Center) {
                Text(tr("Skip"), style = dredfitFont(15f), color = c.ink2)
            }
        }
        HorizontalPager(pager, Modifier.weight(1f)) { page ->
            when (page) {
                // No minute count: prose cannot hold a number only the
                // engine knows, and Today prints the engine's range next.
                0 -> CardShell(tr("Training at home. No questionnaires."),
                               tr("No questions about your goal, your level or how much time you have. Open the app and train — the first workout is already waiting. About half an hour, no equipment.")) {}
                1 -> CardShell(tr("It adjusts like a thermostat."),
                               tr("Dredfit gives you a plan, you say how it went, and the next plan shifts. Answer honestly afterwards and the load becomes yours, step by step.")) {
                    LoopDiagram(Modifier.padding(top = 28.dp))
                }
                // The card Skip lands on: the care note, and the sentence
                // that sizes the first workout, live here.
                else -> CardShell(tr("One tap after the workout."),
                                  tr("“Less · On plan · More” — that is enough. If you want to be exact, tap “Went differently” right on the exercise and put in your number. The first workout is deliberately easy: it is the starting point, not a test.")) {
                    // Statements, not questions: read, not filled in, and
                    // nothing it names is stored.
                    Text(tr("All your data stays on your device.\n\nTalk to a doctor before you start if any of this is you: a heart condition or chest pain under load; blood pressure that is treated or runs high; dizziness or fainting; a joint injury that flares under load; pregnancy or recent childbirth.\n\nSharp pain during an exercise always means stop."),
                         style = dredfitFont(12.5f).copy(lineHeight = 17.sp), color = c.ink2,
                         modifier = Modifier.padding(top = 28.dp).testTag("onboarding-care"))
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 26.dp).clearAndSetSemantics {},
            horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally)) {
            for (i in 0 until PAGE_COUNT) {
                Box(Modifier.size(7.dp).background(if (i == pager.currentPage) c.accent else c.hairline, CircleShape))
            }
        }
        // Today owns the key "Next"; one key cannot carry two meanings.
        PrimaryButton(if (last) tr("I understand — start") else tr("Continue"), tag = "onboarding-primary",
                      modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 20.dp)) {
            if (last) onFinish() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
        }
    }
}

/** Centred while it fits, scrollable once it does not. */
@Composable
private fun CardShell(title: String, body: String, extra: @Composable () -> Unit) {
    val c = Theme.colors
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(horizontal = 24.dp),
               verticalArrangement = Arrangement.Center) {
            Text(title, style = dredfitFont(32f, Weight.heavy, tracking = -0.6f), color = c.ink)
            Text(body, style = dredfitFont(16.5f).copy(lineHeight = 23.sp), color = c.ink2, modifier = Modifier.padding(top = 16.dp))
            extra()
        }
    }
}

/** plan → actual → plan, one element for TalkBack. */
@Composable
private fun LoopDiagram(modifier: Modifier) {
    val label = tr("Plan, then your actual result, then the next plan")
    Row(modifier.clearAndSetSemantics { contentDescription = label }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        LoopChip(tr("plan"), filled = false)
        ArrowRightGlyph(Theme.colors.ink3)
        LoopChip(tr("actual"), filled = true)
        ArrowRightGlyph(Theme.colors.ink3)
        LoopChip(tr("plan"), filled = false)
    }
}

/** ink on the filled chip, not accentText (4.20:1 on accentSoft in dark). */
@Composable
private fun LoopChip(text: String, filled: Boolean) {
    val c = Theme.colors
    Text(text, style = dredfitFont(13f, Weight.semibold), color = if (filled) c.ink else c.ink2,
         modifier = Modifier.background(if (filled) c.accentSoft else c.cardBG, CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
}
