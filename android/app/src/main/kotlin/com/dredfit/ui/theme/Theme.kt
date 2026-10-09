//
//  The palette, the type and the shared controls. Port of
//  ios/Dredfit/Design/Theme.swift and the colorsets of Brand.xcassets — the
//  table below is theirs, and the reasoning behind every value (the contrast
//  floors each token is measured against) is written there.
//
//      token       light     dark
//      bg          #FFFFFF   #090A0C
//      cardBG      #F7F7F5   #1E1F23
//      ink         #111214   #F2F2F4
//      ink2        #6E7075   #98999E
//      ink3        #A7A9AD   #5C5D62
//      hairline    #ECEDEF   #2A2C30
//      restFill    #E2E3E6   #35363A
//      accent      #E8590C   #E8590C
//      accentText  #B44504   #E8590C
//      accentSoft  #FBE3D6   #3A2013
//
//  The Increased Contrast columns of the asset catalog are not here: Android's
//  counterpart (the contrast level of Android 14+) arrives with Settings'
//  appearance, which is where the app reads display preferences.
//

package com.dredfit.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class Palette(
    val bg: Color,
    val cardBG: Color,
    val ink: Color,
    val ink2: Color,
    /** A GRAPHICS tone: under the 4.5:1 small text needs in both schemes. */
    val ink3: Color,
    val hairline: Color,
    val restFill: Color,
    val accent: Color,
    /** Accent for TEXT: #E8590C is 3.58:1 on white, short of 4.5:1. */
    val accentText: Color,
    val accentSoft: Color,
) {
    /** The boundary of a target — an alias of ink2, the quietest tone that
     *  clears 1.4.11's 3:1 on `bg` in both schemes (Theme.swift). */
    val targetStroke: Color get() = ink2

    companion object {
        val light = Palette(
            bg = Color(0xFFFFFFFF), cardBG = Color(0xFFF7F7F5), ink = Color(0xFF111214),
            ink2 = Color(0xFF6E7075), ink3 = Color(0xFFA7A9AD), hairline = Color(0xFFECEDEF),
            restFill = Color(0xFFE2E3E6), accent = Color(0xFFE8590C), accentText = Color(0xFFB44504),
            accentSoft = Color(0xFFFBE3D6))
        val dark = Palette(
            bg = Color(0xFF090A0C), cardBG = Color(0xFF1E1F23), ink = Color(0xFFF2F2F4),
            ink2 = Color(0xFF98999E), ink3 = Color(0xFF5C5D62), hairline = Color(0xFF2A2C30),
            restFill = Color(0xFF35363A), accent = Color(0xFFE8590C),
            // Equal to `accent` on purpose: #E8590C reads 5.5:1 on the dark
            // ground, where the light value would read 3.58:1.
            accentText = Color(0xFFE8590C), accentSoft = Color(0xFF3A2013))
    }
}

val LocalPalette = staticCompositionLocalOf { Palette.light }

/** `Theme.ink` and its siblings, read where they are drawn. */
object Theme {
    val colors: Palette
        @Composable @ReadOnlyComposable get() = LocalPalette.current
}

@Composable
fun DredfitTheme(dark: Boolean, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalPalette provides if (dark) Palette.dark else Palette.light, content = content)
}

/** The floor every tap target in the flow holds to (#193): a bare 14 pt word
 *  is about 17 pt of hit area. */
val MinTarget = 44.dp

/**
 * `dredfitFont`: a design size in points, which Android scales by the
 * reader's font size as sp — Dynamic Type's job on iOS. `cap` bounds the
 * scaled result, and only the few display numbers that are already enormous
 * by design may use it: clipping the reader's setting is what scaling exists
 * to prevent.
 */
@Composable
@ReadOnlyComposable
fun dredfitFont(size: Float, weight: FontWeight = FontWeight.Normal, cap: Float? = null,
                tracking: Float = 0f, monospacedDigit: Boolean = false): TextStyle {
    val scale = LocalDensity.current.fontScale
    val px: TextUnit = if (cap != null && size * scale > cap) (cap / scale).sp else size.sp
    return TextStyle(
        fontSize = px,
        fontWeight = weight,
        letterSpacing = tracking.sp,
        // `.monospacedDigit()`: a figure that changes every second must not
        // make its line breathe.
        fontFeatureSettings = if (monospacedDigit) "tnum" else null,
    )
}

/** SwiftUI's weights by name, so a port reads like its source. */
object Weight {
    val regular = FontWeight.Normal
    val medium = FontWeight.Medium
    val semibold = FontWeight.SemiBold
    val bold = FontWeight.Bold
    val heavy = FontWeight.ExtraBold
}

/** The single full-width action of a screen: ink fill, bg words, 56 tall on
 *  an 18 radius. bg, not white: on the ink fill the label must flip with the
 *  scheme. */
@Composable
fun PrimaryButton(title: String, tag: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(18.dp)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(c.ink, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = dredfitFont(17f, Weight.semibold), color = c.bg)
    }
}

/** The filled half of a side-by-side pair: 46 tall on a 14 radius. */
@Composable
fun PairedPrimary(title: String, tag: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier
            .heightIn(min = 46.dp)
            .clip(shape)
            .background(c.ink, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = dredfitFont(15.5f, Weight.semibold), color = c.bg)
    }
}

/** The outlined half of a pair. The outline IS the button — no fill behind
 *  it — so it owes 1.4.11's 3:1, which `hairline` (1.17:1) does not give. */
@Composable
fun PairedSecondary(title: String, tag: String?, modifier: Modifier = Modifier, enabled: Boolean = true,
                    onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier
            .heightIn(min = 46.dp)
            .clip(shape)
            .border(1.5.dp, c.targetStroke, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = dredfitFont(15.5f, Weight.medium), color = c.ink2)
    }
}

/** "Train anyway" and the quiet "Start": bordered and unfilled, 56 tall. */
@Composable
fun QuietButton(title: String, tag: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(18.dp)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .border(1.5.dp, c.hairline, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = dredfitFont(17f, Weight.medium), color = c.ink2)
    }
}

/** The small uppercase line over a heading. ink2, never ink3: 12 pt
 *  semibold is small text, and ink3 is 2.35:1 on the light ground. */
@Composable
fun Kicker(text: String, modifier: Modifier = Modifier, color: Color = Theme.colors.ink2) {
    Text(text.uppercase(), modifier = modifier, style = dredfitFont(12f, Weight.semibold, tracking = 0.8f),
         color = color)
}
