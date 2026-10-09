//
//  Port of ios/DredfitTests/BrandPaletteTests.swift: every token of the
//  palette in all four appearances (light, dark, each with its Increased
//  Contrast column) pinned against the table of Theme.swift, and the WCAG
//  floors the values were chosen to clear re-derived. All five tests. On
//  iOS the resolution goes through the asset catalog by name; here the
//  palette IS the code (ui/theme/Theme.kt), so the tokens are read by
//  property, and the name table below is the typo net.
//

package com.dredfit

import androidx.compose.ui.graphics.Color
import com.dredfit.ui.theme.Palette
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class BrandPaletteTest {

    private class Token(val name: String, val light: Long, val lightHC: Long, val dark: Long, val darkHC: Long)

    /** Mirrors the table in Theme.swift. */
    private val palette = listOf(
        Token("bg", 0xFFFFFF, 0xFFFFFF, 0x090A0C, 0x090A0C),
        Token("cardBG", 0xF7F7F5, 0xE0E0DD, 0x1E1F23, 0x25262B),
        Token("ink", 0x111214, 0x111214, 0xF2F2F4, 0xF2F2F4),
        Token("ink2", 0x6E7075, 0x535558, 0x98999E, 0xA2A3A8),
        Token("ink3", 0xA7A9AD, 0x727478, 0x5C5D62, 0x7B7C82),
        Token("hairline", 0xECEDEF, 0xD0D2D5, 0x2A2C30, 0x2F3136),
        Token("restFill", 0xE2E3E6, 0xC4C6CA, 0x35363A, 0x35363A),
        Token("accent", 0xE8590C, 0xC94D07, 0xE8590C, 0xE8590C),
        Token("accentText", 0xB44504, 0x993B04, 0xE8590C, 0xFF7526),
        Token("accentSoft", 0xFBE3D6, 0xFBE3D6, 0x3A2013, 0x3A2013),
    )

    private class Floor(val ink: String, val ground: String, val ratio: Double)

    private val darkFloors = listOf(
        Floor("ink", "bg", 7.0), Floor("ink", "cardBG", 7.0), Floor("ink2", "bg", 4.5), Floor("ink2", "cardBG", 4.5),
        Floor("ink3", "bg", 3.0), Floor("hairline", "bg", 1.3), Floor("restFill", "bg", 1.3), Floor("accent", "bg", 3.0),
        Floor("accentText", "bg", 4.5), Floor("accentText", "cardBG", 4.5), Floor("ink", "accentSoft", 4.5),
        Floor("cardBG", "bg", 1.2),
    )

    private val lightTextFloors = listOf(
        Floor("ink", "bg", 7.0), Floor("ink", "cardBG", 7.0), Floor("ink2", "bg", 4.5), Floor("ink2", "cardBG", 4.5),
        Floor("accentText", "bg", 4.5), Floor("accentText", "cardBG", 4.5), Floor("ink", "accentSoft", 7.0),
    )

    private val highContrastFloors = listOf(
        Floor("ink", "bg", 7.0), Floor("ink", "cardBG", 7.0), Floor("ink2", "bg", 7.0), Floor("ink2", "cardBG", 5.5),
        Floor("ink3", "bg", 4.5), Floor("hairline", "bg", 1.5), Floor("restFill", "bg", 1.6), Floor("accent", "bg", 4.5),
        Floor("accentText", "bg", 7.0), Floor("accentText", "cardBG", 4.5), Floor("ink", "accentSoft", 7.0),
        Floor("cardBG", "bg", 1.3),
    )

    @Test
    fun lightSchemeTextTokensClearTheFloorTheKickerRuleRestsOn() = assertFloors(lightTextFloors, Palette.light, "light")

    /** ink3's ratios on bg are quoted by number in Theme.swift's prose: a
     *  pin, both directions. */
    @Test
    fun ink3StandsWhereTheTextRuleQuotesIt() {
        assertRatio("ink3", "bg", 2.35, Palette.light, "light")
        assertRatio("ink3", "bg", 4.68, Palette.lightHighContrast, "light HC")
        assertRatio("ink3", "bg", 3.02, Palette.dark, "dark")
        assertRatio("ink3", "bg", 4.76, Palette.darkHighContrast, "dark HC")
    }

    @Test
    fun everyTokenResolvesToItsSpecValueInAllFourAppearances() {
        for (token in palette) {
            assertToken(token.name, token.light, Palette.light, "light")
            assertToken(token.name, token.lightHC, Palette.lightHighContrast, "light HC")
            assertToken(token.name, token.dark, Palette.dark, "dark")
            assertToken(token.name, token.darkHC, Palette.darkHighContrast, "dark HC")
        }
        // And the selector hands each appearance its own column.
        assertEquals(Palette.light, Palette.of(dark = false, highContrast = false))
        assertEquals(Palette.lightHighContrast, Palette.of(dark = false, highContrast = true))
        assertEquals(Palette.dark, Palette.of(dark = true, highContrast = false))
        assertEquals(Palette.darkHighContrast, Palette.of(dark = true, highContrast = true))
    }

    @Test
    fun darkPairsClearTheFloorsTheyWereChosenAgainst() = assertFloors(darkFloors, Palette.dark, "dark")

    @Test
    fun highContrastPairsClearTheSteppedUpFloorsInBothSchemes() {
        assertFloors(highContrastFloors, Palette.lightHighContrast, "light HC")
        assertFloors(highContrastFloors, Palette.darkHighContrast, "dark HC")
    }

    // MARK: - Resolution

    private fun resolved(name: String, p: Palette): Color = when (name) {
        "bg" -> p.bg
        "cardBG" -> p.cardBG
        "ink" -> p.ink
        "ink2" -> p.ink2
        "ink3" -> p.ink3
        "hairline" -> p.hairline
        "restFill" -> p.restFill
        "accent" -> p.accent
        "accentText" -> p.accentText
        "accentSoft" -> p.accentSoft
        else -> fail("no token named '$name' in the palette")
    }

    private fun assertToken(name: String, rgb: Long, p: Palette, scheme: String) {
        val c = resolved(name, p)
        assertEquals(1f, c.alpha, "every token in the palette is opaque")
        val accuracy = 0.5 / 255
        assertTrue(abs(c.red - ((rgb shr 16) and 0xFF) / 255.0) <= accuracy, "$name red, $scheme")
        assertTrue(abs(c.green - ((rgb shr 8) and 0xFF) / 255.0) <= accuracy, "$name green, $scheme")
        assertTrue(abs(c.blue - (rgb and 0xFF) / 255.0) <= accuracy, "$name blue, $scheme")
    }

    private fun assertRatio(ink: String, ground: String, ratio: Double, p: Palette, scheme: String) {
        val measured = contrast(resolved(ink, p), resolved(ground, p))
        assertEquals(ratio, measured, 0.01, "$ink on $ground moved in $scheme — Theme.swift quotes this number")
    }

    private fun assertFloors(floors: List<Floor>, p: Palette, scheme: String) {
        for (pair in floors) {
            val measured = contrast(resolved(pair.ink, p), resolved(pair.ground, p))
            assertTrue(measured >= pair.ratio, "${pair.ink} on ${pair.ground} is $measured:1 in $scheme")
        }
    }

    // MARK: - WCAG arithmetic

    private fun contrast(ink: Color, ground: Color): Double {
        val a = luminance(ink)
        val b = luminance(ground)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private fun luminance(c: Color): Double {
        fun linear(channel: Float): Double {
            val v = channel.toDouble()
            return if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }
}
