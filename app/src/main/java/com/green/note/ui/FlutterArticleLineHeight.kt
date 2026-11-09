package com.green.note.ui

import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.text.TextRunShaper
import android.os.Build
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import androidx.annotation.RequiresApi
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontSynthesis
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.constrainHeight
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.Bidi
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.roundToInt

internal data class FlutterArticleStyle(
    val style: TextStyle,
    val onTextLayout: (TextLayoutResult) -> Unit,
    val modifier: Modifier = Modifier,
)
private data class ArticleLineRange(val start: Int, val end: Int, val rtl: Boolean, val ellipsis: Boolean)
private data class ArticleLayoutKey(val width: Int, val lines: List<ArticleLineRange>)
private data class StaticArticleMeasureKey(
    val lines: List<Pair<String, Boolean>>, val typeface: Typeface, val size: Float, val height: Float,
    val localeTag: String?, val features: String?,
)
// Static labels recur in recycled feed cards. Bound retained text to 128 * (1000 chars + 3 ellipses).
// Only the worker path accesses this map; no shaping or cache lock is taken by draw/scroll.
private val staticArticleMeasurements = object : LinkedHashMap<StaticArticleMeasureKey, List<ArticleLineMetrics>>(128, .75f, true) {
    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<StaticArticleMeasureKey, List<ArticleLineMetrics>>?): Boolean = size > 128
}

/** Bounded article previews/static labels. Does not rewrite text, links, placeholders or line breaks. */
@Composable
internal fun rememberFlutterArticleStyle(
    text: AnnotatedString,
    style: TextStyle,
    enabled: Boolean = true,
    hasInlineContent: Boolean = false,
    inlineContentRanges: List<IntRange> = emptyList(),
    plainTitle: Boolean = false,
): FlutterArticleStyle {
    val density = LocalDensity.current
    val resolver = LocalFontFamilyResolver.current
    val typeface = resolver.resolve(style.fontFamily, style.fontWeight ?: FontWeight.Normal,
        style.fontStyle ?: FontStyle.Normal, style.fontSynthesis ?: FontSynthesis.All).value as? Typeface
    val plainTitleSupported = remember(text, plainTitle) {
        !plainTitle || (text.spanStyles.isEmpty() && text.paragraphStyles.isEmpty() &&
            !Bidi.requiresBidi(text.text.toCharArray(), 0, text.length))
    }
    val eligible = enabled && plainTitleSupported && Build.VERSION.SDK_INT >= 31 && !hasInlineContent && text.length in 1..1000 &&
        style.fontSize.isSp && style.lineHeight.isSpecified && typeface != null && style.textGeometricTransform == null
    val unsupportedRanges = remember(text, inlineContentRanges) {
        inlineContentRanges + text.paragraphStyles.map { it.start until it.end } + text.spanStyles.filter {
            val s = it.item
            s.fontSize.isSpecified || s.fontFamily != null || s.fontWeight != null || s.fontStyle != null ||
                s.fontSynthesis != null || s.baselineShift != null || s.textGeometricTransform != null ||
                s.fontFeatureSettings != null || s.localeList != null
        }.map { it.start until it.end }
    }
    var layout by remember(text, style, density, typeface, eligible, unsupportedRanges) { mutableStateOf<ArticleLayoutKey?>(null) }
    var adjustment by remember(text, style, density, typeface, eligible, unsupportedRanges) { mutableStateOf<Pair<ArticleLayoutKey, List<ArticleLineMetrics>>?>(null) }
    var originalLayout by remember(text, style, density, typeface, eligible) { mutableStateOf<TextLayoutResult?>(null) }
    val sizePx = if (style.fontSize.isSp) with(density) { style.fontSize.toPx() } else 0f
    val heightPx = when {
        style.lineHeight.isEm -> style.lineHeight.value * sizePx
        style.lineHeight.isSp -> with(density) { style.lineHeight.toPx() }
        else -> 0f
    }
    val localeTag = style.localeList?.let { if (it.size > 0) it[0].toLanguageTag() else null }
    LaunchedEffect(text, style, density, typeface, eligible, unsupportedRanges, layout) {
        val key = layout ?: return@LaunchedEffect
        if (!eligible || typeface == null || Build.VERSION.SDK_INT < 31) return@LaunchedEffect
        // Hidden ellipsized tail annotations must not disable otherwise supported visible lines.
        if (key.lines.any { line -> unsupportedRanges.any { articleRangeIntersects(line.start, line.end, it) } }) {
            adjustment = null
            return@LaunchedEffect
        }
        val computed = withContext(Dispatchers.Default) {
            measureArticleLines(text.text, key.lines, typeface, sizePx, heightPx, localeTag, style.fontFeatureSettings, cacheStatic = plainTitle)
        }
        adjustment = computed?.let { key to it }
    }
    val measuredLines = adjustment?.takeIf { it.first == layout }?.second
    val result = if (plainTitle) null else measuredLines?.let { commonArticleLineAdjustment(it, density.density) }
    val resolved = if (result == null) style else style.copy(
        lineHeight = with(density) { result.height.toFloat().toSp() },
        lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment(result.topRatio), LineHeightStyle.Trim.None),
    )
    val positions = if (plainTitle) measuredLines?.let {
        flutterArticleLinePositions(it.map(ArticleLineMetrics::target), density.density)
    } else null
    val original = originalLayout
    val titleModifier = if (positions == null || original == null || positions.baselines.size != original.lineCount) Modifier else {
        Modifier.layout { measurable, constraints ->
            val child = measurable.measure(constraints)
            layout(child.width, constraints.constrainHeight(ceil(positions.height).toInt()), mapOf(
                FirstBaseline to positions.baselines.first().roundToInt(),
                LastBaseline to positions.baselines.last().roundToInt(),
            )) { child.placeRelative(0, 0) }
        }.drawWithContent {
            // Draw the original single Text paragraph. Only its line-local vertical origin changes;
            // shaping, character offsets, soft wrapping, ellipsis and semantics remain untouched.
            for (index in positions.baselines.indices) {
                val dy = positions.baselines[index] - original.getLineBaseline(index)
                withTransform({
                    translate(top = dy)
                    clipRect(top = original.getLineTop(index), bottom = original.getLineBottom(index))
                }) { this@drawWithContent.drawContent() }
            }
        }
    }
    return FlutterArticleStyle(resolved, onTextLayout = { measured ->
        if (eligible && measured.lineCount in 1..3) {
            val key = ArticleLayoutKey(measured.layoutInput.constraints.maxWidth,
                List(measured.lineCount) { index ->
                    val start = measured.getLineStart(index)
                    val ellipsis = measured.isLineEllipsized(index)
                    var end = measured.getLineEnd(index, visibleEnd = ellipsis)
                    while (end > start && (text[end - 1] == '\n' || text[end - 1] == '\r')) end--
                    ArticleLineRange(start, end,
                        measured.getParagraphDirection(start) == androidx.compose.ui.text.style.ResolvedTextDirection.Rtl,
                        ellipsis)
                })
            // Corrected vertical metrics must not trigger repeated shaping or a layout feedback loop.
            if (layout != key) layout = key
            if (plainTitle && originalLayout != measured) originalLayout = measured
        }
    }, modifier = titleModifier)
}

