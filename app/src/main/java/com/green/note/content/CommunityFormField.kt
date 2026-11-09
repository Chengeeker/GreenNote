package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.layout.*
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*

internal data class CommunityTextLimit(val text: String, val characters: Int)

/** Android's ICU character iterator preserves extended graphemes, including surrogate pairs. */
internal fun communityTextLimit(value: String, maximum: Int): CommunityTextLimit {
    require(maximum >= 0)
    val iterator = android.icu.text.BreakIterator.getCharacterInstance(java.util.Locale.ROOT)
    iterator.setText(value)
    var end = iterator.first()
    var count = 0
    while (count < maximum) {
        val next = iterator.next()
        if (next == android.icu.text.BreakIterator.DONE) return CommunityTextLimit(value, count)
        end = next
        count++
    }
    return CommunityTextLimit(if (end == value.length) value else value.substring(0, end), count)
}

/** The original community form uses underlined TextFormField, not outlined fields. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CommunityFormField(value: String, onChange: (String) -> Unit, label: String,
    modifier: Modifier = Modifier, lines: Int = 1, limit: Int? = null, error: String? = null,
    hint: String? = null, autofocus: Boolean = false, keyboardType: androidx.compose.ui.text.input.KeyboardType = androidx.compose.ui.text.input.KeyboardType.Text,
    prefixIcon: String? = null, imeAction: ImeAction = ImeAction.Default, onSubmit: ((String) -> Unit)? = null,
    minimumLines: Int = lines, suffixIcon: String? = null) {
    val interactions = remember { MutableInteractionSource() }
    val focused by interactions.collectIsFocusedAsState()
    val hovered by interactions.collectIsHoveredAsState()
    val focus = remember { FocusRequester() }
    val colors = MaterialTheme.colorScheme
    val inputStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface)
    val labelStyle = MaterialTheme.typography.bodyLarge.copy(lineHeight = 1.em)
    val density = LocalDensity.current
    val transition = tween<Float>(167, easing = FastOutSlowInEasing)
    val floating by animateFloatAsState(if (focused || value.isNotEmpty()) 1f else 0f, transition, label = "Community label")
    val hintAlpha by animateFloatAsState(if (value.isEmpty() && (label.isEmpty() || focused)) 1f else 0f, tween(20, easing = FastOutSlowInEasing), label = "Community hint")
    val targetColor = when { error != null -> if (!focused && hovered) colors.onErrorContainer else colors.error; focused -> colors.primary; hovered -> colors.onSurface; else -> colors.onSurfaceVariant }
    val borderColor by animateColorAsState(targetColor, tween(167, easing = FastOutSlowInEasing), label = "Community underline")
    val borderWidth by animateFloatAsState(if (focused) 2f else 1f, transition, label = "Community underline width")
    val labelColor by animateColorAsState(when { error != null -> targetColor; focused -> colors.primary; else -> colors.onSurfaceVariant }, tween(167, easing = FastOutSlowInEasing), label = "Community label color")
    val shake = remember { Animatable(1f) }
    var previousError by remember { mutableStateOf(error) }
    LaunchedEffect(error) {
        if (error != null && error != previousError && floating == 1f) { shake.snapTo(0f); shake.animateTo(1f, tween(167, easing = LinearEasing)) }
        previousError = error
    }
    var shownError by remember { mutableStateOf(error) }
    val errorProgress = remember { Animatable(if (error == null) 0f else 1f) }
    LaunchedEffect(error) {
        if (error != null) shownError = error
        errorProgress.animateTo(if (error == null) 0f else 1f, tween(167, easing = LinearEasing))
        if (error == null) shownError = null
    }
    val characters = remember(value, limit) { limit?.let { communityTextLimit(value, Int.MAX_VALUE).characters } }
    if (autofocus) LaunchedEffect(Unit) { focus.requestFocus() }
    Column(modifier.fillMaxWidth()) {
        BasicTextField(value, { onChange(if (limit == null) it else communityTextLimit(it, limit).text) },
            Modifier.fillMaxWidth().focusRequester(focus).hoverable(interactions), singleLine = lines == 1, minLines = minimumLines, maxLines = lines,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
            keyboardActions = if (onSubmit == null) androidx.compose.foundation.text.KeyboardActions.Default else androidx.compose.foundation.text.KeyboardActions(onAny = { onSubmit(value) }),
            textStyle = inputStyle,
            cursorBrush = SolidColor(if (error != null) colors.error else colors.primary), interactionSource = interactions,
            decorationBox = { field ->
                Layout(modifier = Modifier.fillMaxWidth().drawBehind {
                    val stroke = borderWidth.dp.toPx()
                    drawLine(borderColor, Offset(0f, size.height - stroke / 2), Offset(size.width, size.height - stroke / 2), stroke)
                }, content = {
                    Box(Modifier.layoutId("input")) { field() }
                    if (hint != null) Text(hint, Modifier.layoutId("hint").graphicsLayer { alpha = hintAlpha }, style = inputStyle, color = colors.onSurfaceVariant, maxLines = lines, overflow = TextOverflow.Ellipsis)
                    if (label.isNotEmpty()) Text(label, Modifier.layoutId("label").graphicsLayer {
                        val scale = 1f - .25f * floating
                        scaleX = scale; scaleY = scale; transformOrigin = TransformOrigin(0f, 0f)
                        val t = shake.value
                        translationX = (when { t <= .25f -> -t; t < .75f -> t - .5f; else -> (1f - t) * 4f }) * 4.dp.toPx()
                    }, style = labelStyle, color = labelColor, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (prefixIcon != null) Box(Modifier.layoutId("prefix").size(48.dp), contentAlignment = Alignment.Center) { com.green.note.ui.MaterialGlyph(prefixIcon, size = 24.dp, color = colors.onSurfaceVariant) }
                    if (suffixIcon != null) Box(Modifier.layoutId("suffix").size(48.dp), contentAlignment = Alignment.Center) { com.green.note.ui.MaterialGlyph(suffixIcon, size = 24.dp, color = colors.onSurfaceVariant) }
                }, measurePolicy = CommunityFieldMeasurePolicy(
                    floating = floating,
                    floatingHeight = if (label.isEmpty()) 0 else with(density) { (labelStyle.fontSize.value * .75f + 4f).sp.roundToPx() },
                    padding = with(density) { 8.dp.roundToPx() },
                    minimumHeight = with(density) { 48.dp.roundToPx() },
                    iconGap = with(density) { 4.dp.roundToPx() },
                ))
            })
        if (shownError != null || limit != null) Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(shownError.orEmpty(), Modifier.weight(1f).graphicsLayer { alpha = errorProgress.value; translationY = -.25f * size.height * (1f - errorProgress.value) }, color = colors.error, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (limit != null) Text("$characters/$limit", style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
        }
    }
}
