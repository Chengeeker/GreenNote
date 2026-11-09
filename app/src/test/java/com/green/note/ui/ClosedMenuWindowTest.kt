package com.green.note.ui

import android.view.inspector.WindowInspector
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.isPopup
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.launch
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
class ClosedMenuWindowTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun windowCount(): Int {
        var count = -1
        compose.runOnUiThread { count = WindowInspector.getGlobalWindowViews().size }
        return count
    }

    @Test
    fun newlyComposedClosedRowMenusNeverCreatePopupWindows() {
        var renderRows by mutableStateOf(false)
        var windowsAllowed = false
        var lifecycle: Lifecycle? = null
        lateinit var list: LazyListState
        compose.setContent {
            list = rememberLazyListState()
            val allowed = reviewWindowVisible()
            val owner = LocalLifecycleOwner.current
            SideEffect { windowsAllowed = allowed; lifecycle = owner.lifecycle }
            if (renderRows) LazyColumn(Modifier.fillMaxSize(), state = list) {
                items((0 until 242).toList()) { index ->
                    Box(Modifier.fillMaxWidth().height(64.dp)) {
                        Text("Application $index")
                        ReviewPopupMenu(false, {}) { Text("Closed row popup") }
                        ReviewDropdownMenu(false, {}, listOf("One", "Two"), 0,
                            IntRect(0, 0, 120, 48), {})
                    }
                }
            }
        }
        // Let the activity/root attach before freezing time, but do not compose any row menus yet.
        compose.waitForIdle()
        assertTrue(windowsAllowed)
        assertEquals(Lifecycle.State.RESUMED, lifecycle?.currentState)
        val initialWindows = windowCount()
        assertTrue("WindowInspector must observe the attached activity root", initialWindows > 0)
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { renderRows = true }
        try {
            compose.waitForIdle()
            for (target in listOf(0, 30, 70)) {
                if (target != 0) compose.runOnUiThread { compose.activity.lifecycleScope.launch { list.scrollToItem(target) } }
                // Stay inside the old accidental 300ms tween while newly mounted rows run effects.
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                compose.onAllNodes(isPopup(), useUnmergedTree = true).assertCountEquals(0)
                assertEquals("Closed rows must not add a focusable Android window at item $target", initialWindows, windowCount())
                compose.mainClock.advanceTimeBy(64)
                compose.waitForIdle()
                compose.onAllNodes(isPopup(), useUnmergedTree = true).assertCountEquals(0)
                assertEquals(initialWindows, windowCount())
            }
        } finally { compose.mainClock.autoAdvance = true }
    }

    @Test
    fun realOpenAndCloseKeepTheirAnimatedPopupWindowsUntilCompletion() {
        var expanded by mutableStateOf(false)
        var dropdown by mutableStateOf(false)
        var windowsAllowed = false
        var lifecycle: Lifecycle? = null
        compose.setContent {
            val allowed = reviewWindowVisible()
            val owner = LocalLifecycleOwner.current
            SideEffect { windowsAllowed = allowed; lifecycle = owner.lifecycle }
            Box(Modifier.fillMaxSize()) {
                if (!dropdown) ReviewPopupMenu(expanded, {}) {
                    ReviewPopupMenuItem(text = { Text("Actual menu") }, onClick = {})
                }
                else ReviewDropdownMenu(expanded, {}, listOf("One", "Two"), 0,
                    IntRect(60, 100, 300, 244), {})
            }
        }
        compose.waitForIdle()
        assertTrue(windowsAllowed)
        assertEquals(Lifecycle.State.RESUMED, lifecycle?.currentState)
        compose.mainClock.autoAdvance = false
        try {
            compose.waitForIdle()
            val initialWindows = windowCount()
            assertTrue("WindowInspector must observe the attached activity root", initialWindows > 0)
            for (kind in listOf(false, true)) {
                compose.runOnIdle { dropdown = kind }
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                compose.onAllNodes(isPopup(), useUnmergedTree = true).assertCountEquals(0)
                compose.runOnIdle { expanded = true }
                // A Popup is a new Android root; attach it before advancing its content's animation.
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                compose.mainClock.advanceTimeBy(64)
                compose.waitForIdle()
                compose.onAllNodes(isPopup(), useUnmergedTree = true).assertCountEquals(1)
                assertEquals(initialWindows + 1, windowCount())
                compose.mainClock.advanceTimeBy(320)
                compose.waitForIdle()
                compose.runOnIdle { expanded = false }
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                compose.mainClock.advanceTimeBy(64)
                compose.waitForIdle()
                compose.onAllNodes(isPopup(), useUnmergedTree = true).assertCountEquals(1)
                assertEquals("Real dismissal must retain its animated windows", initialWindows + 1, windowCount())
                compose.mainClock.advanceTimeBy(320)
                compose.waitForIdle()
                compose.onAllNodes(isPopup(), useUnmergedTree = true).assertCountEquals(0)
                assertEquals(initialWindows, windowCount())
            }
        } finally { compose.mainClock.autoAdvance = true }
    }
}
