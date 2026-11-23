package com.green.note.media

import android.content.ComponentName
import androidx.activity.ComponentActivity
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import org.junit.runner.RunWith
import org.junit.runners.model.Statement
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LivePhotoControlTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    private val register = TestRule { base, _ -> object : Statement() {
        override fun evaluate() {
            val context = ApplicationProvider.getApplicationContext<android.content.Context>()
            Shadows.shadowOf(context.packageManager).addActivityIfNotPresent(ComponentName(context, ComponentActivity::class.java))
            base.evaluate()
        }
    } }
    @get:Rule val rules: TestRule = RuleChain.outerRule(register).around(compose)

    @Test fun controlTogglesBetweenPlayAndPause() {
        compose.setContent {
            var playing by remember { mutableStateOf(false) }
            LivePhotoControl(playing) { playing = !playing }
        }
        compose.onNodeWithText("播放 Live 图").performClick()
        compose.onNodeWithText("暂停 Live 图").assertExists().performClick()
        compose.onNodeWithText("播放 Live 图").assertExists()
    }
}
