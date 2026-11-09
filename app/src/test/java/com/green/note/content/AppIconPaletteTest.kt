package com.green.note.content

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class AppIconPaletteTest {
    @Test fun pixelsMatchPinnedDartQuantizationScoringAndFidelityPalette() {
        val fixtures = JSONArray(requireNotNull(javaClass.getResourceAsStream("/app-icon-palette-fixtures.json"))
            .bufferedReader().use { it.readText() })
        val names = (0 until fixtures.length()).map { fixtures.getJSONObject(it).getString("name") }
        assertTrue(names.contains("public-deepseek-flutter-nearest112"))
        assertTrue(names.contains("public-deepseek-original-accept-webp"))
        for (index in 0 until fixtures.length()) {
            val fixture = fixtures.getJSONObject(index)
            val runs = fixture.getJSONArray("rgbaRuns")
            val pixels = ArrayList<Int>()
            for (i in 0 until runs.length()) {
                val run = runs.getJSONArray(i)
                repeat(run.getInt(1)) { pixels += run.getLong(0).toInt() }
            }
            val actual = appIconPaletteColors(pixels.toIntArray())
            val name = fixture.getString("name")
            val wu = fixture.getJSONArray("wu")
            assertEquals("$name ordered Wu centroids", (0 until wu.length()).map { wu.getLong(it).toInt() }, flutterIconWu(pixels.toIntArray()))
            assertEquals("$name seed", fixture.getLong("seed").toInt(), actual.seed)
            assertEquals("$name primary", fixture.getLong("primary").toInt(), actual.primary)
            assertEquals("$name onPrimary", fixture.getLong("onPrimary").toInt(), actual.onPrimary)
        }
    }

    @Test fun samplingUses112MaximumWithoutUpscalingOrStretching() {
        assertEquals(AppIconSampleSize(112f, 112f), appIconSampleSize(256, 256))
        assertEquals(AppIconSampleSize(48f, 32f), appIconSampleSize(48, 32))
        val landscape = appIconSampleSize(225, 113)
        assertEquals(112f, landscape.width, .0001f)
        assertEquals(56.24889f, landscape.height, .0001f)
        assertEquals(56, landscape.height.toInt()) // Picture.toImage truncates, paint rect stays fractional.
        assertEquals(AppIconSampleSize(56f, 112f), appIconSampleSize(128, 256))
        assertEquals(0, appIconSampleSize(1, 1000).width.toInt()) // Original invalid raster falls back; no invented 1px image.
    }

    @Test fun rawRgbaConversionPreservesAlphaAndSwapsOnlyRedAndBlue() {
        assertEquals(0x40332211, swapIconRedBlue(0x40112233))
        assertEquals(0xff123456.toInt(), swapIconRedBlue(swapIconRedBlue(0xff123456.toInt())))
    }

    @Test(expected = IllegalArgumentException::class)
    fun paletteRejectsUnboundedFullImagePixelInput() { appIconPaletteColors(IntArray(112 * 112 + 1)) }
}
