//
//  The RENDER half of ios/DredfitTests/ShareCardTests.swift (the wording half
//  is the JVM ShareCardTest): ten tests that need Android's Canvas, Bitmap
//  and StaticLayout. The fit tests measure the headline independently of the
//  card's own arithmetic — the point is to catch the two disagreeing.
//

package com.dredfit

import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.ui.graphics.toArgb
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.ui.progress.ShareCard
import com.dredfit.ui.progress.ShareCardFactory
import com.dredfit.ui.theme.Palette
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ShareCardRenderTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    /** A fixed date line, so two renders differ only by what is tested. */
    private val date = "29 May 2026"

    @Test
    fun cardRendersAtTheSpecifiedPixelSize() {
        val png = ShareCardFactory.png("Unlocked: Pistol squat", date)
        val image = checkNotNull(BitmapFactory.decodeByteArray(png, 0, png.size)) { "the PNG did not decode" }
        // 4:5 at the size the spec calls for — not a scaled multiple of it.
        assertEquals(1080, image.width)
        assertEquals(1350, image.height)
    }

    @Test
    fun cardIsWrittenAsAPNGFile() {
        val card = checkNotNull(ShareCardFactory.card(context, "Workout #50", ShareCardFactory.Slot.milestone, date))
        val file = ShareCardFactory.file(context, ShareCardFactory.Slot.milestone)
        assertEquals("png", file.extension)
        val bytes = context.contentResolver.openInputStream(card.uri)!!.use { it.readBytes() }
        assertFalse(bytes.isEmpty())
        // The PNG magic number — proof it is really a PNG, not just named one.
        assertEquals(listOf(0x89, 0x50, 0x4E, 0x47), bytes.take(4).map { it.toInt() and 0xFF })
    }

    @Test
    fun theTwoSlotsDoNotShareAFile() {
        val milestone = ShareCardFactory.card(context, "Workout #50", ShareCardFactory.Slot.milestone, date)!!
        val progress = ShareCardFactory.card(context, "12 workouts", ShareCardFactory.Slot.progress, date)!!
        assertNotEquals("one file for both would let a new card overwrite an open share", milestone.uri, progress.uri)
    }

    /** iOS pins the card's own colour scheme so a dark viewer's render is
     *  light. Here the card takes no palette at all: its ground is the light
     *  column's ink, whatever the app's appearance — a render that followed
     *  the dark palette would draw on #F2F2F4. */
    @Test
    fun aCardIsDrawnInTheLightPaletteWhateverTheAppearance() {
        val a = ShareCard.render("Workout #50", date, listOf(12, 18, 26), null)
        val b = ShareCard.render("Workout #50", date, listOf(12, 18, 26), null)
        assertTrue("two renders of one card are pixel-identical", a.sameAs(b))
        assertEquals(Palette.light.ink.toArgb(), a.getPixel(4, 4))
        assertNotEquals(Palette.dark.ink.toArgb(), a.getPixel(4, 4))
    }

    // MARK: - The level curve

    @Test
    fun oneSessionIsNotYetACurve() {
        val none = ShareCardFactory.png("Workout #1", date)
        val one = ShareCardFactory.png("Workout #1", date, steps = listOf(12))
        assertArrayEquals("a single session is a dot, not a history", none, one)
        val two = ShareCardFactory.png("Workout #1", date, steps = listOf(12, 26))
        assertFalse("two sessions are a curve and must show up", none.contentEquals(two))
    }

    @Test
    fun aFlatHistoryStillRenders() {
        assertTrue(ShareCardFactory.png("Workout #2", date, steps = listOf(0, 0, 0)).isNotEmpty())
        val png = ShareCardFactory.png("Now 4 sets", date, steps = listOf(96, 96, 96, 96))
        val image = BitmapFactory.decodeByteArray(png, 0, png.size)
        assertEquals(1080, image.width)
        assertEquals(1350, image.height)
    }

    /** The curve is whatever the words did not need — never the other way. */
    /** On iOS 89 characters at 92 pt fill seven lines of SF and leave the
     *  curve nothing. Roboto is narrower — the same text takes five lines
     *  here — so the rule is asserted as a rule: at every size step the curve
     *  is exactly what the independently measured headline leaves, and a
     *  card whose words leave less than a readable line gives it up. */
    @Test
    fun theCurveOnlyTakesWhatTheHeadlineLeaves() {
        assertTrue(ShareCard.curveHeight("Unlocked: Pistol squat") > 0)
        for (length in listOf(89, 149, 219, 300)) {
            val text = headline(ofLength = length)
            val free = ShareCard.CONTENT_BUDGET - headlineHeight(text) - ShareCard.CURVE_GAP
            assertEquals("$length characters", if (free < 140) 0f else minOf(300f, free), ShareCard.curveHeight(text), 0.5f)
        }
        // A jubilee's retrospective under a long headline: nothing is left.
        val tall = headline(ofLength = 89)
        val subline = List(6) { "Your first workout: 3×4 push-ups — today 3×12 push-ups" }.joinToString("\n")
        assertEquals("words that fill the card leave the curve nothing", 0f, ShareCard.curveHeight(tall, subline))
    }

    // MARK: - Fit

    @Test
    fun aSingleUnlockKeepsTheFullSizeHeadline() {
        assertEquals(92f, ShareCard.headlineSize("Unlocked: Pistol squat"))
        assertEquals(92f, ShareCard.headlineSize("Workout #100"))
    }

    /** Worst case: seven unlocks with the longest names, in Russian. */
    @Test
    fun everyUnlockAWorkoutCanEarnStillFitsTheCard() {
        val names = listOf("Болгарский сплит-присед", "Отжимание с ногами на возвышении", "Ягодичный мостик на одной ноге",
                           "Подтягивание австралийское", "Отжимание в стойке у стены", "Приседание на одной ноге",
                           "Планка с подъемом руки и ноги")
        val headline = "Разблокировано: " + names.joinToString(", ")
        assertTrue("the headline would push the date off the card", claimed(headline) <= ShareCard.CONTENT_BUDGET)
    }

    /** The size steps down at 90, 150 and 220 characters: the tallest
     *  headline of each step is the one just under its ceiling. */
    @Test
    fun headlineAtEveryStepBoundaryFits() {
        for (length in listOf(89, 149, 219, 300)) {
            assertTrue("$length characters overflow the card", claimed(headline(ofLength = length)) <= ShareCard.CONTENT_BUDGET)
        }
    }

    /** What the headline and the curve claim between them, measured here. */
    private fun claimed(headline: String): Float {
        val curve = ShareCard.curveHeight(headline)
        return headlineHeight(headline) + if (curve > 0) curve + ShareCard.CURVE_GAP else 0f
    }

    /** The headline in the card's text column (1080 less the 88 px gutters),
     *  in the face and size the card renders it in. */
    private fun headlineHeight(headline: String): Float {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = ShareCard.headlineSize(headline)
            typeface = Typeface.create(Typeface.DEFAULT, 800, false)
            letterSpacing = -0.027f
        }
        return StaticLayout.Builder.obtain(headline, 0, headline.length, paint, ShareCard.WIDTH - 176)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(6f, 1f).setIncludePad(false)
            .build().height.toFloat()
    }

    /** Real exercise names, English and Russian both: filler of wide glyphs
     *  would fail the budget on text the card is never handed. */
    private fun headline(ofLength: Int): String {
        val names = listOf("Bulgarian split squat", "Отжимание с ногами на возвышении", "Single-leg glute bridge",
                           "Приседание на одной ноге")
        val text = StringBuilder("Unlocked: ")
        var i = 0
        while (text.length < ofLength) text.append(names[i++ % names.size]).append(", ")
        return text.substring(0, ofLength)
    }
}
