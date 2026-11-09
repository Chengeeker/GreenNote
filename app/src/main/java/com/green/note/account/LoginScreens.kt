package com.green.note.account

import com.green.note.ui.ReviewText as Text

import android.graphics.BitmapFactory
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceError
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import androidx.compose.ui.viewinterop.AndroidView
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.PreferenceRow
import com.green.note.ui.ReviewPage
import com.green.note.ui.ReviewTileLayout
import com.green.note.ui.adjustedWeight
import com.green.note.ui.tapClickable as clickable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import kotlin.coroutines.resume

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginOptionsSheet(onDismiss: () -> Unit, onOfficial: () -> Unit, onAnonymous: () -> Unit) {
    com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.navigationBarsPadding()) {
            LoginOptionTile("登录方式与账号管理", "匿名资料保留在本机，切换账号不会删除本地收藏。")
            LoginOptionTile("账号登录", "账号密码或酷安官方网页登录", "login", onOfficial)
            LoginOptionTile("匿名登录", "本地关注、收藏和 WebDAV 备份", "person_outline", onAnonymous)
        }
    }
}

@Composable
private fun LoginOptionTile(title: String, subtitle: String, icon: String? = null, onClick: (() -> Unit)? = null) {
    // Original uses three plain dense ListTiles: no chevron, no separate header surface.
    // Flutter ListTile overrides the theme's 15/12.5 sizes to 13/12 in dense mode.
    ReviewTileLayout(modifier = if (onClick == null) Modifier else Modifier.clickable(onClick = onClick),
        horizontalPadding = 14.dp, minVerticalPadding = 4.dp,
        leading = icon?.let { { MaterialGlyph(it, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
        subtitle = { Text(subtitle, fontSize = 12.sp, lineHeight = 1.4.em, color = MaterialTheme.colorScheme.onSurfaceVariant) }) {
        Text(title, fontSize = 13.sp, lineHeight = 1.35.em, fontWeight = adjustedWeight(600), color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
fun OfficialLoginScreen(repository: AccountRepository, validateCookie: suspend (String) -> JSONObject,
                        onBack: () -> Unit, onSuccess: () -> Unit, onCookieLogin: () -> Unit,
                        onWebLogin: () -> Unit, onDeviceIdentity: () -> Unit) {
    val session = remember { OfficialLoginSession() }
    DisposableEffect(session) { onDispose { session.close() } }
    val scope = rememberCoroutineScope()
    var account by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var captcha by remember { mutableStateOf("") }
    var image by remember { mutableStateOf<ByteArray?>(null) }
    var busy by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var showPassword by remember { mutableStateOf(false) }
    var validating by remember { mutableStateOf(false) }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    BackHandler(validating) {}
    fun webLogin() { if (!busy) { password = ""; onWebLogin() } }
    var error by remember { mutableStateOf<String?>(null) }
    fun prepare() { scope.launch {
        busy = true; ready = false; error = null
        try { session.prepare(); ready = true; image = null; captcha = "" }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "连接失败，请检查网络后重试，或使用官方网页登录" }
        finally { busy = false }
    } }
    LaunchedEffect(session) {
        try { session.prepare(); ready = true }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "无法获取登录参数" }
        finally { busy = false }
    }
    fun login() { if (!busy && ready) scope.launch {
                if (account.isBlank() || password.isEmpty()) { error = "请输入账号和密码"; return@launch }
                val ownerRevision = repository.state.value.revision
                busy = true; error = null; keyboard?.hide()
                var webRequired = false
                try {
                    val candidate = session.login(account.trim(), password, captcha.trim())
                    check(repository.state.value.revision == ownerRevision) { "账号已变更，已取消此次登录" }
                    validating = true
                    repository.acceptCookie(candidate, validateCookie)
                    password = ""; onSuccess()
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (failure: Exception) {
                    error = failure.message ?: "连接失败，请检查网络后重试"
                    webRequired = failure is LoginFailure && failure.webRequired
                    if (failure is LoginFailure && failure.captchaRequired) {
                        try { image = session.captcha(); captcha = "" }
                        catch (cancelled: CancellationException) { throw cancelled }
                        catch (_: Exception) { error = "验证码加载失败，请重试或使用官方网页登录" }
                    }
                } finally { busy = false; validating = false }
                if (webRequired) webLogin()
                } }
    ReviewPage("账号登录", { if (!validating) onBack() }, topPadding = 16.dp, contentHorizontalPadding = 20.dp, bottomPadding = 20.dp, actions = {
            com.green.note.ui.ReviewTextButton(onClick = onCookieLogin, enabled = !busy) { Text("Cookie 登录") }
            Spacer(Modifier.width(8.dp))
    }) {
        // Original maxWidth=560 includes the ListView's 20dp padding on both sides.
        Column(Modifier.widthIn(max = 520.dp).align(Alignment.CenterHorizontally)) {
            Text("使用酷安账号登录。密码仅用于本次登录，不会保存；登录凭据通过校验后保存在本机安全存储中。")
            Spacer(Modifier.height(24.dp))
            AccountTextField(account, { account = it }, Modifier.fillMaxWidth(), enabled = !busy,
                label = "账号", placeholder = "用户名 / 手机号 / 邮箱", singleLine = true, keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Next))
            Spacer(Modifier.height(16.dp))
            PrivateTextInput { AccountTextField(password, { password = it }, Modifier.fillMaxWidth(), enabled = !busy,
                label = "密码", singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false, imeAction = if (image == null) ImeAction.Done else ImeAction.Next), keyboardActions = KeyboardActions(onDone = { if (image == null) login() }),
                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = { com.green.note.ui.ReviewIconButton(onClick = { showPassword = !showPassword }, enabled = !busy) {
                    MaterialGlyph(if (showPassword) "visibility_off_outlined" else "visibility_outlined", contentDescription = if (showPassword) "隐藏密码" else "显示密码")
                } }) }
            image?.let { bytes ->
                Spacer(Modifier.height(16.dp))
                val bitmap = remember(bytes) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
                if (bitmap == null) Text("验证码图片无法显示，请刷新") else Image(bitmap, "酷安图形验证码", Modifier.fillMaxWidth().height(72.dp))
                com.green.note.ui.ReviewTextButton(modifier = Modifier.fillMaxWidth(), enabled = !busy, onClick = { scope.launch {
                    busy = true; error = null
                    try { image = session.captcha(); captcha = "" }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { error = "验证码加载失败，请重试或使用官方网页登录" }
                    finally { busy = false }
                } }) { Text("刷新验证码") }
                AccountTextField(captcha, { captcha = it }, Modifier.fillMaxWidth(), enabled = !busy, label = "图形验证码", singleLine = true, keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { login() }))
            }
            if (busy) com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth().padding(vertical = 16.dp))
            error?.let { Text(it, Modifier.padding(vertical = 16.dp), color = MaterialTheme.colorScheme.error) }
            Spacer(Modifier.height(20.dp))
            com.green.note.ui.ReviewButton(enabled = !busy && ready, modifier = Modifier.fillMaxWidth(), onClick = ::login) { Text("登录并校验") }
            com.green.note.ui.ReviewTextButton(onClick = ::prepare, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("重新加载登录参数") }
            Spacer(Modifier.height(8.dp))
            com.green.note.ui.ReviewOutlinedButton(iconPadding = true, onClick = ::webLogin, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                MaterialGlyph("public"); com.green.note.ui.ReviewButtonIconGap(); Text("使用官方网页登录")
            }
            Spacer(Modifier.height(8.dp))
            Text("需要人机验证或无法直接登录时，可在酷安官方网页中完成登录。")
            Spacer(Modifier.height(24.dp))
            com.green.note.ui.ReviewOutlinedButton(iconPadding = true, onClick = onDeviceIdentity, enabled = !busy, modifier = Modifier.fillMaxWidth()) { MaterialGlyph("phonelink_setup_outlined"); com.green.note.ui.ReviewButtonIconGap(); Text("导入官方设备标识") }
        }
    }
}

@Composable
fun CookieLoginScreen(repository: AccountRepository, validateCookie: suspend (String) -> JSONObject,
                      onBack: () -> Unit, onSuccess: () -> Unit) {
    var cookie by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    ReviewPage("登录酷安", onBack, topPadding = 16.dp, contentHorizontalPadding = 20.dp, bottomPadding = 20.dp) {
        Text("在酷安官方客户端或浏览器登录后，复制自己的 Cookie 粘贴到此处。请勿把 Cookie 发给他人。")
        Spacer(Modifier.height(18.dp))
        PrivateTextInput { AccountTextField(cookie, { cookie = it }, Modifier.fillMaxWidth(), enabled = !busy,
            singleLine = true, label = "酷安 Cookie", keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false), visualTransformation = PasswordVisualTransformation()) }
        Spacer(Modifier.height(12.dp))
        com.green.note.ui.ReviewButton(iconPadding = true, enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = { scope.launch {
            if (cookie.isBlank()) return@launch
            busy = true; error = null
            try { repository.acceptCookie(cookie.trim(), validateCookie); cookie = ""; error = "已通过酷安接口校验，Cookie 保存在本机安全存储中。" }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = "校验失败：${failure.message ?: failure}" }
            finally { busy = false }
        } }) {
            if (busy) com.green.note.ui.ReviewCircularProgress(Modifier.size(18.dp), strokeWidth = 2.dp) else MaterialGlyph("verified_user_outlined")
            com.green.note.ui.ReviewButtonIconGap(); Text("安全保存并校验")
        }
        error?.let { Spacer(Modifier.height(12.dp)); Text(it) }
    }
}

