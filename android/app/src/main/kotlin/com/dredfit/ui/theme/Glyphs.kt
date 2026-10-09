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

/** "chevron.right"; rotated by the caller for the other three directions. */
@Composable
fun ChevronGlyph(color: Color, size: Dp = 12.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
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

/** "square.and.arrow.up" (`up`) and "square.and.arrow.down": an open tray
 *  and an arrow out of it or into it. */
@Composable
fun TrayArrowGlyph(color: Color, up: Boolean, size: Dp = 16.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.09f
        val stroke = Stroke(line, cap = StrokeCap.Round, join = StrokeJoin.Round)
        val tray = Path().apply {
            moveTo(w * 0.3f, w * 0.42f); lineTo(w * 0.14f, w * 0.42f); lineTo(w * 0.14f, w * 0.95f)
            lineTo(w * 0.86f, w * 0.95f); lineTo(w * 0.86f, w * 0.42f); lineTo(w * 0.7f, w * 0.42f)
        }
        drawPath(tray, color, style = stroke)
        val top = if (up) w * 0.05f else w * 0.12f
        val bottom = if (up) w * 0.62f else w * 0.7f
        drawLine(color, Offset(w / 2, top), Offset(w / 2, bottom), line, StrokeCap.Round)
        val tip = if (up) top else bottom
        val back = if (up) tip + w * 0.18f else tip - w * 0.18f
        val head = Path().apply { moveTo(w * 0.32f, back); lineTo(w / 2, tip); lineTo(w * 0.68f, back) }
        drawPath(head, color, style = stroke)
    }
}

/** "questionmark.circle". */
@Composable
fun QuestionGlyph(color: Color, size: Dp = 16.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.09f
        drawCircle(color, radius = w / 2 - line / 2, style = Stroke(line))
        val hook = Path().apply {
            moveTo(w * 0.36f, w * 0.38f)
            cubicTo(w * 0.36f, w * 0.2f, w * 0.64f, w * 0.2f, w * 0.64f, w * 0.38f)
            cubicTo(w * 0.64f, w * 0.5f, w * 0.5f, w * 0.5f, w * 0.5f, w * 0.62f)
        }
        drawPath(hook, color, style = Stroke(line, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawCircle(color, radius = line * 0.75f, center = Offset(w / 2, w * 0.76f))
    }
}

/** "arrow.right". */
@Composable
fun ArrowRightGlyph(color: Color, size: Dp = 11.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.14f
        val stroke = Stroke(line, cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawLine(color, Offset(w * 0.08f, w / 2), Offset(w * 0.92f, w / 2), line, StrokeCap.Round)
        drawPath(Path().apply { moveTo(w * 0.55f, w * 0.15f); lineTo(w * 0.92f, w / 2); lineTo(w * 0.55f, w * 0.85f) },
                 color, style = stroke)
    }
}

/** "star": five points, outlined. */
@Composable
fun StarGlyph(color: Color, size: Dp = 16.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val star = Path()
        for (i in 0 until 10) {
            // Outer and inner corners in turn, the first one straight up.
            val r = if (i % 2 == 0) w * 0.48f else w * 0.2f
            val a = Math.toRadians(-90.0 + i * 36.0)
            val x = w / 2 + r * kotlin.math.cos(a).toFloat()
            val y = w * 0.53f + r * kotlin.math.sin(a).toFloat()
            if (i == 0) star.moveTo(x, y) else star.lineTo(x, y)
        }
        star.close()
        drawPath(star, color, style = Stroke(w * 0.08f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** "heart": two lobes meeting in a point, outlined. */
@Composable
fun HeartGlyph(color: Color, size: Dp = 16.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val heart = Path().apply {
            moveTo(w / 2, w * 0.9f)
            cubicTo(w * 0.1f, w * 0.6f, w * 0.0f, w * 0.3f, w * 0.18f, w * 0.17f)
            cubicTo(w * 0.33f, w * 0.06f, w * 0.47f, w * 0.15f, w / 2, w * 0.27f)
            cubicTo(w * 0.53f, w * 0.15f, w * 0.67f, w * 0.06f, w * 0.82f, w * 0.17f)
            cubicTo(w * 1.0f, w * 0.3f, w * 0.9f, w * 0.6f, w / 2, w * 0.9f)
            close()
        }
        drawPath(heart, color, style = Stroke(w * 0.08f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** The tab bar's three: "circle.inset.filled" (Today), "calendar" and
 *  "chart.line.uptrend.xyaxis" (Progress). */
@Composable
fun TodayGlyph(color: Color, size: Dp = 22.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.08f
        drawCircle(color, radius = w / 2 - line / 2, style = Stroke(line))
        drawCircle(color, radius = w * 0.28f)
    }
}

@Composable
fun CalendarGlyph(color: Color, size: Dp = 22.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.08f
        drawRoundRect(color, topLeft = Offset(w * 0.08f, w * 0.14f),
                      size = androidx.compose.ui.geometry.Size(w * 0.84f, w * 0.78f),
                      cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.14f), style = Stroke(line))
        drawRect(color, Offset(w * 0.08f, w * 0.14f), androidx.compose.ui.geometry.Size(w * 0.84f, w * 0.18f))
        for (row in 0 until 2) for (col in 0 until 4) {
            drawCircle(color, radius = line * 0.6f, center = Offset(w * (0.24f + col * 0.17f), w * (0.52f + row * 0.2f)))
        }
    }
}

@Composable
fun ChartGlyph(color: Color, size: Dp = 22.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.minDimension
        val line = w * 0.08f
        val stroke = Stroke(line, cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawPath(Path().apply { moveTo(w * 0.08f, w * 0.06f); lineTo(w * 0.08f, w * 0.92f); lineTo(w * 0.94f, w * 0.92f) },
                 color, style = stroke)
        drawPath(Path().apply {
            moveTo(w * 0.2f, w * 0.72f); lineTo(w * 0.42f, w * 0.48f); lineTo(w * 0.6f, w * 0.6f); lineTo(w * 0.88f, w * 0.24f)
        }, color, style = stroke)
    }
}
