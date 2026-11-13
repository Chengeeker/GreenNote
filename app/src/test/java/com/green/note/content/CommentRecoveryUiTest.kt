package com.green.note.content

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.inspector.WindowInspector
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
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
@Config(sdk = [35], application = Application::class, qualifiers = "zh-rCN-w360dp-h800dp-mdpi")
class CommentRecoveryUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val unusedApi = object : ContentApi {
        override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject =
            error("Unexpected request")
    }

    @Test fun childReplyImportHidesTheSheetAndCancellationKeepsItsRowsWithoutReloading() {
        val required = challenge("replyList?id=5&feedType=feed_reply")
        val reload = CompletableDeferred<JSONObject>()
        val calls = AtomicInteger()
        val imports = AtomicInteger()
        var imported = false
        var root by mutableStateOf(JSONObject("""{"id":"5","feedid":"42","uid":"8","username":"作者",
            "message":"父评论","replynum":2,"replyRowsMore":2,"replyRows":[
            {"id":"6","uid":"9","username":"读者","message":"已读子评论"}]}"""))
        lateinit var recovery: MutableState<CommentDeviceRecovery>
        recovery = mutableStateOf(CommentDeviceRecovery(false, onImport = {
            imports.incrementAndGet()
            recovery.value = recovery.value.copy(importing = true, preserveOwner = true)
        }))
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                assertEquals("/v6/feed/replyList", path)
                assertEquals("5", query["id"])
                assertEquals("feed_reply", query["feedType"])
                assertEquals("1", query["page"])
                calls.incrementAndGet()
                if (!imported) throw required
                return reload.await()
            }
        }
        compose.setContent { MaterialTheme {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides recovery.value) {
                Column {
                    if (recovery.value.importing) Text("本机导入页")
                    ReplyRow(api, root, {}, {}, { _, _, _ -> })
                }
            }
        } }
        compose.onNodeWithText("共 2 条回复 >").performClick()
        awaitText("导入本机设备标识")
        expandReplySheet()
        showDialogText("已读子评论")
        showDialogText("导入本机设备标识").performClick()
        awaitText("本机导入页")
        compose.onNodeWithText("查看原动态").assertDoesNotExist()
        compose.runOnIdle { recovery.value = recovery.value.copy(importing = false, preserveOwner = false) }
        awaitText("导入本机设备标识")
        expandReplySheet()
        compose.onNodeWithText("查看原动态").assertIsDisplayed()
        showDialogText("已读子评论")
        assertEquals(1, calls.get())

        showDialogText("导入本机设备标识").performClick()
        awaitText("本机导入页")
        val restored = JSONObject("""{"hasMore":false,"data":[
            {"id":"6","uid":"9","username":"读者","message":"已读子评论"},
            {"id":"7","uid":"10","username":"另一位读者","message":"恢复的子评论"}]}""")
        compose.mainClock.autoAdvance = false
        try {
            compose.runOnUiThread {
                imported = true
                root = JSONObject(root.toString()).put("message", "刷新后的父评论")
                recovery.value = recovery.value.copy(imported = true, importing = false, revision = 1, preserveOwner = true)
            }
            compose.waitUntil(5000) { advanceCompositionFrame(); calls.get() == 2 }
            expandReplySheet()
            showDialogText("已读子评论")
            reload.complete(restored)
            compose.waitUntil(5000) {
                advanceCompositionFrame()
                compose.onAllNodesWithText("恢复的子评论").fetchSemanticsNodes().isNotEmpty()
            }
            showDialogText("恢复的子评论")
        } finally {
            reload.complete(restored)
            compose.mainClock.autoAdvance = true
        }
        compose.onNodeWithText("导入本机设备标识").assertDoesNotExist()
        assertEquals(2, calls.get())
        assertEquals(2, imports.get())
    }

    @Test fun unsupportedChallengeOffersUpdatingAnImportedIdentityWithoutFakeVerification() {
        val imports = AtomicInteger()
        val state = ContentListState { _, _, _ -> throw UnsupportedCaptcha() }
        compose.setContent { MaterialTheme {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides CommentDeviceRecovery(true, { imports.incrementAndGet() })) {
                commentList(state)
            }
        } }
        awaitText("更新本机设备标识")
        awaitText("已导入本机官方设备标识，也可尝试更新；仍可能需要完成验证。")
        compose.onNodeWithText("服务器要求人机验证，但暂未提供可用的验证参数。").assertIsDisplayed()
        compose.onNodeWithText("导入本机设备标识").assertDoesNotExist()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        compose.onNodeWithText("重试").assertDoesNotExist()
        compose.onNodeWithText("更新本机设备标识").performClick()
        assertEquals(1, imports.get())
    }

    @Test fun ordinary403RemainsRetryableAndNeverBecomesDeviceOrCaptchaAdvice() {
        val calls = AtomicInteger()
        val state = ContentListState { page, _, _ ->
            if (calls.incrementAndGet() == 1) throw ApiException("暂时拒绝请求（403）")
            ContentPage(listOf(row("1", "重试后读到的评论")), page, "1", "1", false)
        }
        compose.setContent { MaterialTheme {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides CommentDeviceRecovery(false, { error("No import for general 403") })) {
                commentList(state)
            }
        } }
        awaitText("重试")
        compose.onNodeWithText("导入本机设备标识").assertDoesNotExist()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        compose.onNodeWithText("服务器要求人机验证，但暂未提供可用的验证参数。").assertDoesNotExist()
        compose.onNodeWithText("重试").performClick()
        awaitText("重试后读到的评论")
        assertEquals(2, calls.get())
    }

    @Test fun unrelatedListsDoNotReloadOrShowDeviceActionsAfterAnImportEvent() {
        val calls = AtomicInteger()
        var revision by mutableLongStateOf(0L)
        val state = ContentListState { _, _, _ -> calls.incrementAndGet(); throw UnsupportedCaptcha() }
        compose.setContent { MaterialTheme {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides CommentDeviceRecovery(false, {}, revision = revision)) {
                commentList(state, comments = false)
            }
        } }
        awaitText("重试")
        compose.runOnIdle { revision++ }
        compose.waitForIdle()
        compose.onNodeWithText("导入本机设备标识").assertDoesNotExist()
        compose.onNodeWithText("完成验证并重试").assertDoesNotExist()
        assertEquals(1, calls.get())
    }

    @Test fun anAccountChangeCannotReuseOldRowsEvenWhenAnImportRevisionAlsoAdvances() {
        var owner by mutableStateOf("old-account")
        var recovery by mutableStateOf(CommentDeviceRecovery(false, {}))
        val nextPage = CompletableDeferred<JSONObject>()
        val calls = AtomicInteger()
        val requestEvents = CopyOnWriteArrayList<String>()
        val feed = JSONObject("""{"id":"42","uid":"8","username":"作者","message":"正文"}""")
        val api = object : ContentApi {
            override fun imageCacheScope() = owner
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requestEvents += "$owner $path page=${query["page"]} order=${query["listType"]} start"
                if (path == "/v6/feed/detail") return JSONObject().put("data", feed)
                calls.incrementAndGet()
                return if (owner == "old-account") JSONObject().put("hasMore", false).put("data", JSONArray().put(row("1", "旧账号可见评论")))
                    else try { nextPage.await() } catch (cancelled: CancellationException) {
                        requestEvents += "$owner $path cancelled"
                        throw cancelled
                    }
            }
        }
        compose.setContent { MaterialTheme {
            CompositionLocalProvider(LocalCommentDeviceRecovery provides recovery) {
                FeedDetailScreen(api, "42", ContentSession(authenticated = true), {}, {}, {}, { _, _, _ -> }, {}, {}, {}, initialFeed = feed)
            }
        } }
        awaitText("旧账号可见评论")
        val restored = JSONObject().put("hasMore", false).put("data", JSONArray().put(row("2", "新账号评论")))
        compose.mainClock.autoAdvance = false
        try {
            compose.runOnUiThread {
                owner = "other-account"
                recovery = recovery.copy(revision = 1, preserveOwner = false)
            }
            try { compose.waitUntil(5000) { advanceCompositionFrame(); calls.get() == 2 } }
            catch (timeout: ComposeTimeoutException) {
                throw AssertionError("Expected 2 comment requests, observed ${calls.get()}; fixture events: ${requestEvents.toList()}", timeout)
            }
            compose.onNodeWithText("旧账号可见评论").assertDoesNotExist()
            nextPage.complete(restored)
            compose.waitUntil(5000) {
                advanceCompositionFrame()
                compose.onAllNodesWithText("新账号评论").fetchSemanticsNodes().isNotEmpty()
            }
        } finally {
            nextPage.complete(restored)
            compose.mainClock.autoAdvance = true
        }
        awaitText("新账号评论")
        compose.onNodeWithText("旧账号可见评论").assertDoesNotExist()
    }

    @Test @Config(qualifiers = "zh-rCN-w320dp-h800dp-mdpi")
    fun recoveryActionsWrapAt320DpWith150PercentText() {
        val readable = row("1", "已加载的评论仍然保留")
        val state = ContentListState { page, _, _ ->
            ContentPage(listOf(readable), page, "1", "1", false, error = challenge("replyDetail?id=2"), pendingReplyCount = 1)
        }
        compose.setContent { MaterialTheme {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.5f),
                LocalCommentDeviceRecovery provides CommentDeviceRecovery(true, {})) {
                Surface(Modifier.fillMaxSize()) { commentList(state) }
            }
        } }
        awaitText("更新本机设备标识")
        compose.onNodeWithText("完成验证并重试").assertIsDisplayed()
        compose.onNodeWithText("已加载的评论仍然保留").assertIsDisplayed()
        val update = compose.onNodeWithText("更新本机设备标识").fetchSemanticsNode().boundsInRoot
        val verify = compose.onNodeWithText("完成验证并重试").fetchSemanticsNode().boundsInRoot
        val viewport = compose.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue(update.left >= viewport.left && update.right <= viewport.right)
        assertTrue(verify.left >= viewport.left && verify.right <= viewport.right)
        assertTrue("Actions should wrap instead of overflowing", verify.top >= update.bottom)
        compose.runOnUiThread {
            val view = WindowInspector.getGlobalWindowViews().last { it.width > 0 && it.height > 0 }
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            java.io.File("build/parity/comment-recovery-320-150.png").apply { parentFile.mkdirs() }.outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
        }
    }

    @Composable private fun commentList(state: ContentListState, comments: Boolean = true) {
        ContentList(unusedApi, state, {}, {}, {}, { _, _, _ -> }, {}, {}, commentErrors = comments,
            itemContent = { Text(it.text("message")) })
    }

    private fun row(id: String, message: String) = JSONObject().put("id", id).put("feedid", "42")
        .put("uid", "9").put("username", "读者").put("message", message)
    private fun challenge(route: String) = CaptchaRequired(CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "当前访问需要验证码",
        CommentCaptchaRequest("https://api.coolapk.com/v6/feed/$route".toHttpUrl(), false, Any()))
    private fun advanceCompositionFrame() {
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
    }
    private fun expandReplySheet() {
        if (!compose.mainClock.autoAdvance) {
            compose.mainClock.advanceTimeBy(1000)
            compose.waitForIdle()
        }
        val expand = SemanticsMatcher.keyIsDefined(SemanticsActions.Expand) and hasAnyAncestor(isDialog())
        if (compose.onAllNodes(expand).fetchSemanticsNodes().isNotEmpty()) {
            compose.onNode(expand).performSemanticsAction(SemanticsActions.Expand) { assertTrue(it()) }
            if (!compose.mainClock.autoAdvance) compose.mainClock.advanceTimeBy(1000)
            compose.waitForIdle()
        }
    }
    private fun showDialogText(text: String): SemanticsNodeInteraction {
        val list = compose.onNode(hasScrollAction() and hasAnyAncestor(isDialog()))
        list.performScrollToNode(hasText(text))
        if (!compose.mainClock.autoAdvance) advanceCompositionFrame()
        val node = compose.onNode(hasText(text) and hasAnyAncestor(isDialog()))
        try { return node.assertIsDisplayed() }
        catch (failure: AssertionError) {
            val nodeBounds = node.fetchSemanticsNode().boundsInWindow
            val listBounds = list.fetchSemanticsNode().boundsInWindow
            compose.runOnUiThread {
                val view = WindowInspector.getGlobalWindowViews().last { it.width > 0 && it.height > 0 }
                val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bitmap))
                java.io.File("build/parity/comment-recovery-child-failure.png").apply { parentFile.mkdirs() }.outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
            throw AssertionError("Dialog text '$text' outside visible window: node=$nodeBounds list=$listBounds", failure)
        }
    }
    private fun awaitText(text: String) {
        compose.waitUntil(5000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
        compose.onNodeWithText(text).assertIsDisplayed()
    }
}