object LoginWebCookies {
    private val hosts = listOf("account.coolapk.com", "www.coolapk.com", "api.coolapk.com", "api2.coolapk.com")
    private val paths = linkedSetOf("/", "/auth", "/auth/", "/auth/login", "/auth/loginByCoolApk")
    fun notePath(url: String) {
        if (!official(url)) return
        val path = Uri.parse(url).encodedPath.orEmpty()
        if (path.length > 512 || paths.size >= 64) return
        paths.add(path.ifEmpty { "/" })
        path.indices.filter { path[it] == '/' }.forEach { index -> if (index > 0 && paths.size < 62) { paths.add(path.substring(0, index)); paths.add(path.substring(0, index + 1)) } }
    }
    fun read(): String {
        val values = linkedMapOf<String, String>()
        for (host in hosts) for (part in CookieManager.getInstance().getCookie("https://$host/").orEmpty().split(';')) {
            val index = part.indexOf('=')
            if (index > 0) values[part.substring(0, index).trim()] = part.substring(index + 1).trim()
        }
        return values.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }
    fun clearAsync(onComplete: () -> Unit = {}) {
        val manager = CookieManager.getInstance()
        val names = mutableSetOf("uid", "username", "token", "SESSID", "validate", "forward")
        val knownPaths = paths.toList()
        for (host in hosts) for (path in knownPaths) {
            manager.getCookie("https://$host$path").orEmpty().split(';').forEach { part ->
                part.substringBefore('=').trim().takeIf { Regex("[A-Za-z0-9_-]{1,128}").matches(it) }?.let(names::add)
            }
        }
        val removals = hosts.flatMap { host -> names.flatMap { name -> knownPaths.flatMap { path ->
            listOf("", "; Domain=.coolapk.com", "; Domain=$host").map { domain ->
                "https://$host/" to "$name=; Path=$path$domain; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly"
            }
        } } }
        var remaining = removals.size
        removals.forEach { (url, value) -> manager.setCookie(url, value) {
            remaining--
            if (remaining == 0) { manager.flush(); onComplete() }
        } }
    }
    suspend fun clear() = withTimeout(10000) {
        suspendCancellableCoroutine<Unit> { continuation -> clearAsync { if (continuation.isActive) continuation.resume(Unit) } }
    }
    fun official(url: String): Boolean = runCatching {
        val uri = Uri.parse(url)
        uri.scheme == "https" && uri.host in listOf("account.coolapk.com", "www.coolapk.com") && uri.port in listOf(-1, 443) && uri.userInfo.isNullOrEmpty()
    }.getOrDefault(false)
}

