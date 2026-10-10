//
//  The widget picker's preview on Android 12–14 (layout/widget_preview.xml)
//  is inflated by the launcher without app code, so its colours are
//  resources, not the palette. No Swift twin (iOS's gallery draws the widget
//  itself). This holds the two copies together: a palette token moved in
//  Theme.kt and not here would show the picker a widget the home screen
//  never draws.
//

package com.dredfit

import com.dredfit.ui.theme.Palette
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.test.Test
import kotlin.test.assertEquals

class WidgetPreviewTest {

    private val res: Path = Paths.get("src/main/res")

    private fun colors(folder: String): Map<String, Int> {
        val xml = Files.readString(res.resolve("$folder/widget_preview_colors.xml"))
        return Regex("""<color name="(\w+)">#([0-9A-Fa-f]{8})</color>""").findAll(xml)
            .associate { it.groupValues[1] to it.groupValues[2].toLong(16).toInt() }
    }

    private fun assertMatches(folder: String, palette: Palette) {
        val expected = mapOf("widget_preview_bg" to palette.bg, "widget_preview_ink" to palette.ink,
                             "widget_preview_ink2" to palette.ink2, "widget_preview_accent" to palette.accent)
            .mapValues { (_, c: Color) -> c.toArgb() }
        assertEquals(expected, colors(folder), "$folder against the palette")
    }

    @Test
    fun thePreviewsColoursAreThePalettes() {
        assertMatches("values", Palette.light)
        assertMatches("values-night", Palette.dark)
    }
}
