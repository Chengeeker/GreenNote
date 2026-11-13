package com.green.note.content

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.green.note.settings.AppPreferences
import com.green.note.ui.LocalAppPreferences
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
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h760dp-xxhdpi")
class CommentImportNavigationUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun importKeepsTheOriginalPostAcrossOwnerMigrationButARealAccountSwitchRemovesIt() {
        val owner = mutableStateOf("account-a-device-original")
        val session = mutableStateOf(ContentSession(uid = "7", username = "A", authenticated = true))
        val recovery = mutableStateOf(CommentDeviceRecovery(imported = false, onImport = {}))
        val destination = mutableStateOf<ContentDestination?>(ContentDestination("feed", "动态详情", "42"))
        val detailRequests = AtomicInteger()
        val refreshedDetail = CompletableDeferred<JSONObject>()
        val feed = JSONObject("""{"id":"42","uid":"8","username":"作者","message":"导入前已经读到的原帖正文","replynum":0}""")
        val api = object : ContentApi {
            override fun imageCacheScope(): String = owner.value
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail" && query["id"] == "42") {
                    if (detailRequests.incrementAndGet() == 1) return JSONObject().put("data", feed)
                    // A slow refresh must not hide the existing body or navigate away from this post.
                    return refreshedDetail.await()
                }
                return JSONObject().put("data", JSONArray())
            }
        }
        compose.setContent {
            MaterialTheme {
                CompositionLocalProvider(
                    LocalAppPreferences provides AppPreferences(liquidGlassNavBar = false),
                    LocalCommentDeviceRecovery provides recovery.value,
                ) {
                    ContentApp(api, session.value, {}, {}, { _, _, _ -> }, { _, _, _ -> }, {},
                        bottomBar = { _, _ -> }, externalDestination = destination.value,
                        onExternalDestinationConsumed = { destination.value = null },
                        preserveCommentNavigation = recovery.value.preserveOwner)
                }
            }
        }
        try {
            awaitBody()
            compose.runOnIdle { assertNull(destination.value) }
            assertEquals(1, detailRequests.get())

            compose.runOnIdle { recovery.value = recovery.value.copy(importing = true, preserveOwner = true) }
            compose.waitForIdle()
            compose.runOnIdle { owner.value = "account-a-device-imported" }
            compose.waitForIdle()
            compose.onNodeWithText("导入前已经读到的原帖正文").assertIsDisplayed()
            assertEquals("The intermediate epoch must not start another detail request", 1, detailRequests.get())

            compose.runOnIdle {
                recovery.value = recovery.value.copy(imported = true, importing = false, revision = 1)
            }
            compose.waitUntil(5000) { detailRequests.get() == 2 }
            compose.onNodeWithText("导入前已经读到的原帖正文").assertIsDisplayed()
            assertFalse(refreshedDetail.isCompleted)

            compose.runOnIdle {
                session.value = ContentSession(uid = "9", username = "B", authenticated = true)
                owner.value = "account-b-device-imported"
                recovery.value = recovery.value.copy(preserveOwner = false)
            }
            compose.waitForIdle()
            compose.onNodeWithText("导入前已经读到的原帖正文").assertDoesNotExist()
            assertEquals("The consumed external destination must not reopen the previous account's post", 2, detailRequests.get())
        } finally {
            refreshedDetail.complete(JSONObject().put("data", feed))
        }
    }

    private fun awaitBody() {
        compose.waitUntil(5000) {
            compose.onAllNodesWithText("导入前已经读到的原帖正文").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("导入前已经读到的原帖正文").assertIsDisplayed()
    }
}
