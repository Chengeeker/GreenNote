package com.green.note.ui

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Density

/** Scale display annotations after the caller's transform, never the editable value or its offsets. */
internal class LinearInputTransformation(private val original: VisualTransformation, private val scale: Float) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val result = original.filter(text)
        return TransformedText(linearAnnotatedText(result.text, scale), result.offsetMapping)
    }
}

private fun originalDensitySlot(density: Density, content: (@Composable () -> Unit)?): (@Composable () -> Unit)? =
    content?.let { original -> { CompositionLocalProvider(LocalDensity provides density, content = original) } }

private fun originalDensityDecoration(source: Density, physical: Density,
    decoration: @Composable (@Composable () -> Unit) -> Unit): @Composable (@Composable () -> Unit) -> Unit = { inner ->
    CompositionLocalProvider(LocalDensity provides source) {
        decoration { CompositionLocalProvider(LocalDensity provides physical) { inner() } }
    }
}

/** String and TextFieldValue retain the foundation editing/selection/IME implementation unchanged. */
@Composable
fun ReviewBasicTextField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, readOnly: Boolean = false, textStyle: TextStyle = TextStyle.Default,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false, maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE, minLines: Int = 1,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    onTextLayout: (TextLayoutResult) -> Unit = {}, interactionSource: MutableInteractionSource? = null,
    cursorBrush: Brush = SolidColor(Color.Black), decorationBox: @Composable (@Composable () -> Unit) -> Unit = { it() }) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val physical = remember(source.density) { Density(source.density, 1f) }
    val style = remember(textStyle, scale) { if (scale == 1f) textStyle else linearTextStyle(textStyle, scale) }
    val transformation = remember(visualTransformation, scale) {
        if (scale == 1f) visualTransformation else LinearInputTransformation(visualTransformation, scale)
    }
    val decoration = if (scale == 1f) decorationBox else originalDensityDecoration(source, physical, decorationBox)
    val field: @Composable () -> Unit = {
        androidx.compose.foundation.text.BasicTextField(value = value, onValueChange = onValueChange,
            modifier = modifier, enabled = enabled, readOnly = readOnly, textStyle = style,
            keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, singleLine = singleLine,
            maxLines = maxLines, minLines = minLines, visualTransformation = transformation,
            onTextLayout = onTextLayout, interactionSource = interactionSource, cursorBrush = cursorBrush,
            decorationBox = decoration)
    }
    if (scale == 1f) field() else CompositionLocalProvider(LocalDensity provides physical, content = field)
}

@Composable
fun ReviewBasicTextField(value: TextFieldValue, onValueChange: (TextFieldValue) -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, readOnly: Boolean = false, textStyle: TextStyle = TextStyle.Default,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false, maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE, minLines: Int = 1,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    onTextLayout: (TextLayoutResult) -> Unit = {}, interactionSource: MutableInteractionSource? = null,
    cursorBrush: Brush = SolidColor(Color.Black), decorationBox: @Composable (@Composable () -> Unit) -> Unit = { it() }) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val physical = remember(source.density) { Density(source.density, 1f) }
    val style = remember(textStyle, scale) { if (scale == 1f) textStyle else linearTextStyle(textStyle, scale) }
    val transformation = remember(visualTransformation, scale) {
        if (scale == 1f) visualTransformation else LinearInputTransformation(visualTransformation, scale)
    }
    val decoration = if (scale == 1f) decorationBox else originalDensityDecoration(source, physical, decorationBox)
    val field: @Composable () -> Unit = {
        androidx.compose.foundation.text.BasicTextField(value = value, onValueChange = onValueChange,
            modifier = modifier, enabled = enabled, readOnly = readOnly, textStyle = style,
            keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, singleLine = singleLine,
            maxLines = maxLines, minLines = minLines, visualTransformation = transformation,
            onTextLayout = onTextLayout, interactionSource = interactionSource, cursorBrush = cursorBrush,
            decorationBox = decoration)
    }
    if (scale == 1f) field() else CompositionLocalProvider(LocalDensity provides physical, content = field)
}

