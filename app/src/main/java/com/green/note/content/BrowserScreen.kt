package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.viewinterop.AndroidView
import org.json.JSONObject

internal fun validWebUrl(raw: String): Boolean = runCatching { java.net.URI(raw).let { it.scheme in setOf("http", "https") && !it.host.isNullOrBlank() && it.rawUserInfo == null } }.getOrDefault(false)
internal fun isActivityDocument(raw: String): Boolean = runCatching { java.net.URI(raw).let {
    it.scheme == "https" && it.rawUserInfo == null && it.host in setOf("m.coolapk.com", "www.coolapk.com", "coolapk.com") && (it.path.startsWith("/activity/") || it.path.startsWith("/mp/feedLotto/"))
} }.getOrDefault(false)
internal fun unwrapShoppingLink(raw: String): String {
    var url = raw
    repeat(5) {
        val uri = Uri.parse(url)
        if (uri.host?.let { it == "coolapk.com" || it.endsWith(".coolapk.com") } == true && uri.path == "/link") {
            uri.getQueryParameter("url")?.takeIf { Uri.parse(it).scheme != null }?.let { url = it }
        }
    }
    return url
}
internal fun shoppingPackage(uri: Uri): String? {
    val host = uri.host.orEmpty().lowercase()
    if (host.isEmpty() || uri.userInfo != null) return null
    fun domain(value: String) = host == value || host.endsWith(".$value")
    val web = uri.scheme in setOf("https", "http")
    return when {
        web && (domain("jd.com") || domain("3.cn")) || uri.scheme == "openapp.jdmobile" -> "com.jingdong.app.mall"
        web && (domain("taobao.com") || domain("tmall.com") || domain("tb.cn")) || uri.scheme == "taobao" -> "com.taobao.taobao"
        web && (domain("yangkeduo.com") || domain("pinduoduo.com")) || uri.scheme == "pinduoduo" -> "com.xunmeng.pinduoduo"
        else -> null
    }
}
internal fun openShoppingApp(context: Context, raw: String): Boolean {
    val uri = Uri.parse(raw)
    val target = shoppingPackage(uri) ?: return false
    val destination = if (uri.scheme in setOf("https", "http") && target == "com.jingdong.app.mall") {
        val params = JSONObject().put("category", "jump").put("des", "m").put("url", raw)
        Uri.parse("openapp.jdmobile://virtual?params=${Uri.encode(params.toString())}")
    } else uri
    return try { context.startActivity(Intent(Intent.ACTION_VIEW, destination).addCategory(Intent.CATEGORY_BROWSABLE).setPackage(target)); true }
    catch (_: android.content.ActivityNotFoundException) { false } catch (_: SecurityException) { false }
}

internal enum class ActivityNavigationKind { WEB, NATIVE, WRITER, EXTERNAL, BLOCK }
internal data class ActivityNavigation(val kind: ActivityNavigationKind, val target: String)
internal fun activityNavigation(raw: String, mainFrame: Boolean): ActivityNavigation {
    fun result(kind: ActivityNavigationKind, target: String = raw) = ActivityNavigation(kind, target)
    val uri = runCatching { java.net.URI(raw) }.getOrNull() ?: return result(ActivityNavigationKind.BLOCK)
    if (uri.rawUserInfo != null) return result(ActivityNavigationKind.BLOCK)
    if (isActivityDocument(raw) || !mainFrame) return result(ActivityNavigationKind.WEB)
    val host = uri.host.orEmpty().lowercase()
    val path = uri.path.orEmpty()
    val official = host == "coolapk.com" || host.endsWith(".coolapk.com")
    if (official && path == "/feed/writer") {
        val type = uri.rawQuery.orEmpty().split('&').firstOrNull { it.substringBefore('=') == "type" }
            ?.substringAfter('=', "")?.let { java.net.URLDecoder.decode(it, "UTF-8") }
        return result(if (type == "rating") ActivityNavigationKind.EXTERNAL else ActivityNavigationKind.WRITER)
    }
    val routes = listOf("/t/", "/feed/", "/u/", "/product/")
    if (official && (routes.any(path::startsWith) || path == "/page")) return result(ActivityNavigationKind.NATIVE)
    if (uri.scheme in setOf("http", "https") && host.isNotEmpty()) return result(ActivityNavigationKind.EXTERNAL)
    if (uri.scheme == "coolmarket") {
        val route = "/$host$path" + (uri.rawQuery?.let { "?$it" } ?: "")
        if ((routes + "/page").any(route::startsWith)) return result(ActivityNavigationKind.NATIVE, route)
    }
    return result(ActivityNavigationKind.BLOCK)
}

