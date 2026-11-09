package com.green.note.content

import android.app.Application
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.lifecycle.compose.LocalLifecycleOwner
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.ConcurrentLinkedQueue

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w320dp-h640dp-xxhdpi")
class AppUpdateLayoutTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun startupChecksBeforeManagementOpensAndReusesResultsInUpdateTab() {
        install("example.update", "样例应用")
        install("example.system", "系统应用", system = true)
        val requests = ConcurrentLinkedQueue<String>()
        val api = UpdateTestApi { id -> requests.add(id); updateDetail(id, if (id == "example.update") 2 else 1) }
        var opened: String? = null
        var showManagement by mutableStateOf(false)
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 1.5f)) {
                MaterialTheme(colorScheme = darkColorScheme()) {
                    val state = rememberAppManagement(api, LocalLifecycleOwner.current.lifecycle)
                    if (showManagement) AppManagementScreen(state, {}, { opened = it }) { _, _ -> }
                }
            }
        }
        compose.mainClock.advanceTimeBy(1800)
        compose.waitUntil(timeoutMillis = 5000) { requests.count { it == "example.update" } == 1 }
        compose.runOnIdle { showManagement = true }
        compose.waitUntil(timeoutMillis = 5000) {
            runCatching { compose.onNodeWithText("样例应用").assertIsDisplayed() }.isSuccess
        }
        compose.onNodeWithText("更新").performClick()
        compose.onNodeWithText("1.0 → 2.0").assertIsDisplayed()
        val result = compose.onNodeWithText("版本号 2 · 31.5 MB").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val button = compose.onNodeWithText("检查更新").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val root = compose.onRoot().fetchSemanticsNode().boundsInRoot
        assertEquals(root.center.x, button.center.x, 2f)
        assertTrue(result.center.y < root.height * .5f && button.center.y > root.height * .75f)
        assertEquals(1, requests.count { it == "example.update" })
        assertFalse(requests.contains("example.system"))
        compose.onNodeWithText("只比较已安装第三方应用的版本号。", substring = true).assertDoesNotExist()
        compose.onNodeWithText("样例应用").performClick()
        compose.runOnIdle { assertEquals("example.update", opened) }

        compose.onNodeWithText("下载管理").performClick()
        compose.onNodeWithText("更新").performClick()
        compose.onNodeWithText("版本号 2 · 31.5 MB").assertIsDisplayed()
        assertEquals(1, requests.count { it == "example.update" })
        compose.onNodeWithText("检查更新").performClick()
        compose.waitUntil(timeoutMillis = 5000) { requests.count { it == "example.update" } == 2 }
    }

    private fun install(id: String, label: String, system: Boolean = false) {
        val pm = shadowOf(compose.activity.packageManager)
        pm.installPackage(PackageInfo().apply {
            packageName = id
            versionName = "1.0"
            setLongVersionCode(1)
            applicationInfo = ApplicationInfo().apply {
                packageName = id
                nonLocalizedLabel = label
                enabled = true
                flags = if (system) ApplicationInfo.FLAG_SYSTEM else 0
                icon = android.R.drawable.sym_def_app_icon
            }
        })
    }
}
