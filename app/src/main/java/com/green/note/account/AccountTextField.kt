package com.green.note.account

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.*
import androidx.compose.foundation.layout.*
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.green.note.ui.LocalMaterialGlyphColor
import com.green.note.ui.LocalIconButtonColor
import kotlin.math.*

internal object AccountFieldGeometry {
    fun height(input: Float, outlined: Boolean, floatingHeight: Float) = max(48f, input + if (outlined) 32f else 16f + floatingHeight)
    fun inputStart(hasIcon: Boolean, outlined: Boolean) = if (hasIcon) 52f else if (outlined) 16f else 0f
    fun labelStart(progress: Float, hasIcon: Boolean, outlined: Boolean): Float {
        val from = inputStart(hasIcon, outlined)
        val to = if (outlined) 16f else from
        return from + (to - from) * progress
    }
}

/** Account pages use Flutter's non-dense, unfilled InputDecorator. This decoration
 * keeps its border at y=0 (no Compose 8dp outer label reserve), 4dp subtext gap,
 * original prefix/suffix slots, and the 167ms floating-label transform. */
@Composable
internal fun AccountTextField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, label: String, placeholder: String? = null,
    singleLine: Boolean = true, minLines: Int = 1, maxLines: Int = 1,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    leadingIcon: (@Composable () -> Unit)? = null, trailingIcon: (@Composable () -> Unit)? = null,
    supportingText: (@Composable () -> Unit)? = null, isError: Boolean = false, outlined: Boolean = true) {
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    val interactions = remember { MutableInteractionSource() }
    val focused by interactions.collectIsFocusedAsState()
    val hovered by interactions.collectIsHoveredAsState()
    val floating = focused || value.isNotEmpty()
    val controller = remember { Animatable(if (floating) 1f else 0f) }
    LaunchedEffect(floating) { val target = if (floating) 1f else 0f; controller.animateTo(target, tween((167 * abs(target - controller.value)).roundToInt(), easing = LinearEasing)) }
    val progress = if (floating) FastOutSlowInEasing.transform(controller.value) else 1 - FastOutSlowInEasing.transform(1 - controller.value)
    val targetBorder = when {
        !enabled -> scheme.onSurface.copy(alpha = .12f)
        isError -> if (hovered && !focused) scheme.onErrorContainer else scheme.error
        focused -> scheme.primary
        hovered -> scheme.onSurface
        outlined -> scheme.outline
        else -> scheme.onSurfaceVariant
    }
    val border by animateColorAsState(targetBorder, tween(167, easing = FastOutSlowInEasing), label = "account field border")
    val stroke by animateFloatAsState(if (enabled && focused) 2f else 1f, tween(167, easing = FastOutSlowInEasing), label = "account field stroke")
    val targetLabel = when { !enabled -> scheme.onSurface.copy(alpha = .38f); isError -> if (hovered && !focused) scheme.onErrorContainer else scheme.error; focused -> scheme.primary; else -> scheme.onSurfaceVariant }
    val labelColor by animateColorAsState(targetLabel, tween(167, easing = FastOutSlowInEasing), label = "account field label")
    val inputStyle = MaterialTheme.typography.bodyLarge.copy(color = if (enabled) scheme.onSurface else scheme.onSurface.copy(alpha = .38f))
    val labelStyle = MaterialTheme.typography.bodyLarge.copy(color = labelColor)
    val iconColor = if (enabled) scheme.onSurfaceVariant else scheme.onSurface.copy(alpha = .38f)
    val hintAlpha by animateFloatAsState(if (floating && value.isEmpty()) 1f else 0f, tween(167, easing = FastOutSlowInEasing), label = "account field hint")
    val measurer = rememberTextMeasurer()
    val floatHeight = with(density) { (4.sp.toPx() + labelStyle.fontSize.toPx() * .75f) / this.density }
    val naturalLabelWidth = measurer.measure(label, labelStyle, maxLines = 1).size.width
    val fieldPolicy = remember(leadingIcon != null, trailingIcon != null, outlined, naturalLabelWidth, floatHeight) {
        AccountFieldMeasurePolicy(leadingIcon != null, trailingIcon != null, outlined, naturalLabelWidth, floatHeight)
    }
    Column(modifier) {
        BasicTextField(value, onValueChange, Modifier.fillMaxWidth().hoverable(interactions, enabled).semantics {
            contentDescription = label
            if (isError) { error("请填写内容"); liveRegion = LiveRegionMode.Polite }
        }, enabled = enabled, singleLine = singleLine, minLines = minLines, maxLines = maxLines,
            keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, textStyle = inputStyle,
            cursorBrush = SolidColor(if (isError) scheme.error else scheme.primary), visualTransformation = visualTransformation,
            interactionSource = interactions, decorationBox = { field ->
                Layout(modifier = Modifier.drawWithCache {
                    val labelScale = 1f - .25f * progress
                    val left = AccountFieldGeometry.inputStart(leadingIcon != null, outlined).dp.toPx()
                    val right = (if (trailingIcon != null) 52.dp else if (outlined) 16.dp else 0.dp).toPx()
                    val labelText = measurer.measure(label, labelStyle, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        constraints = Constraints(maxWidth = max(0, ((size.width - left - right) / labelScale).roundToInt())))
                    onDrawWithContent {
                        val px = stroke.dp.toPx(); val inset = px / 2
                        if (outlined && size.width >= px && size.height >= px) {
                            val gapLeft = 12.dp.toPx()
                            val gapRight = gapLeft + (labelText.size.width * .75f + 8.dp.toPx()) * progress
                            clipRect(gapLeft, -px, gapRight, px * 2, clipOp = ClipOp.Difference) {
                                drawRoundRect(border, Offset(inset, inset), Size(size.width - px, size.height - px), CornerRadius(max(0f, 4.dp.toPx() - inset)), style = Stroke(px))
                            }
                        } else if (!outlined && size.height >= px) drawLine(border, Offset(0f, size.height - inset), Offset(size.width, size.height - inset), px)
                        drawContent()
                        val inlineY = (size.height - labelText.size.height) / 2
                        val floatingY = if (outlined) -labelText.size.height * .75f / 2 + px / 2 else 8.dp.toPx()
                        translate(AccountFieldGeometry.labelStart(progress, leadingIcon != null, outlined).dp.toPx(), inlineY + (floatingY - inlineY) * progress) {
                            scale(labelScale, pivot = Offset.Zero) { drawText(labelText) }
                        }
                    }
                }, content = {
                    Box { field(); if (placeholder != null && value.isEmpty()) Text(placeholder, Modifier.graphicsLayer { alpha = hintAlpha },
                        style = inputStyle.copy(color = iconColor), maxLines = maxLines, overflow = TextOverflow.Clip) }
                    Box(contentAlignment = Alignment.Center) { if (leadingIcon != null) CompositionLocalProvider(LocalMaterialGlyphColor provides iconColor, LocalIconButtonColor provides iconColor, LocalContentColor provides iconColor) { leadingIcon() } }
                    Box(contentAlignment = Alignment.Center) { if (trailingIcon != null) CompositionLocalProvider(LocalMaterialGlyphColor provides iconColor, LocalIconButtonColor provides iconColor, LocalContentColor provides iconColor) { trailingIcon() } }
                }, measurePolicy = fieldPolicy)
            })
        if (supportingText != null) Box(Modifier.fillMaxWidth().padding(start = if (outlined) 16.dp else 0.dp, end = if (outlined) 16.dp else 0.dp, top = 4.dp)) {
            val supportingColor = if (isError) scheme.error else if (enabled) scheme.onSurfaceVariant else scheme.onSurface.copy(alpha = .38f)
            CompositionLocalProvider(LocalContentColor provides supportingColor) {
                ProvideTextStyle(MaterialTheme.typography.bodySmall.copy(color = supportingColor)) { supportingText() }
            }
        }
    }
}
