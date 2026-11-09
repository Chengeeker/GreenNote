package com.green.note.content

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ResolveInfo
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import com.green.note.MainActivity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w320dp-h640dp-xxhdpi")
class StoreDownloadButtonTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun showsBothChoicesAndOpensAnExternalChooserAtLargeTextSize() {
        val uri = Uri.parse("https://example.org/app.apk")
        val packageManager = shadowOf(compose.activity.packageManager)
        packageManager.addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, uri), ResolveInfo().apply {
            activityInfo = ActivityInfo().apply { packageName = "example.downloader"; name = "example.downloader.OpenActivity" }
            isDefault = true
        })
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject =
                error("unexpected request")
        }
        val app = JSONObject().put("title", "测试应用").put("downloadUrl", uri.toString())
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 1.5f)) {
                MaterialTheme(colorScheme = darkColorScheme()) { NativeAppDownload(api, app, compact = true) }
            }
        }
        compose.onNodeWithText("下载").performClick()
        compose.onNodeWithText("应用内下载").assertIsDisplayed()
        compose.onNodeWithText("用其他应用打开").assertIsDisplayed().performClick()
        compose.waitForIdle()
        val chooser = shadowOf(compose.activity).nextStartedActivity
        assertNotNull(chooser)
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        assertEquals(uri, chooser.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)?.data)
        val excluded = chooser.getParcelableArrayExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, ComponentName::class.java)
        assertTrue(excluded.orEmpty().contains(ComponentName(compose.activity, MainActivity::class.java)))
    }
}
