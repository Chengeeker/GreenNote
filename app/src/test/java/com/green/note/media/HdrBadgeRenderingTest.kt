package com.green.note.media

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HdrBadgeRenderingTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    private val register = org.junit.rules.TestRule { base, _ -> object : org.junit.runners.model.Statement() {
        override fun evaluate() {
            val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
            org.robolectric.Shadows.shadowOf(context.packageManager).addActivityIfNotPresent(
                android.content.ComponentName(context, ComponentActivity::class.java))
            base.evaluate()
        }
    } }
    @get:org.junit.Rule val rules: org.junit.rules.TestRule = org.junit.rules.RuleChain.outerRule(register).around(compose)

    @Test fun fullAndThumbnailLabelsRemainSingleLineWithScaledText() {
        val scale = mutableFloatStateOf(1f)
        compose.setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalDensity provides Density(1f, scale.floatValue)) {
                    Column {
                        HdrBadge(Modifier.testTag("full"))
                        Box(Modifier.size(64.dp)) {
                            HdrBadge(Modifier.testTag("thumbnail"), description = "第 2 张 HDR 图片", compact = true)
                        }
                    }
                }
            }
        }
        for (factor in listOf(1f, 1.5f)) {
            compose.runOnIdle { scale.floatValue = factor }
            for ((tag, size, height) in listOf(Triple("full", 10f, 12f), Triple("thumbnail", 8f, 9f))) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithTag(tag).assertIsDisplayed().performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                val layout = layouts.single()
                assertEquals(1, layout.lineCount)
                // Paragraph width can retain parent constraints; check the actual label bounds.
                assertTrue("$tag label is clipped", layout.getLineLeft(0) >= 0f && layout.getLineRight(0) <= layout.size.width + .5f)
                assertFalse(layout.isLineEllipsized(0))
                assertEquals(size * factor, layout.layoutInput.style.fontSize.value, .001f)
                assertEquals(height * factor, layout.layoutInput.style.lineHeight.value, .001f)
                assertEquals(FontWeight.Normal, layout.layoutInput.style.fontWeight)
            }
            compose.onNodeWithContentDescription("HDR 图片").assertIsDisplayed()
            compose.onNodeWithContentDescription("第 2 张 HDR 图片").assertIsDisplayed()
        compose.runOnUiThread {
            val view = compose.activity.findViewById<android.view.View>(android.R.id.content)
            val bitmap = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
            try {
                view.draw(android.graphics.Canvas(bitmap))
                java.io.File("build/parity/hdr-badges.png").apply { parentFile.mkdirs() }.outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally { bitmap.recycle() }
        }
        }
    }
}
