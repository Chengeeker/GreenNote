package com.green.note.media

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import coil.Coil
import coil.ImageLoader
import coil.decode.DataSource
import coil.fetch.DrawableResult
import coil.fetch.Fetcher
import coil.imageLoader
import com.green.note.settings.AppPreferences
import com.green.note.ui.LocalAppPreferences
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Real GalleryScreen touch handling and pixels, with a local Coil fixture instead of a network. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w360dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GalleryZoomRenderingTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun pinchingAndLiftingTheLastFingerKeepsTheImageVisibleAndDraggable() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val previousLoader = context.imageLoader
        val bitmap = Bitmap.createBitmap(360, 360, Bitmap.Config.ARGB_8888).apply {
            val canvas = Canvas(this)
            val paint = Paint()
            listOf(android.graphics.Color.RED, android.graphics.Color.GREEN, android.graphics.Color.BLUE).forEachIndexed { i, color ->
                paint.color = color
                canvas.drawRect(i * 120f, 0f, (i + 1) * 120f, 360f, paint)
            }
        }
        val url = "https://image.coolapk.com/gallery-zoom-fixture.png"
        val drawable = BitmapDrawable(context.resources, bitmap)
        val loader = ImageLoader.Builder(context).diskCache(null).components {
            add(Fetcher.Factory<String> { data, _, _ ->
                if (data != url) null else Fetcher { DrawableResult(drawable, false, DataSource.MEMORY) }
            })
        }.build()
        Coil.setImageLoader(loader)
        GalleryHeroRegistry.record(url, Rect(0f, 0f, 360f, 360f), drawable, ContentScale.Fit)
        var closed = 0
        try {
            compose.setContent {
                MaterialTheme {
                    CompositionLocalProvider(LocalAppPreferences provides AppPreferences(liquidGlassNavBar = false)) {
                        GalleryScreen(listOf(url), 0, { closed++ })
                    }
                }
            }
            compose.waitForIdle()
            compose.waitUntil(5_000) {
                compose.onAllNodesWithContentDescription("图片 1").fetchSemanticsNodes().isNotEmpty()
            }
            compose.mainClock.advanceTimeBy(400)
            compose.waitForIdle()
            fun assertImageVisible(label: String): Int {
                val bounds = compose.onNodeWithContentDescription("图片 1").fetchSemanticsNode().boundsInRoot
                assertTrue("$label: finite transformed bounds: $bounds", listOf(bounds.left, bounds.top, bounds.right, bounds.bottom).all { it.isFinite() })
                assertTrue("$label: image covers the center", bounds.contains(Offset(180f, 400f)))
                var color = 0
                compose.runOnUiThread {
                    val view = compose.activity.findViewById<android.view.View>(android.R.id.content)
                    val frame = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                    try {
                        view.draw(Canvas(frame))
                        color = frame.getPixel(frame.width / 2, frame.height / 2)
                        assertTrue("$label: decoded image, not black/loading at center: ${color.toUInt().toString(16)}",
                            maxOf(android.graphics.Color.red(color), android.graphics.Color.green(color), android.graphics.Color.blue(color)) > 220)
                    } finally { frame.recycle() }
                }
                assertEquals("Gestures must not dismiss the gallery", 0, closed)
                return color
            }
            assertEquals(android.graphics.Color.GREEN, assertImageVisible("loaded"))
            repeat(2) { iteration ->
                compose.onRoot().performTouchInput {
                    down(0, center - Offset(24f, 0f)); down(1, center + Offset(24f, 0f))
                    moveTo(0, center - Offset(96f, 0f)); moveTo(1, center + Offset(96f, 0f))
                    up(0); up(1)
                }
                compose.waitForIdle()
                assertImageVisible("pinch/release $iteration")
            }
            val beforePan = compose.onNodeWithContentDescription("图片 1").fetchSemanticsNode()
                .layoutInfo.coordinates.localToRoot(Offset.Zero)
            repeat(2) {
                compose.onRoot().performTouchInput {
                    down(Offset(30f, center.y))
                    moveTo(Offset(330f, center.y), delayMillis = 300)
                    up()
                }
                compose.waitForIdle()
                assertImageVisible("continued pan $it")
            }
            val afterPan = compose.onNodeWithContentDescription("图片 1").fetchSemanticsNode()
                .layoutInfo.coordinates.localToRoot(Offset.Zero)
            assertTrue("A new drag must move the zoomed image: $beforePan -> $afterPan", afterPan.x > beforePan.x + 1f)
            compose.onRoot().performTouchInput { doubleClick(center) }
            compose.waitForIdle()
            assertImageVisible("double tap back to fit")
        } finally {
            GalleryHeroRegistry.clear()
            Coil.setImageLoader(previousLoader)
            loader.shutdown()
        }
    }
}
