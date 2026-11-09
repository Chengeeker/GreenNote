package com.green.note.ui

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

internal data class FlutterFontMetrics(val ascent: Float, val descent: Float, val leading: Float = 0f)
internal data class FlutterLineMetrics(val ascent: Float, val descent: Float) {
    val height: Float get() = descent - ascent
}

/** Skia Run.cpp at Flutter's pinned 8df24be6: normalize each run, THEN union the line. */
internal fun unionFlutterRunMetrics(fonts: List<FlutterFontMetrics>, requestedHeight: Float): FlutterLineMetrics? {
    if (fonts.isEmpty() || !requestedHeight.isFinite() || requestedHeight <= 0f) return null
    var ascent = Float.POSITIVE_INFINITY
    var descent = Float.NEGATIVE_INFINITY
    for (font in fonts) {
        if (!font.ascent.isFinite() || !font.descent.isFinite() || !font.leading.isFinite() || font.descent <= font.ascent) return null
        val a = font.ascent - font.leading / 2f
        val d = font.descent + font.leading / 2f
        val extra = (requestedHeight - (d - a)) / 2f
        ascent = minOf(ascent, a - extra)
        descent = maxOf(descent, d + extra)
    }
    return FlutterLineMetrics(ascent, descent)
}

internal data class ArticleLineMetrics(val target: FlutterLineMetrics, val rawAscent: Int, val rawDescent: Int)
internal data class ArticleLineAdjustment(val height: Int, val topRatio: Float)
internal data class ArticleLinePositions(val height: Float, val baselines: List<Float>)

/** Skia rounds paragraph-local (logical), not raster (physical) coordinates. */
internal fun flutterArticleLinePositions(lines: List<FlutterLineMetrics>, density: Float): ArticleLinePositions? {
    if (lines.isEmpty() || !density.isFinite() || density <= 0f) return null
    var top = 0f
    val baselines = ArrayList<Float>(lines.size)
    for (line in lines) {
        if (!line.height.isFinite() || !line.ascent.isFinite() || line.height <= 0f) return null
        val height = floor(line.height / density + .5f) * density
        if (height <= 0f) return null
        baselines += top + floor(-line.ascent / density + .5f) * density
        top += height
    }
    return ArticleLinePositions(top, baselines)
}

internal fun articleRangeIntersects(start: Int, end: Int, annotation: IntRange): Boolean =
    start < end && !annotation.isEmpty() && annotation.first < end && annotation.last >= start

/** Only a single unchanged paragraph style is allowed; unrepresentable lines retain native layout. */
internal fun commonArticleLineAdjustment(lines: List<ArticleLineMetrics>, density: Float = 1f): ArticleLineAdjustment? {
    val first = lines.firstOrNull() ?: return null
    if (lines.any { abs(it.target.ascent - first.target.ascent) > .001f ||
            abs(it.target.descent - first.target.descent) > .001f ||
            it.rawAscent != first.rawAscent || it.rawDescent != first.rawDescent }) return null
    if (!first.target.height.isFinite() || !first.target.descent.isFinite()) return null
    val position = flutterArticleLinePositions(listOf(first.target), density) ?: return null
    val height = position.height.roundToInt()
    val baseline = position.baselines.single().roundToInt()
    // Android's LineHeightSpan has integer metrics. Do not approximate fractional raster baselines.
    if (abs(height - position.height) > .001f || abs(baseline - position.baselines.single()) > .001f) return null
    val rawHeight = first.rawDescent - first.rawAscent
    if (height <= 0 || rawHeight <= 0) return null
    val difference = height - rawHeight
    val desiredDescent = height - baseline
    val descentDifference = desiredDescent - first.rawDescent
    if (descentDifference !in minOf(0, difference)..maxOf(0, difference)) return null
    val ratio = when {
        difference == 0 -> .5f
        descentDifference == 0 -> if (difference > 0) 1f else 0f
        difference > 0 -> 1f - (descentDifference - .5f) / difference
        else -> (descentDifference - .5f) / difference
    }.coerceIn(0f, 1f)
    // Match Compose 1.9.2 LineHeightStyleSpan's integer rounding, not a guessed alignment.
    val computedDescent = first.rawDescent + ceil(if (difference <= 0) difference * ratio else difference * (1f - ratio)).toInt()
    if (computedDescent != desiredDescent) return null
    return ArticleLineAdjustment(height, ratio)
}
