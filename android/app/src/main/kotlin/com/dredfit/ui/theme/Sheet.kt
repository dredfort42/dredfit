//
//  SwiftUI's `.sheet` with `.presentationDetents([.large])`, a drag
//  indicator and the `bg` ground: a modal bottom sheet opened straight to its
//  full height. A swipe down or the back gesture closes it, as the swipe does
//  on iOS, and both reach `onDismiss` — the place the flow's frozen
//  countdowns pick up again.
//

package com.dredfit.ui.theme

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DredfitSheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val c = Theme.colors
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = c.bg,
        contentColor = c.ink,
        content = content,
    )
}
