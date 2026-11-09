package com.green.note.content

import androidx.activity.ComponentActivity
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class DigitalHomeRetentionTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun slowPrimarySurvivesTabExitAndCardsAppearBeforeSlowAnonymousFollow() {
        val primary = CompletableDeferred<JSONObject>()
        val follow = CompletableDeferred<List<JSONObject>>()
        var calls = 0
        var followCalls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls++
                return primary.await()
            }
            override suspend fun localLibrary(field: String): List<JSONObject> { followCalls++; return follow.await() }
        }
        var showDigital by mutableStateOf(false)
        lateinit var state: ContentListState
        compose.setContent {
            state = rememberDigitalHomeState(api, ContentSession(anonymous = true), null)
            if (showDigital) ContentList(api, state, {}, {}, {}, { _, _, _ -> }, {}, {},
                modifier = Modifier.testTag("digital-content"), itemContent = { Text(it.text("title")) }, loadInitially = false)
            else Text("首页")
        }
        compose.waitUntil { calls == 1 && state.busy }
        // The original indeterminate spinner deliberately requests frames forever. Exercise a
        // bounded loading interval instead of asking an actively loading page to become idle.
        compose.mainClock.autoAdvance = false
        try {
            compose.runOnUiThread { showDigital = true }
            repeat(3) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle() }
            compose.onNodeWithTag("digital-content").assertIsDisplayed()
            compose.runOnUiThread { assertTrue(state.busy); assertEquals(1, calls) }
        } finally {
            compose.runOnUiThread { showDigital = false }
            repeat(2) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle() }
            compose.mainClock.autoAdvance = true
        }
        compose.waitForIdle()
        compose.runOnIdle {
            assertEquals(1, calls)
            assertTrue(state.busy)
            primary.complete(digitalHomeFixture())
        }
        compose.waitUntil { state.rows.any { it.text("title") == "首屏数据" } && followCalls == 1 }
        compose.runOnIdle {
            assertFalse("The slow follow must not keep the primary page busy", state.busy)
            assertFalse(follow.isCompleted)
            showDigital = true
        }
        compose.onNodeWithText("首屏数据").assertIsDisplayed()
        compose.runOnIdle { showDigital = false }
        compose.waitForIdle()
        compose.runOnIdle { showDigital = true }
        compose.onNodeWithText("首屏数据").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals("Re-entering must reuse the completed primary page", 1, calls)
            follow.complete(emptyList())
        }
        compose.waitUntil { !state.rows.first().optBoolean("_digitalFollowPending") }
        compose.runOnIdle { assertEquals(1, followCalls); assertNull(state.error) }
    }
}
