package com.green.note.content

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.ContextWrapper
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import com.green.note.settings.AppPreferences
import com.green.note.ui.LocalAppPreferences
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
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
class PromotionContentTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun feedHydrationKeepsExistingBodyWithoutCaptchaNotices() {
        val challenge = com.green.note.network.ApiException("当前访问需要验证码")
        val verifications = AtomicInteger()
        val commentPaths = java.util.concurrent.CopyOnWriteArrayList<String>()
        val seed = JSONObject("""{"id":"42","uid":"8","username":"作者","message":"可以继续阅读的正文"}""")
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") throw challenge
                commentPaths += path
                return JSONObject("""{"data":[{"id":"17","uid":"8","username":"作者","message":"可以继续阅读的评论"}],"hasMore":false}""")
            }
            override suspend fun verifyFeedDetail(id: String, challenge: com.green.note.network.CaptchaRequired): JSONObject {
                verifications.incrementAndGet()
                return JSONObject().put("data", JSONObject(seed.toString()).put("message", "验证后的完整正文"))
            }
        }
        compose.setContent { MaterialTheme {
            FeedDetailScreen(api, "42", ContentSession(uid = "1", authenticated = true), {}, {}, {}, { _, _, _ -> }, {}, {}, {}, initialFeed = seed)
        } }
        compose.waitUntil(5000) { commentPaths.isNotEmpty() }
        compose.waitForIdle()
        assertEquals(0, verifications.get())
        compose.onNodeWithText("可以继续阅读的正文").assertIsDisplayed()
        assertEquals("/v6/feed/replyList", commentPaths.first())
        compose.onNodeWithText("验证码", substring = true).assertDoesNotExist()
        compose.onNodeWithText("重新加载原帖").assertDoesNotExist()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
    }

    @Test fun missingFeedStillOffersExplicitVerification() {
        val challenge = com.green.note.network.CaptchaRequired(com.green.note.network.CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "当前访问需要验证码")
        val verifications = AtomicInteger()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") throw challenge
                return JSONObject("""{"data":[],"hasMore":false}""")
            }
            override suspend fun verifyFeedDetail(id: String, challenge: com.green.note.network.CaptchaRequired): JSONObject {
                verifications.incrementAndGet()
                return JSONObject("""{"data":{"id":"42","uid":"8","username":"作者","message":"验证后的完整正文"}}""")
            }
        }
        compose.setContent { MaterialTheme {
            FeedDetailScreen(api, "42", ContentSession(uid = "1", authenticated = true), {}, {}, {}, { _, _, _ -> }, {}, {}, {})
        } }
        compose.waitUntil(5000) { compose.onAllNodesWithText("完成验证并重试").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(0, verifications.get())
        compose.onNodeWithText("完成验证并重试").performClick()
        compose.waitUntil(5000) { compose.onAllNodesWithText("验证后的完整正文").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, verifications.get())
    }

    @Test fun longArticleOpensBeforeTheFullBodyReturns() {
        val seed = JSONObject("""{"id":"8","entityType":"feedarticle","uid":"80","username":"文章作者","title":"长文卡片","description":"列表摘要","issummary":1,"message":"已有正文","message_raw_output":[{"type":"text","text":"已有正文"}]}""")
        val fullBody = """<p>完整正文</p><img src="https://example.invalid/full.jpg">""" +
            (1..40).joinToString("") { "<p>这是一段很长的文章正文。第 ${it} 段。</p>" }
        val release = CompletableDeferred<Unit>()
        val requests = AtomicInteger()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail" && query["id"] == "8") {
                    requests.incrementAndGet()
                    release.await()
                    return JSONObject().put("data", JSONObject().put("id", "8").put("message", fullBody))
                }
                val rows = if (path == "/v6/main/headline" && query["page"] == "1") JSONArray().put(seed) else JSONArray()
                return JSONObject().put("data", rows)
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalAppPreferences provides AppPreferences(liquidGlassNavBar = false)) {
              MaterialTheme {
                ContentApp(api, ContentSession(anonymous = true), {}, {}, { _, _, _ -> }, { _, _, _ -> }, {},
                    bottomBar = { _, _ -> })
              }
            }
        }
        compose.waitUntil(timeoutMillis = 5000) { compose.onAllNodesWithText("长文卡片").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("长文卡片").performSemanticsAction(SemanticsActions.OnClick) { assertTrue(it()) }
        compose.waitUntil(timeoutMillis = 5000) { requests.get() == 1 }
        compose.mainClock.advanceTimeBy(300)
        compose.onNodeWithText("已有正文").assertIsDisplayed()
        compose.onNodeWithText("查看更多", substring = true).assertDoesNotExist()
        assertFalse(release.isCompleted)
        release.complete(Unit)
        compose.waitUntil(timeoutMillis = 5000) { compose.onAllNodesWithText("完整正文", substring = true).fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, requests.get())
        compose.onNodeWithText("共 0 回复").assertIsNotDisplayed()
        compose.onNodeWithText("评论").performSemanticsAction(SemanticsActions.OnClick) { assertTrue(it()) }
        compose.onNodeWithText("共 0 回复").assertIsDisplayed()
    }

    @Test fun partialTradeDetailRetainsProviderAndValidatesItsTargets() {
        val info = JSONObject("""{"deal_type":1,"product_price":"3650","province":"福建","city":"宁德","store_type_txt":"闲鱼","link_url":"https://m.tb.cn/h.example","link_app_url":"fleamarket://item?id=123"}""")
        val seed = JSONObject().put("ershou_info", info.toString())
        val detail = JSONObject("""{"ershou_info":{"product_title":"手机"}}""")
        val trade = requireNotNull(secondhandInfo(mergeFeedDetail(seed, detail)))
        assertEquals("手机", trade.title)
        assertEquals("3650", trade.price)
        assertEquals("福建 宁德", trade.location)
        assertTrue(trade.merchant)
        assertEquals(XianyuDestination("fleamarket://item?id=123", "https://m.tb.cn/h.example"), trade.destination)
        info.put("link_app_url", "javascript:alert(1)").put("link_url", "https://goofish.com.example.org/item")
        assertNull(secondhandInfo(JSONObject().put("ershou_info", info))?.destination)
        info.put("link_url", "https://www.goofish.com/item").put("is_link", 0)
        assertNull(secondhandInfo(JSONObject().put("ershou_info", info))?.destination)
    }

    @Test fun xianyuShortLinkOpensOnlyTheNativeItem() = runBlocking {
        val requested = mutableListOf<String>()
        val client = OkHttpClient.Builder().followRedirects(false).addInterceptor { chain ->
            val request = chain.request()
            requested.add(request.url.host)
            val response = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).message("Fixture")
            if (request.url.encodedPath == "/h.other") response.code(302)
                .header("Location", "https://www.goofish.com.example.invalid/item?id=123").body("".toResponseBody()).build()
            else response.code(200).body(
                """<script>var url = 'https://h5.m.goofish.com/item?forceFlush=1&itemId=123&hitNativeDetail=true';</script>""".toResponseBody()
            ).build()
        }.build()
        assertEquals("fleamarket://item?id=321", resolveXianyuItem(XianyuDestination(null, "https://www.goofish.com/item?id=321"), client))
        assertTrue(requested.isEmpty())
        val target = requireNotNull(resolveXianyuItem(XianyuDestination(null, "https://m.tb.cn/h.sample"), client))
        assertEquals("fleamarket://item?id=123", target)
        assertNull(resolveXianyuItem(XianyuDestination(null, "https://m.tb.cn/h.other"), client))
        assertEquals(listOf("m.tb.cn", "m.tb.cn"), requested)

        val intents = mutableListOf<Intent>()
        val missingApp = object : ContextWrapper(compose.activity) {
            override fun startActivity(intent: Intent) {
                intents.add(intent)
                throw ActivityNotFoundException()
            }
        }
        assertFalse(openXianyu(missingApp, target))
        val intent = intents.single()
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("com.taobao.idlefish", intent.`package`)
        assertEquals(target, intent.dataString)
    }

    @Test fun secondhandCardOpensDetailWithCarouselAndXianyuAction() {
        val row = JSONObject("""{"id":"91","entityType":"feed","username":"二手卖家","message":"商品描述","pic":"https://example.invalid/one.jpg,https://example.invalid/two.jpg","ershou_info":{"product_title":"闲置手机","product_price":"3650","deal_type":1,"province":"福建","city":"宁德","store_type_txt":"闲鱼","link_url":"https://m.tb.cn/h.example"}}""")
        val detail = CompletableDeferred<JSONObject>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail" && query["id"] == "91") return JSONObject().put("data", detail.await())
                val rows = if (query["url"] == "V11_DISCOVERY_SECOND_HAND" && query["page"] == "1") JSONArray().put(row) else JSONArray()
                return JSONObject().put("data", rows)
            }
        }
        compose.setContent {
            MaterialTheme {
                ContentApp(api, ContentSession(anonymous = true), {}, {}, { _, _, _ -> }, { _, _, _ -> }, {},
                    bottomBar = { _, select -> TextButton(onClick = { select(3) }) { androidx.compose.material3.Text("打开发现") } })
            }
        }
        compose.onNodeWithText("打开发现").performClick()
        compose.onNodeWithText("二手").performClick()
        compose.waitUntil(timeoutMillis = 5000) { compose.onAllNodesWithText("闲置手机").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("闲置手机").performClick()
        compose.onNodeWithText("去闲鱼").assertIsDisplayed()
        detail.complete(JSONObject("""{"id":"91","message":"刷新后的商品描述"}"""))
        compose.waitUntil(timeoutMillis = 5000) { compose.onAllNodesWithText("刷新后的商品描述").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("去闲鱼").assertIsDisplayed()
    }

    @Test fun emptyReplyContentUsesTheWholeWidth() {
        compose.setContent { MaterialTheme { Box(Modifier.fillMaxSize()) { FeedRepliesEmpty(false, false) } } }
        val root = compose.onRoot().fetchSemanticsNode().boundsInRoot
        val message = compose.onNodeWithText("还没有回复哦，快来回复一下吧~").fetchSemanticsNode().boundsInRoot
        assertEquals(root.center.x, message.center.x, 1f)
        assertTrue(message.width > root.width * .85f)
    }
}
