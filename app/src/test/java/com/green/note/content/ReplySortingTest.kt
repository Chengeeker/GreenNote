package com.green.note.content

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import com.green.note.network.ApiException
import com.green.note.network.CaptchaChallenge
import com.green.note.network.CaptchaRequired
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
import java.util.concurrent.CopyOnWriteArrayList

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h760dp-xxhdpi")
class ReplySortingTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val feed = JSONObject("""{"id":"42","uid":"8","username":"作者","message":"正文","replynum":55}""")

    @Test fun uncachedEntryShowsCommentsBeforeAndAfterPostDetailIsBlocked() {
        val detail = CompletableDeferred<Unit>()
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls += path
                if (path == "/v6/feed/detail") {
                    detail.await()
                    throw CaptchaRequired(CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "当前访问需要验证码")
                }
                assertEquals("/v6/feed/hotReplyList", path)
                return response("热门")
            }
        }
        show(api, initialFeed = null)
        awaitText("热门评论")
        assertFalse(detail.isCompleted)
        detail.complete(Unit)
        awaitText("原帖暂不可用")
        compose.onNodeWithText("热门评论").assertIsDisplayed()
        assertEquals(1, calls.count { it == "/v6/feed/hotReplyList" })
    }

    @Test fun restoredDefaultStartsOneHotRequestWhenItsListIsBlockedAndUncached() {
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                calls += path
                if (path == "/v6/feed/hotReplyList") return response("热门")
                throw ApiException("当前访问需要验证码")
            }
        }
        val restoration = StateRestorationTester(compose)
        restoration.setContent { TestFeed(api, feed) }
        awaitText("热门评论")
        sort("默认").performClick()
        awaitText("当前排序暂不可用，已显示热门评论")
        calls.clear()
        restoration.emulateSavedInstanceStateRestore()
        awaitText("当前排序暂不可用，已显示热门评论")
        compose.onNodeWithText("热门评论").assertIsDisplayed()
        sort("默认").assertIsSelected()
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList"), calls.toList())
    }

    @Test fun blockedSortRecoversRecentReplyIdsThatArriveWithPostDetail() {
        val detail = CompletableDeferred<JSONObject>()
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return detail.await()
                calls += path
                return when (path) {
                    "/v6/feed/hotReplyList" -> JSONObject("""{"data":[],"hasMore":false}""")
                    "/v6/feed/replyList" -> throw ApiException("当前访问需要验证码")
                    "/v6/feed/replyDetail" -> {
                        assertEquals("6", query["id"])
                        JSONObject("""{"data":{"id":"6","feedid":"42","uid":"9","username":"读者","message":"稍后补读的评论"}}""")
                    }
                    else -> error("Unexpected request $path")
                }
            }
        }
        show(api)
        awaitText("暂无热门评论")
        sort("最新").performClick()
        awaitText("暂时无法加载评论")
        detail.complete(JSONObject("""{"data":{"id":"42","recent_reply_ids":"6"}}"""))
        awaitText("稍后补读的评论")
        awaitText("已显示部分评论，完整列表暂不可用")
        sort("最新").assertIsSelected()
        assertEquals(listOf("/v6/feed/hotReplyList", "/v6/feed/replyList", "/v6/feed/replyDetail"), calls.toList())
    }

    @Test fun plainCaptchaErrorStillShowsRepliesFromLaterPostDetail() {
        val detail = CompletableDeferred<JSONObject>()
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return detail.await()
                calls += path
                if (path == "/v6/feed/hotReplyList") return JSONObject("""{"data":[],"hasMore":false}""")
                throw ApiException("当前访问需要验证码")
            }
        }
        show(api)
        awaitText("暂无热门评论")
        sort("默认").performClick()
        awaitText("暂时无法加载评论")
        detail.complete(JSONObject("""{"data":{"id":"42","replyRows":[{"id":"6","uid":"9","username":"读者","message":"稍后收到的附带评论"}]}}"""))
        awaitText("稍后收到的附带评论")
        awaitText("已显示部分评论，完整列表暂不可用")
        sort("默认").assertIsSelected()
        compose.onNodeWithText("当前访问需要验证码").assertDoesNotExist()
        compose.onNodeWithText("已经到底了").assertDoesNotExist()
        assertEquals(listOf("/v6/feed/hotReplyList", "/v6/feed/replyList"), calls.toList())
    }

    @Test fun hotLoadsOnEntryAndItsRowsRemainVisibleWhenDefaultIsBlocked() {
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                calls += path
                if (path == "/v6/feed/hotReplyList") return response("热门")
                throw CaptchaRequired(CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "请完成验证")
            }
        }
        show(api)
        awaitText("热门评论")
        sort("热门").assertIsSelected()
        assertEquals(listOf("/v6/feed/hotReplyList"), calls.toList())
        sort("默认").performClick()
        awaitText("当前排序暂不可用，已显示热门评论")
        compose.onNodeWithText("热门评论").assertIsDisplayed()
        sort("默认").assertIsSelected()
        compose.onNodeWithText("查看热门评论").performClick()
        awaitText("热门评论")
        sort("热门").assertIsSelected()
        assertEquals(listOf("/v6/feed/hotReplyList", "/v6/feed/replyList"), calls.toList())
    }

    @Test fun emptyHotPageRecoversRecentReplyBodiesWithoutClaimingTheFullList() {
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject("""{"data":{"id":"42","recent_reply_ids":"6,6"}}""")
                calls += path
                if (path == "/v6/feed/hotReplyList") {
                    assertEquals(setOf("id", "page", "discussMode"), query.keys)
                    return JSONObject("""{"data":[]}""")
                }
                assertEquals("/v6/feed/replyDetail", path)
                assertEquals("6", query["id"])
                return JSONObject("""{"data":{"id":"6","feedid":"42","uid":"9","username":"读者","message":"普通帖子已有回复"}}""")
            }
        }
        show(api)
        awaitText("普通帖子已有回复")
        awaitText("已显示原帖附带的部分评论")
        compose.onNodeWithText("已经到底了").assertDoesNotExist()
        assertEquals(listOf("/v6/feed/hotReplyList", "/v6/feed/replyDetail"), calls.toList())
    }

    @Test fun allFiltersSwitchAndFailureCannotKeepHotSelectedOrReplaceTheRequestedOrder() {
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path.endsWith("/detail")) return JSONObject().put("data", feed)
                assertEquals("1", query["page"])
                assertNull(query["firstItem"]); assertNull(query["lastItem"])
                val mode = when {
                    path.endsWith("hotReplyList") -> "热门"
                    query["fromFeedAuthor"] == "1" -> "楼主"
                    query["listType"] == "dateline_desc" -> "最新"
                    else -> "默认"
                }
                calls += mode
                if (mode == "最新" && calls.count { it == mode } == 1) error("评论网络失败")
                return response(mode)
            }
        }
        show(api)
        awaitText("热门评论")
        sort("默认").performClick()
        awaitText("默认评论")
        compose.onNodeWithText("默认").assertIsSelected()
        compose.onNodeWithText("共 55 回复").assertIsDisplayed()
        compose.onNodeWithText("热门").performClick()
        awaitText("热门评论")
        compose.onNodeWithText("热门").assertIsSelected()
        compose.onNodeWithText("最新").performClick()
        awaitText("评论网络失败")
        compose.onNodeWithText("最新").assertIsSelected()
        compose.onNodeWithText("热门评论").assertDoesNotExist()
        compose.onNodeWithText("最新").performClick()
        awaitText("最新评论")
        sort("楼主").performClick()
        awaitText("楼主评论")
        sort("楼主").assertIsSelected()
        compose.onNodeWithText("默认").performClick()
        awaitText("默认评论")
        assertEquals(listOf("热门", "默认", "最新", "最新", "楼主"), calls.toList())
        compose.onNodeWithText("默认").performClick()
        compose.waitUntil(5000) { calls.count { it == "默认" } == 2 }
    }

    @Test fun switchingAwayCancelsPendingSortAndReturningCanRetryIt() {
        val pending = CompletableDeferred<Unit>()
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path.endsWith("/detail")) return JSONObject().put("data", feed)
                val mode = if (path.endsWith("hotReplyList")) "热门" else if (query["listType"] == "dateline_desc") "最新" else "默认"
                calls += mode
                if (mode == "最新") pending.await()
                return response(mode)
            }
        }
        show(api)
        awaitText("热门评论")
        compose.mainClock.autoAdvance = false
        try {
            sort("最新").performSemanticsAction(SemanticsActions.OnClick) { assertTrue(it()) }
            compose.waitUntil(5000) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle(); calls.contains("最新") }
            compose.onNodeWithText("最新").assertIsSelected()
            sort("热门").performSemanticsAction(SemanticsActions.OnClick) { assertTrue(it()) }
            compose.waitUntil(5000) {
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                sort("热门").fetchSemanticsNode().config[SemanticsProperties.Selected]
            }
        } finally {
            pending.complete(Unit)
            compose.mainClock.autoAdvance = true
        }
        awaitText("热门评论")
        compose.waitForIdle()
        compose.onNodeWithText("热门").assertIsSelected()
        compose.onNodeWithText("最新评论").assertDoesNotExist()
        compose.onNodeWithText("最新").performClick()
        awaitText("最新评论")
        assertEquals(2, calls.count { it == "最新" })
    }

    @Test fun shortPagesFillTheViewportWithoutRequiringAnotherScrollGesture() {
        val calls = CopyOnWriteArrayList<Int>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                val page = query.getValue("page").toInt()
                calls += page
                val rows = if (page <= 3) JSONArray().put(JSONObject().put("id", "$page").put("message", "短页$page")) else JSONArray()
                return JSONObject().put("data", rows)
            }
        }
        val state = ContentListState { page, first, last ->
            val root = api.request("/fixture", query = mapOf("page" to "$page", "firstItem" to first, "lastItem" to last))
            parsePage(root, page, allowShort = true)
        }
        compose.setContent { MaterialTheme {
            ContentList(api, state, {}, {}, {}, { _, _, _ -> }, {}, {}, itemContent = { androidx.compose.material3.Text(it.text("message")) })
        } }
        compose.waitUntil(5000) { calls.size == 4 }
        compose.waitForIdle()
        assertEquals(listOf(1, 2, 3, 4), calls.toList())
        assertEquals(3, state.rows.size)
        assertFalse(state.more)
    }

    private fun response(mode: String) = JSONObject().put("hasMore", false).put("data", JSONArray().put(
        JSONObject().put("id", "1").put("uid", "8").put("username", "作者").put("message", "${mode}评论")))

    private fun sort(label: String) = compose.onNode(hasText(label) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Selected))

    private fun show(api: ContentApi, initialFeed: JSONObject? = feed) {
        compose.setContent { TestFeed(api, initialFeed) }
    }

    @Composable
    private fun TestFeed(api: ContentApi, initialFeed: JSONObject?) {
        MaterialTheme {
            FeedDetailScreen(api, "42", ContentSession(authenticated = true, uid = "1"), {}, {}, {}, { _, _, _ -> }, {}, {}, {}, initialFeed = initialFeed)
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(5000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
        compose.onNodeWithText(text).assertIsDisplayed()
    }
}
