package com.green.note.content

import android.app.Application
import android.graphics.BitmapFactory
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import coil.Coil
import coil.ImageLoader
import com.green.note.R
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h800dp-mdpi")
class ComposerEmojiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var originalLoader: ImageLoader
    private lateinit var offlineLoader: ImageLoader
    private val networkAttempts = AtomicInteger()

    @Before fun disableImageNetwork() {
        originalLoader = Coil.imageLoader(compose.activity)
        val client = OkHttpClient.Builder().addInterceptor {
            networkAttempts.incrementAndGet()
            throw IOException("Image network disabled in test")
        }.build()
        offlineLoader = ImageLoader.Builder(compose.activity).diskCache(null).okHttpClient(client).build()
        Coil.setImageLoader(offlineLoader)
    }

    @After fun restoreImageLoader() {
        Coil.setImageLoader(originalLoader)
        offlineLoader.shutdown()
        assertEquals(0, networkAttempts.get())
    }

    @Test fun pickerAndLegacyNumberedImagesDecodeFromPackagedResources() {
        val resources = compose.activity.resources
        assertEquals(81, contentEmojiCodes.keys().asSequence().mapNotNull(::contentEmojiCode).filter { it in contentEmojiDrawables }.toSet().size)
        assertEquals(121, contentEmojiDrawables.size)
        assertEquals(121, contentEmojiDrawables.values.toSet().size)
        assertEquals(R.drawable.coolapk_emoji_40, contentEmojiDrawables[contentEmojiCode("[40]")])
        for ((code, drawable) in contentEmojiDrawables) {
            val bitmap = resources.openRawResource(drawable).use { BitmapFactory.decodeStream(it) }
            assertNotNull(code, bitmap)
            requireNotNull(bitmap)
            try {
                assertEquals(code, 96, bitmap.width)
                assertEquals(code, 96, bitmap.height)
            } finally {
                bitmap.recycle()
            }
        }
    }

    @Test fun commentInsertsTheEmojiAtTheSelectionAndSendsItsToken() {
        val sent = CompletableDeferred<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/reply") sent.complete(body?.get("message").orEmpty())
                return JSONObject()
            }
        }
        val draft = ReplyDraft().apply { message = TextFieldValue("甲原乙", TextRange(1, 2)) }
        compose.setContent {
            val scope = rememberCoroutineScope()
            var open by remember { mutableStateOf(true) }
            MaterialTheme {
                CompositionLocalProvider(LocalContentSession provides ContentSession(uid = "1", authenticated = true)) {
                    if (open) ReplyComposer(api, "42", "", draft, { open = false }, {}, scope)
                }
            }
        }
        compose.onNodeWithContentDescription("表情").performClick()
        compose.onNodeWithContentDescription("[滑稽]", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("滑稽").performClick()
        assertEquals(TextFieldValue("甲[滑稽]乙", TextRange(5)), draft.message)
        compose.onNodeWithText("发送").performClick()
        compose.waitUntil(timeoutMillis = 5000) { sent.isCompleted }
        assertEquals("甲[滑稽]乙", runBlocking { sent.await() })
    }

    @Test fun privateMessageCanSendAnEmojiBeyondTheFirstTwelveOptions() {
        val sent = CompletableDeferred<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject =
                JSONObject().put("data", JSONArray())

            override suspend fun submitMultipart(path: String, fields: Map<String, String>, query: Map<String, String>): JSONObject {
                if (path == "/v6/message/send") sent.complete(fields["message"].orEmpty())
                return JSONObject()
            }
        }
        compose.setContent {
            MaterialTheme {
                MessageChatScreen(api, ContentSession(uid = "1", authenticated = true), MessagePartner("42", "酷友", ""),
                    "test-chat", { _, _, _ -> }, {}, {}, {})
            }
        }
        compose.onNodeWithContentDescription("表情").performClick()
        compose.onNodeWithContentDescription("表情列表").performScrollToKey("[害羞]")
        compose.onNodeWithContentDescription("[害羞]", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("害羞").performClick()
        compose.onNodeWithContentDescription("发送私信").performClick()
        compose.waitUntil(timeoutMillis = 5000) { sent.isCompleted }
        assertEquals("[害羞]", runBlocking { sent.await() })
    }
}
