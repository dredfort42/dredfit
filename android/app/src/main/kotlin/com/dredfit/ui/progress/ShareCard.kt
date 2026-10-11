//
//  The share card: rendered locally, 1080×1350 (4:5), on a Canvas. Nothing
//  leaves the device on its own. Port of
//  ios/Dredfit/Views/Progress/ShareCard.swift — it never carries body
//  metrics, weight, photos, a name or a streak.
//
//  Fixed pixel sizes: this is an image of a known size, not a screen, so the
//  reader's font scale must not reflow what other people receive. And it is
//  light for everyone — the palette's light ink as its ground — whatever the
//  app's appearance: the colours below are the light column by name.
//

package com.dredfit.ui.progress

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.FileProvider
import com.dredfit.ui.theme.Palette
import com.dredfit.workout.Milestone
import com.dredfit.workout.Words
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

object ShareCard {
    const val WIDTH = 1080
    const val HEIGHT = 1350
    const val CURVE_GAP = 56f

    /** Vertical room the headline, date and curve share. */
    const val CONTENT_BUDGET = 940f

    private const val GUTTER = 88f
    private const val COLUMN = WIDTH - 2 * GUTTER

    /** Thresholds count characters, not bytes, so Cyrillic is measured the
     *  same way as Latin. */
    fun headlineSize(headline: String): Float = when (headline.codePointCount(0, headline.length)) {
        in 0 until 90 -> 92f
        in 90 until 150 -> 70f
        in 150 until 220 -> 54f
        else -> 44f
    }

    /** Measured rather than guessed from a character count, which wraps to a
     *  different number of lines in every language. */
    fun headlineHeight(headline: String): Float = layout(headline, headlinePaint(headline), lineSpacing = 6f).height.toFloat()

    fun sublineHeight(subline: String?): Float =
        if (subline == null) 0f else layout(subline, sublinePaint(), lineSpacing = 5f).height + 26f

    /** Takes what the headline and subline leave, and gives up its place
     *  entirely when that is too thin to read as a line. */
    fun curveHeight(headline: String, subline: String? = null): Float {
        val free = CONTENT_BUDGET - headlineHeight(headline) - sublineHeight(subline) - CURVE_GAP
        return if (free < 140) 0f else minOf(300f, free)
    }

    private fun paint(size: Float, weight: Int, color: Int, alpha: Float = 1f): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            typeface = Typeface.create(Typeface.DEFAULT, weight, false)
            this.color = color
            this.alpha = (alpha * 255).toInt()
        }

    private fun headlinePaint(headline: String): TextPaint {
        val size = headlineSize(headline)
        return paint(size, 800, WHITE).apply { letterSpacing = -0.027f }
    }

    private fun sublinePaint(): TextPaint = paint(36f, 400, WHITE, alpha = 0.7f)

    private fun layout(text: String, paint: TextPaint, lineSpacing: Float): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, COLUMN.toInt())
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(lineSpacing, 1f)
            .setIncludePad(false)
            .build()

    private const val WHITE = android.graphics.Color.WHITE

    /** The card, drawn top to bottom the way ShareCard.swift stacks it: the
     *  word-mark, the accent rule, the headline, the date, the subline, the
     *  curve, and the domain we own at the foot. */
    fun render(headline: String, date: String, steps: List<Int>, subline: String?): Bitmap {
        val light = Palette.light
        val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(light.ink.toArgb())

        val mark = paint(46f, 800, WHITE).apply { letterSpacing = -1f / 46f }
        canvas.drawText("Dredfit", GUTTER, GUTTER - mark.ascent(), mark)
        val footer = paint(34f, 400, WHITE, alpha = 0.4f)
        val footerTop = HEIGHT - GUTTER - (footer.descent() - footer.ascent())

        val headlineLayout = layout(headline, headlinePaint(headline), lineSpacing = 6f)
        val datePaint = paint(38f, 400, WHITE, alpha = 0.55f)
        val dateHeight = datePaint.descent() - datePaint.ascent()
        val sublineLayout = subline?.let { layout(it, sublinePaint(), lineSpacing = 5f) }
        val curveHeight = if (steps.size > 1) curveHeight(headline, subline) else 0f
        val curveBlock = if (curveHeight > 0) curveHeight + CURVE_GAP else 0f

        // The text block sits between two flexible gaps, as the Spacers do;
        // the curve hangs above the footer.
        val block = 8f + 44f + headlineLayout.height + 34f + dateHeight + (sublineLayout?.let { it.height + 26f } ?: 0f)
        val markBottom = GUTTER + (mark.descent() - mark.ascent())
        val curveTop = footerTop - curveBlock
        val free = (curveTop - markBottom - block).coerceAtLeast(0f)
        var y = markBottom + free / 2

        val accent = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = light.accent.toArgb() }
        canvas.drawRect(GUTTER, y, GUTTER + 132f, y + 8f, accent)
        y += 8f + 44f
        canvas.save()
        canvas.translate(GUTTER, y)
        headlineLayout.draw(canvas)
        canvas.restore()
        y += headlineLayout.height + 34f
        canvas.drawText(date, GUTTER, y - datePaint.ascent(), datePaint)
        y += dateHeight
        sublineLayout?.let {
            y += 26f
            canvas.save()
            canvas.translate(GUTTER, y)
            it.draw(canvas)
            canvas.restore()
        }
        if (curveHeight > 0) drawCurve(canvas, steps, top = curveTop, height = curveHeight, color = light.accent.toArgb())
        canvas.drawText("dredfit.com", GUTTER, footerTop - footer.ascent(), footer)
        return bitmap
    }

    /** Drawn the way the Progress screen draws it — zero-based, edge to edge
     *  of the card (the gutters given back), 6 px where the screen's is 2 dp
     *  on a card 1080 wide. */
    private fun drawCurve(canvas: Canvas, values: List<Int>, top: Float, height: Float, color: Int) {
        val peak = values.maxOrNull() ?: return
        val inset = 14f
        val width = WIDTH - inset * 2
        val h = height - inset * 2
        val points = values.mapIndexed { i, v ->
            val x = inset + width * i / (values.size - 1)
            val t = if (peak <= 0) 0f else v.toFloat() / peak
            x to top + inset + h * (1 - t)
        }
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = 6f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val path = android.graphics.Path()
        points.forEachIndexed { i, (x, y) -> if (i == 0) path.moveTo(x, y) else path.lineTo(x, y) }
        canvas.drawPath(path, stroke)
        val (lx, ly) = points.last()
        canvas.drawCircle(lx, ly, 11f, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
    }
}

