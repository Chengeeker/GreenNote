package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.GlassBackdropHost
import com.green.note.ui.LocalAppPreferences
import com.green.note.ui.ActivePage
import com.green.note.ui.StackedRoutes
import com.green.note.account.LocalAvatar
import com.green.note.media.DownloadScreen
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import coil.imageLoader
import org.json.JSONObject

private data class Channel(val title: String, val route: String)
private val digitalChannels = listOf(Channel("数码库", "/product/categoryList"), Channel("数码", "V10_DIGITAL_HOME"),
    Channel("手机", "V10_CHANNEL_SJB"), Channel("排行榜", "V10_CHANNEL_SMB_TOP"), Channel("系统", "V13_DIGITAL_ROM"),
    Channel("平板", "V15_PAD"), Channel("电脑", "V8_ZHUANTI_COMPUTER_20230413"))
private val discoveryChannels = listOf(Channel("酷品", "V11_FIND_GOODS"), Channel("生活", "V15_ZHUANTI_SHENGHUO"),
    Channel("二手", "V11_DISCOVERY_SECOND_HAND"), Channel("酷图", "V11_FIND_COOLPIC"), Channel("宠物", "V15_CHONGWU"),
    Channel("运动", "V15_YUNDONG"), Channel("看看号", "/user/dyhSubscribe"), Channel("商家", "V14_SALE"), Channel("好物榜", "V12_FIND_KUBANG"))

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContentApp(
    api: ContentApi,
    session: ContentSession,
    onOpenSettings: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGallery: (List<String>, Int, JSONObject?) -> Unit,
    onOpenCoolPictureGallery: (List<String>, Int, JSONObject) -> Unit,
    onOpenVideo: (JSONObject) -> Unit,
    bottomBar: @Composable (Int, (Int) -> Unit) -> Unit,
    externalDestination: ContentDestination? = null,
    onExternalDestinationConsumed: () -> Unit = {},
    onAccountAction: (String) -> Unit = {},
) {
    var selected by rememberSaveable { mutableIntStateOf(0) }
    var digital by rememberSaveable { mutableIntStateOf(1) }
    var discovery by rememberSaveable { mutableIntStateOf(3) }
    var stack by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    val repository = remember(api) { ContentRepository(api) }
    val lists = remember(api, api.imageCacheScope()) { mutableMapOf<String, ContentListState>() }
    val discoveryStates = remember(api, api.imageCacheScope()) { mutableMapOf<String, DiscoveryState>() }
    val sortRoutes = remember(api, api.imageCacheScope()) { mutableStateMapOf<String, Pair<String, String>>() }
    val digitalHomeState = rememberDigitalHomeState(api, session, sortRoutes["digital:1"])
    val transientEntities = remember { mutableMapOf<String, JSONObject>() }
    var libraryCreationRevision by remember { mutableIntStateOf(0) }
    val mainPageHolder = rememberSaveableStateHolder()
    val scope = rememberCoroutineScope()
    val snackbar = remember { com.green.note.ui.AppToastState() }
    val context = LocalContext.current
    val homeManager = remember(context, scope) { HomeChannelState(context, scope) }
    val homeChannels = homeManager.channels
    val home = homeManager.selectedIndex
    var mainTabRoutes by remember { mutableStateOf(MainTabRoutes(emptyMap(), emptyMap())) }
    var homeRoutesReady by remember(api, api.imageCacheScope()) { mutableStateOf(false) }
    var homeChannelsReady by remember(homeManager) { mutableStateOf(false) }
    LaunchedEffect(homeManager) {
        try { homeManager.restore() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { snackbar.showSnackbar("频道设置读取失败") }
        homeChannelsReady = true
    }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    val topics = remember(api) { TopicPreparation(api, scope) { raw ->
        val url = com.green.note.network.normalizeNetworkImageUrl(raw)
        if (url.isNotEmpty()) context.imageLoader.execute(coil.request.ImageRequest.Builder(context).data(url).size(192)
            .diskCacheKey("${api.imageCacheScope()}|$url").apply { api.imageHeaders(url).forEach { (name, value) -> addHeader(name, value) } }.build())
    } }
    var topicOpening by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var topicProgress by remember { mutableStateOf(false) }
    var detailOpening by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var detailProgress by remember { mutableStateOf(false) }
    val currentOwner = api.imageCacheScope()
    val preparedApps = remember(api, currentOwner) { linkedMapOf<String, PreparedAppDetail>() }
    val fastAppUpdates = remember(stack) { stack.any { JSONObject(it).text("type") in setOf("market", "market_list", "appmanager") } }
    val appManagement = rememberAppManagement(api, lifecycle, fastAppUpdates)
    val accountHome = rememberAccountHome(api, session, lifecycle)
    val homeFollowStore = remember(api, currentOwner) { HomeFollowStore(api) }
    val homeTopicState = remember(api, currentOwner) { HomeTopicState(api) }
    val homeFeedStates = remember(api, currentOwner) { mutableMapOf<String, HomeFeedState>() }
    val homeHeadlineCache = remember(context) { HomeHeadlineCache(context) }
    var navigationOwner by remember { mutableStateOf(currentOwner) }
    LaunchedEffect(api, currentOwner) {
        mainTabRoutes = MainTabRoutes(emptyMap(), emptyMap())
        try { val parsed = parseMainTabRoutes(api.request("/v6/main/init", query = mapOf("appVersionCode" to "2604201"))); if (currentOwner == api.imageCacheScope()) mainTabRoutes = parsed }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) { }
        homeRoutesReady = true
    }
    val followChannel = homeChannels.firstOrNull { it.id == "follow" }
    val followRoute = followChannel?.let { mainTabRoutes.home[it.id] ?: it.route }
    val officialFollow = followRoute?.takeIf { session.authenticated && !session.anonymous }?.let(homeFollowStore::official)
    val localFollowEnabled = followChannel != null && session.anonymous
    val followSource by produceState<LocalFollowSource?>(null, api, currentOwner, localFollowEnabled) {
        value = null
        if (localFollowEnabled) api.localFollowSources().collect { value = it }
    }
    val localFollow = followSource?.takeIf {
        localFollowEnabled && it.profileId.isNotEmpty() && it.publicUid == session.uid && it.revision == api.localFollowRevision()
    }?.let(homeFollowStore::local)
    val warmOfficialFollow = homeRoutesReady && officialFollow != null
    LaunchedEffect(officialFollow, localFollow, lifecycle, warmOfficialFollow, homeChannelsReady) {
        if (!homeChannelsReady || officialFollow == null && localFollow == null) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            delay(150)
            if (warmOfficialFollow && officialFollow?.initialized == false && officialFollow.error == null) officialFollow.resume()
            if (localFollow?.initialized == false && localFollow.sourceError == null) localFollow.refresh()
        }
    }
    LaunchedEffect(currentOwner) {
        if (navigationOwner != currentOwner) { stack = arrayListOf(); transientEntities.clear(); lists.clear(); clearContentTextCache(); clearContentDeviceCache(); navigationOwner = currentOwner }
    }
    var moreRow by remember { mutableStateOf<JSONObject?>(null) }
    var publishPicker by remember { mutableStateOf(false) }
    fun push(type: String, title: String = "", id: String = "", route: String = "") {
        if (route.length > 8192 || id.length > 1024 || title.length > 1024) { snackbar.showSnackbar("页面参数过长"); return }
        stack = ArrayList((stack + JSONObject().put("type", type).put("title", title).put("id", id).put("route", route).toString()).takeLast(32))
    }
    fun back() { if (stack.isNotEmpty()) stack = ArrayList(stack.dropLast(1)) else selected = 0 }
    fun notice(text: String) { scope.launch { snackbar.showSnackbar(text) } }
    LaunchedEffect(stack.toList(), selected, home, digital, discovery, currentOwner) {
        topicOpening?.cancel()
        topicProgress = false
        detailOpening?.cancel()
        detailProgress = false
    }
    fun openPreparedDetail(error: String, open: suspend (() -> Boolean) -> Unit) {
        if (detailOpening?.isActive == true) return
        val source = stack.toList()
        val tabs = listOf(selected, homeManager.selectedId, digital, discovery)
        fun canOpen() = stack == source && tabs == listOf(selected, homeManager.selectedId, digital, discovery) &&
            currentOwner == api.imageCacheScope() && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        val job = scope.launch(start = kotlinx.coroutines.CoroutineStart.LAZY) {
            var progress: kotlinx.coroutines.Job? = null
            try {
                lifecycle.currentStateFlow.first { it == Lifecycle.State.DESTROYED || it.isAtLeast(Lifecycle.State.RESUMED) }
                if (!canOpen()) return@launch
                progress = launch { delay(180); if (canOpen()) detailProgress = true }
                open(::canOpen)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                if (canOpen()) notice(error)
            } finally {
                progress?.cancel()
                if (detailOpening === coroutineContext[kotlinx.coroutines.Job]) {
                    detailProgress = false
                    detailOpening = null
                }
            }
        }
        detailOpening = job
        job.start()
    }
    fun openAppDetail(id: String, title: String = "应用详情") {
        if (id.isBlank() || id.length > 1024) return
        openPreparedDetail("无法打开应用详情，请重试") { canOpen ->
            val detail = prepareAppDetail(context, api, id)
            if (canOpen()) {
                preparedApps.remove(id)
                preparedApps[id] = detail
                if (preparedApps.size > 8) preparedApps.remove(preparedApps.keys.first())
                push("apk", title, id)
            }
        }
    }
    fun openPreparedTopic(tag: String, initial: JSONObject) {
        if (topicOpening?.isActive == true) return
        val source = stack.toList(); val tab = listOf(selected, home, digital, discovery); val owner = api.imageCacheScope()
        fun canOpen() = stack == source && tab == listOf(selected, home, digital, discovery) && owner == api.imageCacheScope() && lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
        topicOpening = scope.launch {
            val delay = launch { kotlinx.coroutines.delay(180); if (canOpen()) topicProgress = true }
            try { topics.prepare(tag).await(); if (canOpen()) { transientEntities["topic:$tag"] = initial; push("topic", initial.text("title").ifEmpty { tag }, tag) } }
            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: Exception) { if (canOpen()) notice("打开话题失败，请点击重试：${failure.message}") }
            finally { delay.cancel(); topicProgress = false }
        }
    }
    fun requireAccount(message: String = session.loginRequiredMessage): Boolean {
        if (session.authenticated) return true
        notice(message)
        return false
    }
    fun openList(title: String, route: String) {
        val uri = Uri.parse(route)
        if (uri.path in setOf("/v6/user/hitHistoryList", "/v6/user/productAlbumList", "/v6/user/dyhFollowList", "/v6/user/dyhSubscribe", "/v6/user/editorDyhList", "/v6/user/albumList")) {
            val path = uri.path.orEmpty(); val kind = when { path.endsWith("hitHistoryList") -> "history"; path.endsWith("productAlbumList") -> "anylist"; path.endsWith("albumList") -> "albums"; else -> "dyh" }
            push("community_library", title, uri.getQueryParameter("uid").orEmpty().ifEmpty { session.uid }, JSONObject().put("kind", kind).put("initialTab", when { path.endsWith("dyhSubscribe") -> 1; path.endsWith("editorDyhList") -> 2; else -> 0 }).toString())
        }
        else if (uri.path == "/local/favorites" || uri.path == "/local/follows" || uri.path == "/local/productFollows") push("local_library", title, uri.lastPathSegment.orEmpty())
        else if (uri.path in setOf("/v6/topic/myFollowTopicList", "/v6/user/recentHistoryList")) push("account_topics", title, if (uri.path!!.contains("myFollowTopic")) "followed" else "recent")
        else if (uri.path in setOf("/v6/collection/list", "/v6/collection/myCollectionList")) push("collections", title, uri.getQueryParameter("uid").orEmpty().ifEmpty { session.uid }, route)
        else if (uri.path in setOf("/v6/user/followList", "/v6/user/myFollowList", "/v6/user/fansList", "/v6/user/myFansList", "/v6/user/userFansList"))
            push("relations", "酷友列表", uri.getQueryParameter("uid").orEmpty().ifEmpty { session.uid }, if (uri.path.orEmpty().contains("Fans", true)) "3" else "0")
        else push("list", title, route = route)
    }
    fun openLink(input: String) {
        var raw = unwrapShoppingLink(input.trim()).removePrefix("#")
        if (raw.isBlank() || raw.length > 8192 || raw.any { it.code < 32 }) { notice("网页地址无效"); return }
        if (Regex("^(feed|picture|u|user|t|topic|product|collection)/").containsMatchIn(raw)) raw = "/$raw"
        val uri = Uri.parse(raw)
        val path = if (uri.scheme == "coolmarket") "/${uri.host.orEmpty()}${uri.path.orEmpty()}" else uri.path.orEmpty()
        if (uri.userInfo != null) { notice("不支持的链接"); return }
        if (shoppingPackage(uri) != null && openShoppingApp(context, raw)) return
        val official = uri.scheme == "coolmarket" || uri.scheme == null && !raw.startsWith("//") || uri.scheme in setOf("https", "http") && uri.host?.let { it == "coolapk.com" || it.endsWith(".coolapk.com") } == true
        val parts = path.trim('/').split('/').filter(String::isNotEmpty)
        val kind = parts.firstOrNull().orEmpty()
        val value = parts.getOrNull(1).orEmpty()
        val replyId = if (uri.isHierarchical) uri.getQueryParameter("rid").orEmpty().ifEmpty { uri.getQueryParameter("replyId").orEmpty() } else ""
        val threadId = when { kind == "reply" -> if (value == "detail") uri.getQueryParameter("id").orEmpty() else value; kind == "feed" && value == "reply" -> parts.getOrNull(2).orEmpty(); kind == "feed" -> replyId; else -> "" }
        when {
            official && Regex("[1-9][0-9]*").matches(threadId) -> push("reply_thread", "评论详情", threadId)
            official && path == "/feed/headline" -> openList("今日酷安", "/v6/main/headline" + uri.encodedQuery?.let { "?$it" }.orEmpty())
            official && kind == "event" && Regex("[1-9][0-9]*").matches(value) -> push("event", "活动详情", value)
            official && kind == "search" -> { val query = uri.getQueryParameter("q").orEmpty().ifEmpty { uri.getQueryParameter("searchValue").orEmpty() }; if (query.isEmpty()) push("search") else push("searchresults", query, uri.getQueryParameter("type").orEmpty().ifEmpty { "feed" }) }
            official && path == "/v6/feed/replyDetail" -> push("api_detail", "评论详情", route = raw)
            official && (raw.contains("/productSelector/configSearch") || raw.contains("V9_DEVICE_SELECTOR")) -> push("product_selector", "选机中心")
            official && homeDestination("", raw) != null -> homeDestination("", raw)!!.let { push("home_destination", it.title, it.kind, raw) }
            official && kind in setOf("question", "live", "collection", "dyh", "album", "anylist", "productAlbum") && value.isNotEmpty() -> {
                val id = if (value == "detail") uri.getQueryParameter("id").orEmpty() else value
                if (Regex("[1-9][0-9]*").matches(id)) push("community", communityTitle(if (kind == "productAlbum") "anylist" else kind), id, if (kind == "productAlbum") "anylist" else kind) else notice("页面地址无效")
            }
            official && kind == "goods" && value in setOf("lists", "ranking") && parts.getOrNull(2)?.toLongOrNull() != null -> push("community", "好物榜单", parts[2], "goods")
            official && path == "/feed/writer" -> if (requireAccount()) push("publish", "发布动态", "feed", route = JSONObject().put("tag", uri.getQueryParameter("tag").orEmpty()).put("productId", uri.getQueryParameter("productId").orEmpty()).toString())
            official && kind in setOf("feed", "picture") && parts.size <= 2 -> {
                val id = if (value.isEmpty() || value == "detail") uri.getQueryParameter("id").orEmpty() else value
                if (Regex("[1-9][0-9]*").matches(id)) push("feed", "动态详情", id) else notice("动态地址无效")
            }
            official && kind in setOf("u", "user") && value.isNotEmpty() -> push("user", "个人主页", Uri.decode(value))
            official && kind in setOf("t", "topic") && value.isNotEmpty() -> push("topic", "话题", Uri.decode(value))
            official && kind == "product" && (value.toLongOrNull() != null || uri.getQueryParameter("id")?.toLongOrNull() != null) -> push("product", "机型详情", value.ifEmpty { uri.getQueryParameter("id").orEmpty() })
            official && kind in setOf("apk", "game") && value.isNotEmpty() -> openAppDetail(value)
            official && path in setOf("/page", "/v6/page/dataList") -> push("list", "", route = "$path${uri.encodedQuery?.let { "?$it" }.orEmpty()}")
            uri.scheme == null && raw.startsWith("/v6/") -> openList("", raw)
            isActivityDocument(raw) -> push("activity_document", "活动详情", route = raw)
            validWebUrl(raw) -> push("browser", route = raw)
            raw.startsWith('/') && !raw.startsWith("//") -> push("browser", route = "https://www.coolapk.com$raw")
            uri.scheme in setOf("mailto", "tel") -> try { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (_: Exception) { notice("无法打开链接") }
            else -> notice("不支持的链接")
        }
    }
    fun openFeed(row: JSONObject, route: String = "") {
        val id = row.text("id", "entityId")
        if (id.isBlank()) return
        transientEntities["feed:$currentOwner:$id"] = row
        if (transientEntities.size > 64) transientEntities.remove(transientEntities.keys.first())
        push("feed", "动态详情", id, route)
    }
    fun openEntity(row: JSONObject) {
        val templateRoute = contentTemplateListRoute(row)
        if (templateRoute.isNotEmpty()) { openList(row.text("goods_title", "title", "name", "username", "productName", "tag").ifEmpty { "酷安内容" }, "/v6/page/dataList?url=" + Uri.encode(templateRoute)); return }
        if (row.optBoolean("_composeInAppBrowser")) {
            val url = row.text("url")
            if (validWebUrl(url)) push("browser", route = url) else notice("网页地址无效")
            return
        }
        if (row.optBoolean("_composeHeadlineTarget") && row.text("entityType") !in setOf("topic", "tag")) {
            val route = row.text("url"); val title = row.text("title", "entityTitle", "name")
            val stripped = route.removePrefix("#"); val parsed = runCatching { Uri.parse(stripped) }.getOrNull()
            when {
                title == "发视频" || route.contains("feed/create") || route.contains("feed/compose") -> { push("publish", "发布动态", "feed"); return }
                route.startsWith("#/") && !route.contains("/rankList") && !route.contains("coolPictureRankList") -> { openList(title.ifEmpty { "酷安内容" }, "/v6/page/dataList?url=" + Uri.encode(route)); return }
                route.contains("coolPictureRankList") || title.contains("酷图") -> { openList(title.ifEmpty { "酷图榜" }, "/v6/feed/coolPictureRankList"); return }
                route.contains("rankList") || route.contains("RANK") -> {
                    val type = parsed?.takeIf { it.isHierarchical }?.getQueryParameter("type").orEmpty().ifEmpty { if (title.contains("月")) "monthly" else if (title.contains("收藏")) "favorite" else "weekly" }
                    openList(title.ifEmpty { "榜单" }, "/v6/feed/rankList?type=" + Uri.encode(type)); return
                }
                route.startsWith("searchTab://") || listOf("search?key=", "search?keywords=", "search?searchValue=").any(route::contains) -> {
                    val query = parsed?.takeIf { it.isHierarchical }?.let { it.getQueryParameter("key") ?: it.getQueryParameter("keywords") ?: it.getQueryParameter("searchValue") }.orEmpty().ifEmpty { title }
                    push("search", id = query); return
                }
                parsed?.path in setOf("/feed/headline", "/v6/main/headline") -> { openList(title.ifEmpty { "今日酷安" }, "/v6/main/headline" + parsed?.encodedQuery?.let { "?$it" }.orEmpty()); return }
                parsed?.path == "/page/dataList" -> { openList(title.ifEmpty { "酷安内容" }, "/v6/page/dataList" + parsed.encodedQuery?.let { "?$it" }.orEmpty()); return }
            }
        }
        if ((row.text("_composeQuestionId").isNotEmpty() || listOf(row.text("entityType", "entity_type"), row.text("feedType", "feed_type"), row.text("targetType")).any { it.contains("answer", true) }) && row.text("id", "entityId").isNotEmpty()) { openFeed(row, JSONObject().put("questionId", row.text("_composeQuestionId", "questionId", "question_id", "fid")).toString()); return }
        val topicTag = carouselTopicTag(row)
        if (topicTag.isNotEmpty() && !contentEntityIsFeed(row)) { openPreparedTopic(topicTag, row); return }
        if (row.optBoolean("_composeMarketList")) { push("market_list", row.text("title"), route = row.text("url")); return }
        val homeTarget = homeDestination(row.text("title"), row.text("url"))
        if (row.text("title") == "选机中心") { push("product_selector", "选机中心"); return }
        if (homeTarget != null) { push("home_destination", homeTarget.title, homeTarget.kind, row.text("url").ifEmpty { homeTarget.route }); return }
        val community = communityKind(row)
        if (community != null && row.text("id", "entityId").isNotEmpty()) { transientEntities["community:$community:${row.text("id", "entityId")}"] = row; if (transientEntities.size > 64) transientEntities.remove(transientEntities.keys.first()); push("community", communityTitle(community), row.text("id", "entityId"), community); return }
        if (contentEntityType(row) == "pear_goods" || row.has("goods_buy_url") || row.has("goods_url")) {
            val target = contentGoodsTarget(row)
            if (target.isNotEmpty()) openLink(target) else notice("暂无商品链接")
            return
        }
        val destination = contentEntityDestination(row)
        when (destination?.type) {
            "feed" -> openFeed(JSONObject(row.toString()).put("id", destination.id))
            "dyh", "collection" -> push("community", communityTitle(destination.type), destination.id, destination.type)
            "event" -> push("event", "活动详情", destination.id)
            "reply_thread" -> push("reply_thread", "评论详情", destination.id)
            "user" -> push("user", "个人主页", destination.id)
            "product" -> push("product", row.text("title", "name"), destination.id)
            "apk" -> openAppDetail(destination.id, row.text("title", "name"))
            "topic" -> openPreparedTopic(destination.id, row)
            else -> {
                val url = row.text("url")
                if (destination?.type != "raw" && url.isNotEmpty()) openLink(url)
                else {
                    val key = java.util.UUID.randomUUID().toString()
                    transientEntities[key] = row
                    if (transientEntities.size > 64) transientEntities.remove(transientEntities.keys.first())
                    push("raw", row.text("title"), key)
                }
            }
        }
    }
    fun like(row: JSONObject) {
        if (session.anonymous) { notice(session.loginRequiredMessage); return }
        val id = row.text("id")
        if (id.isEmpty()) return
        scope.launch {
            try {
                api.request(if (row.optJSONObject("userAction")?.optInt("like") == 1) "/v6/feed/unlike" else "/v6/feed/like", "POST", mapOf("id" to id))
                notice("操作成功")
            } catch (error: Exception) { notice(error.message ?: "操作失败") }
        }
    }
    BackHandler(stack.isEmpty() && selected != 0) { back() }
    BackHandler(stack.isEmpty() && selected == 0 && homeManager.showOverlay) { homeManager.showOverlay = false }
    LaunchedEffect(externalDestination?.eventId) {
        externalDestination?.let { destination ->
            when (destination.type) {
                "link" -> openLink(destination.route)
                "apk" -> openAppDetail(destination.id, destination.title)
                else -> push(destination.type, destination.title, destination.id, destination.route)
            }
            onExternalDestinationConsumed()
        }
    }
    BackHandler(detailOpening?.isActive == true) { detailOpening?.cancel() }
    val floatingNav = LocalAppPreferences.current.floatingNavBar
    val selectNav: (Int) -> Unit = { index ->
        if (index == 2) { val denied = publishMenuDenied(session); if (denied == null) publishPicker = true else notice(denied) } else selected = index
    }
    @Composable fun Page(current: JSONObject?) {
    val todayPage = current?.text("type") == "list" && (current.text("title").trim().startsWith("今日酷安") || Uri.parse(current.text("route")).path in setOf("/v6/main/headline", "/main/headline"))
    val edgeTop = current?.text("type") in setOf("event", "user", "topic", "apk", "product")
    val ownsToolbar = current?.text("type") in setOf("search", "searchresults", "publish", "blacklist", "browser", "activity_document", "topic", "home_destination", "product_selector", "user", "apk", "product", "community", "community_library", "messages", "sessions", "chat", "market", "feed", "relations", "appmanager", "collections", "event", "account_topics") || current?.text("id") == "rating"
    val backdropSource = if (current == null) selected to when (selected) {
        0 -> home
        1 -> digital
        3 -> discovery
        else -> 0
    } else current
    GlassBackdropHost(Modifier.fillMaxSize(), sourceKey = backdropSource, content = {
    Scaffold(
        containerColor = com.green.note.ui.LocalScaffoldColor.current,
        contentWindowInsets = when {
            current?.text("type") in setOf("apk", "product") -> WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal)
            edgeTop -> WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom)
            else -> ScaffoldDefaults.contentWindowInsets
        },
        snackbarHost = { com.green.note.ui.AppToastSink(snackbar) },
        bottomBar = { if (current == null && !floatingNav) bottomBar(selected, selectNav) },
        topBar = {
            com.green.note.ui.ReviewToolbarIcons {
            if (!edgeTop) Column(Modifier.background(com.green.note.ui.LocalScaffoldColor.current).statusBarsPadding().contentToolbarBorder(current == null && selected !in setOf(0, 4))) {
                if (current == null) {
                    // Flutter's 48dp menu target expands the 38dp preferred bottom;
                    // AppBar keeps its 90dp total and constrains the toolbar to 42dp.
                    val homeTabsVisible = selected == 0 && !homeManager.showOverlay
                    Row(Modifier.fillMaxWidth().height(if (homeTabsVisible) 42.dp else 52.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (selected != 4) {
                            Box(Modifier.width(54.dp).padding(start = 14.dp), contentAlignment = Alignment.Center) {
                            if (session.anonymous) LocalAvatar(session.avatar, session.username, Modifier.size(34.dp).clickable { selected = 4 })
                            else ContentAvatar(api, session.avatar, session.username, 34.dp) { if (session.uid.isNotEmpty()) push("user", "个人主页", session.uid) else selected = 4 }
                            }
                            Spacer(Modifier.width(8.dp))
                            Row(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(18.dp))
                                .background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .65f)).clickable { push("search") }.padding(horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                Text("搜索动态/话题/应用/酷友...", Modifier.weight(1f), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                MaterialGlyph("search_rounded", size = 20.dp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.width(8.dp))
                        } else {
                            Spacer(Modifier.weight(1f))
                            com.green.note.ui.ReviewToolbarIcons(MaterialTheme.colorScheme.onSurfaceVariant) {
                                ContentIcon("search_rounded", "搜索", { push("search") })
                                ContentIcon("settings_outlined", "设置", onOpenSettings)
                            }
                        }
                        Box(Modifier.size(48.dp).clickable { push("market", "应用商城") }, contentAlignment = Alignment.Center) {
                            Text("APP", Modifier.border(1.4.dp, MaterialTheme.colorScheme.onSurface, RoundedCornerShape(4.dp)).padding(1.4.dp).padding(horizontal = 4.dp, vertical = 1.5.dp), fontSize = 9.5.sp, fontWeight = FontWeight.Black, letterSpacing = .5.sp)
                        }
                        com.green.note.ui.ReviewToolbarIcons(MaterialTheme.colorScheme.onSurfaceVariant) {
                            ContentIcon("mail_outline_rounded", "消息", { push("messages", "消息") })
                        }
                        Spacer(Modifier.width(4.dp))
                    }
                    val channels = when (selected) { 0 -> homeChannels.map { Channel(it.title, it.route) }; 1 -> digitalChannels; 3 -> discoveryChannels; else -> emptyList() }
                    if (channels.isNotEmpty() && !(selected == 0 && homeManager.showOverlay)) Row(verticalAlignment = Alignment.CenterVertically) {
                        ChannelTabs(channels.map { it.title }, when (selected) { 0 -> home; 1 -> digital; else -> discovery }, Modifier.weight(1f), selected) {
                            when (selected) { 0 -> homeManager.select(it); 1 -> digital = it; else -> discovery = it }
                        }
                        if (selected == 0) com.green.note.ui.ReviewIconButton(onClick = { homeManager.showOverlay = true; homeManager.editing = false }, modifier = Modifier.size(48.dp)) { MaterialGlyph("menu_rounded", size = 20.dp, contentDescription = "自定义频道") }
                    }
                } else if (!ownsToolbar) {
                    Row(Modifier.fillMaxWidth().height(if (todayPage) 56.dp else 52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
                        ContentIcon("arrow_back", "返回", ::back, Modifier.width(56.dp)); Spacer(Modifier.width(if (todayPage) 4.dp else 16.dp))
                        val title = if (todayPage) java.util.Calendar.getInstance().let { "今日酷安:${it.get(java.util.Calendar.YEAR)}年${it.get(java.util.Calendar.MONTH) + 1}月${it.get(java.util.Calendar.DAY_OF_MONTH)}日" } else current.text("title")
                        Text(title, Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (todayPage) ContentIcon("refresh_rounded", "刷新", { lists.filterKeys { it.startsWith(current.toString() + ":") }.values.forEach { state -> scope.launch { state.load(true) } } })
                    }
                }
            }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
            val onUser: (String) -> Unit = { push("user", "个人主页", it) }
            val renderList: @Composable (String, ContentRequest, Boolean) -> Unit = { key, request, isHome ->
                val sorting = sortRoutes[key]
                val activeRequest = sorting?.first?.let(::contentRequest) ?: request
                val cardContext = when {
                    current != null && (request.path in setOf("/v6/main/headline", "/main/headline") || current.text("title").trim().startsWith("今日酷安")) -> "today"
                    key.startsWith("home:") -> "home"
                    key == "digital:1" -> "digital_home"
                    key == "digital:4" -> "system"
                    key.startsWith("brand:") -> "brand"
                    key.startsWith("digital") -> "digital_channel"
                    key.startsWith("discover:") -> "discovery"
                    else -> "api"
                }
                val state = if (key == "digital:1") digitalHomeState else lists.getOrPut(key) { ContentListState() }
                LaunchedEffect(state, activeRequest, sorting) {
                    if (key == "digital:1") return@LaunchedEffect
                    state.bind(activeRequest to sorting) { page, first, last ->
                        val result = if (isHome && sorting == null) repository.home(request.path, page, first, last) else repository.page(activeRequest, page, first, last)
                        val baseRows = state.rows
                        val sortIndex = baseRows.indexOfFirst { it.text("title").contains("动态区") || it.text("entityTemplate").equals("sortSelectCard", true) }
                        val prefix = if (sorting != null && page == 1 && sortIndex >= 0) baseRows.take(sortIndex + 1) else emptyList()
                        val rows = if (prefix.isEmpty()) result.rows else prefix + result.rows.filterNot {
                            it.text("entityTemplate").equals("sortSelectCard", true) && prefix.any { card -> card.text("entityTemplate").equals("sortSelectCard", true) }
                        }
                        result.copy(rows = normalizeSpecializedCards(rows.map { JSONObject(it.toString()).put("_composeCardContext", cardContext).put("_composeGroupProducts", key.startsWith("brand:") || key.startsWith("digitalrank:")).put("_composeHeadline", key.startsWith("home:headline:")).put("_composeOfficialLayout", key.startsWith("home:follow:")).put("_selectedSortTitle", sorting?.second.orEmpty()).put("_composeSelectedRoute", sorting?.first.orEmpty()).put("_composeDiscoveryChannel", if (key.startsWith("discover:")) discoveryChannels[discovery].title else "") }))
                    }
                }
                LaunchedEffect(key, state.rows, sorting) {
                    if (key.startsWith("brand:") && sorting == null) {
                        val latest = state.rows.firstOrNull { it.text("entityTemplate").equals("sortSelectCard", true) }?.optJSONArray("entities").objects().firstOrNull { it.text("title") == "最新" && it.text("url").isNotEmpty() }
                        if (latest != null) sortRoutes[key] = latest.text("url") to latest.text("title")
                    }
                }
                key(key) { ContentList(api, state, { row ->
                    if (row.optBoolean("_composeFollowRetry")) scope.launch { state.load(true) }
                    else if (row.optBoolean("_composeSortRequest") || row.optBoolean("_composeDiscoverySelect")) sortRoutes[key] = row.text("url") to row.text("title") else openEntity(row)
                }, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }, contentPadding = PaddingValues(bottom = if (current == null) 92.dp else 0.dp), endText = if (key == "digital:1") "没有更多了" else "", refreshTextDimension = if (key == "digital:1") with(androidx.compose.ui.platform.LocalDensity.current) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.width.toDp() } - 80.dp else null, loadInitially = false) }
            }
            if (current == null) {
                mainPageHolder.SaveableStateProvider("main:$selected") {
                when (selected) {
                    0 -> Box(Modifier.fillMaxSize()) {
                        ContentChannelPager(home, homeChannels.size, homeManager::select) { index ->
                            val channel = homeChannels[index]
                            val route = if (channel.id == "topic") channel.route else mainTabRoutes.home[channel.id] ?: channel.route
                            key(channel.id, route) {
                                if (channel.id == "topic") HomeTopicScreen(api, ::openEntity, state = homeTopicState)
                                else if (channel.id == "follow") HomeFollowScreen(api, session, ::openEntity, onUser, ::openLink,
                                    onOpenGallery, ::like, { moreRow = it }, onOpenAccount, officialFollow, localFollow)
                                else {
                                    val state = homeFeedStates.getOrPut(channel.id) { HomeFeedState(api, channel.id, route, homeHeadlineCache) }
                                    LaunchedEffect(state, route) { state.updateRoute(route) }
                                    HomeFeedScreen(api, state, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it })
                                }
                            }
                        }
                        if (homeManager.showOverlay) HomeChannelOverlay(homeManager)
                    }
                    1 -> ContentChannelPager(digital, digitalChannels.size, { digital = it }) { index -> if (index == 0) DigitalLibraryScreen(api, onProduct = ::openEntity, onBrand = { title, route -> push("digitalbrand", title, route = route) }, onLogin = onOpenAccount)
                        else if (index == 2) Column { DigitalDeviceOverview(api, ::openEntity, { digital = 0 }, { digital = 4 }); Box(Modifier.weight(1f)) { renderList("digital:2", contentRequest(digitalChannels[2].route), false) } }
                        else if (index == 3) DigitalTabsScreen(api, "V10_CHANNEL_SMB_TOP") { title, route -> renderList("digitalrank:$title", contentRequest(route), false) }
                        else renderList("digital:$index", contentRequest(digitalChannels[index].route), false) }
                    3 -> ContentChannelPager(discovery, discoveryChannels.size, { discovery = it }) { index -> val channel = discoveryChannels[index]; val route = mainTabRoutes.discovery[channel.title] ?: channel.route; val state = discoveryStates.getOrPut("${channel.title}:$route") { DiscoveryState(api, channel.title, route) }
                        key(channel.title, route) { DiscoveryScreen(api, state, ::openEntity, onUser, ::openLink, onOpenGallery, onOpenCoolPictureGallery, ::like, { moreRow = it }) }
                    }
                    4 -> AccountOverview(api, session, accountHome, onUser, ::openList, ::openLink, onOpenGallery, ::like, { moreRow = it }) { action ->
                        when (action) { "appmanager" -> push("appmanager", "应用管理"); "settings" -> onOpenSettings(); else -> onAccountAction(action) }
                    }
                }
                }
            } else when (current.text("type")) {
                "search" -> SearchScreen(api, ::back, { query, type -> push("searchresults", query, type) }, initialQuery = current.text("id"))
                "searchresults" -> SearchResultsScreen(api, current.text("title"), current.text("id"), ::back, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it })
                "list" -> renderList(current.toString(), contentRequest(current.text("route")), false)
                "local_library" -> LocalLibraryScreen(api, current.text("id"), ::openEntity, onUser)
                "account_topics" -> AccountTopicScreen(api, current.text("id") == "followed", ::openEntity, onUser, ::openLink, ::back)
                "event" -> EventDetailScreen(api, current.text("id"), ::back, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it })
                "collections" -> CollectionLibraryScreen(api, current.text("id"), ::back, ::openEntity, onUser, ::openLink, onOpenGallery, title = current.text("title"), route = current.text("route"))
                "home_destination" -> HomeDestinationScreen(api, current.text("id"), current.text("title"), current.text("route"), ::back, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }) { if (session.authenticated || session.anonymous) push("publish", "发布动态", "feed") else notice(session.loginRequiredMessage) }
                "product_selector" -> NativeProductSelector(api, ::back, ::openEntity)
                "feed" -> { val detailArgs = runCatching { JSONObject(current.text("route")) }.getOrNull(); val id = current.text("id"); FeedDetailScreen(api, id, session, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }, onOpenAccount, initialReplyId = detailArgs?.text("replyId") ?: current.text("route"), onBack = ::back, questionId = detailArgs?.text("questionId").orEmpty(), initialFeed = transientEntities["feed:$currentOwner:$id"]) }
                "user" -> UserScreen(api, current.text("id"), ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }, session, ::back, onAccountAction,
                    { partner -> push("chat", partner.name.ifEmpty { "私信" }, partner.uid, JSONObject().put("avatar", partner.avatar).toString()) }, onOpenAccount)
                "topic" -> TopicScreen(api, current.text("id"), ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }, ::back,
                    { push("search", id = it) }, { tag -> push("publish", "发布动态", "feed", "tag:$tag") }, initial = transientEntities["topic:${current.text("id")}"])
                "market" -> MarketScreen(api, ::back, { query -> push("searchresults", query, "apk") }, { push("appmanager", "应用管理") }, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it })
                "market_list" -> MarketListScreen(api, current.text("route"), ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it })
                "messages" -> NotificationCenterScreen(api, ::back, { title, path -> push("notification_list", title, route = path) }, { push("sessions", "私信") },
                    { feed, reply -> push("feed", "动态详情", feed, reply) }, onUser, ::openLink, { push("reply_thread", "评论详情", it) })
                "notification_list" -> NotificationListScreen(api, current.text("route"), { feed, reply -> push("feed", "动态详情", feed, reply) }, onUser, ::openLink, { push("reply_thread", "评论详情", it) })
                "reply_thread" -> NotificationReplyThread(api, current.text("id"), { feed, reply -> push("feed", "动态详情", feed, reply) }, { push("reply_thread", "评论详情", it) }, ::openLink)
                "sessions" -> MessageSessionsScreen(api, ::back) { partner, key -> push("chat", partner.name.ifEmpty { "私信" }, partner.uid, route = JSONObject().put("ukey", key).put("avatar", partner.avatar).toString()) }
                "chat" -> {
                    val metadata = runCatching { JSONObject(current.text("route")) }.getOrDefault(JSONObject())
                    MessageChatScreen(api, session, MessagePartner(current.text("id"), current.text("title"), metadata.text("avatar")), metadata.text("ukey"), onOpenGallery, ::openLink, ::back) { push("user", "个人主页", it) }
                }
                "appmanager" -> AppManagementScreen(appManagement, ::back, { openAppDetail(it) }) { packages, active -> DownloadScreen(api, ::back, packages = packages, showAppBar = false, active = active) }
                "blacklist" -> BlacklistScreen(api, session, ::back, onUser)
                "browser" -> BrowserScreen(current.text("route"), ::back)
                "activity_document" -> BrowserScreen(current.text("route"), ::back, activityDocument = true, onNavigate = ::openLink)
                "digitalbrand" -> DigitalTabsScreen(api, current.text("route"), brand = true) { title, route -> renderList("brand:${current.text("route")}:$title", contentRequest(route), false) }
                "relations" -> FollowingScreen(api, current.text("id"), current.text("route").toIntOrNull() ?: 0, ::back, onUser) { partner ->
                    push("chat", partner.name, partner.uid, JSONObject().put("avatar", partner.avatar).toString())
                }
                "community" -> CommunityDetailScreen(api, current.text("route"), current.text("id"), ::back, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }, initial = transientEntities["community:${current.text("route")}:${current.text("id")}"]) { push("feed", "评论", current.text("id")) }
                "community_library" -> { val args = JSONObject(current.text("route")); CommunityLibraryScreen(api, args.text("kind"), current.text("id"), session, ::back, ::openEntity, onUser, ::openLink, onOpenGallery, ::like, { moreRow = it }, { if (requireAccount("请先使用酷安账号登录")) push("publish", "创建清单", "collection") }, initialTab = args.optInt("initialTab"), creationRevision = libraryCreationRevision) }
                "apk", "product" -> NativeEntityDetailScreen(api, current.text("type"), current.text("id"), ::openLink,
                    onOpenGallery, ::back, ::openEntity, ::like, { moreRow = it },
                    preparedApp = preparedApps[current.text("id")]) { push("publish", "发布动态", "feed") }
                "publish" -> when {
                    current.text("id").startsWith("forward:") -> PublishScreen(api, current.text("id"), ::back)
                    current.text("id") in setOf("collection", "rank") -> AlbumCreateScreen(api, current.text("id") == "rank", session = session, onMyRatings = { uid -> openList("我的点评", "/v6/page/dataList?url=" + Uri.encode("#/feed/nodeRatingList") + "&uid=" + Uri.encode(uid) + "&targetType=all&parseRatingToFeed=1") }, onDone = ::back, onCreated = { libraryCreationRevision++; back() })
                    current.text("id") == "rating" -> RatingSquareScreen(api, ::back, session, onMyRatings = { uid -> openList("我的点评", "/v6/page/dataList?url=" + Uri.encode("#/feed/nodeRatingList") + "&uid=" + Uri.encode(uid) + "&targetType=all&parseRatingToFeed=1") })
                    else -> {
                        val route = current.text("route")
                        val fields = remember(route) { runCatching { JSONObject(route) }.getOrNull() }
                        TypedPublishScreen(api, current.text("id"), ::back, initialProductId = fields?.text("productId") ?: route.takeUnless { it.startsWith("tag:") }.orEmpty(), initialTag = fields?.text("tag") ?: route.takeIf { it.startsWith("tag:") }?.removePrefix("tag:").orEmpty(), onLink = ::openLink)
                    }
                }
                "api_detail" -> ApiObjectDetail(api, request = contentRequest(current.text("route")))
                "raw" -> transientEntities[current.text("id")]?.let { ApiObjectDetail(api, initial = it) }
                    ?: Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewTextButton(onClick = ::back) { Text("内容已失效，返回重新打开") } }
            }
        }
    }
    }, overlay = {
        if (current == null && floatingNav) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) { bottomBar(selected, selectNav) }
    })
    }
    CompositionLocalProvider(LocalContentVideo provides onOpenVideo, LocalContentSession provides session, LocalContentLogin provides onOpenAccount, LocalTopicPreparation provides topics) {
        Box(Modifier.fillMaxSize()) {
            ActivePage(stack.isEmpty()) { Page(null) }
            StackedRoutes(stack, ::back, Modifier.fillMaxSize()) { route -> Page(remember(route) { JSONObject(route) }) }
            if (topicProgress || detailProgress) com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth().height(2.dp).align(Alignment.TopCenter))
        }
    }
    if (publishPicker) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { publishPicker = false }, containerColor = androidx.compose.ui.graphics.Color.Transparent, shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)) {
        PublishPicker(onDismiss = { publishPicker = false }) { title, type -> publishPicker = false; push("publish", title, type) }
    }
    moreRow?.let { row -> FeedMoreSheet(api, row, session, onDismiss = { moreRow = null }, onLogin = onOpenAccount,
        onForward = { moreRow = null; push("publish", "转发动态", "forward:${row.text("id")}") }, onLink = ::openLink) }
}

