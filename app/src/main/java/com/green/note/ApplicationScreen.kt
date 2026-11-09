package com.green.note

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.luminance
import androidx.core.view.WindowCompat
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.invisibleToUser
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.green.note.account.*
import com.green.note.content.*
import com.green.note.media.*
import com.green.note.network.CaptchaScreen
import com.green.note.notifications.ReplyRuntime
import com.green.note.settings.*
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import okio.ByteString.Companion.encodeUtf8

@Composable
internal fun ApplicationScreen(graph: AppGraph, preferences: AppPreferences, replyScope: String?, consumeReply: () -> Unit,
    pendingLink: IncomingLink?, consumeLink: () -> Unit, scrolling: ScrollRateController,
    showDownloads: Boolean, consumeDownloads: () -> Unit,
) {
    DisposableEffect(scrolling) { onDispose { scrolling.release() } }
    val context = LocalContext.current
    val account by graph.accounts.state.collectAsState()
    val pendingCaptcha by graph.captcha.state.collectAsState()
    val local = remember(account.localJson) { JSONObject(account.localJson) }
    val identity = local.optJSONObject("publicIdentity")
    val session = ContentSession(if (account.anonymous) identity?.optString("uid").orEmpty() else account.uid,
        if (account.anonymous) local.optString("name") else account.username,
        if (account.anonymous) local.optString("avatar") else account.avatar, account.authenticated, account.anonymous)
    var routes by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    val route = routes.lastOrNull()
    var loginOptions by remember { mutableStateOf(false) }
    var anonymousPicker by remember { mutableStateOf(false) }
    var gallery by remember { mutableStateOf<GalleryRequest?>(null) }
    var video by remember { mutableStateOf<JSONObject?>(null) }
    var galleryCollections by remember { mutableStateOf(false) }
    val view = LocalView.current
    val photoStatusBars = remember { mutableStateMapOf<Any, Unit>() }
    val darkBars = gallery != null || video != null || MaterialTheme.colorScheme.background.luminance() < .5f
    val lightStatusBarBackground = !darkBars && (route != null || photoStatusBars.isEmpty())
    SideEffect {
        (view.context as? android.app.Activity)?.window?.let { window ->
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = lightStatusBarBackground
                isAppearanceLightNavigationBars = !darkBars
            }
        }
    }
    var destination by remember { mutableStateOf<ContentDestination?>(null) }
    var working by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val snackbar = remember { AppToastState() }
    val runtime = remember { ReplyRuntime(context) }
    val cache = remember { ComposeCacheManager(context) }
    var reminder by remember { mutableStateOf(ReplyReminderSettings()) }
    var reminderStatus by remember { mutableStateOf("尚未检查") }
    var reminderPermission by remember { mutableStateOf(runtime.permitted()) }
    var permissionPending by remember { mutableStateOf<ReplyReminderSettings?>(null) }
    fun push(next: String) { routes = ArrayList(routes + next) }
    fun back() { routes = ArrayList(routes.dropLast(1)) }
    LaunchedEffect(showDownloads) {
        if (showDownloads) {
            gallery = null
            video = null
            if (route != "downloads") push("downloads")
            consumeDownloads()
        }
    }
    fun task(block: suspend () -> Unit) {
        if (working) return
        working = true
        scope.launch {
            try { block() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { snackbar.showSnackbar(error.message ?: "操作失败，请重试") }
            finally { working = false }
        }
    }
    fun openContent(type: String, title: String = "", id: String = "", target: String = "") {
        routes = arrayListOf(); destination = ContentDestination(type, title, id, target)
    }
    fun saveReminder(next: ReplyReminderSettings) = task { runtime.save(next); runtime.configure(true); reminder = next; reminderPermission = runtime.permitted() }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val next = permissionPending; permissionPending = null; reminderPermission = granted
        if (granted && next != null) saveReminder(next) else scope.launch { snackbar.showSnackbar("未获得通知权限，自动检查未开启") }
    }
    LaunchedEffect(account.requestCookie, account.anonymous, local.optString("activeProfileId"), graph.session().device) {
        GalleryHeroRegistry.clear(); gallery = null; video = null; galleryCollections = false
        pendingCaptcha?.let { graph.captcha.finish(it, null) }; runtime.clearNotifications(); runtime.configure(true)
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(route, lifecycle) {
        fun refreshReminder() { if (route == "notifications") scope.launch {
            withContext(Dispatchers.IO) { reminder = runtime.settings(); reminderStatus = runtime.status(); reminderPermission = runtime.permitted() }
        } }
        refreshReminder()
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) refreshReminder() }
        lifecycle.addObserver(observer)
        val stop = if (route == "notifications") runtime.observe(::refreshReminder) else ({})
        onDispose { lifecycle.removeObserver(observer); stop() }
    }
    LaunchedEffect(Unit) {
        try { cache.clearIfNeeded(preferences.autoClearCacheThresholdMb) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { snackbar.showSnackbar("自动清理缓存失败，可在设置中重试") }
    }
    LaunchedEffect(replyScope) { if (replyScope != null) {
        val current = graph.session()
        val key = current.effectiveCookie.encodeUtf8().sha256().hex()
        if (current.authenticated && replyScope == key) openContent("notification_list", "评论与回复", target = "/v6/notification/list") else openContent("messages", "消息")
        consumeReply()
    } }
    LaunchedEffect(pendingLink, destination) {
        if (pendingLink != null && destination == null) openContent("link", target = pendingLink.url)
    }
    BackHandler(route != null || gallery != null || video != null) {
        when { gallery != null -> gallery = null; video != null -> video = null; else -> back() }
    }
    CompositionLocalProvider(LocalScrollRateController provides scrolling, LocalPhotoStatusBars provides photoStatusBars) {
    Box(Modifier.fillMaxSize()) {
        ActivePage(route == null && gallery == null && video == null && pendingCaptcha == null) {
        Box(if (route != null || gallery != null || video != null || pendingCaptcha != null) Modifier.clearAndSetSemantics { invisibleToUser() } else Modifier) {
            ContentApp(graph.contentApi, session, { push("settings") }, { loginOptions = true },
                { urls, index, feed -> gallery = GalleryRequest(urls, index, feed) },
                { urls, index, feed -> gallery = GalleryRequest(urls, index, feed, coolPicture = true) },
                { video = it },
                bottomBar = { selected, change -> ReviewNavigationBar(selected, change) }, externalDestination = destination,
                onExternalDestinationConsumed = {
                    val delivered = destination
                    destination = null
                    if (pendingLink != null && delivered?.type == "link" && delivered.route == pendingLink.url) consumeLink()
                }, onAccountAction = { action ->
                    when (action) {
                        "appmanager" -> openContent("appmanager", "应用管理")
                        "switch_anonymous" -> anonymousPicker = true
                        "clear_public_identity" -> if (account.anonymous) task {
                            graph.accounts.updateProfile(local.getString("activeProfileId"), local.getString("name"), local.getString("avatar"), null, expectedRevision = account.revision)
                            snackbar.showSnackbar("已恢复本地匿名资料显示")
                        }
                        else -> push(action)
                    }
                })
        }
        }
        StackedRoutes(routes, ::back, active = gallery == null && video == null && pendingCaptcha == null) { pageRoute ->
            when (pageRoute) {
                "settings" -> SettingsScreen(::back, if (account.anonymous) "匿名登录" else if (account.authenticated) "账号登录" else "游客（未登录）",
                    account.authenticated, account.hasAccount, account.anonymous, onNavigate = { page -> when (page) {
                        SettingsDestination.ACCOUNT -> loginOptions = true
                        SettingsDestination.BLACKLIST -> openContent("blacklist", "屏蔽与黑名单")
                        else -> push(page.name.lowercase())
                    } }, onLogout = { task { try { graph.api.logoutRemote() } finally { graph.accounts.logout() } } }, working = working)
                "personalization" -> PersonalizationScreen(preferences, { change -> scope.launch {
                    try { graph.settings.update(change) }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { snackbar.showSnackbar("设置保存失败，请重试") }
                } }, ::back, true)
                "storage" -> StorageSettingsScreen(preferences, session.username, { change -> task { graph.settings.update(change) } }, ::back)
                "cache" -> CacheManagementScreen(cache, preferences, { change -> task { graph.settings.update(change) } }, ::back)
                "webdav" -> WebDavBackupScreen(graph.settings, graph.accounts, graph.api::validateCookie, ::back)
                "notifications" -> NotificationSettingsScreen(reminder, account.authenticated, reminderPermission, ReplyRuntime.residentRunning,
                    reminderStatus, runtime.runtimeError(), working, onSave = { next ->
                        if (next.enabled && !reminder.enabled && !runtime.permitted()) {
                            if (Build.VERSION.SDK_INT >= 33) { permissionPending = next; permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }
                            else scope.launch { snackbar.showSnackbar("未获得通知权限，自动检查未开启") }
                        }
                        else saveReminder(next)
                    }, onCheck = { task { snackbar.showSnackbar(runtime.check(true)); reminderStatus = runtime.status() } },
                    onSystemSettings = {
                        val settingsIntent = if(Build.VERSION.SDK_INT>=26)Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))
                        try { context.startActivity(settingsIntent) } catch (_: Exception) { snackbar.showSnackbar("无法打开系统通知设置") }
                    },
                    onReplies = { openContent("notification_list", "评论与回复", target = "/v6/notification/list") }, onBack = ::back)
                "official" -> OfficialLoginScreen(graph.accounts, graph.api::validateCookie, ::back, { routes = arrayListOf() }, { push("cookie") }, { push("web_login") }, { push("device") })
                "cookie" -> CookieLoginScreen(graph.accounts, graph.api::validateCookie, ::back, { routes = arrayListOf() })
                "web_login" -> OfficialWebLoginScreen(graph.accounts, graph.api::validateCookie, ::back, { routes = arrayListOf() })
                "anonymous", "local_profile" -> LocalProfileScreen(graph.accounts, pageRoute == "anonymous", graph.api::requestPublic, ::back, { push("local_accounts") })
                "local_accounts" -> AnonymousAccountsScreen(graph.accounts, graph.api::requestPublic, ::back) { id -> task { graph.accounts.switchProfile(id); push("local_profile") } }
                "device" -> DeviceIdentityScreen(graph.session().device, graph::importDevice, graph::restoreDevice, ::back)
                "profile" -> OfficialProfileScreen(graph.accounts, graph.api::request, { bytes -> graph.api.multipart("/v6/account/changeAvatar", emptyMap(), avatar = bytes) }, ::back, imageApi = graph.contentApi)
                "qr" -> UserQrScreen(graph.contentApi, session.uid, session.username, if (account.anonymous) identity?.optString("userAvatar").orEmpty() else session.avatar, ::back)
                "downloads" -> DownloadScreen(graph.contentApi, ::back)
            }
        }
        gallery?.let { request -> GalleryScreen(request.urls, request.index, { gallery = null; galleryCollections = false }, graph.api::imageHeaders,
            graph.api.imageCacheScope(), request.feed, showPostChrome = request.coolPicture, onFeedAction = { action ->
                val feed = request.feed.takeIf { request.coolPicture }
                if (feed != null) when (action) {
                    "comment", "reply", "detail" -> { gallery = null; openContent("feed", "动态详情", feed.optString("id")) }
                    "author" -> { gallery = null; openContent("user", "个人主页", feed.optString("uid")) }
                    "share" -> task { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "https://www.coolapk.com/feed/${feed.optString("id")}")
                    }, "分享动态")) }
                    "collections" -> if (account.authenticated) galleryCollections = true else scope.launch { snackbar.showSnackbar(if (account.anonymous) "匿名账户仅支持本地收藏，暂不支持收藏夹" else "请先使用酷安账号登录") }
                    "favorite" -> if (!account.hasAccount) loginOptions = true else task {
                        val selected = graph.contentApi.toggleDefaultFavorite(feed)
                        gallery = request.copy(feed = galleryFavorite(feed, selected, account.anonymous))
                    }
                    "follow" -> if (!account.hasAccount) loginOptions = true else task {
                        val following = if (account.anonymous) local.optJSONObject("follows")?.has(feed.optString("uid")) == true else feed.optInt("isFollow") == 1
                        graph.contentApi.followUser(feed, following)
                        gallery = request.copy(feed = JSONObject(feed.toString()).put("isFollow", if (following) 0 else 1))
                    }
                    "like" -> if (!account.authenticated) { if (!account.anonymous) loginOptions = true else scope.launch { snackbar.showSnackbar("当前为匿名登录，无法使用此功能") } } else task {
                        val liked = feed.optJSONObject("userAction")?.optInt("like") == 1
                        graph.api.request(if (liked) "/v6/feed/unlike" else "/v6/feed/like", "POST", query = mapOf("id" to feed.optString("id")))
                        val updated = JSONObject(feed.toString())
                        updated.put("userAction", (updated.optJSONObject("userAction") ?: JSONObject()).put("like", if (liked) 0 else 1))
                        feed.optString("likenum").toLongOrNull()?.let { updated.put("likenum", (it + if (liked) -1 else 1).coerceIn(0, 1L shl 31)) }
                        gallery = request.copy(feed = updated)
                    }
                }
            }, saveDirectory = MediaDirectories.resolve(preferences.imageSavePathType, session.username, request.feed?.optString("username"))) }
        if (galleryCollections) gallery?.takeIf { it.coolPicture }?.let { request -> request.feed?.let { feed ->
            CollectionPicker(graph.contentApi, feed, { galleryCollections = false }) { selected ->
                gallery = request.copy(feed = galleryFavorite(feed, selected, account.anonymous)); galleryCollections = false
            }
        } }
        video?.let { row -> ResolvedVideoScreen(row, graph, { video = null }, MediaDirectories.resolve(preferences.videoSavePathType, session.username, row.optString("username"))) }
        if (loginOptions) LoginOptionsSheet({ loginOptions = false }, { loginOptions = false; push("official") }, { loginOptions = false; push("anonymous") })
        if (anonymousPicker) AnonymousAccountPickerSheet(graph.accounts, graph.api::requestPublic, { anonymousPicker = false }, { anonymousPicker = false; push("local_accounts") })
        pendingCaptcha?.let { pending -> Surface(Modifier.fillMaxSize()) { CaptchaScreen(pending.error.challenge) { graph.captcha.finish(pending, it) } } }
        AppToastHost()
    }
    }
}

private data class GalleryRequest(val urls: List<String>, val index: Int, val feed: JSONObject?, val coolPicture: Boolean = false)

internal fun galleryFavorite(feed: JSONObject, selected: Boolean, anonymous: Boolean): JSONObject {
    val wasSelected = feed.optInt("isFavorite") == 1 || feed.optJSONObject("userAction")?.optInt("favorite") == 1
    return JSONObject(feed.toString()).apply {
        put("isFavorite", if (selected) 1 else 0)
        put("userAction", (optJSONObject("userAction") ?: JSONObject()).put("favorite", if (selected) 1 else 0))
        if (!anonymous) feed.optString("favnum").toLongOrNull()?.let { count -> put("favnum", (count + (if (selected) 1 else 0) - (if (wasSelected) 1 else 0)).coerceIn(0, 1L shl 31)) }
    }
}
