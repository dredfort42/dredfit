//
//  The share control of the Progress header, and the one way a card leaves
//  the app: the system share sheet over a content:// URI of the rendered
//  PNG. Port of ios/Dredfit/Views/Progress/ShareButton.swift (`ShareLink`).
//
//  An icon, not a labelled pill: in Russian the word does not fit beside the
//  number and its caption, and what would give is the number.
//

package com.dredfit.ui.progress

import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.TrayArrowGlyph
import com.dredfit.ui.tr

@Composable
fun ShareButton(card: ShareCardFactory.Card?, headline: String) {
    val card = card ?: return
    val c = Theme.colors
    val context = LocalContext.current
    val label = tr("Share progress")
    // Capped like the iOS glyph: the ring does not grow, and past ~22 pt the
    // arrow spills out of it.
    val glyph = minOf(15.dp * LocalDensity.current.fontScale, 20.dp)
    Box(Modifier.size(MinTarget).clickable(role = Role.Button) { shareCard(context, card, headline) }
            .semantics { contentDescription = label }.testTag("share-progress"),
        contentAlignment = Alignment.Center) {
        // The ring is the only thing saying this glyph is a control:
        // `targetStroke`, the milestone's Share button's role.
        Box(Modifier.size(38.dp).clip(CircleShape).background(c.bg).border(1.5.dp, c.targetStroke, CircleShape),
            contentAlignment = Alignment.Center) {
            TrayArrowGlyph(c.ink2, up = true, size = glyph)
        }
    }
}

/** The system share sheet over the card. The preview carries the PICTURE
 *  (the ClipData thumbnail Android 10+ shows), titled with the headline —
 *  what the card says about the athlete is what they would check first. */
fun shareCard(context: Context, card: ShareCardFactory.Card, headline: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "image/png"
        putExtra(Intent.EXTRA_STREAM, card.uri)
        putExtra(Intent.EXTRA_TITLE, headline)
        clipData = ClipData.newRawUri(headline, card.uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, headline))
}