@Composable
private fun ContentChannelPager(selected: Int, count: Int, onSelected: (Int) -> Unit, content: @Composable (Int) -> Unit) {
    val pager = rememberPagerState(initialPage = selected) { count }
    val callback by rememberUpdatedState(onSelected)
    LaunchedEffect(selected) { if (selected != pager.currentPage && !pager.isScrollInProgress) pager.animateScrollToPage(selected, animationSpec = androidx.compose.animation.core.tween(300)) }
    LaunchedEffect(pager) { snapshotFlow { pager.settledPage }.collect { callback(it) } }
    HorizontalPager(pager, Modifier.fillMaxSize()) { index -> ActivePage(index == pager.currentPage) { content(index) } }
}

@Composable
internal fun ChannelTabs(titles: List<String>, selected: Int, modifier: Modifier = Modifier, section: Int = 0, onSelected: (Int) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
    val scroll = rememberScrollState()
    val bounds = remember { mutableMapOf<Int, androidx.compose.ui.geometry.Rect>() }
    var viewport by remember { mutableStateOf(androidx.compose.ui.geometry.Rect.Zero) }
    LaunchedEffect(selected, titles, viewport.size) {
        withFrameNanos { }
        bounds[selected]?.let { item -> if (viewport.width > 0) scroll.animateScrollTo((scroll.value + item.center.x - viewport.center.x).toInt().coerceIn(0, scroll.maxValue), androidx.compose.animation.core.tween(300)) }
    }
    Row(modifier.fillMaxWidth().height(if (section == 0) 38.dp else 35.dp).onGloballyPositioned { viewport = it.boundsInRoot() }.horizontalScroll(scroll), verticalAlignment = Alignment.CenterVertically) {
        titles.forEachIndexed { index, title ->
            val active = index == selected
            Box(Modifier.fillMaxHeight().onGloballyPositioned { bounds[index] = it.boundsInRoot() }.clickable { onSelected(index) }.padding(horizontal = if (section == 0) 14.dp else 12.dp), contentAlignment = Alignment.Center) {
                Text(title, fontSize = if (section == 3) if (active) 17.sp else 16.sp else if (active) 16.sp else if (section == 0) 15.5.sp else 15.sp,
                    fontWeight = if (section == 3) if (active) FontWeight.Medium else com.green.note.ui.adjustedWeight(400) else if (active) FontWeight.Bold else if (section == 0) FontWeight.Medium else FontWeight.Normal,
                    color = if (active) scheme.primary else if (section == 0) if (dark) androidx.compose.ui.graphics.Color(0xFFC8C8C8) else androidx.compose.ui.graphics.Color(0xFF4A4A4A) else scheme.onSurfaceVariant)
            }
        }
    }
}
@Composable
internal fun LoginRequired(onLogin: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewTextButton(onClick = onLogin) { Text("请先登录") } }
}
