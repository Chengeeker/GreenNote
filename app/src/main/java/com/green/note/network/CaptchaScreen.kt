package com.green.note.network

import com.green.note.ui.ReviewText as Text

import android.annotation.SuppressLint
import android.webkit.*
import androidx.activity.compose.BackHandler
import com.green.note.content.contentToolbarBorder
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.green.note.ui.MaterialGlyph

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CaptchaScreen(challenge: CaptchaChallenge, onResult: (String?) -> Unit) {
    val context = LocalContext.current
    var loadError by remember { mutableStateOf(if (challenge.proof("test") == null) "验证参数无效，请重新加载榜单" else null) }
    var browser by remember { mutableStateOf<WebView?>(null) }
    var finished by remember { mutableStateOf(false) }
    val currentResult by rememberUpdatedState(onResult)
    val html = remember(challenge.id) { context.assets.open("captcha.html").bufferedReader().use { it.readText() }.replace("%CAPTCHA_ID%", challenge.id) }
    BackHandler { onResult(null) }
    DisposableEffect(Unit) { onDispose { browser?.removeJavascriptInterface("CoolapkCaptcha"); browser?.stopLoading(); browser?.destroy() } }
    Scaffold(containerColor = com.green.note.ui.LocalScaffoldColor.current, topBar = {
        Column(Modifier.statusBarsPadding()) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = { onResult(null) }, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", contentDescription = "返回") }
            Spacer(Modifier.width(16.dp))
            Text("人机验证", Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
            com.green.note.ui.ReviewIconButton(onClick = {
                if (challenge.proof("test") == null) loadError = "验证参数无效，请重新加载榜单"
                else { loadError = null; browser?.loadDataWithBaseURL(BASE, html, "text/html", "UTF-8", null) }
            }) {
                MaterialGlyph("refresh", contentDescription = "重新加载验证")
            }
        }
        }
    }) { padding ->
        if (loadError != null) Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) { Text(loadError.orEmpty()) }
        else AndroidView(modifier = Modifier.padding(padding).fillMaxSize(), factory = { ctx ->
            try { browser ?: WebView(ctx).apply {
                browser = this
                if (android.os.Build.VERSION.SDK_INT >= 29) isForceDarkAllowed = false
                settings.javaScriptEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                        request.isForMainFrame && request.url.toString() !in setOf(BASE, "about:blank")
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                        if (request.isForMainFrame) loadError = "验证页面加载失败，请重试"
                    }
                    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) { handler.cancel() }
                }
                addJavascriptInterface(object {
                    @JavascriptInterface fun postMessage(value: String) {
                        post {
                            if (!finished && challenge.proof(value) != null) { finished = true; currentResult(value) }
                        }
                    }
                }, "CoolapkCaptcha")
                if (challenge.proof("test") == null) loadError = "验证参数无效，请重新加载榜单"
                else loadDataWithBaseURL(BASE, html, "text/html", "UTF-8", null)
            } } catch (_: Exception) { browser?.destroy(); browser = null; loadError = "验证页面加载失败，请重试"; android.widget.FrameLayout(ctx) }
        })
    }
}

private const val BASE = "https://captcha.greennote.invalid/"


