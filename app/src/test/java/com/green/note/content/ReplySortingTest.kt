package com.green.note.content

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
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
import com.green.note.network.CommentCaptchaRequest
import com.green.note.network.UnsupportedCaptcha
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import okhttp3.HttpUrl.Companion.toHttpUrl
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
import java.util.concurrent.atomic.AtomicInteger

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
                assertEquals("/v6/feed/replyList", path)
                assertEquals("lastupdate_desc", query["listType"])
                return response("默认")
            }
        }
        show(api, initialFeed = null)
        awaitText("默认评论")
        assertFalse(detail.isCompleted)
        detail.complete(Unit)
        awaitText("原帖暂不可用")
        compose.onNodeWithText("默认评论").assertIsDisplayed()
        sort("默认").assertIsSelected()
        assertEquals(1, calls.count { it == "/v6/feed/replyList" })
        assertEquals(0, calls.count { it == "/v6/feed/hotReplyList" })
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
        awaitText("当前排序暂不可用，已显示热门评论")
        sort("默认").assertIsSelected()
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList"), calls.toList())
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
                    "/v6/feed/replyList" -> if (query["listType"] == "dateline_desc") {
                        throw ApiException("当前访问需要验证码")
                    } else response("默认")
                    "/v6/feed/replyDetail" -> {
                        assertEquals("6", query["id"])
                        JSONObject("""{"data":{"id":"6","feedid":"42","uid":"9","username":"读者","message":"稍后补读的评论"}}""")
                    }
                    else -> error("Unexpected request $path")
                }
            }
        }
        show(api)
        awaitText("默认评论")
        sort("最新").performClick()
        awaitText("暂时无法加载评论")
        detail.complete(JSONObject("""{"data":{"id":"42","recent_reply_ids":"6"}}"""))
        awaitText("稍后补读的评论")
        awaitText("已显示部分评论，完整列表暂不可用")
        sort("最新").assertIsSelected()
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/feed/replyDetail"), calls.toList())
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
        awaitText("暂时无法加载评论")
        detail.complete(JSONObject("""{"data":{"id":"42","replyRows":[{"id":"6","uid":"9","username":"读者","message":"稍后收到的附带评论"}]}}"""))
        awaitText("稍后收到的附带评论")
        awaitText("已显示部分评论，完整列表暂不可用")
        sort("默认").assertIsSelected()
        compose.onNodeWithText("当前访问需要验证码").assertDoesNotExist()
        compose.onNodeWithText("已经到底了").assertDoesNotExist()
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList"), calls.toList())
    }

    @Test fun defaultEntryKeepsItsSelectionWhenOnlyHotPreviewCanLoad() {
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
        awaitText("当前排序暂不可用，已显示热门评论")
        compose.onNodeWithText("热门评论").assertIsDisplayed()
        sort("默认").assertIsSelected()
        compose.onNodeWithText("查看热门评论").assertDoesNotExist()
        sort("热门").performClick()
        awaitText("热门评论")
        sort("热门").assertIsSelected()
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList"), calls.toList())
    }

    @Test fun emptyHotPageRecoversRecentReplyBodiesWithoutClaimingTheFullList() {
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject("""{"data":{"id":"42","recent_reply_ids":"6,6"}}""")
                calls += path
                if (path == "/v6/feed/replyList") return response("默认")
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
        awaitText("默认评论")
        sort("热门").performClick()
        awaitText("普通帖子已有回复")
        awaitText("已显示原帖附带的部分评论")
        compose.onNodeWithText("已经到底了").assertDoesNotExist()
        sort("热门").assertIsSelected()
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/feed/replyDetail"), calls.toList())
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
        assertEquals(listOf("默认", "热门", "最新", "最新", "楼主"), calls.toList())
        compose.onNodeWithText("默认").performClick()
        compose.waitUntil(5000) { calls.count { it == "默认" } == 2 }
    }

    @Test fun switchingAwayCancelsPendingSortAndReturningCanRetryIt() {
        val pending = CompletableDeferred<Unit>()
        val cancelled = CompletableDeferred<Unit>()
        val calls = CopyOnWriteArrayList<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path.endsWith("/detail")) return JSONObject().put("data", feed)
                val mode = if (path.endsWith("hotReplyList")) "热门" else if (query["listType"] == "dateline_desc") "最新" else "默认"
                calls += mode
                if (mode == "最新") try { pending.await() } catch (failure: CancellationException) {
                    cancelled.complete(Unit)
                    throw failure
                }
                return response(mode)
            }
        }
        show(api)
        awaitText("默认评论")
        sort("热门").performClick()
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
            compose.waitUntil(5000) {
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                cancelled.isCompleted
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

    @Test fun commentListVerificationIsExplicitAndRestoresTheRequestedDefaultSort() {
        val expectedChallenge = commentChallenge("replyList?id=42&page=1&listType=lastupdate_desc")
        val calls = CopyOnWriteArrayList<String>()
        val verificationCalls = AtomicInteger()
        var verified = false
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) {
                assertSame(expectedChallenge, challenge)
                verificationCalls.incrementAndGet()
                verified = true
            }

            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                calls += path
                if (path == "/v6/feed/hotReplyList") return response("热门")
                assertEquals("/v6/feed/replyList", path)
                assertEquals("lastupdate_desc", query["listType"])
                assertEquals("1", query["page"])
                assertNull(query["firstItem"])
                assertNull(query["lastItem"])
                if (!verified) throw expectedChallenge
                return response("默认")
            }
        }

        show(api)
        awaitText("当前排序暂不可用，已显示热门评论")
        awaitText("完成验证并重试")
        sort("默认").assertIsSelected()
        assertEquals(0, verificationCalls.get())
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList"), calls.toList())

        compose.onNodeWithText("完成验证并重试").performClick()
        awaitText("默认评论")
        sort("默认").assertIsSelected()
        compose.onNodeWithText("热门评论").assertDoesNotExist()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        assertEquals(1, verificationCalls.get())
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/feed/replyList"), calls.toList())
    }

    @Test fun hydrationVerificationKeepsReadableCommentsAndResumesTheSamePage() {
        val expectedChallenge = commentChallenge("replyDetail?id=2")
        val verificationGate = CompletableDeferred<Unit>()
        val verificationCalls = AtomicInteger()
        val listQueries = CopyOnWriteArrayList<Map<String, String>>()
        val detailCalls = AtomicInteger()
        var verified = false
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) {
                assertSame(expectedChallenge, challenge)
                verificationCalls.incrementAndGet()
                verificationGate.await()
                verified = true
            }

            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                return when (path) {
                    "/v6/feed/detail" -> JSONObject().put("data", feed)
                    "/v6/feed/replyList" -> {
                        listQueries += query.toMap()
                        JSONObject("""{"hasMore":false,"data":[
                            {"id":"1","feedid":"42","uid":"8","username":"作者","message":"已经可读的普通评论","replynum":0},
                            {"id":"2","feedid":"42","uid":"9","username":"读者","entityType":"feed_reply"}
                        ]}""")
                    }
                    "/v6/feed/replyDetail" -> {
                        assertEquals("2", query["id"])
                        detailCalls.incrementAndGet()
                        if (!verified) throw expectedChallenge
                        JSONObject("""{"data":{"id":"2","feedid":"42","uid":"9","username":"读者","message":"补全的纯评论","replynum":0}}""")
                    }
                    else -> error("Unexpected request $path")
                }
            }
        }

        show(api)
        awaitText("已经可读的普通评论")
        awaitText("完成验证并重试")
        awaitText("还有 1 条评论等待补全")
        compose.onNodeWithText("已经到底了").assertDoesNotExist()
        assertEquals(0, verificationCalls.get())
        assertEquals(1, listQueries.size)
        assertEquals(1, detailCalls.get())

        try {
            compose.onNodeWithText("完成验证并重试").performClick()
            awaitText("正在验证")
            compose.onNodeWithText("已经可读的普通评论").assertIsDisplayed()
            sort("默认").assertIsSelected()
            assertEquals(1, verificationCalls.get())
            assertEquals(1, listQueries.size)
        } finally {
            verificationGate.complete(Unit)
        }

        awaitText("补全的纯评论")
        compose.onNodeWithText("已经可读的普通评论").assertIsDisplayed()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        compose.onNodeWithText("还有 1 条评论等待补全").assertDoesNotExist()
        sort("默认").assertIsSelected()
        assertEquals(1, verificationCalls.get())
        assertEquals(2, detailCalls.get())
        assertEquals(2, listQueries.size)
        assertEquals(listQueries[0], listQueries[1])
        assertEquals("1", listQueries[1]["page"])
        assertEquals("lastupdate_desc", listQueries[1]["listType"])
    }

    @Test fun unsupportedCaptchaExplainsTheMissingChallengeWithoutOfferingFakeVerification() {
        val unavailable = UnsupportedCaptcha()
        val calls = CopyOnWriteArrayList<String>()
        val verificationCalls = AtomicInteger()
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) {
                verificationCalls.incrementAndGet()
                error("Unsupported captcha must never open verification")
            }

            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                calls += path
                if (path == "/v6/feed/hotReplyList") return response("热门")
                assertEquals("/v6/feed/replyList", path)
                throw unavailable
            }
        }

        show(api)
        awaitText("服务器要求人机验证，但暂未提供可用的验证参数。")
        awaitText("热门评论")
        sort("默认").assertIsSelected()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        compose.onNodeWithText("正在验证").assertDoesNotExist()
        assertEquals(0, verificationCalls.get())

        compose.onNodeWithText("重试").performClick()
        compose.waitUntil(5000) { calls.count { it == "/v6/feed/replyList" } == 2 }
        awaitText("服务器要求人机验证，但暂未提供可用的验证参数。")
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        assertEquals(0, verificationCalls.get())
        assertEquals(listOf("/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/feed/replyList"), calls.toList())
    }

    @Test fun localDeviceImportPreservesLatestRowsAndReloadsOnceOnlyAfterSuccess() {
        val required = commentChallenge("replyDetail?id=2")
        val reload = CompletableDeferred<JSONObject>()
        val listCalls = CopyOnWriteArrayList<String>()
        val requestEvents = CopyOnWriteArrayList<String>()
        val importCalls = AtomicInteger()
        val verificationCalls = AtomicInteger()
        var owner by mutableStateOf("original-device")
        var imported = false
        lateinit var recovery: MutableState<CommentDeviceRecovery>
        recovery = mutableStateOf(CommentDeviceRecovery(false, onImport = {
            importCalls.incrementAndGet()
            recovery.value = recovery.value.copy(importing = true, preserveOwner = true)
        }))
        val api = object : ContentApi {
            override fun imageCacheScope() = owner
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) {
                verificationCalls.incrementAndGet()
                error("Import must not open verification")
            }
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requestEvents += "$owner $path page=${query["page"]} order=${query["listType"]} start"
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                if (path == "/v6/feed/replyDetail") throw required
                assertEquals("/v6/feed/replyList", path)
                val order = query.getValue("listType")
                listCalls += order
                assertEquals("1", query["page"])
                if (order == "lastupdate_desc") return response("默认")
                if (imported) return try { reload.await() } catch (cancelled: CancellationException) {
                    requestEvents += "$owner $path cancelled"
                    throw cancelled
                }
                return JSONObject("""{"hasMore":false,"data":[
                    {"id":"1","feedid":"42","uid":"9","username":"读者","message":"已加载的最新评论","replynum":0},
                    {"id":"2","feedid":"42","uid":"9","username":"读者","entityType":"feed_reply"}
                ]}""")
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides recovery.value) { TestFeed(api, feed) }
        }
        awaitText("默认评论")
        sort("最新").performClick()
        awaitText("导入本机设备标识")
        awaitText("已加载的最新评论")
        compose.onNodeWithText("重试").assertDoesNotExist()
        compose.onNodeWithText("导入本机设备标识").performClick()
        compose.runOnIdle { recovery.value = recovery.value.copy(importing = false, preserveOwner = false) }
        awaitText("导入本机设备标识")
        assertEquals(1, listCalls.count { it == "dateline_desc" })
        sort("最新").assertIsSelected()
        compose.onNodeWithText("正文").assertIsDisplayed()

        compose.onNodeWithText("导入本机设备标识").performClick()
        compose.runOnIdle { owner = "device-epoch-updated" }
        compose.waitForIdle()
        assertEquals(1, listCalls.count { it == "dateline_desc" })
        compose.onNodeWithText("已加载的最新评论").assertIsDisplayed()
        val restored = JSONObject("""{"hasMore":false,"data":[
            {"id":"1","uid":"9","username":"读者","message":"已加载的最新评论","replynum":0},
            {"id":"2","uid":"9","username":"读者","message":"恢复的最新评论","replynum":0}
        ]}""")
        compose.mainClock.autoAdvance = false
        try {
            compose.runOnUiThread {
                owner = "imported-device"
                imported = true
                recovery.value = recovery.value.copy(imported = true, importing = false, revision = 1, preserveOwner = true)
            }
            try { compose.waitUntil(5000) {
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                listCalls.count { it == "dateline_desc" } == 2
            } }
            catch (timeout: androidx.compose.ui.test.ComposeTimeoutException) {
                throw AssertionError("Expected 2 latest comment requests, observed ${listCalls.toList()}; fixture events: ${requestEvents.toList()}", timeout)
            }
            compose.onNodeWithText("已加载的最新评论").assertIsDisplayed()
            sort("最新").assertIsSelected()
            reload.complete(restored)
            compose.waitUntil(5000) {
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
                compose.onAllNodesWithText("恢复的最新评论").fetchSemanticsNodes().isNotEmpty()
            }
        } finally {
            reload.complete(restored)
            compose.mainClock.autoAdvance = true
        }
        awaitText("恢复的最新评论")
        compose.onNodeWithText("正文").assertIsDisplayed()
        compose.onNodeWithText("导入本机设备标识").assertDoesNotExist()
        sort("最新").assertIsSelected()
        assertEquals(listOf("lastupdate_desc", "dateline_desc", "dateline_desc"), listCalls.toList())
        assertEquals(2, importCalls.get())
        assertEquals(0, verificationCalls.get())
    }

    @Test fun recoveryActionsAppearBeforeTenHotPreviewRowsWithoutDuplicateButtons() {
        val required = commentChallenge("replyList?id=42")
        val verifyCalls = AtomicInteger()
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) { verifyCalls.incrementAndGet() }
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                if (path == "/v6/feed/replyList") throw required
                assertEquals("/v6/feed/hotReplyList", path)
                return JSONObject().put("hasMore", false).put("data", JSONArray().apply {
                    repeat(10) { index -> put(JSONObject().put("id", "${index + 10}").put("uid", "9")
                        .put("username", "读者").put("message", "热门预览${index + 1}")) }
                })
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides CommentDeviceRecovery(false, {})) { TestFeed(api, feed) }
        }
        awaitText("当前排序暂不可用，已显示热门评论")
        compose.onNodeWithText("导入本机设备标识").assertIsDisplayed()
        compose.onNodeWithText("完成验证并重试").assertIsDisplayed()
        compose.onNodeWithText("重试").assertDoesNotExist()
        compose.onNodeWithText("查看热门评论").assertDoesNotExist()
        compose.onNodeWithText("热门预览10").assertDoesNotExist()
        sort("默认").assertIsSelected()
        assertEquals(0, verifyCalls.get())
    }

    private fun commentChallenge(route: String) = CaptchaRequired(
        CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "当前访问需要验证码",
        CommentCaptchaRequest("https://api.coolapk.com/v6/feed/$route".toHttpUrl(), false, Any()),
    )

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
