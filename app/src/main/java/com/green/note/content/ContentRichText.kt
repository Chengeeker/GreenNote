package com.green.note.content

import android.text.Html
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.text.style.UnderlineSpan
import android.text.style.URLSpan
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.MaterialTheme
import com.green.note.ui.ReviewText as Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

internal data class ParsedContentText(
    val plain: String,
    val anchors: List<Triple<Int, Int, String>> = emptyList(),
    val styles: List<AnnotatedString.Range<SpanStyle>> = emptyList(),
)

// shortcut: inline styling only, use a CommonMark parser if block or nested syntax becomes a publishing format.
private val inlineMarkup = Regex("""https?://[^\s<>"']+|\\([\\*_~`])|(`+)([^`\r\n]+)\2|(?:(?<![A-Za-z0-9_])(___|__|_)(?!_)|(?<!\*)(\*\*\*|\*\*|\*)(?!\*)|(?<!~)(~~)(?!~))(?=\S)([^\r\n]+?)(?<=\S)(?<!\\)(?:\4(?![A-Za-z0-9_])|\5(?!\*)|\6(?!~))""")
private val boldStyle = SpanStyle(fontWeight = FontWeight.Bold)
private val italicStyle = SpanStyle(fontStyle = FontStyle.Italic)
private val codeStyle = SpanStyle(fontFamily = FontFamily.Monospace)
private val strikeStyle = SpanStyle(textDecoration = TextDecoration.LineThrough)

internal fun renderInlineMarkup(content: ParsedContentText): ParsedContentText {
    val matches = inlineMarkup.findAll(content.plain).filter { match ->
        match.groups[1] != null || match.groups[3] != null || match.groups[7] != null
    }.iterator()
    if (!matches.hasNext()) return content
    val result = StringBuilder(content.plain.length)
    val offsets = IntArray(content.plain.length + 1)
    val styles = mutableListOf<AnnotatedString.Range<SpanStyle>>()
    var cursor = 0
    fun copyUntil(end: Int, visible: Boolean) {
        while (cursor < end) {
            offsets[cursor] = result.length
            if (visible) result.append(content.plain[cursor])
            cursor++
        }
    }
    while (matches.hasNext()) {
        val match = matches.next()
        val label = match.groups[1] ?: match.groups[3] ?: match.groups[7]!!
        val marker = match.groups[4]?.value ?: match.groups[5]?.value
        val style = when {
            match.groups[1] != null -> null
            match.groups[3] != null -> codeStyle
            match.groups[6] != null -> strikeStyle
            marker?.length == 3 -> boldStyle.merge(italicStyle)
            marker?.length == 2 -> boldStyle
            else -> italicStyle
        }
        copyUntil(match.range.first, true)
        copyUntil(label.range.first, false)
        val start = result.length
        copyUntil(label.range.last + 1, true)
        style?.let { styles += AnnotatedString.Range(it, start, result.length) }
        copyUntil(match.range.last + 1, false)
    }
    copyUntil(content.plain.length, true)
    offsets[cursor] = result.length
    fun mapped(index: Int) = offsets[index.coerceIn(0, content.plain.length)]
    return ParsedContentText(
        result.toString(),
        content.anchors.map { (start, end, url) -> Triple(mapped(start), mapped(end), url) },
        content.styles.map { AnnotatedString.Range(it.item, mapped(it.start), mapped(it.end)) } + styles,
    )
}
private val contentTextCache = LinkedHashMap<String, ParsedContentText>()
private var contentTextCacheCharacters = 0
fun clearContentTextCache() = synchronized(contentTextCache) { contentTextCache.clear(); contentTextCacheCharacters = 0 }
internal fun parseContentText(value: String): ParsedContentText = synchronized(contentTextCache) {
    contentTextCache[value]?.let { return@synchronized it }
    val parsed = renderInlineMarkup(if (!value.contains('<') && !value.contains('&')) ParsedContentText(value.trimEnd()) else {
        val clean = value.replace(Regex("<script[^>]*>[\\s\\S]*?</script>|<style[^>]*>[\\s\\S]*?</style>", RegexOption.IGNORE_CASE), "")
            .replace(Regex("<br\\s*/?>|</?p[^>]*>", RegexOption.IGNORE_CASE), "\n")
            .replace(Regex("<img[^>]*alt=[\"'](\\[[^\\]]+\\])[\"'][^>]*>", RegexOption.IGNORE_CASE)) { it.groupValues[1] }
            .replace(Regex("<(?!/?(?:a|b|strong|i|em|del|s|strike|tt|code|u)\\b)[^>]+>", RegexOption.IGNORE_CASE), "")
            .replace(Regex("<(/?)code\\b[^>]*>", RegexOption.IGNORE_CASE), "<$1tt>")
        val spanned = Html.fromHtml(clean.replace("\n", "<br>"), Html.FROM_HTML_MODE_COMPACT)
        val plain = spanned.toString().trimEnd()
        val spans = spanned.getSpans(0, spanned.length, Any::class.java)
        ParsedContentText(plain, spans.filterIsInstance<URLSpan>().map { Triple(spanned.getSpanStart(it), spanned.getSpanEnd(it), it.url) },
            spans.mapNotNull { span ->
                val style = when (span) {
                    is StyleSpan -> when (span.style) {
                        android.graphics.Typeface.BOLD -> boldStyle
                        android.graphics.Typeface.ITALIC -> italicStyle
                        android.graphics.Typeface.BOLD_ITALIC -> boldStyle.merge(italicStyle)
                        else -> null
                    }
                    is StrikethroughSpan -> strikeStyle
                    is TypefaceSpan -> codeStyle
                    is UnderlineSpan -> SpanStyle(textDecoration = TextDecoration.Underline)
                    else -> null
                } ?: return@mapNotNull null
                val start = spanned.getSpanStart(span)
                val end = spanned.getSpanEnd(span).coerceAtMost(plain.length)
                if (start < end) AnnotatedString.Range(style, start, end) else null
            })
    })
    if (value.length <= 16_384) {
        while (contentTextCache.isNotEmpty() && (contentTextCache.size >= 500 || contentTextCacheCharacters + value.length + parsed.plain.length > 1_000_000)) {
            val oldest = contentTextCache.entries.first(); contentTextCacheCharacters -= oldest.key.length + oldest.value.plain.length; contentTextCache.remove(oldest.key)
        }
        contentTextCache[value] = parsed; contentTextCacheCharacters += value.length + parsed.plain.length
    }
    parsed
}

