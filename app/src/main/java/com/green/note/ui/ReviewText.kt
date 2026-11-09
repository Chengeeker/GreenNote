package com.green.note.ui

import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.sp

internal fun linearSp(value: TextUnit, scale: Float): TextUnit =
    if (scale != 1f && value.type == TextUnitType.Sp) (value.value * scale).sp else value

/** Flutter scales the font size, but leaves logical letter/word spacing unchanged. */
internal fun linearTextStyle(style: TextStyle, scale: Float): TextStyle = if (scale == 1f) style else style.copy(
    fontSize = linearSp(if (style.fontSize == TextUnit.Unspecified) 14.sp else style.fontSize, scale),
    lineHeight = linearSp(style.lineHeight, scale),
)

/** Map only size-bearing styles; retain all other annotations, listeners, tags and UTF-16 ranges. */
internal fun linearAnnotatedText(text: AnnotatedString, scale: Float): AnnotatedString {
    if (scale == 1f || (text.spanStyles.none { it.item.fontSize.type == TextUnitType.Sp } &&
            text.paragraphStyles.none { it.item.lineHeight.type == TextUnitType.Sp })) return text
    return text.mapAnnotations { range ->
        val item = when (val annotation = range.item) {
            is SpanStyle -> annotation.copy(fontSize = linearSp(annotation.fontSize, scale))
            is ParagraphStyle -> annotation.copy(lineHeight = linearSp(annotation.lineHeight, scale))
            else -> annotation
        }
        AnnotatedString.Range(item, range.start, range.end, range.tag)
    }
}

@Composable
private fun LinearTextDensity(source: Density, content: @Composable () -> Unit) {
    if (source.fontScale == 1f) content()
    else {
        val actual = remember(source.density) { ReviewLinearDensity(source.density, 1f) }
        CompositionLocalProvider(LocalDensity provides actual, content = content)
    }
}

@Composable
private fun linearInlineContent(content: Map<String, InlineTextContent>, source: Density): Map<String, InlineTextContent> {
    if (source.fontScale == 1f || content.isEmpty()) return content
    return remember(content, source) {
        content.mapValues { (_, item) ->
            val placeholder = item.placeholder
            InlineTextContent(Placeholder(linearSp(placeholder.width, source.fontScale), linearSp(placeholder.height, source.fontScale), placeholder.placeholderVerticalAlign)) { text ->
                // Only paragraph measurement is unscaled. Inline composables retain their source environment.
                CompositionLocalProvider(LocalDensity provides source) { item.children(text) }
            }
        }
    }
}

@Composable
internal fun ReviewText(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    style: TextStyle = LocalTextStyle.current,
) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val scaled = if (scale == 1f) style else remember(style, scale) { linearTextStyle(style, scale) }
    LinearTextDensity(source) {
        Text(text = text, modifier = modifier, color = color, fontSize = linearSp(fontSize, scale),
            fontStyle = fontStyle, fontWeight = fontWeight, fontFamily = fontFamily,
            letterSpacing = letterSpacing, textDecoration = textDecoration, textAlign = textAlign,
            lineHeight = linearSp(lineHeight, scale), overflow = overflow, softWrap = softWrap,
            maxLines = maxLines, minLines = minLines, onTextLayout = onTextLayout, style = scaled)
    }
}

@Composable
internal fun ReviewText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    inlineContent: Map<String, InlineTextContent> = mapOf(),
    onTextLayout: (TextLayoutResult) -> Unit = {},
    style: TextStyle = LocalTextStyle.current,
) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val scaledStyle = if (scale == 1f) style else remember(style, scale) { linearTextStyle(style, scale) }
    val scaledText = if (scale == 1f) text else remember(text, scale) { linearAnnotatedText(text, scale) }
    val scaledContent = linearInlineContent(inlineContent, source)
    LinearTextDensity(source) {
        Text(text = scaledText, modifier = modifier, color = color, fontSize = linearSp(fontSize, scale),
            fontStyle = fontStyle, fontWeight = fontWeight, fontFamily = fontFamily,
            letterSpacing = letterSpacing, textDecoration = textDecoration, textAlign = textAlign,
            lineHeight = linearSp(lineHeight, scale), overflow = overflow, softWrap = softWrap,
            maxLines = maxLines, minLines = minLines, inlineContent = scaledContent,
            onTextLayout = onTextLayout, style = scaledStyle)
    }
}

@Composable
internal fun ReviewBasicText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = TextStyle.Default,
    onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    color: ColorProducer? = null,
) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val scaled = if (scale == 1f) style else remember(style, scale) { linearTextStyle(style, scale) }
    LinearTextDensity(source) { BasicText(text = text, modifier = modifier, style = scaled,
        onTextLayout = onTextLayout, overflow = overflow, softWrap = softWrap,
        maxLines = maxLines, minLines = minLines, color = color) }
}

@Composable
internal fun ReviewBasicText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    style: TextStyle = TextStyle.Default,
    onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    inlineContent: Map<String, InlineTextContent> = mapOf(),
    color: ColorProducer? = null,
) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val scaledStyle = if (scale == 1f) style else remember(style, scale) { linearTextStyle(style, scale) }
    val scaledText = if (scale == 1f) text else remember(text, scale) { linearAnnotatedText(text, scale) }
    val scaledContent = linearInlineContent(inlineContent, source)
    LinearTextDensity(source) { BasicText(text = scaledText, modifier = modifier, style = scaledStyle,
        onTextLayout = onTextLayout, overflow = overflow, softWrap = softWrap,
        maxLines = maxLines, minLines = minLines, inlineContent = scaledContent, color = color) }
}
