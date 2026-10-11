//
//  The one alert of the app, in place of SwiftUI's `.alert`. Every question
//  the iOS app asks before a change it cannot take back is an ALERT there,
//  never a popover: it is centred whatever raised it, and it SWALLOWS a tap
//  outside instead of reading it as an answer (TodayView.swift). So here a
//  tap outside does nothing, and the back gesture is the cancel button — the
//  one whose words say what it keeps.
//

package com.dredfit.ui.theme

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.window.DialogProperties

/** One action of an alert. `cancel` is the escape the back gesture takes;
 *  `destructive` paints the words in the accent, as iOS paints them red. */
data class AlertAction(
    val title: String,
    val tag: String?,
    val cancel: Boolean = false,
    val destructive: Boolean = false,
    val run: () -> Unit,
)

@Composable
fun DredfitAlert(title: String, message: String?, actions: List<AlertAction>, onClose: () -> Unit) {
    val c = Theme.colors
    val cancel = actions.firstOrNull { it.cancel }
    AlertDialog(
        onDismissRequest = {
            // Only the back gesture reaches here (outside taps are off): it
            // answers with the cancel action, never with nothing.
            onClose()
            cancel?.run?.invoke()
        },
        properties = DialogProperties(dismissOnClickOutside = false),
        containerColor = c.cardBG,
        title = { Text(title, style = dredfitFont(18f, Weight.semibold), color = c.ink) },
        text = message?.let { { Text(it, style = dredfitFont(14.5f), color = c.ink2) } },
        // Stacked, cancel last, like a three- or four-button iOS alert: the
        // words of every action stay whole in every language.
        confirmButton = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End,
                   verticalArrangement = Arrangement.spacedBy(0.dp0)) {
                for (action in actions.filter { !it.cancel } + listOfNotNull(cancel)) {
                    TextButton(
                        onClick = {
                            onClose()
                            action.run()
                        },
                        modifier = Modifier.heightIn(min = MinTarget)
                            .then(if (action.tag != null) Modifier.testTag(action.tag) else Modifier),
                    ) {
                        Text(action.title,
                             style = dredfitFont(15.5f, if (action.cancel) Weight.semibold else Weight.medium),
                             color = if (action.destructive) c.accentText else c.ink)
                    }
                }
            }
        },
    )
}

private val Int.dp0 get() = androidx.compose.ui.unit.Dp(this.toFloat())
private val dp0 = 0.dp0