internal fun contentEmojiCode(name: String): String? {
    val clean = name.removePrefix("[").removeSuffix("]")
    return contentEmojiCodes.optString(clean).ifEmpty { contentEmojiCodes.optString(clean.lowercase()) }.takeIf(String::isNotEmpty)
        ?: clean.removePrefix("c-").toIntOrNull()?.takeIf { it in 1..100 }?.let { "c-$it" }
}

@Composable
internal fun ContentEmotion(name: String, modifier: Modifier = Modifier, fontSize: TextUnit = 24.sp) {
    val code = contentEmojiCode(name)
    var source by remember(code) { mutableIntStateOf(0) }
    val bases = listOf("https://coolemotion.netlify.app/source/png/", "https://cdn.jsdelivr.net/gh/Coolapk-Dev/Coolapk-Emotion/source/png/", "https://fastly.jsdelivr.net/gh/Coolapk-Dev/Coolapk-Emotion/source/png/")
    Box(modifier, contentAlignment = Alignment.Center) {
        if (code == null || source >= bases.size) Text(contentUnicodeEmojiFallback.optString(name).ifEmpty { "[$name]" }, fontSize = fontSize)
        else AsyncImage(bases[source] + code + ".png", "[$name]", Modifier.fillMaxSize(), contentScale = ContentScale.Fit, onError = { source++ })
    }
}