@Composable
fun OfficialWebLoginScreen(repository: AccountRepository, validateCookie: suspend (String) -> JSONObject, onBack: () -> Unit, onSuccess: () -> Unit) {
    val context = LocalContext.current
    val background = MaterialTheme.colorScheme.surface.toArgb()
    val scope = rememberCoroutineScope()
    var web by remember { mutableStateOf<WebView?>(null) }
    var ready by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var closing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var progress by remember { mutableIntStateOf(0) }
    var initializeAttempt by remember { mutableIntStateOf(0) }
    var lastCandidate by remember { mutableStateOf<String?>(null) }
    var validation by remember { mutableStateOf<Job?>(null) }
    fun close(success: Boolean) { if (!closing) scope.launch {
        if (!success) validation?.cancel()
        closing = true; web?.stopLoading(); web?.loadUrl("about:blank")
        try { LoginWebCookies.clear(); if (success) onSuccess() else onBack() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "网页登录会话清理失败，请重试"; closing = false }
    } }
    fun finish(automatic: Boolean = false) { if (!busy && !closing) validation = scope.launch {
        busy = true; error = null
        try {
            val candidate = LoginWebCookies.read()
            if (!OfficialLoginSession.hasAccountCookie(candidate)) {
                if (!automatic) error = "尚未取得完整登录凭据，请先在网页中完成登录"
                return@launch
            }
            if (automatic && lastCandidate == candidate) return@launch
            lastCandidate = candidate
            repository.acceptCookie(candidate, validateCookie); close(true)
        }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "账号校验失败" }
        finally { busy = false }
    } }
    BackHandler { if (!busy) close(false) }
    LaunchedEffect(initializeAttempt) {
        error = null
        try { LoginWebCookies.clear(); ready = true }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "无法初始化网页登录，请返回重试" }
    }
    DisposableEffect(Unit) { onDispose { validation?.cancel(); web?.stopLoading(); web?.destroy(); web = null; if (!closing) LoginWebCookies.clearAsync() } }
    Column(Modifier.fillMaxSize().background(com.green.note.ui.LocalScaffoldColor.current).statusBarsPadding().navigationBarsPadding()) {
        val toolbarBorder=MaterialTheme.colorScheme.outlineVariant.copy(alpha=.24f)
        com.green.note.ui.ReviewToolbarIcons() { Row(Modifier.fillMaxWidth().height(52.dp).drawWithContent { drawContent(); val stroke=.5.dp.toPx(); drawRect(toolbarBorder, topLeft=androidx.compose.ui.geometry.Offset(0f,size.height-stroke), size=androidx.compose.ui.geometry.Size(size.width,stroke)) }, verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = { close(false) }, enabled = !busy && !closing, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", contentDescription = "返回") }
            Spacer(Modifier.width(16.dp))
            Text("酷安官方网页登录", Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
            com.green.note.ui.ReviewIconButton(onClick = { error = null; lastCandidate = null; web?.reload() }, enabled = ready && !busy && !closing) { MaterialGlyph("refresh", contentDescription = "重新加载") }
        } }
        if (busy) com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth())
        else if (progress < 100) com.green.note.ui.ReviewLinearProgress(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth())
        error?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
        if (ready) AndroidView(modifier = Modifier.weight(1f).fillMaxWidth(), factory = {
            WebView(context).apply {
                if (android.os.Build.VERSION.SDK_INT >= 29) isForceDarkAllowed = false
                if (android.os.Build.VERSION.SDK_INT >= 33) settings.isAlgorithmicDarkeningAllowed = false
                setBackgroundColor(background)
                settings.javaScriptEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
                webChromeClient = object : WebChromeClient() { override fun onProgressChanged(view: WebView?, newProgress: Int) { progress = newProgress } }
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean {
                        if (closing) return request.url.toString() != "about:blank"
                        if (!request.isForMainFrame || LoginWebCookies.official(request.url.toString())) return false
                        error = "此登录页仅支持酷安官方站内登录，请返回使用账号密码登录"
                        return true
                    }
                    override fun onPageFinished(view: WebView?, url: String?) {
                        if (!closing && url != null && LoginWebCookies.official(url)) {
                            LoginWebCookies.notePath(url)
                            val uri = Uri.parse(url)
                            if (uri.host == "www.coolapk.com" && uri.path.orEmpty() in listOf("", "/")) finish(automatic = true)
                        }
                    }
                    override fun onReceivedError(view: WebView?, request: WebResourceRequest?, failure: WebResourceError?) {
                        if (request?.isForMainFrame == true && !closing) error = "官方登录页面加载失败，请重新加载"
                    }
                    override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, response: android.webkit.WebResourceResponse?) {
                        if (request?.isForMainFrame == true && !closing) error = "官方登录页面暂不可用，请重新加载"
                    }
                }
                web = this
                loadUrl("https://account.coolapk.com/auth/login?type=mobile")
            }
        }, update = { it.setBackgroundColor(background) })
        else Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (error == null) com.green.note.ui.ReviewCircularProgress()
            else com.green.note.ui.ReviewTextButton(onClick = { initializeAttempt++ }) { Text("重新初始化网页登录") }
        }
        com.green.note.ui.ReviewButton(onClick = { finish() }, enabled = ready && !busy && !closing, modifier = Modifier.align(Alignment.CenterHorizontally).padding(12.dp)) { Text("已完成网页登录，校验并保存") }
    }
}
