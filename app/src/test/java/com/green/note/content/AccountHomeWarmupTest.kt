package com.green.note.content

import android.app.Application
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.ConcurrentLinkedQueue

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h800dp-xxhdpi")
class AccountHomeWarmupTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun preparesVisibleCardsAndProfileBeforeFirstEntryAndReusesThem() {
        val hidden = "我关注的话题"
        compose.activity.getSharedPreferences("greennote_compose_account_dashboard", Context.MODE_PRIVATE)
            .edit().putString("hiddenCards", JSONArray(listOf(hidden)).toString()).commit()
        val requests = ConcurrentLinkedQueue<String>()
        val login = CompletableDeferred<Unit>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requests.add(path)
                return when (path) {
                    "/v6/account/checkLoginInfo" -> {
                        login.await()
                        JSONObject().put("data", JSONObject().put("username", "已登录的昵称"))
                    }
                    "/v6/user/space" -> JSONObject().put("data", JSONObject().put("feed", "1234").put("level", "6"))
                    "/v6/user/profile" -> JSONObject().put("data", JSONObject().put("fans", "123"))
                    else -> JSONObject().put("data", JSONArray())
                }
            }
        }
        val session = ContentSession(uid = "42", username = "已登录的昵称", authenticated = true)
        var open by mutableStateOf(false)
        lateinit var dashboard: AccountHomeState
        compose.setContent {
            MaterialTheme {
                val state = rememberAccountHome(api, session, LocalLifecycleOwner.current.lifecycle)
                SideEffect { dashboard = state }
                Box(Modifier.fillMaxSize()) {
                    if (open) AccountOverview(api, session, state, {}, { _, _ -> }, {}) {}
                }
            }
        }
        compose.waitUntil(timeoutMillis = 5000) { requests.isNotEmpty() }
        assertEquals(listOf("/v6/account/checkLoginInfo"), requests.toList())
        compose.runOnIdle {
            assertNull(dashboard.login)
            assertFalse(dashboard.canReadCard(1))
        }

        login.complete(Unit)
        compose.waitUntil(timeoutMillis = 5000) { requests.size == 7 }
        assertFalse(requests.contains("/v6/topic/myFollowTopicList"))
        compose.runOnIdle {
            assertEquals("1234", dashboard.profile.text("feed_num"))
            assertEquals(4, dashboard.previews.size)
            open = true
        }
        compose.onNodeWithText("已登录的昵称").assertIsDisplayed()
        compose.onNodeWithText(hidden).assertDoesNotExist()
        compose.onNodeWithText("1234").assertIsDisplayed()
        compose.runOnIdle { open = false }
        compose.waitForIdle()
        compose.runOnIdle { open = true }
        compose.onNodeWithText("1234").assertIsDisplayed()
        assertEquals(1, requests.count { it == "/v6/account/checkLoginInfo" })
        assertEquals(1, requests.count { it == "/v6/user/space" })
    }
}
