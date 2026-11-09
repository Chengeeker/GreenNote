package com.green.note.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.*
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w360dp-h800dp-xxhdpi")
class ReviewLinearInputTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun materialEditorsUsePhysicalDensityAndRestoreLabelAndSupportingSlots() {
        var scale by mutableFloatStateOf(1f)
        val slots = mutableMapOf<Pair<Float, String>, Float>()
        compose.setContent {
            val requested = scale
            val physical = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides ReviewLinearDensity(physical, requested)) {
                Column {
                    ReviewTextField("888", {}, Modifier.testTag("filled"), textStyle = TextStyle(fontSize = 38.sp),
                        label = { slots[requested to "label"] = LocalDensity.current.fontScale; ReviewText("Label") })
                    ReviewOutlinedTextField("888", {}, Modifier.testTag("outlined"), textStyle = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
                        supportingText = { slots[requested to "supporting"] = LocalDensity.current.fontScale; ReviewText("Supporting") })
                    // Independent engine oracle: no production scaler/helper or adapter is called here.
                    CompositionLocalProvider(LocalDensity provides Density(physical, 1f)) {
                        androidx.compose.material3.TextField(value = "888", onValueChange = {},
                            modifier = Modifier.testTag("filled-control"), textStyle = TextStyle(fontSize = (38f * requested).sp))
                        androidx.compose.material3.OutlinedTextField(value = "888", onValueChange = {},
                            modifier = Modifier.testTag("outlined-control"),
                            textStyle = TextStyle(fontSize = (14f * requested).sp, lineHeight = (20f * requested).sp))
                    }
                }
            }
        }
        compose.waitForIdle()
        fun read(tag: String): TextLayoutResult {
            val values = mutableListOf<TextLayoutResult>()
            compose.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(values) }
            return values.single()
        }
        val before = listOf("filled", "outlined").associateWith(::read)
        for (kind in before.keys) assertEquals(read("$kind-control").getLineRight(0), before.getValue(kind).getLineRight(0), .01f)
        compose.runOnIdle { scale = 1.2f }
        compose.waitForIdle()
        for (kind in before.keys) {
            val after = read(kind)
            val control = read("$kind-control")
            assertEquals("$kind must match the independently scaled native editor", control.getLineRight(0), after.getLineRight(0), .01f)
            assertEquals(control.size.height, after.size.height)
            if (kind == "filled") assertTrue(after.getLineRight(0) / before.getValue(kind).getLineRight(0) >= 1.18f)
            println("LinearInput $kind original=${before.getValue(kind).getLineRight(0)} scaled=${after.getLineRight(0)} nativeExplicit=${control.getLineRight(0)}")
            assertEquals(1f, after.layoutInput.density.fontScale, 0f)
        }
        compose.runOnIdle {
            assertEquals(1.2f, slots.getValue(1.2f to "label"), 0f)
            assertEquals(1.2f, slots.getValue(1.2f to "supporting"), 0f)
        }
    }

    @Test fun actualEditorScalesLinearlyWithoutChangingSelectionCompositionDecorationsOrIme() {
        var scale by mutableFloatStateOf(1f)
        val initial = TextFieldValue("1234", TextRange(1, 3), TextRange(0, 2))
        var editor by mutableStateOf(initial)
        var changes = 0
        var done = 0
        val layouts = mutableMapOf<Pair<Float, String>, TextLayoutResult>()
        val controls = mutableMapOf<Pair<Float, String>, TextLayoutResult>()
        val iconSizes = mutableMapOf<Float, IntSize>()
        val decorationScales = mutableMapOf<Float, Float>()
        compose.setContent {
            val physical = LocalDensity.current.density
            val requested = scale
            CompositionLocalProvider(LocalDensity provides ReviewLinearDensity(physical, requested)) {
                Column {
                    ReviewBasicTextField(editor, { editor = it; changes++ }, Modifier.fillMaxWidth().testTag("editor"),
                        textStyle = TextStyle(fontSize = 38.sp, lineHeight = 1.1.em, letterSpacing = 0.sp),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { done++ }),
                        onTextLayout = { layouts[requested to "editor"] = it },
                        decorationBox = { inner ->
                            decorationScales[requested] = LocalDensity.current.fontScale
                            Row {
                                Box(Modifier.size(24.dp).onGloballyPositioned { iconSizes[requested] = it.size })
                                Column(Modifier.weight(1f)) {
                                    ReviewText("888", fontSize = 14.sp, lineHeight = 20.sp,
                                        onTextLayout = { layouts[requested to "hint"] = it })
                                    inner()
                                }
                            }
                        })
                    ReviewBasicTextField("888", {}, textStyle = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
                        onTextLayout = { layouts[requested to "small"] = it })
                    ReviewBasicTextField("secret", {}, textStyle = TextStyle(fontSize = 14.sp),
                        visualTransformation = PasswordVisualTransformation(),
                        onTextLayout = { layouts[requested to "password"] = it })
                    CompositionLocalProvider(LocalDensity provides Density(physical, 1f)) {
                        androidx.compose.foundation.text.BasicTextField(value = initial, onValueChange = {},
                            textStyle = TextStyle(fontSize = (38f * requested).sp, lineHeight = 1.1.em, letterSpacing = 0.sp),
                            onTextLayout = { controls[requested to "editor"] = it })
                        androidx.compose.foundation.text.BasicTextField(value = "888", onValueChange = {},
                            textStyle = TextStyle(fontSize = (14f * requested).sp, lineHeight = (20f * requested).sp),
                            onTextLayout = { controls[requested to "small"] = it })
                        androidx.compose.material3.Text(text = "888", fontSize = (14f * requested).sp,
                            lineHeight = (20f * requested).sp, onTextLayout = { controls[requested to "hint"] = it })
                    }
                }
            }
        }
        compose.waitForIdle()
        compose.runOnIdle { scale = 1.2f }
        compose.waitForIdle()
        compose.runOnIdle {
            assertSame("Scaling must never replace the editing model", initial, editor)
            assertEquals(0, changes)
            assertEquals(TextRange(1, 3), editor.selection)
            assertEquals(TextRange(0, 2), editor.composition)
            assertEquals(1.2f, decorationScales.getValue(1.2f), 0f)
            assertEquals(iconSizes.getValue(1f), iconSizes.getValue(1.2f))
            for (kind in listOf("editor", "small", "hint")) {
                val before = layouts.getValue(1f to kind)
                val after = layouts.getValue(1.2f to kind)
                val control = controls.getValue(1.2f to kind)
                assertEquals(controls.getValue(1f to kind).getLineRight(0), before.getLineRight(0), .01f)
                assertEquals("$kind must match the independently scaled native component", control.getLineRight(0), after.getLineRight(0), .01f)
                assertEquals(control.size.height, after.size.height)
                if (kind == "editor") assertTrue(after.getLineRight(0) / before.getLineRight(0) >= 1.18f)
                println("LinearInput $kind original=${before.getLineRight(0)} scaled=${after.getLineRight(0)} nativeExplicit=${control.getLineRight(0)}")
                assertEquals(1f, after.layoutInput.density.fontScale, 0f)
            }
            assertEquals("••••••", layouts.getValue(1.2f to "password").layoutInput.text.text)
        }
        compose.onNodeWithTag("editor").performSemanticsAction(SemanticsActions.RequestFocus) { it() }
        compose.onNodeWithTag("editor").performSemanticsAction(SemanticsActions.SetSelection) { it(1, 3, false) }
        compose.onNodeWithTag("editor").performTextInput("9")
        compose.onNodeWithTag("editor").performImeAction()
        compose.runOnIdle {
            assertEquals("194", editor.text)
            assertEquals(TextRange(2), editor.selection)
            assertEquals(1, done)
        }
    }

    @Test fun visualScalingKeepsCharactersOffsetMappingAndEditableAnnotationsUntouched() {
        val original = buildAnnotatedString {
            append("abcd")
            addStyle(SpanStyle(fontSize = 12.sp), 1, 3)
            addStyle(ParagraphStyle(lineHeight = 20.sp), 0, 4)
            addStringAnnotation("source", "unchanged", 0, 4)
        }
        val mapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int) = offset
            override fun transformedToOriginal(offset: Int) = offset
        }
        val transformed = LinearInputTransformation(VisualTransformation { TransformedText(it, mapping) }, 1.2f).filter(original)
        assertEquals(original.text, transformed.text.text)
        assertSame(mapping, transformed.offsetMapping)
        assertEquals(original.getStringAnnotations(0, 4), transformed.text.getStringAnnotations(0, 4))
        assertEquals(14.4f, transformed.text.spanStyles.single().item.fontSize.value, .001f)
        assertEquals(24f, transformed.text.paragraphStyles.single().item.lineHeight.value, 0f)
        assertEquals(12.sp, original.spanStyles.single().item.fontSize)
        assertEquals(20.sp, original.paragraphStyles.single().item.lineHeight)
        for (offset in 0..4) assertEquals(offset, transformed.offsetMapping.transformedToOriginal(offset))
    }
}