/** Material slots keep their original theme and density, independently from the native editor. */
@Composable
fun ReviewTextField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, readOnly: Boolean = false, textStyle: TextStyle = LocalTextStyle.current,
    label: (@Composable () -> Unit)? = null, placeholder: (@Composable () -> Unit)? = null,
    leadingIcon: (@Composable () -> Unit)? = null, trailingIcon: (@Composable () -> Unit)? = null,
    prefix: (@Composable () -> Unit)? = null, suffix: (@Composable () -> Unit)? = null,
    supportingText: (@Composable () -> Unit)? = null, isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false, maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE, minLines: Int = 1,
    interactionSource: MutableInteractionSource? = null, shape: Shape = TextFieldDefaults.shape,
    colors: TextFieldColors = TextFieldDefaults.colors()) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val physical = remember(source.density) { Density(source.density, 1f) }
    val style = remember(textStyle, scale) { if (scale == 1f) textStyle else linearTextStyle(textStyle, scale) }
    val transformation = remember(visualTransformation, scale) {
        if (scale == 1f) visualTransformation else LinearInputTransformation(visualTransformation, scale)
    }
    fun slot(content: (@Composable () -> Unit)?) = if (scale == 1f) content else originalDensitySlot(source, content)
    val field: @Composable () -> Unit = {
        androidx.compose.material3.TextField(value = value, onValueChange = onValueChange, modifier = modifier,
            enabled = enabled, readOnly = readOnly, textStyle = style,
            label = slot(label), placeholder = slot(placeholder), leadingIcon = slot(leadingIcon), trailingIcon = slot(trailingIcon),
            prefix = slot(prefix), suffix = slot(suffix), supportingText = slot(supportingText), isError = isError,
            visualTransformation = transformation, keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
            singleLine = singleLine, maxLines = maxLines, minLines = minLines, interactionSource = interactionSource,
            shape = shape, colors = colors)
    }
    if (scale == 1f) field() else CompositionLocalProvider(LocalDensity provides physical, content = field)
}

@Composable
fun ReviewOutlinedTextField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, readOnly: Boolean = false, textStyle: TextStyle = LocalTextStyle.current,
    label: (@Composable () -> Unit)? = null, placeholder: (@Composable () -> Unit)? = null,
    leadingIcon: (@Composable () -> Unit)? = null, trailingIcon: (@Composable () -> Unit)? = null,
    prefix: (@Composable () -> Unit)? = null, suffix: (@Composable () -> Unit)? = null,
    supportingText: (@Composable () -> Unit)? = null, isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false, maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE, minLines: Int = 1,
    interactionSource: MutableInteractionSource? = null, shape: Shape = OutlinedTextFieldDefaults.shape,
    colors: TextFieldColors = OutlinedTextFieldDefaults.colors()) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val physical = remember(source.density) { Density(source.density, 1f) }
    val style = remember(textStyle, scale) { if (scale == 1f) textStyle else linearTextStyle(textStyle, scale) }
    val transformation = remember(visualTransformation, scale) {
        if (scale == 1f) visualTransformation else LinearInputTransformation(visualTransformation, scale)
    }
    fun slot(content: (@Composable () -> Unit)?) = if (scale == 1f) content else originalDensitySlot(source, content)
    val field: @Composable () -> Unit = {
        androidx.compose.material3.OutlinedTextField(value = value, onValueChange = onValueChange, modifier = modifier,
            enabled = enabled, readOnly = readOnly, textStyle = style,
            label = slot(label), placeholder = slot(placeholder), leadingIcon = slot(leadingIcon), trailingIcon = slot(trailingIcon),
            prefix = slot(prefix), suffix = slot(suffix), supportingText = slot(supportingText), isError = isError,
            visualTransformation = transformation, keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
            singleLine = singleLine, maxLines = maxLines, minLines = minLines, interactionSource = interactionSource,
            shape = shape, colors = colors)
    }
    if (scale == 1f) field() else CompositionLocalProvider(LocalDensity provides physical, content = field)
}

@Composable
internal fun ReviewOutlinedTextField(value: TextFieldValue, onValueChange: (TextFieldValue) -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, textStyle: TextStyle = LocalTextStyle.current,
    minLines: Int = 1, maxLines: Int = Int.MAX_VALUE, placeholder: (@Composable () -> Unit)? = null,
    shape: Shape = OutlinedTextFieldDefaults.shape) {
    val source = LocalDensity.current
    val scale = source.fontScale
    val physical = remember(source.density) { Density(source.density, 1f) }
    val style = remember(textStyle, scale) { linearTextStyle(textStyle, scale) }
    val field: @Composable () -> Unit = {
        androidx.compose.material3.OutlinedTextField(value, onValueChange, modifier, enabled = enabled,
            textStyle = style, minLines = minLines, maxLines = maxLines,
            placeholder = if (scale == 1f) placeholder else originalDensitySlot(source, placeholder), shape = shape)
    }
    if (scale == 1f) field() else CompositionLocalProvider(LocalDensity provides physical, content = field)
}
