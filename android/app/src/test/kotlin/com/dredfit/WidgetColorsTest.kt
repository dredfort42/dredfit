//
//  The widget's colours (TodayStatusWidget.kt, `WidgetColors`): the app's
//  palette tokens as day/night pairs, the second column under raised
//  contrast. No Swift twin — iOS's widget reads the same asset colours as the
//  app by construction; here the pairs are spelled out, so a token can be
//  swapped for its neighbour without anything else noticing.
//

package com.dredfit

import androidx.glance.color.DayNightColorProvider
import com.dredfit.ui.theme.Palette
import com.dredfit.widgets.WidgetColors
import kotlin.test.Test
import kotlin.test.assertEquals

class WidgetColorsTest {

    private fun assertColumns(colors: WidgetColors, day: Palette, night: Palette) {
        assertEquals(DayNightColorProvider(day.bg, night.bg), colors.bg)
        assertEquals(DayNightColorProvider(day.ink, night.ink), colors.ink)
        assertEquals(DayNightColorProvider(day.ink2, night.ink2), colors.ink2)
        assertEquals(DayNightColorProvider(day.hairline, night.hairline), colors.hairline)
        assertEquals(DayNightColorProvider(day.restFill, night.restFill), colors.restFill)
        assertEquals(DayNightColorProvider(day.accent, night.accent), colors.accent)
        // iOS's `Theme.planned` is ink3, the graphics tone.
        assertEquals(DayNightColorProvider(day.ink3, night.ink3), colors.planned)
    }

    @Test
    fun eachTokenIsThePalettesInBothModes() {
        assertColumns(WidgetColors(highContrast = false), Palette.light, Palette.dark)
    }

    @Test
    fun raisedContrastTakesTheSecondColumn() {
        assertColumns(WidgetColors(highContrast = true), Palette.lightHighContrast, Palette.darkHighContrast)
    }
}
