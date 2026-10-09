//
//  The handful of SF Symbols the screens use, drawn rather than shipped: the
//  app carries no icon font and no third-party dependency, and each of these
//  is a few strokes. Sized in dp like the symbol's point size on iOS.
//

package com.dredfit.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** "info.circle". */
@Composable
fun InfoGlyph(color: Color, size: Dp = 16.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.09f
        drawCircle(color, radius = w / 2 - line / 2, style = Stroke(line))
        drawCircle(color, radius = line * 0.75f, center = Offset(w / 2, w * 0.3f))
        drawLine(color, Offset(w / 2, w * 0.45f), Offset(w / 2, w * 0.74f), line * 1.1f, StrokeCap.Round)
    }
}

/** "pause.fill" / "play.fill". */
@Composable
fun PauseGlyph(paused: Boolean, color: Color, size: Dp = 13.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        if (paused) {
            val p = Path().apply {
                moveTo(w * 0.15f, 0f); lineTo(w, w / 2); lineTo(w * 0.15f, w); close()
            }
            drawPath(p, color)
        } else {
            val bar = w * 0.3f
            drawRect(color, Offset(w * 0.1f, 0f), androidx.compose.ui.geometry.Size(bar, w))
            drawRect(color, Offset(w * 0.9f - bar, 0f), androidx.compose.ui.geometry.Size(bar, w))
        }
    }
}

/** "chevron.right". */
@Composable
fun ChevronGlyph(color: Color, size: Dp = 12.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val p = Path().apply { moveTo(w * 0.3f, w * 0.1f); lineTo(w * 0.7f, w / 2); lineTo(w * 0.3f, w * 0.9f) }
        drawPath(p, color, style = Stroke(w * 0.16f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** "checkmark". */
@Composable
fun CheckGlyph(color: Color, size: Dp = 44.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val p = Path().apply { moveTo(w * 0.12f, w * 0.52f); lineTo(w * 0.4f, w * 0.8f); lineTo(w * 0.9f, w * 0.2f) }
        drawPath(p, color, style = Stroke(w * 0.12f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** "gearshape" — the eight teeth as short rays around a ring. */
@Composable
fun GearGlyph(color: Color, size: Dp = 19.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val r = w / 2
        val line = w * 0.11f
        drawCircle(color, radius = r * 0.62f, style = Stroke(line))
        drawCircle(color, radius = r * 0.22f, style = Stroke(line))
        for (i in 0 until 8) {
            val a = Math.toRadians(i * 45.0)
            val from = Offset(center.x + (r * 0.7f) * kotlin.math.cos(a).toFloat(),
                              center.y + (r * 0.7f) * kotlin.math.sin(a).toFloat())
            val to = Offset(center.x + (r * 0.98f) * kotlin.math.cos(a).toFloat(),
                            center.y + (r * 0.98f) * kotlin.math.sin(a).toFloat())
            drawLine(color, from, to, line * 1.6f, StrokeCap.Round)
        }
    }
}