@Composable
internal fun ContentRichText(value: String, maxLines: Int = Int.MAX_VALUE, secondary: Boolean = false, onLink: (String) -> Unit,
    fontSize: TextUnit = 16.sp, lineHeight: TextUnit = 23.2.sp, textAlign: TextAlign = TextAlign.Start, prefix: AnnotatedString? = null,
    color: androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color.Unspecified,
    maxCharacters: Int? = null, suffix: AnnotatedString? = null, letterSpacing: TextUnit = 0.sp, prefixInline: Map<String, InlineTextContent> = emptyMap(),
    linkColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.primary, flutterArticleMetrics: Boolean = false) {
    val colors = MaterialTheme.colorScheme
    val navigate by rememberUpdatedState(onLink)
    val rendered = remember(value, prefix, linkColor, fontSize, maxCharacters, suffix) {
        val parsed = parseContentText(value)
        val fullPlain = parsed.plain
        val limit = maxCharacters?.coerceIn(0, fullPlain.length) ?: fullPlain.length
        val end = if (limit > 0 && limit < fullPlain.length && Character.isHighSurrogate(fullPlain[limit - 1])) limit - 1 else limit
        val plain = fullPlain.take(end)
        val anchors = parsed.anchors.map { Triple(it.first, it.second.coerceAtMost(plain.length), it.third) }.associateBy { it.first }
        val regex = Regex("\\[([^]\\n]+)]|#[^#\\n\\r\\t]+#|https?://[^\\s<>\"']+|@[a-zA-Z0-9_-]+|@[\\u4e00-\\u9fa5]{2,12}(?=[\\s:：，。、！？/,\\.!?#@\\n\\r]|$)")
        val code = parsed.styles.filter { it.item.fontFamily == FontFamily.Monospace }
        val tokens = regex.findAll(plain).filter { token -> code.none { token.range.first < it.end && token.range.last >= it.start } }.associateBy { it.range.first }
        val images = linkedMapOf<String, String>()
        val text = buildAnnotatedString {
            prefix?.let(::append)
            val start = length
            var position = 0
            fun link(label: String, url: String) {
                withLink(LinkAnnotation.Clickable(url, TextLinkStyles(style = SpanStyle(color = linkColor)), LinkInteractionListener { navigate(url) })) { append(label) }
            }
            while (position < plain.length) {
                val anchor = anchors[position]
                if (anchor != null && anchor.second > position) { link(plain.substring(position, anchor.second), anchor.third); position = anchor.second; continue }
                val token = tokens[position]
                if (token == null) { append(plain[position]); position++; continue }
                val display = token.value
                when {
                    display.startsWith('[') && contentEmojiCode(display) != null -> {
                        val key = "emoji:${images.size}"; images[key] = display.removePrefix("[").removeSuffix("]"); appendInlineContent(key, display)
                    }
                    display.startsWith('#') -> link(display, "/t/${android.net.Uri.encode(display.trim('#'))}")
                    display.startsWith('@') -> link(display, "/u/${android.net.Uri.encode(display.removePrefix("@"))}")
                    display.startsWith("http") -> link(display, display)
                    else -> append(display)
                }
                position = token.range.last + 1
            }
            // Inline emoji use their original spelling as alternate text, preserving offsets.
            parsed.styles.forEach { range ->
                val styleEnd = range.end.coerceAtMost(plain.length)
                if (range.start < styleEnd) addStyle(range.item, start + range.start, start + styleEnd)
            }
            suffix?.let(::append)
        }
        text to images
    }
    val inline = rendered.second.mapValues { (_, name) -> InlineTextContent(Placeholder(fontSize * 1.25f, fontSize * 1.25f, PlaceholderVerticalAlign.TextCenter)) { ContentEmotion(name, Modifier.fillMaxSize(), fontSize) } }
    val allInline = prefixInline + inline
    val textStyle = MaterialTheme.typography.bodyLarge.copy(fontSize = fontSize, lineHeight = lineHeight, letterSpacing = letterSpacing)
    val articleStyle = if (flutterArticleMetrics) {
        val inlineRanges = remember(rendered.first, allInline.keys) {
            rendered.first.getStringAnnotations(0, rendered.first.length)
                .filter { it.tag == "androidx.compose.foundation.text.inlineContent" && it.item in allInline }
                .map { it.start until it.end }
        }
        com.green.note.ui.rememberFlutterArticleStyle(rendered.first, textStyle, inlineContentRanges = inlineRanges)
    } else null
    Text(rendered.first, inlineContent = allInline, style = articleStyle?.style ?: textStyle, onTextLayout = articleStyle?.onTextLayout ?: {},
        color = if (color != androidx.compose.ui.graphics.Color.Unspecified) color else if (secondary) colors.onSurfaceVariant else colors.onSurface, maxLines = maxLines, overflow = TextOverflow.Ellipsis, textAlign = textAlign)
}
