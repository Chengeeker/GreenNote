package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class FlutterLineMetricsTest {
    // Explicit synthetic metrics, not claimed to be measurements from a particular device font.
    private val latin = FlutterFontMetrics(-45f, 12f)
    private val cjk = FlutterFontMetrics(-56f, 14f)

    @Test fun appDetailMixedLabelsHaveTheirOwnLineHeightsWithoutExpandingPureLabels() {
        fun fonts(size: Float) = listOf(FlutterFontMetrics(-.9375f * size, .25f * size),
            FlutterFontMetrics(-7f / 6f * size, 7f / 24f * size))
        fun height(fonts: List<FlutterFontMetrics>, requested: Float) =
            flutterArticleLinePositions(listOf(unionFlutterRunMetrics(fonts, requested)!!), 3f)!!.height
        assertEquals(78f, height(fonts(48f), 48f * 1.5f), .001f)
        assertEquals(72f, height(fonts(48f).take(1), 48f * 1.5f), .001f)
        assertEquals(51f, height(fonts(33f), 33f * 1.45f), .001f)
        assertEquals(48f, height(fonts(33f).take(1), 33f * 1.45f), .001f)
        assertEquals(48f, height(fonts(33f).takeLast(1), 33f * 1.45f), .001f)
    }

    @Test fun explicitQuoteHeightIsNotClampedToTheFontsLargerIntrinsicBox() {
        val target = unionFlutterRunMetrics(listOf(FlutterFontMetrics(-78f, 22f)), 28f * 3 * .9f)!!
        val result = flutterArticleLinePositions(listOf(target), 3f)!!
        assertEquals(75f, result.height, .001f)
        assertEquals(66f, result.baselines.single(), .001f)
    }

    @Test fun headerNameAndMetadataNormalizeTheirOwnFontSizeBeforeLogicalRounding() {
        // Synthetic scalable fallback fonts. This checks the header's inherited 1.43 height,
        // not hard-coded 66/54-pixel measurements from a screenshot.
        fun target(size: Float): FlutterLineMetrics = unionFlutterRunMetrics(listOf(
            FlutterFontMetrics(-.9375f * size, .25f * size),
            FlutterFontMetrics(-7f / 6f * size, 7f / 24f * size),
        ), size * 1.43f)!!
        val name = flutterArticleLinePositions(listOf(target(14.5f * 3)), 3f)!!
        val metadata = flutterArticleLinePositions(listOf(target(11.5f * 3)), 3f)!!
        assertEquals(66f, name.height, .001f)
        assertEquals(54f, metadata.height, .001f)
        assertEquals(51f, name.baselines.single(), .001f)
        assertEquals(39f, metadata.baselines.single(), .001f)
        // An expanded line can still require a smaller ascent: an Alignment-only fix cannot do it.
        assertNull(commonArticleLineAdjustment(listOf(ArticleLineMetrics(target(34.5f), -40, 10)), 3f))
    }

    @Test fun skiaRoundsLogicalHeightAndPaintBaselineBeforeRasterScaling() {
        // Height 24.6 logical -> 25, baseline 18.6 logical -> 19; not 74 / 56 raster.
        val positions = flutterArticleLinePositions(listOf(FlutterLineMetrics(-55.8f, 18f)), 3f)!!
        assertEquals(75f, positions.height, .001f)
        assertEquals(57f, positions.baselines.single(), .001f)
        val line = ArticleLineMetrics(FlutterLineMetrics(-55.8f, 18f), -56, 14)
        val style = commonArticleLineAdjustment(listOf(line, line, line), 3f)!!
        assertEquals(75, style.height)
        assertEquals(.3f, style.topRatio, .001f)
    }

    @Test fun mixedFirstTitleLineAndChineseSecondLineKeepSeparateBaselinesAndAccumulateRoundedHeights() {
        val mixed = unionFlutterRunMetrics(listOf(latin, cjk), 64.8f)!!
        val chinese = unionFlutterRunMetrics(listOf(cjk), 64.8f)!!
        val result = flutterArticleLinePositions(listOf(mixed, chinese), 3f)!!
        assertEquals(135f, result.height, .001f) // 23 + 22 logical pixels.
        assertEquals(listOf(54f, 123f), result.baselines)
        assertNull(commonArticleLineAdjustment(listOf(
            ArticleLineMetrics(mixed, -56, 14), ArticleLineMetrics(chinese, -56, 14)), 3f))
    }

    @Test fun rasterFractionalPositionsAreKeptForDrawingButNotMisrepresentedByIntegerStyle() {
        val metrics = FlutterLineMetrics(-18.6f * 2.625f, 6f * 2.625f)
        val result = flutterArticleLinePositions(listOf(metrics, metrics), 2.625f)!!
        assertEquals(131.25f, result.height, .001f)
        assertEquals(listOf(49.875f, 115.5f), result.baselines)
        assertNull(commonArticleLineAdjustment(listOf(ArticleLineMetrics(metrics, -49, 16)), 2.625f))
    }

    @Test fun lineRoundingUsesPositiveHalfUpAndRejectsInvalidDensity() {
        assertEquals(25f, flutterArticleLinePositions(listOf(FlutterLineMetrics(-18.5f, 6f)), 1f)!!.height, .001f)
        assertEquals(19f, flutterArticleLinePositions(listOf(FlutterLineMetrics(-18.5f, 6f)), 1f)!!.baselines.single(), .001f)
        assertNull(flutterArticleLinePositions(emptyList(), 3f))
        assertNull(flutterArticleLinePositions(listOf(FlutterLineMetrics(-10f, 2f)), 0f))
        assertNull(flutterArticleLinePositions(listOf(FlutterLineMetrics(-10f, 2f)), Float.NaN))
    }

    @Test fun hiddenTailAnnotationsDoNotDisableVisibleLineMetrics() {
        assertFalse(articleRangeIntersects(0, 30, 30 until 40))
        assertFalse(articleRangeIntersects(0, 30, 50 until 60))
        assertTrue(articleRangeIntersects(0, 30, 29 until 40))
        assertTrue(articleRangeIntersects(30, 60, 20 until 31))
        assertFalse(articleRangeIntersects(30, 60, 20 until 30))
        assertFalse(articleRangeIntersects(30, 30, 20 until 40))
        assertFalse(articleRangeIntersects(0, 30, 20 until 20))
    }

    @Test fun singleFontChineseAndLatinPreserveRequestedHeightButHaveDifferentBaselines() {
        val chinese = unionFlutterRunMetrics(listOf(cjk), 70f)!!
        val english = unionFlutterRunMetrics(listOf(latin), 70f)!!
        assertEquals(70f, chinese.height, .001f)
        assertEquals(70f, english.height, .001f)
        assertEquals(-56f, chinese.ascent, .001f)
        assertEquals(-51.5f, english.ascent, .001f)
    }

    @Test fun chineseAndLatinUnionOccursAfterNormalizingEachFont() {
        val result = unionFlutterRunMetrics(listOf(latin, cjk), 70f)!!
        assertEquals(-56f, result.ascent, .001f)
        assertEquals(18.5f, result.descent, .001f)
        assertEquals(74.5f, result.height, .001f)
        // Normalizing the raw union would incorrectly give 70, losing 4.5 pixels.
        assertNotEquals(70f, result.height, .001f)
    }

    @Test fun leadingCancelsUnderEvenDistributionAndMixedDirectionIsOrderIndependent() {
        val expected = unionFlutterRunMetrics(listOf(latin, cjk), 70f)
        assertEquals(expected, unionFlutterRunMetrics(listOf(cjk.copy(leading = 6f), latin.copy(leading = 3f)), 70f))
        assertEquals(expected, unionFlutterRunMetrics(listOf(cjk, latin, cjk), 70f))
    }

    @Test fun whitespaceUsesItsActualFontWhileAnEmptyOrInvalidRunDoesNotInventMetrics() {
        assertEquals(unionFlutterRunMetrics(listOf(latin), 70f), unionFlutterRunMetrics(listOf(latin, latin), 70f))
        assertNull(unionFlutterRunMetrics(emptyList(), 70f))
        assertNull(unionFlutterRunMetrics(listOf(latin), Float.NaN))
        assertNull(unionFlutterRunMetrics(listOf(FlutterFontMetrics(1f, 0f)), 70f))
    }

    @Test fun commonMixedLinesProduceAnExactlyRepresentableComposeAdjustment() {
        val metrics = ArticleLineMetrics(unionFlutterRunMetrics(listOf(latin, cjk), 70f)!!, -56, 14)
        val adjustment = commonArticleLineAdjustment(listOf(metrics, metrics, metrics))!!
        assertEquals(75, adjustment.height)
        assertEquals(.1f, adjustment.topRatio, .001f)
    }

    @Test fun differentLineFontsAndUnrepresentableBaselineKeepExistingLayout() {
        val mixed = ArticleLineMetrics(unionFlutterRunMetrics(listOf(latin, cjk), 70f)!!, -56, 14)
        val chinese = ArticleLineMetrics(unionFlutterRunMetrics(listOf(cjk), 70f)!!, -56, 14)
        assertNull(commonArticleLineAdjustment(listOf(mixed, chinese)))
        // Same height but a translated baseline cannot be encoded by LineHeightStyle.Alignment.
        assertNull(commonArticleLineAdjustment(listOf(ArticleLineMetrics(FlutterLineMetrics(-54f, 16f), -56, 14))))
        assertNull(commonArticleLineAdjustment(emptyList()))
    }

    @Test fun shrinkingHeightOnlyAppliesWhenDesiredBaselineFitsTheOriginalLineBox() {
        assertNotNull(commonArticleLineAdjustment(listOf(ArticleLineMetrics(FlutterLineMetrics(-52f, 13f), -56, 14))))
        assertNull(commonArticleLineAdjustment(listOf(ArticleLineMetrics(FlutterLineMetrics(-49f, 16f), -56, 14))))
    }
}