object ShareCardFactory {

    fun headline(milestone: Milestone): Words = when (milestone) {
        is Milestone.VariationUp -> Words.of("Unlocked: %@", Words.name(milestone.exercise))
        is Milestone.SetBand -> Words.of("Now %lld sets", milestone.sets)
        is Milestone.Jubilee -> Words.of("Workout #%lld", milestone.workouts)
    }

    /** Every unlocked variation is named — a session can unlock several at
     *  once. With no unlock at all the first milestone speaks for the card.
     *  Same key as the single unlock, so every translation covers it. */
    fun headline(milestones: List<Milestone>): Words {
        val unlocked = milestones.filterIsInstance<Milestone.VariationUp>().map { Words.name(it.exercise) }
        if (unlocked.isEmpty()) return milestones.firstOrNull()?.let(::headline) ?: Words.join("")
        if (unlocked.size == 1) return Words.of("Unlocked: %@", unlocked[0])
        return Words.of("Unlocked: %@", Words.narrowList(unlocked))
    }

    /** Two strings on purpose: as one it would need a nested plural (Russian
     *  inflects both halves, and differently). */
    fun summaryHeadline(workouts: Int, totalSteps: Int): Words =
        Words.join("%@ · %@", Words.of("%lld workouts", workouts), Words.of("%lld steps", totalSteps))

    /** So the two sources never overwrite each other's file while a share
     *  sheet is open on it. */
    enum class Slot(val fileName: String) { milestone("dredfit-milestone"), progress("dredfit-progress") }

    fun png(headline: String, date: String, subline: String? = null, steps: List<Int> = emptyList()): ByteArray =
        ByteArrayOutputStream().use { out ->
            ShareCard.render(headline, date, steps, subline).compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }

    /** The file that travels and the picture of it, from one render. */
    class Card(val uri: Uri, val image: Bitmap)

    /** One fixed name per slot, so the cache never accumulates; null when
     *  the file could not be written. Off the main thread. */
    fun card(context: Context, headline: String, slot: Slot, date: String, subline: String? = null,
             steps: List<Int> = emptyList()): Card? {
        val image = ShareCard.render(headline, date, steps, subline)
        val file = file(context, slot)
        return try {
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, file.name + ".tmp")
            temp.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            if (!temp.renameTo(file)) throw IOException("rename failed")
            Card(FileProvider.getUriForFile(context, authority(context), file), image)
        } catch (_: IOException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    fun file(context: Context, slot: Slot): File = File(File(context.cacheDir, "share"), "${slot.fileName}.png")

    /** The FileProvider of the manifest (res/xml/share_paths.xml). */
    fun authority(context: Context): String = "${context.packageName}.share"
}
