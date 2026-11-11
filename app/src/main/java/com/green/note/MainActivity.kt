package com.green.note

import com.green.note.ui.ReviewText as Text

import android.content.Intent
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.notifications.ReplyRuntime
import com.green.note.media.OPEN_DOWNLOADS
import com.green.note.ui.GreenNoteTheme
import com.green.note.ui.ScrollRateController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase)
        // Flutter fixes zh-CN. Override only language/direction, allowing all display settings to update.
        applyOverrideConfiguration(Configuration().apply {
            setLocale(Locale.SIMPLIFIED_CHINESE)
            setLayoutDirection(Locale.SIMPLIFIED_CHINESE)
        })
    }

    private val scrolling by lazy { ScrollRateController(window) }
    private var replyScope by mutableStateOf<String?>(null)
    private var showDownloads by mutableStateOf(false)
    private lateinit var incomingLinks: IncomingLinks
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (android.os.Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
        replyScope = notificationScope(intent)
        showDownloads = savedInstanceState?.getBoolean("pending_downloads") ?: (intent.action == OPEN_DOWNLOADS)
        incomingLinks = IncomingLinks(savedInstanceState?.getStringArrayList("incoming_links").orEmpty())
        if (savedInstanceState == null) incomingLinks.offer(intent.dataString)
        val graph = AppGraph.get(this)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ReplyRuntime.visible = true
                try {
                    graph.initialize()
                    val runtime = ReplyRuntime(this@MainActivity)
                    runtime.configure(true)
                    while (true) { runtime.check(); delay(60000) }
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { /* The content initialization exposes storage errors with retry. */ }
                finally { ReplyRuntime.visible = false }
            }
        }
        setContent {
            var ready by remember { mutableStateOf(false) }
            var error by remember { mutableStateOf<String?>(null) }
            var attempt by remember { mutableIntStateOf(0) }
            var recoveryAvailable by remember { mutableStateOf(false) }
            var recover by remember { mutableStateOf(false) }
            LaunchedEffect(attempt) {
                error = null
                try {
                    if (recover) graph.accounts.recoverAfterTransfer()
                    graph.initialize(); ready = true
                }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (failure: Exception) {
                    recoveryAvailable = recoveryAvailable || failure is com.green.note.account.AccountKeyUnavailableException
                    error = failure.message ?: "初始化失败，请重试"
                }
                finally { recover = false }
            }
            val preferences by graph.settings.state.collectAsState()
            GreenNoteTheme(preferences) {
                val pendingLink = incomingLinks.first
                if (ready) ApplicationScreen(graph, preferences, replyScope, { replyScope = null }, pendingLink,
                    { if (pendingLink != null) incomingLinks.consume(pendingLink) }, scrolling,
                    showDownloads, { showDownloads = false })
                else Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                        if (error == null) com.green.note.ui.ReviewCircularProgress() else {
                            Text(error!!)
                            if (recoveryAvailable) {
                                Spacer(Modifier.height(12.dp))
                                Text("继续后需重新登录。原加密文件将保留，匿名收藏等本地资料可在原手机通过应用内备份导出后恢复。")
                                Spacer(Modifier.height(16.dp))
                                com.green.note.ui.ReviewButton(onClick = { recover = true; attempt++ }) { Text("保留旧资料并继续") }
                            }
                            com.green.note.ui.ReviewButton(onClick = { attempt++ }) { Text("重试") }
                        }
                    }
                }
            }
        }
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val handled = super.dispatchTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_DOWN) scrolling.requests.stopOnPress(lifecycleScope)
        return handled
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        replyScope = notificationScope(intent)
        if (intent.action == OPEN_DOWNLOADS) showDownloads = true
        incomingLinks.offer(intent.dataString)
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putStringArrayList("incoming_links", incomingLinks.snapshot())
        outState.putBoolean("pending_downloads", showDownloads)
        super.onSaveInstanceState(outState)
    }
    private fun notificationScope(intent: Intent): String? =
        (intent.getStringExtra("reply_scope") ?: intent.getStringExtra("payload")?.takeIf { it.startsWith("reply:") }?.removePrefix("reply:"))
            ?.takeIf { it.matches(Regex("[0-9a-f]{64}")) }
}
