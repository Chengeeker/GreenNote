package com.green.note.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text as NativeMaterialText
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w360dp-h800dp-xxhdpi")
class ReviewLinearFontRenderingTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun changingAppFontScaleRelayoutsActualLargeAndSmallText() {
        var scale by mutableFloatStateOf(1f)
        val layouts = mutableMapOf<Pair<Float, Int>, TextLayoutResult>()
        val nativeLayouts = mutableMapOf<Pair<Float, Int>, TextLayoutResult>()
        compose.setContent {
            val physical = LocalDensity.current.density
            val requestedScale = scale
            val density = remember(physical, requestedScale) { ReviewLinearDensity(physical, requestedScale) }
            CompositionLocalProvider(LocalDensity provides density) {
                Column {
                    for (fontSize in listOf(38, 14)) {
                        ReviewText("888", style = TextStyle(fontSize = fontSize.sp, lineHeight = 1.1.em,
                            fontFamily = FontFamily.SansSerif, letterSpacing = 0.sp),
                            softWrap = false,
                            onTextLayout = { result ->
                                layouts[requestedScale to fontSize] = result
                                val actual = result.layoutInput.density
                                println("ReviewLinearFontRendering requested=$requestedScale font=${fontSize}sp " +
                                    "densityClass=${actual.javaClass.name} density=${actual.density} " +
                                    "fontScale=${actual.fontScale} toPx=${with(actual) { fontSize.sp.toPx() }} " +
                                    "layoutWidth=${result.size.width} lineRight=${result.getLineRight(0)}")
                            })
                        CompositionLocalProvider(LocalDensity provides Density(physical, 1f)) {
                            NativeMaterialText("888", style = TextStyle(fontSize = (fontSize * requestedScale).sp,
                                lineHeight = 1.1.em, fontFamily = FontFamily.SansSerif, letterSpacing = 0.sp),
                                softWrap = false, onTextLayout = { nativeLayouts[requestedScale to fontSize] = it })
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
        compose.runOnIdle {
            assertTrue("Both baseline texts must actually lay out", layouts.keys.containsAll(listOf(1f to 38, 1f to 14)))
            scale = 1.2f
        }
        compose.waitForIdle()
        compose.runOnIdle {
            assertTrue("Changing LocalDensity must produce new actual text layouts; available=${layouts.keys}",
                layouts.keys.containsAll(listOf(1.2f to 38, 1.2f to 14)))
            for (fontSize in listOf(38, 14)) {
                val before = layouts.getValue(1f to fontSize).getLineRight(0)
                val after = layouts.getValue(1.2f to fontSize).getLineRight(0)
                assertTrue("${fontSize}sp text must have nonzero advance", before > 0f)
                for (appliedScale in listOf(1f, 1.2f)) {
                    val oracle = nativeLayouts.getValue(appliedScale to fontSize)
                    assertEquals((fontSize * appliedScale).sp, oracle.layoutInput.style.fontSize)
                    assertEquals(1f, oracle.layoutInput.density.fontScale, 0f)
                    assertEquals("${fontSize}sp production must match native explicit-size glyphs at $appliedScale",
                        oracle.getLineRight(0), layouts.getValue(appliedScale to fontSize).getLineRight(0), .01f)
                }
                assertTrue("Actual text must enlarge", after > before)
                if (fontSize == 38) {
                    assertTrue("38sp score must visibly enlarge: $before -> $after", after / before >= 1.18f)
                    assertEquals(before * 1.2f, after, 2f)
                }
            }
        }
    }

    @Test
    fun publicExplicitFontSizeControlEnlargesGlyphsButKeepsDpBox() {
        var scale by mutableFloatStateOf(1f)
        val layouts = mutableMapOf<Pair<Float, Int>, TextLayoutResult>()
        compose.setContent {
            val physical = LocalDensity.current.density
            val requestedScale = scale
            // Control only: bypass platform nonlinear scaling through the public native API.
            // Production must do this at its text boundary, never compensate individual pages.
            CompositionLocalProvider(LocalDensity provides Density(physical, 1f)) {
                Column {
                    Box(Modifier.size(20.dp).testTag("explicit-control-dp-box"))
                    for (fontSize in listOf(38, 14)) {
                        BasicText("888", style = TextStyle(fontSize = (fontSize * requestedScale).sp,
                            lineHeight = 1.1.em, fontFamily = FontFamily.SansSerif, letterSpacing = 0.sp),
                            softWrap = false, onTextLayout = { result ->
                                layouts[requestedScale to fontSize] = result
                                val actual = result.layoutInput.density
                                println("ExplicitFontSizeControl requested=$requestedScale font=${fontSize}sp " +
                                    "densityClass=${actual.javaClass.name} density=${actual.density} " +
                                    "fontScale=${actual.fontScale} toPx=${with(actual) { (fontSize * requestedScale).sp.toPx() }} " +
                                    "layoutWidth=${result.size.width} lineRight=${result.getLineRight(0)}")
                            })
                    }
                }
            }
        }
        compose.waitForIdle()
        val boxBefore = compose.onNodeWithTag("explicit-control-dp-box").fetchSemanticsNode().boundsInRoot
        compose.runOnIdle { scale = 1.2f }
        compose.waitForIdle()
        val boxAfter = compose.onNodeWithTag("explicit-control-dp-box").fetchSemanticsNode().boundsInRoot
        assertEquals("Text scale must not enlarge the physical dp box width", boxBefore.width, boxAfter.width, 0f)
        assertEquals("Text scale must not enlarge the physical dp box height", boxBefore.height, boxAfter.height, 0f)
        compose.runOnIdle {
            for (fontSize in listOf(38, 14)) {
                val before = layouts.getValue(1f to fontSize).getLineRight(0)
                val after = layouts.getValue(1.2f to fontSize).getLineRight(0)
                for (appliedScale in listOf(1f, 1.2f)) {
                    val actual = layouts.getValue(appliedScale to fontSize).layoutInput
                    assertEquals("Control must request the exact public font size", (fontSize * appliedScale).sp, actual.style.fontSize)
                    assertEquals("Control must disable platform font scaling", 1f, actual.density.fontScale, 0f)
                }
                assertTrue("Explicit ${fontSize}sp text must grow", after > before)
                // Native Robolectric rounds each small glyph: 14sp '888' is 72 -> 84px,
                // despite requesting 14 -> 16.8sp. It is the oracle, not a theoretical width.
                if (fontSize == 38) {
                    assertTrue("Explicit 38sp glyph advance: $before -> $after", after / before >= 1.18f)
                    assertEquals(before * 1.2f, after, 2f)
                }
            }
        }
    }

    @Test
    fun annotatedFontSizeAndInlinePlaceholderScaleWithoutLosingLinkOrChildDensity() {
        var scale by mutableFloatStateOf(1f)
        val layouts = mutableMapOf<Float, TextLayoutResult>()
        val nativeLayouts = mutableMapOf<Float, TextLayoutResult>()
        val childDensities = mutableMapOf<Float, Density>()
        val text = buildAnnotatedString {
            append("88")
            withStyle(SpanStyle(fontSize = 38.sp)) {
                withLink(LinkAnnotation.Url("https://example.test/font-parity")) { append("88") }
            }
            appendInlineContent("fixed-icon", "x")
        }
        compose.setContent {
            val physical = LocalDensity.current.density
            val requestedScale = scale
            val density = remember(physical, requestedScale) { ReviewLinearDensity(physical, requestedScale) }
            CompositionLocalProvider(LocalDensity provides density) {
                val inline = mapOf("fixed-icon" to InlineTextContent(
                    Placeholder(20.sp, 20.sp, PlaceholderVerticalAlign.Center)) {
                    val childDensity = LocalDensity.current
                    SideEffect { childDensities[requestedScale] = childDensity }
                    Box(Modifier.fillMaxSize()) {
                        // A child inside the growing placeholder retains its physical dp size.
                        Box(Modifier.size(12.dp).testTag("inline-fixed-dp-box"))
                    }
                })
                Column {
                ReviewBasicText(text, style = TextStyle(fontSize = 14.sp, lineHeight = 1.1.em,
                    fontFamily = FontFamily.SansSerif, letterSpacing = 0.sp),
                    inlineContent = inline, softWrap = false, onTextLayout = { result ->
                        layouts[requestedScale] = result
                        val actual = result.layoutInput.density
                        println("AnnotatedFontRendering requested=$requestedScale densityClass=${actual.javaClass.name} " +
                            "density=${actual.density} fontScale=${actual.fontScale} " +
                            "toPx38=${with(actual) { 38.sp.toPx() }} width=${result.getLineRight(0)} " +
                            "spanAdvance=${result.getHorizontalPosition(4, true) - result.getHorizontalPosition(2, true)} " +
                            "placeholder=${result.placeholderRects.singleOrNull()}")
                    })
                CompositionLocalProvider(LocalDensity provides Density(physical, 1f)) {
                    // Independent public API oracle: no production style/annotation scaling helper.
                    val nativeText = buildAnnotatedString {
                        append("88")
                        withStyle(SpanStyle(fontSize = (38f * requestedScale).sp)) {
                            withLink(LinkAnnotation.Url("https://example.test/font-parity")) { append("88") }
                        }
                        appendInlineContent("fixed-icon", "x")
                    }
                    BasicText(nativeText, style = TextStyle(fontSize = (14f * requestedScale).sp,
                        lineHeight = 1.1.em, fontFamily = FontFamily.SansSerif, letterSpacing = 0.sp),
                        softWrap = false, inlineContent = mapOf("fixed-icon" to InlineTextContent(
                            Placeholder((20f * requestedScale).sp, (20f * requestedScale).sp,
                                PlaceholderVerticalAlign.Center)) { Box(Modifier.fillMaxSize()) }),
                        onTextLayout = { nativeLayouts[requestedScale] = it })
                }
                }
            }
        }
        compose.waitForIdle()
        val beforeBox = compose.onNodeWithTag("inline-fixed-dp-box", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        compose.runOnIdle { scale = 1.2f }
        compose.waitForIdle()
        val afterBox = compose.onNodeWithTag("inline-fixed-dp-box", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertEquals(beforeBox.width, afterBox.width, 0f)
        assertEquals(beforeBox.height, afterBox.height, 0f)
        compose.runOnIdle {
            val before = layouts.getValue(1f)
            val after = layouts.getValue(1.2f)
            for ((start, end) in listOf(0 to 2, 2 to 4)) {
                val baseline = before.getHorizontalPosition(end, true) - before.getHorizontalPosition(start, true)
                val enlarged = after.getHorizontalPosition(end, true) - after.getHorizontalPosition(start, true)
                assertTrue("Actual annotated run [$start,$end) must enlarge", enlarged > baseline)
                for (appliedScale in listOf(1f, 1.2f)) {
                    val oracle = nativeLayouts.getValue(appliedScale)
                    val actual = layouts.getValue(appliedScale)
                    val expected = oracle.getHorizontalPosition(end, true) - oracle.getHorizontalPosition(start, true)
                    val actualAdvance = actual.getHorizontalPosition(end, true) - actual.getHorizontalPosition(start, true)
                    assertEquals("Annotated run [$start,$end) must match native explicit sizes at $appliedScale", expected, actualAdvance, .01f)
                    assertEquals(1f, oracle.layoutInput.density.fontScale, 0f)
                }
                if (start == 2) {
                    assertTrue("38sp annotated run must visibly enlarge", enlarged / baseline >= 1.18f)
                    assertEquals(baseline * 1.2f, enlarged, 2f)
                }
            }
            assertEquals("Adapter must preserve annotated text", text.text, after.layoutInput.text.text)
            val link = after.layoutInput.text.getLinkAnnotations(2, 4).single()
            assertEquals(2, link.start)
            assertEquals(4, link.end)
            assertEquals("https://example.test/font-parity", (link.item as LinkAnnotation.Url).url)
            val beforePlaceholder = before.placeholderRects.single()!!
            val afterPlaceholder = after.placeholderRects.single()!!
            assertEquals(beforePlaceholder.width * 1.2f, afterPlaceholder.width, 1f)
            assertEquals(beforePlaceholder.height * 1.2f, afterPlaceholder.height, 1f)
            val oldDensity = childDensities.getValue(1f)
            val newDensity = childDensities.getValue(1.2f)
            assertTrue("Inline children must retain the original density implementation", newDensity is ReviewLinearDensity)
            assertEquals(oldDensity.density, newDensity.density, 0f)
            assertEquals(1.2f, newDensity.fontScale, 0f)
        }
    }

    @Test
    fun omittedStyleInheritsButFreshExplicitStyleKeepsMaterialDefaultBase() {
        var scale by mutableFloatStateOf(1f)
        val layouts = mutableMapOf<String, TextLayoutResult>()
        compose.setContent {
            val physical = LocalDensity.current.density
            val requestedScale = scale
            val inherited = TextStyle(fontSize = 38.sp, lineHeight = 1.1.em,
                fontFamily = FontFamily.SansSerif, letterSpacing = 0.sp)
            val fresh = TextStyle(fontWeight = FontWeight.Bold)
            Column {
                CompositionLocalProvider(LocalDensity provides Density(physical, 1f)) {
                    ProvideTextStyle(inherited) {
                        NativeMaterialText("888", softWrap = false,
                            onTextLayout = { layouts["native-inherited"] = it })
                        NativeMaterialText("888", style = fresh, softWrap = false,
                            onTextLayout = { layouts["native-fresh"] = it })
                        // These controls establish the pinned Material implementation's real bases.
                        NativeMaterialText("888", style = inherited, fontSize = 38.sp, softWrap = false,
                            onTextLayout = { layouts["native-explicit38"] = it })
                        NativeMaterialText("888", style = fresh, fontSize = 14.sp, softWrap = false,
                            onTextLayout = { layouts["native-explicit14"] = it })
                        NativeMaterialText("888", style = inherited, fontSize = (38f * requestedScale).sp, softWrap = false,
                            onTextLayout = { layouts["native-scaled-inherited-$requestedScale"] = it })
                        NativeMaterialText("888", style = fresh, fontSize = (14f * requestedScale).sp, softWrap = false,
                            onTextLayout = { layouts["native-scaled-fresh-$requestedScale"] = it })
                    }
                }
                CompositionLocalProvider(LocalDensity provides ReviewLinearDensity(physical, requestedScale)) {
                    ProvideTextStyle(inherited) {
                        ReviewText("888", softWrap = false, onTextLayout = {
                            layouts["review-inherited-$requestedScale"] = it
                            println("MaterialStyleBranch inherited scale=$requestedScale actualStyle=${it.layoutInput.style} advance=${it.getLineRight(0)}")
                        })
                        ReviewText("888", style = fresh, softWrap = false, onTextLayout = {
                            layouts["review-fresh-$requestedScale"] = it
                            println("MaterialStyleBranch fresh scale=$requestedScale actualStyle=${it.layoutInput.style} advance=${it.getLineRight(0)}")
                        })
                    }
                }
            }
        }
        compose.waitForIdle()
        compose.runOnIdle { scale = 1.2f }
        compose.waitForIdle()
        compose.runOnIdle {
            fun advance(key: String) = layouts.getValue(key).getLineRight(0)
            assertEquals("Omitted style inherits the native 38sp local style",
                advance("native-explicit38"), advance("native-inherited"), .01f)
            assertEquals("Fresh explicit style is not merged with LocalTextStyle; its base is native 14sp",
                advance("native-explicit14"), advance("native-fresh"), .01f)
            for (branch in listOf("inherited", "fresh")) {
                val baseline = advance("native-$branch")
                assertEquals("At 1.0 the production adapter must preserve native $branch semantics",
                    baseline, advance("review-$branch-1.0"), .01f)
                val enlarged = advance("review-$branch-1.2")
                assertEquals("Production $branch must match the same native explicit scaled base",
                    advance("native-scaled-$branch-1.2"), enlarged, .01f)
                assertTrue("Production $branch glyph advance must grow", enlarged > baseline)
                if (branch == "inherited") {
                    assertTrue("38sp inherited text must visibly enlarge", enlarged / baseline >= 1.18f)
                    assertEquals(baseline * 1.2f, enlarged, 2f)
                }
            }
        }
    }
}
