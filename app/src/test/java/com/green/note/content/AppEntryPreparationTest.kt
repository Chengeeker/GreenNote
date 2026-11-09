package com.green.note.content

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h760dp-xxhdpi")
class AppEntryPreparationTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun leavesSourceVisibleUntilAppDetailIsReadyAndUsesPreparedResponseOnce() {
        val requests = AtomicInteger()
        val release = CompletableDeferred<Unit>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/apk/detail" && query["id"] == "example.prepared") {
                    requests.incrementAndGet()
                    release.await()
                    return JSONObject().put("data", JSONObject().put("apkname", "example.prepared").put("title", "准备好的应用"))
                }
                return JSONObject().put("data", JSONArray())
            }
        }
        compose.mainClock.autoAdvance = false
        compose.setContent {
            MaterialTheme {
                ContentApp(api, ContentSession("", "", "", false, false), {}, {}, { _, _, _ -> }, { _, _, _ -> }, {},
                    bottomBar = { _, _ -> }, externalDestination = ContentDestination("apk", "应用详情", "example.prepared"))
            }
        }
        compose.mainClock.advanceTimeBy(64)
        compose.waitUntil(timeoutMillis = 5000) { requests.get() == 1 }
        compose.onNodeWithText("头条").assertIsDisplayed()
        compose.onNodeWithText("应用详情").assertDoesNotExist()
        release.complete(Unit)
        compose.mainClock.autoAdvance = true
        compose.waitUntil(timeoutMillis = 5000) { compose.onAllNodesWithText("准备好的应用").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, requests.get())
    }
}
