package com.green.note.ui

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.Window
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Actual Foundation lazy layout and Android touchscreen dispatch, not a fake ScrollableState. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w360dp-h800dp-xxhdpi")
class ScrollPressRenderingTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun afterDispatchPressStopsActualFlingAndAllowsNextDrag() {
        lateinit var state: LazyListState
        lateinit var controller: ScrollRateController
        var density = 1f
        var lifecycle: Lifecycle? = null
        compose.setContent {
            density = LocalDensity.current.density
            controller = androidx.compose.runtime.remember { ScrollRateController(compose.activity.window) }
            CompositionLocalProvider(LocalScrollRateController provides controller) {
                ActivePage(true) {
                    state = rememberLazyListState()
                    ReviewScrollActivity(state)
                    val owner = LocalLifecycleOwner.current
                    SideEffect { lifecycle = owner.lifecycle }
                    LazyColumn(state = state, modifier = Modifier.fillMaxSize().testTag("scroll-list")) {
                        items((0 until 242).toList()) { index ->
                            Box(Modifier.fillMaxWidth().height(64.dp)) { Text("Application $index") }
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(Lifecycle.State.RESUMED, lifecycle?.currentState) }
        val original = compose.activity.window.callback
        var downCount = 0
        compose.runOnUiThread {
            compose.activity.window.callback = object : Window.Callback by original {
                override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                    val handled = original.dispatchTouchEvent(event)
                    if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                        downCount++
                        println("ScrollPress DOWN source=${event.source} scrolling=${state.isScrollInProgress} " +
                            "index=${state.firstVisibleItemIndex} offset=${state.firstVisibleItemScrollOffset} lifecycle=${lifecycle?.currentState}")
                        controller.requests.stopOnPress(compose.activity.lifecycleScope)
                    }
                    return handled
                }
            }
        }
        compose.mainClock.autoAdvance = false
        var time = SystemClock.uptimeMillis()
        var downTime = time
        fun frame(milliseconds: Long = 16L) {
            compose.mainClock.advanceTimeBy(milliseconds)
            compose.waitForIdle()
        }
        fun event(action: Int, yDp: Float, elapsed: Long = 16L) {
            time = maxOf(time + elapsed, SystemClock.uptimeMillis())
            if (action == MotionEvent.ACTION_DOWN) downTime = time
            compose.runOnUiThread {
                val event = MotionEvent.obtain(downTime, time, action, 180f * density, yDp * density, 0)
                event.source = InputDevice.SOURCE_TOUCHSCREEN
                try { compose.activity.window.callback.dispatchTouchEvent(event) }
                finally { event.recycle() }
            }
        }
        fun position() = state.firstVisibleItemIndex * (64f * density) + state.firstVisibleItemScrollOffset
        try {
            // The first contact may race the UP-triggered fling coroutine. Cover all three timings.
            for (delayFrames in 0..2) {
                compose.runOnUiThread { compose.activity.lifecycleScope.launch { state.scrollToItem(0) } }
                frame()
                event(MotionEvent.ACTION_DOWN, 680f)
                for (y in listOf(600f, 520f, 440f, 360f, 280f, 200f)) {
                    event(MotionEvent.ACTION_MOVE, y)
                    frame()
                }
                event(MotionEvent.ACTION_UP, 160f)
                val releasedAt = position()
                repeat(delayFrames) { frame() }
                val beforePress = position()
                if (delayFrames == 2) assertTrue("The fixture must actually fling after UP before testing its cancellation", beforePress > releasedAt)
                event(MotionEvent.ACTION_DOWN, 450f)
                frame(250L)
                val first = position()
                frame(700L)
                val second = position()
                println("ScrollPress delayFrames=$delayFrames before=$beforePress held250=$first held950=$second " +
                    "scrolling=${state.isScrollInProgress} lifecycle=${lifecycle?.currentState}")
                assertTrue("The actual list must move before the held press", beforePress > 0f)
                assertEquals("A held DOWN must stop the actual lazy-list fling (delay=$delayFrames)", first, second, 0f)
                event(MotionEvent.ACTION_MOVE, 350f)
                frame()
                event(MotionEvent.ACTION_MOVE, 250f)
                frame()
                assertTrue("The new held contact must still be able to drag", position() > second)
                event(MotionEvent.ACTION_UP, 250f)
                frame()
            }
            assertEquals(6, downCount)
        } finally {
            event(MotionEvent.ACTION_CANCEL, 250f)
            compose.runOnUiThread {
                compose.activity.window.callback = original
                controller.release()
            }
            compose.mainClock.autoAdvance = true
        }
    }
}
