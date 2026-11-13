package com.green.note.account

import android.content.ComponentName
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.junit.Assert.*
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
@Config(sdk = [35], qualifiers = "w600dp-h1400dp-mdpi")
class DeviceIdentityRecoveryTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    private val register = TestRule { base, _ -> object : Statement() {
        override fun evaluate() {
            val context = ApplicationProvider.getApplicationContext<Context>()
            Shadows.shadowOf(context.packageManager).addActivityIfNotPresent(ComponentName(context, ComponentActivity::class.java))
            base.evaluate()
        }
    } }
    @get:Rule val rules: TestRule = RuleChain.outerRule(register).around(compose)

    private fun recognizeAndSave() {
        compose.onNode(hasSetTextAction()).performTextInput("ShuzlmID: synthetic-device-123")
        compose.onNodeWithText("识别输入内容").performScrollTo().performClick()
        compose.onNodeWithText("保存并应用").performScrollTo().performClick()
    }

    @Test fun successReturnsOnlyAfterTheIdentityHasBeenAppliedAndOnlyOnce() {
        var applied = false
        var imported = 0
        var backs = 0
        compose.setContent { MaterialTheme {
            DeviceIdentityScreen("guest", { applied = true }, {}, { backs++ }, onImported = {
                assertTrue(applied)
                imported++
            })
        } }
        recognizeAndSave()
        compose.runOnIdle {
            assertTrue(applied)
            assertEquals(1, imported)
            assertEquals(0, backs)
        }
        compose.onNodeWithText("保存并应用").assertIsNotEnabled()
        compose.waitForIdle()
        assertEquals(1, imported)
    }

    @Test fun persistenceFailureDoesNotReturnAndAllowsAnExplicitRetry() {
        var attempts = 0
        var imported = 0
        compose.setContent { MaterialTheme {
            DeviceIdentityScreen("guest", { if (++attempts == 1) error("synthetic failure") }, {}, {},
                onImported = { imported++ })
        } }
        recognizeAndSave()
        compose.runOnIdle { assertEquals(0, imported) }
        compose.onNodeWithText("保存失败，设备标识未应用，请重试").assertExists()
        compose.onNodeWithText("保存并应用").assertIsEnabled().performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(2, attempts)
            assertEquals(1, imported)
        }
    }

    @Test fun dismissedScreenCannotReturnWhenItsCommittedSaveFinishesLate() {
        val visible = mutableStateOf(true)
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val published = CompletableDeferred<Unit>()
        val disposed = CompletableDeferred<Unit>()
        var imported = 0
        compose.setContent { MaterialTheme {
            if (visible.value) {
                DisposableEffect(Unit) { onDispose { disposed.complete(Unit) } }
                DeviceIdentityScreen("guest", {
                    // AppGraph finishes its committed write/runtime publication even after UI cancellation.
                    withContext(NonCancellable) {
                        entered.complete(Unit)
                        release.await()
                        published.complete(Unit)
                    }
                }, {}, {}, onImported = { imported++ })
            }
        } }
        try {
            recognizeAndSave()
            compose.waitUntil { entered.isCompleted }
            // The busy progress painter requests frames continuously. Dismiss on the UI thread
            // without waiting for that animation to become idle, then await actual disposal.
            compose.runOnUiThread { visible.value = false }
            compose.waitUntil { disposed.isCompleted }
        } finally {
            release.complete(Unit)
        }
        compose.waitUntil { published.isCompleted }
        compose.runOnIdle { assertEquals(0, imported) }
    }
}
