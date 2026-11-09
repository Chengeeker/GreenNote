package com.green.note.content

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import kotlinx.coroutines.runBlocking
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
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h760dp-xxhdpi")
class PromotionContentTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun summaryOpensWithServerBodyInsteadOfPreviewBlocks() = runBlocking {
        val seed = JSONObject("""{"id":"8","issummary":1,"message":"摘要","message_raw_output":[{"type":"text","text":"摘要"}]}""")
        val fullBody = """<p>完整正文</p><img src="https://example.org/full.jpg">"""
        var requests = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requests++
                assertEquals("/v6/feed/detail", path)
                assertEquals("8", query["id"])
                return JSONObject().put("data", JSONObject().put("id", "8").put("message", fullBody))
            }
        }
        assertTrue(needsFullFeedOnOpen(seed))
        assertFalse(needsFullFeedOnOpen(JSONObject().put("message", "短帖")))
        val prepared = prepareFeedDetail(api, "8", seed)
        assertEquals(1, requests)
        assertEquals(fullBody, prepared.feed.getString("message"))
        assertFalse(prepared.feed.has("message_raw_output"))
        assertTrue(prepared.parts.any { it.url == "https://example.org/full.jpg" })
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

    @Test fun emptyReplyContentUsesTheWholeWidth() {
        compose.setContent { MaterialTheme { Box(Modifier.fillMaxSize()) { FeedRepliesEmpty(false, false) } } }
        val root = compose.onRoot().fetchSemanticsNode().boundsInRoot
        val message = compose.onNodeWithText("还没有回复哦，快来回复一下吧~").fetchSemanticsNode().boundsInRoot
        assertEquals(root.center.x, message.center.x, 1f)
        assertTrue(message.width > root.width * .85f)
    }
}
