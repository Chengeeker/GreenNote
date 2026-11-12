package com.green.note.settings

import androidx.activity.ComponentActivity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.inspector.WindowInspector
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.green.note.account.AccountMode
import com.green.note.account.AccountRepository
import com.green.note.account.ReplacingAtomicFileShadow
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import javax.crypto.KeyGenerator

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w360dp-h800dp-mdpi", shadows = [ReplacingAtomicFileShadow::class])
class WebDavResultDialogTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val server = MockWebServer()
    private lateinit var settings: SettingsStore
    private lateinit var accounts: AccountRepository
    private lateinit var config: WebDavConfig

    @Before fun prepare() = runBlocking {
        server.start()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        accounts = AccountRepository(compose.activity) { key }
        settings = SettingsStore(compose.activity)
        accounts.initialize(); settings.initialize()
        config = WebDavConfig(server.url("/").toString(), "synthetic-user")
        settings.saveWebDavConfig(config)
        accounts.writeSecret(WebDavBackups.PASSWORD_KEY, "synthetic-password")
        compose.setContent { MaterialTheme { WebDavBackupScreen(settings, accounts, { error("No official account in this test") }, {}) } }
        compose.waitUntil(10_000) { compose.onAllNodesWithText(config.url).fetchSemanticsNodes().isNotEmpty() }
    }

    @After fun closeServer() { server.shutdown() }

    private fun tap(label: String) { compose.onNodeWithText(label).performScrollTo().performClick() }
    private fun result(title: String, message: String) {
        compose.waitUntil(10_000) { compose.onAllNodesWithText(message).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText(title).assert(hasAnyAncestor(isDialog())).assertIsDisplayed()
        compose.onNodeWithText(message).assert(hasAnyAncestor(isDialog())).assertIsDisplayed()
        compose.runOnUiThread {
            val view = WindowInspector.getGlobalWindowViews().last { it.width > 0 && it.height > 0 }
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            try {
                view.draw(Canvas(bitmap))
                java.io.File("build/parity/webdav-result-${message.hashCode()}.png").apply { parentFile.mkdirs() }
                    .outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() }
        }
    }
    private fun pageHeight() = compose.onNode(hasScrollAction() and hasAnyDescendant(hasText("WebDAV 服务器配置")))
        .fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].maxValue()

    @Test fun completedOperationsShowDialogsAtPageBottomAndLegacyActivationStaysAvailable() {
        tapReady()
        val height = pageHeight()
        server.enqueue(MockResponse().setResponseCode(207))
        tap("测试服务器连接")
        result("连接测试结果", "连接成功。")
        compose.onNodeWithText("知道了").performClick()
        compose.onAllNodes(isDialog()).assertCountEquals(0)
        assertEquals(height, pageHeight(), .1f)

        server.enqueue(MockResponse().setResponseCode(201))
        server.enqueue(MockResponse().setResponseCode(201))
        tap("立即备份到云端")
        result("备份结果", "全量安全备份已上传，未包含 Cookie、Token 与 WebDAV 密码。")
        compose.onNodeWithText("知道了").performClick()
        assertEquals(height, pageHeight(), .1f)

        val backup = runBlocking { WebDavBackups(settings, accounts) { error("No cookie") }.export(config, false) }
        backup.remove("accountMode")
        server.enqueue(MockResponse().setBody(backup.toString()))
        tap("从云端恢复备份")
        compose.onNodeWithText("恢复 WebDAV 备份？").assert(hasAnyAncestor(isDialog()))
        compose.onNodeWithText("恢复设置").performClick()
        result("恢复结果", "设置和匿名资料已恢复，匿名资料可切换后使用。")
        compose.onNodeWithText("使用已恢复的匿名账户").assertIsDisplayed().performClick()
        result("恢复结果", "已进入恢复的匿名账户。")
        assertEquals(AccountMode.ANONYMOUS, accounts.state.value.mode)
        compose.onNodeWithText("知道了").performClick()
        assertEquals(height, pageHeight(), .1f)
    }

    @Test fun failuresAndFieldValidationAreVisibleInDialogsAndCanBeDismissed() {
        tapReady()
        server.enqueue(MockResponse().setResponseCode(401))
        tap("测试服务器连接")
        result("连接测试结果", "WebDAV 连接测试 失败（HTTP 401）：身份验证失败，请检查账号和授权密码")
        compose.onNodeWithText("知道了").performClick()
        server.enqueue(MockResponse().setResponseCode(403))
        tap("从云端恢复备份")
        compose.onNodeWithText("恢复设置").performClick()
        result("恢复结果", "WebDAV 下载 失败（HTTP 403）：权限不足，请检查该操作的权限")
        compose.onNodeWithText("知道了").performClick()
        compose.onNodeWithContentDescription("账号 / 邮箱").performScrollTo().performTextClearance()
        tap("测试服务器连接")
        compose.onNode(hasText("请输入账号") and hasAnyAncestor(isDialog())).assertIsDisplayed()
        compose.onNodeWithText("知道了").performClick()
        compose.onAllNodes(isDialog()).assertCountEquals(0)
        assertEquals(2, server.requestCount)
    }

    private fun tapReady() {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText("测试服务器连接").fetchSemanticsNodes().any {
                !it.config.contains(SemanticsProperties.Disabled)
            }
        }
    }
}