@RequiresApi(31)
private fun measureArticleLines(
    text: String, lines: List<ArticleLineRange>, typeface: Typeface,
    size: Float, height: Float, localeTag: String?, features: String?, cacheStatic: Boolean,
): List<ArticleLineMetrics>? {
    // Key the real displayed runs, including ellipsis, rather than card IDs or width alone.
    val visibleLines = lines.map { line ->
        (text.substring(line.start, line.end) + if (line.ellipsis) "\u2026" else "") to line.rtl
    }
    val cacheKey = if (cacheStatic) StaticArticleMeasureKey(visibleLines, typeface, size, height, localeTag, features) else null
    if (cacheKey != null) synchronized(staticArticleMeasurements) { staticArticleMeasurements[cacheKey] }?.let { return it }
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        this.typeface = typeface
        textSize = size
        if (localeTag != null) textLocale = Locale.forLanguageTag(localeTag)
        fontFeatureSettings = features
    }
    val measured = ArrayList<ArticleLineMetrics>(lines.size)
    for ((visible, rtl) in visibleLines) {
        // Shape the displayed suffix too. Never include hidden tail fonts in an ellipsized line.
        if (visible.isBlank()) return null
        val metrics = shapeFlutterLineMetrics(visible, paint, height, rtl) ?: return null
        val raw = StaticLayout.Builder.obtain(visible, 0, visible.length, paint, 1_000_000)
            .setIncludePad(false).setUseLineSpacingFromFallbacks(true)
            .setTextDirection(if (rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR)
            .build()
        measured += ArticleLineMetrics(metrics, raw.getLineAscent(0), raw.getLineDescent(0))
    }
    if (cacheKey != null) synchronized(staticArticleMeasurements) { staticArticleMeasurements[cacheKey] = measured }
    return measured
}

/** Caller owns Paint and dispatch; never call in draw/scroll. API 24–30 retain their existing layout. */
@RequiresApi(31)
internal fun shapeFlutterLineMetrics(text: String, paint: Paint, requestedHeightPx: Float, isRtl: Boolean = false): FlutterLineMetrics? {
    if (text.isEmpty()) return null
    val bidi = Bidi(text, if (isRtl) Bidi.DIRECTION_RIGHT_TO_LEFT else Bidi.DIRECTION_LEFT_TO_RIGHT)
    val fonts = LinkedHashSet<Font>()
    for (run in 0 until bidi.runCount) {
        val start = bidi.getRunStart(run)
        val end = bidi.getRunLimit(run)
        val glyphs = TextRunShaper.shapeTextRun(text, start, end - start, 0, text.length,
            0f, 0f, bidi.getRunLevel(run) % 2 != 0, paint)
        for (i in 0 until glyphs.glyphCount()) fonts += glyphs.getFont(i)
    }
    return unionFlutterRunMetrics(fonts.map { font ->
        val raw = Paint.FontMetrics()
        font.getMetrics(paint, raw)
        FlutterFontMetrics(raw.ascent, raw.descent, raw.leading)
    }, requestedHeightPx)
}