// Keep each rule's original condition: changing the theme must not erase width/orientation queries.
internal fun activityThemeScript(dark: Boolean): String = """
(function(){
 const originals=window.__greenNoteThemeMedia||(window.__greenNoteThemeMedia=new WeakMap());
 const wanted='${if (dark) "dark" else "light"}';
 function visit(rules){for(const rule of rules){try{
   if(rule.media){
     const original=originals.has(rule)?originals.get(rule):rule.media.mediaText;
     if(/prefers-color-scheme/i.test(original)){
       originals.set(rule,original);
       rule.media.mediaText=original.replace(/\(\s*prefers-color-scheme\s*:\s*(dark|light)\s*\)/gi,
         function(_,value){return value.toLowerCase()===wanted?'(min-width: 0px)':'(min-width: 2147483647px)';});
     }
   }
   if(rule.cssRules)visit(rule.cssRules);
 }catch(_){}}}
 for(const sheet of document.styleSheets){try{visit(sheet.cssRules);}catch(_){}}
})();
""".trimIndent()

@SuppressLint("SetJavaScriptEnabled")
@Composable
internal fun BrowserScreen(initialUrl: String, onBack: () -> Unit, showToolbar: Boolean = true, activityDocument: Boolean = false, onNavigate: (String) -> Unit = {}) {
    val context = LocalContext.current
    var url by remember(initialUrl) { mutableStateOf(initialUrl) }
    var title by remember(initialUrl) { mutableStateOf(if (activityDocument) "活动详情" else "") }
    var progress by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    var canBack by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    var web by remember { mutableStateOf<WebView?>(null) }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val latestDark by rememberUpdatedState(dark)
    val navigate by rememberUpdatedState(onNavigate)
    val session by rememberUpdatedState(LocalContentSession.current)
    fun external(value: String) {
        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(value))) }
        catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("无法打开外部浏览器") }
    }
    fun intercept(value: String, mainFrame: Boolean): Boolean {
        if (!activityDocument) return !validWebUrl(value)
        val action = activityNavigation(value, mainFrame)
        when (action.kind) {
            ActivityNavigationKind.WEB -> return false
            ActivityNavigationKind.NATIVE -> navigate(action.target)
            ActivityNavigationKind.WRITER -> if (session.authenticated && !session.anonymous) navigate(action.target)
                else com.green.note.ui.AppToastState().showSnackbar(if (session.anonymous) "当前为匿名登录，无法使用此功能" else "请先登录")
            ActivityNavigationKind.EXTERNAL -> external(action.target)
            ActivityNavigationKind.BLOCK -> Unit
        }
        return true
    }
    fun retry() {
        error = null; progress = 0
        web?.let { if (activityDocument) it.loadUrl(initialUrl) else it.reload() } ?: run { attempt++ }
    }
    LaunchedEffect(initialUrl, activityDocument, attempt) {
        web?.let { it.stopLoading(); it.destroy() }; web = null
        error = null; progress = 0; canBack = false
        if (activityDocument && !isActivityDocument(initialUrl)) { error = "活动地址无效"; return@LaunchedEffect }
        if (!validWebUrl(initialUrl)) { error = "当前无法打开内置浏览器"; return@LaunchedEffect }
        var candidate: WebView? = null
        try {
            candidate = WebView(context).apply {
                if (android.os.Build.VERSION.SDK_INT >= 29) isForceDarkAllowed = false
                if (android.os.Build.VERSION.SDK_INT >= 33) settings.isAlgorithmicDarkeningAllowed = false
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                if (activityDocument) setBackgroundColor(if (latestDark) 0xff0d1726.toInt() else android.graphics.Color.WHITE)
                webChromeClient = object : WebChromeClient() {
                    override fun onProgressChanged(view: WebView?, newProgress: Int) { progress = newProgress }
                    override fun onReceivedTitle(view: WebView?, value: String?) { if (!activityDocument || !value.isNullOrEmpty()) title = value.orEmpty() }
                }
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = intercept(request.url.toString(), request.isForMainFrame)
                    @Deprecated("Legacy platform callback") override fun shouldOverrideUrlLoading(view: WebView, value: String) = intercept(value, true)
                    override fun onPageStarted(view: WebView, value: String, favicon: android.graphics.Bitmap?) { url = value; error = null; progress = 0 }
                    override fun onPageFinished(view: WebView, value: String) {
                        canBack = view.canGoBack()
                        if (!activityDocument || !view.title.isNullOrEmpty()) title = view.title.orEmpty()
                        if (activityDocument && isActivityDocument(value)) view.evaluateJavascript(activityThemeScript(latestDark), null)
                    }
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) {
                        if (request.isForMainFrame) error = if (activityDocument) "活动页面加载失败：${failure.description}" else "网页加载失败，请重试"
                    }
                    override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                        if (activityDocument && request.url.toString() == initialUrl) error = "活动页面暂不可用（HTTP ${response.statusCode}）"
                    }
                    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, failure: android.net.http.SslError) { handler.cancel() }
                }
            }
            web = candidate
            candidate.loadUrl(initialUrl)
        } catch (failure: Exception) {
            candidate?.destroy(); web = null
            error = if (activityDocument) "无法加载活动页面：${failure.message.orEmpty()}" else "当前无法打开内置浏览器"
        }
    }
    DisposableEffect(Unit) { onDispose { web?.let { it.stopLoading(); it.destroy() }; web = null } }
    LaunchedEffect(web, dark) {
        web?.takeIf { activityDocument }?.let {
            it.setBackgroundColor(if (dark) 0xff0d1726.toInt() else android.graphics.Color.WHITE)
            if (isActivityDocument(it.url.orEmpty())) it.evaluateJavascript(activityThemeScript(dark), null)
        }
    }
    BackHandler(!activityDocument && canBack) { web?.goBack() }
    val background = if (activityDocument && showToolbar) Color(0xff101010) else com.green.note.ui.LocalScaffoldColor.current
    Column(Modifier.fillMaxSize().background(background)) {
        if (showToolbar && activityDocument) {
            com.green.note.ui.ReviewToolbarIcons(Color(0xffcccccc)) {
                Row(Modifier.fillMaxWidth().height(52.dp).background(Color(0xff1e1e1e)), verticalAlignment = Alignment.CenterVertically) {
                    ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(4.dp))
                    Text(title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 20.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
                    Box {
                        ContentIcon("more_vert", "更多选项", { menu = true })
                        com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) {
                            com.green.note.ui.ReviewPopupMenuItem(text = { Text("在浏览器打开") }, onClick = { menu = false; external(initialUrl) })
                        }
                    }
                }
            }
        } else if (showToolbar) com.green.note.ui.ReviewToolbarIcons() { Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("close", "关闭网页", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                if (title.isNotEmpty()) Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 15.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
                Text(Uri.parse(url).host.orEmpty(), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 12.sp, fontWeight = com.green.note.ui.adjustedWeight(700), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            ContentIcon("refresh", "刷新网页", ::retry)
            Box {
                ContentIcon("more_vert_rounded", "网页选项", { menu = true })
                com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) {
                    com.green.note.ui.ReviewPopupMenuItem(text = { Text("用外部浏览器打开") }, onClick = { menu = false; external(url) })
                    com.green.note.ui.ReviewPopupMenuItem(text = { Text("复制链接") }, onClick = { menu = false; (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("链接", url)) })
                }
            }
        } }
        if (activityDocument) Box(Modifier.weight(1f).fillMaxWidth()) {
            // Keep the same native view attached under the error state, so retry never leaks an orphan WebView.
            web?.let { current -> key(current) { AndroidView(factory = { current }, update = { it.visibility = if (error == null) android.view.View.VISIBLE else android.view.View.INVISIBLE }, modifier = Modifier.fillMaxSize()) } }
            if (web == null || error != null) Column(Modifier.fillMaxSize().background(background).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                error?.let { Text(it) } ?: com.green.note.ui.ReviewCircularProgress()
                com.green.note.ui.ReviewTextButton(onClick = { external(initialUrl) }) { Text("在浏览器打开活动详情") }
                if (error != null) com.green.note.ui.ReviewTextButton(onClick = ::retry) { Text("重试") }
            } else if (progress < 100) com.green.note.ui.ReviewLinearProgress(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter))
        } else {
            if (progress < 100 && error == null) com.green.note.ui.ReviewLinearProgress(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth())
            error?.let { message ->
                Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
                    Column {
                        val density = androidx.compose.ui.platform.LocalDensity.current
                        val cappedScale = density.fontScale.coerceAtMost(1.5f)
                        val linearDensity = remember(density.density, cappedScale) { com.green.note.ui.ReviewLinearDensity(density.density, cappedScale) }
                        CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides linearDensity) {
                            Row(Modifier.fillMaxWidth().padding(start = 16.dp, top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(message, Modifier.weight(1f))
                                Box(Modifier.heightIn(min = 52.dp).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewTextButton(onClick = ::retry) { Text("重试") } }
                            }
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
            web?.let { current -> key(current) { AndroidView(factory = { current }, modifier = Modifier.weight(1f).fillMaxWidth()) } }
        }
    }
}
