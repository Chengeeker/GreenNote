package com.green.note.ui

import android.view.HapticFeedbackConstants
import android.view.ViewGroup
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import com.green.note.settings.AppPreferences
import com.green.note.settings.NotificationSettingsScreen
import com.green.note.settings.ReplyReminderSettings
import java.time.Duration
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowSystemClock
import org.robolectric.shadows.ShadowViewGroup

/** Observe attached Activity/Dialog/Popup views without replacing their window or lifecycle. */
@Implements(ViewGroup::class)
class SettingsFeedbackViewShadow : ShadowViewGroup() {
    companion object { val pulses = mutableListOf<Int>() }
    @Implementation
    override fun performHapticFeedback(feedbackConstant: Int): Boolean {
        pulses += feedbackConstant
        return super.performHapticFeedback(feedbackConstant)
    }
}

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-mdpi", shadows = [SettingsFeedbackViewShadow::class])
class SettingsHapticInteractionTest {
    companion object { private var testEpoch = Duration.ofDays(1).toMillis() }
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val pulses get() = SettingsFeedbackViewShadow.pulses

    @Before fun isolateHostClockAndFeedback() {
        // Keep the host's public clock monotonic across fixtures without touching the real gate.
        testEpoch = maxOf(testEpoch, SystemClock.elapsedRealtime()) + 60_000L
        ShadowSystemClock.advanceBy(Duration.ofMillis(testEpoch - SystemClock.elapsedRealtime()))
        pulses.clear()
    }

    @Composable private fun Host(enabled: Boolean = true, content: @Composable () -> Unit) {
        MaterialTheme {
            CompositionLocalProvider(LocalAppPreferences provides AppPreferences(haptics = enabled), content = content)
        }
    }

    private fun nextGesture() {
        ShadowSystemClock.advanceBy(Duration.ofMillis(80))
        compose.mainClock.advanceTimeBy(80)
    }

    private fun tap(text: String) {
        nextGesture()
        compose.onNodeWithText(text).performTouchInput { click() }
        compose.waitForIdle()
    }

    @Test fun rowsAndButtonsOnlyPulseOnConfirmedEnabledClickIncludingReselection() {
        var enabled by mutableStateOf(true)
        var preferences = 0
        var choices = 0
        var buttons = 0
        var checked by mutableStateOf(false)
        compose.setContent { Host(enabled) { Column {
            PreferenceRow("打开设置", onClick = { preferences++ })
            PreferenceRow("不可点击", enabled = false, onClick = { fail("Disabled row fired") })
            ChoiceRow("当前选项", selected = true, onClick = { choices++ })
            SwitchRow("开关行", checked, { checked = it })
            ReviewButton(onClick = { buttons++ }) { ReviewText("保存") }
        } } }
        val row = compose.onNodeWithText("打开设置")
        row.performTouchInput { down(center) }
        compose.runOnIdle { assertTrue(pulses.isEmpty()); assertEquals(0, preferences) }
        row.performTouchInput { cancel() }
        compose.runOnIdle { assertTrue(pulses.isEmpty()) }
        tap("打开设置")
        assertEquals(1, preferences)
        assertEquals(1, pulses.size)
        tap("当前选项")
        assertEquals("Reselection keeps the no-write behavior", 0, choices)
        assertEquals(2, pulses.size)
        tap("开关行")
        assertTrue(checked)
        assertEquals("Nested switch/row must not double pulse", 3, pulses.size)
        tap("保存")
        assertEquals(1, buttons)
        assertEquals(4, pulses.size)
        tap("不可点击")
        assertEquals(4, pulses.size)
        compose.runOnIdle { enabled = false }
        tap("打开设置")
        tap("保存")
        assertEquals(2, preferences)
        assertEquals(2, buttons)
        assertEquals("Global setting suppresses feedback, not the action", 4, pulses.size)
    }

    @Test fun glassMaterialEntrySelectionAndCancelEachUseTheSharedFeedback() {
        var selected by mutableStateOf(false)
        var writes = 0
        compose.setContent { Host { NavigationGlassChoice(selected) { selected = it; writes++ } } }
        tap("底栏玻璃样式")
        assertEquals(1, pulses.size)
        tap("经典玻璃")
        assertTrue(selected)
        assertEquals(1, writes)
        assertEquals(2, pulses.size)
        tap("底栏玻璃样式")
        tap("取消")
        assertEquals(4, pulses.size)
        assertEquals(1, writes)
    }

    @Test fun actualNotificationDropdownAnchorAndSelectionPulseButBusyDoesNot() {
        var settings by mutableStateOf(ReplyReminderSettings())
        var busy by mutableStateOf(false)
        compose.setContent { Host { NotificationSettingsScreen(settings, true, true, false,
            "暂无记录", null, busy, { settings = it }, {}, {}, {}, {}) } }
        tap("后台检查方式")
        assertEquals(1, pulses.size)
        tap("常驻后台检查")
        assertTrue(settings.resident)
        assertEquals(2, pulses.size)
        compose.runOnIdle { busy = true }
        tap("后台检查方式")
        assertEquals(2, pulses.size)
    }

    @Test fun sliderTicksOnlyForActualHorizontalStepsNotDownSameStepScrollOrProgrammaticChanges() {
        var value by mutableFloatStateOf(0f)
        var haptics by mutableStateOf(true)
        var enabled by mutableStateOf(true)
        compose.setContent { Host(haptics) {
            ReviewSlider(value, { value = it }, Modifier.width(300.dp).testTag("slider"),
                divisions = 10, label = null, enabled = enabled)
        } }
        val slider = compose.onNodeWithTag("slider")
        slider.performTouchInput { down(Offset(24f, 24f)) }
        compose.runOnIdle { assertTrue(pulses.isEmpty()) }
        slider.performTouchInput { moveTo(Offset(24f, 90f)); up() }
        compose.runOnIdle { assertTrue("Vertical scroll must not pulse", pulses.isEmpty()) }
        nextGesture()
        slider.performTouchInput { down(Offset(24f, 24f)); moveTo(Offset(80f, 24f)) }
        compose.runOnIdle { assertEquals(1, pulses.size) }
        nextGesture()
        slider.performTouchInput { moveTo(Offset(82f, 24f)) }
        compose.runOnIdle { assertEquals("Motion inside one discrete step must stay silent", 1, pulses.size) }
        nextGesture()
        slider.performTouchInput { moveTo(Offset(130f, 24f)); up() }
        compose.runOnIdle {
            assertEquals(2, pulses.size)
            assertTrue(pulses.all { it == HapticFeedbackConstants.CLOCK_TICK })
            value = .8f
        }
        compose.waitForIdle()
        assertEquals("Programmatic value is not user interaction", 2, pulses.size)
        compose.runOnIdle { haptics = false }
        nextGesture()
        slider.performTouchInput { click(Offset(24f, 24f)) }
        compose.runOnIdle { assertEquals(0f, value, .001f); assertEquals(2, pulses.size) }
        compose.runOnIdle { haptics = true; enabled = false }
        nextGesture()
        slider.performTouchInput { click(Offset(240f, 24f)) }
        compose.runOnIdle { assertEquals("Disabled slider cannot update", 0f, value, .001f); assertEquals(2, pulses.size) }
    }

    @Test fun switchDragPulsesAtConfirmedReleaseNotDownOrCancelledDrag() {
        var checked by mutableStateOf(false)
        compose.setContent { Host { ReviewSwitch(checked, { checked = it }, Modifier.testTag("switch")) } }
        val control = compose.onNodeWithTag("switch")
        control.performTouchInput { down(Offset(20f, 24f)); moveTo(Offset(56f, 24f)) }
        compose.runOnIdle { assertTrue(pulses.isEmpty()) }
        control.performTouchInput { up() }
        compose.waitForIdle()
        assertTrue(checked)
        assertEquals(1, pulses.size)
        nextGesture()
        control.performTouchInput { down(Offset(40f, 24f)); moveTo(Offset(4f, 24f)); cancel() }
        compose.waitForIdle()
        assertEquals("Cancellation is not a confirmed drag release", 1, pulses.size)
    }
}
