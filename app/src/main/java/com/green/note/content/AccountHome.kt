package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.ReviewTextField as TextField

import android.content.Context
import android.net.Uri
import com.green.note.ui.tapToggleable as toggleable
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import coil.imageLoader
import com.green.note.network.normalizeNetworkImageUrl
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewRefreshBox
import com.green.note.ui.ReviewScrollActivity
import com.green.note.ui.AppToastState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

internal val accountHomeCards = listOf("我关注的话题", "我的常去", "浏览历史", "我的收藏单", "我的问答")
private val accountHomePaths = listOf("/v6/topic/myFollowTopicList", "/v6/user/recentHistoryList", "/v6/user/hitHistoryList", "/v6/collection/list", "/v6/user/questionAndAnswerList")
internal data class AccountPreview(val rows: List<JSONObject> = emptyList(), val error: String? = null)

/** Merge the original public-space/profile envelopes without losing valid nested feed counts. */
internal fun mergeAccountHomeProfile(space: JSONObject, profile: JSONObject): JSONObject {
    val spaceData = space.optJSONObject("data") ?: JSONObject()
    val profileData = profile.optJSONObject("data") ?: JSONObject()
    val spaceUser = spaceData.optJSONObject("userInfo") ?: spaceData.optJSONObject("user_info") ?: JSONObject()
    val profileUser = profileData.optJSONObject("userInfo") ?: profileData.optJSONObject("user_info") ?: JSONObject()
    val merged = JSONObject()
    listOf(spaceUser, profileUser, profileData, spaceData, space).forEach { source -> source.keys().forEach { key -> merged.put(key, source.opt(key)) } }
    val aliases = arrayOf("feed_num", "feedNum", "feednum", "feed_count", "feedCount", "feed_num_txt", "feedNumTxt", "feed")
    listOf(spaceUser, spaceData, space, profileUser, profileData, profile).firstNotNullOfOrNull { it.text(*aliases).takeIf(String::isNotEmpty) }?.let { merged.put("feed_num", it) }
    return merged
}

internal class AccountHomeState(context: Context, private val api: ContentApi, private val session: ContentSession) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences("greennote_compose_account_dashboard", Context.MODE_PRIVATE)
    private val owner = api.imageCacheScope()
    private val preferencesMutex = Mutex()
    private val loadingPreviews = mutableSetOf<String>()
    val localOnly = session.anonymous && session.uid.isEmpty()
    var hidden by mutableStateOf<Set<String>>(emptySet())
        private set
    var preferencesReady by mutableStateOf(false)
        private set
    var profile by mutableStateOf(JSONObject())
        private set
    var login by mutableStateOf<JSONObject?>(null)
        private set
    var loginError by mutableStateOf<String?>(null)
        private set
    var profileError by mutableStateOf<String?>(null)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var localFollowCount by mutableIntStateOf(0)
        private set
    private val previewState = mutableStateMapOf<String, AccountPreview>()
    val previews: Map<String, AccountPreview> get() = previewState
    private var checking = false
    var initialized = false
        private set

    private fun owns() = owner == api.imageCacheScope()
    fun route(index: Int) = accountHomePaths[index] +
        if (index >= 3) "?uid=${Uri.encode(session.uid)}${if (index == 3) "&showDefault=1" else ""}" else ""
    fun canReadCard(index: Int) = session.authenticated && login != null ||
        session.anonymous && session.uid.isNotEmpty() && index >= 3

    private suspend fun restorePreferences(quiet: Boolean) {
        if (preferencesReady) return
        try {
            hidden = withContext(Dispatchers.IO) {
                if (!prefs.contains("hiddenCards")) {
                    val legacy = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .all["flutter.greennote.account.hiddenCards"]
                    val old = SearchHistory.decodeLegacy(legacy).filter(accountHomeCards::contains)
                    check(prefs.edit().putString("hiddenCards", JSONArray(old).toString()).commit())
                }
                val array = JSONArray(prefs.getString("hiddenCards", "[]"))
                (0 until array.length()).map { array.getString(it) }.filter(accountHomeCards::contains).toSet()
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (!quiet) AppToastState().showSnackbar("卡片设置读取失败，原记录已保留")
        }
        preferencesReady = true
    }

    suspend fun setCardVisible(title: String, visible: Boolean) {
        preferencesMutex.withLock {
            val next = if (visible) hidden - title else hidden + title
            withContext(NonCancellable) {
                withContext(Dispatchers.IO) { check(prefs.edit().putString("hiddenCards", JSONArray(next.toList()).toString()).commit()) }
                hidden = next
            }
        }
    }

    suspend fun loadPreview(index: Int) {
        val title = accountHomeCards[index]
        if (!owns() || !canReadCard(index) || !loadingPreviews.add(title)) return
        try {
            val request = contentRequest(route(index))
            val result = extractEntities(api.request(request.path, query = request.query + ("page" to "1")))
            if (owns()) previewState[title] = AccountPreview(result)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            if (owns()) previewState[title] = AccountPreview(error = failure.message ?: "内容加载失败")
        } finally {
            loadingPreviews.remove(title)
        }
    }

    suspend fun readLocalFollowCount() {
        val count = api.localLibrary("follows").size
        if (owns()) localFollowCount = count
    }

    suspend fun loadMissingPreviews() = coroutineScope {
        accountHomeCards.forEachIndexed { index, title ->
            if (title !in hidden && title !in previewState && canReadCard(index)) launch { loadPreview(index) }
        }
    }

    suspend fun refresh(quiet: Boolean = false) {
        if (checking || !owns()) return
        checking = true
        refreshing = !quiet
        try {
            restorePreferences(quiet)
            coroutineScope {
                if (session.authenticated) {
                    try {
                        val response = api.request("/v6/account/checkLoginInfo")
                        if (!owns()) return@coroutineScope
                        login = response.optJSONObject("data") ?: response
                        loginError = null
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        if (owns()) {
                            if (login == null) loginError = failure.message ?: "登录校验失败"
                            else if (!quiet) AppToastState().showSnackbar("刷新账户信息失败: ${failure.message}")
                        }
                        return@coroutineScope
                    }
                }
                if (localOnly) { readLocalFollowCount(); return@coroutineScope }
                if (session.uid.isEmpty()) return@coroutineScope
                launch { loadProfile() }
                accountHomeCards.forEachIndexed { index, title ->
                    if (title !in hidden && canReadCard(index)) launch { loadPreview(index) }
                }
            }
            if (owns()) initialized = true
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            if (!quiet && owns()) AppToastState().showSnackbar(failure.message ?: "账户资料读取失败")
        } finally {
            checking = false
            refreshing = false
        }
    }

    private suspend fun loadProfile() = supervisorScope {
        try {
            val query = mapOf("uid" to session.uid)
            val space = async { api.request("/v6/user/space", query = query) }
            val publicProfile = async {
                try { api.request("/v6/user/profile", query = query) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { JSONObject() }
            }
            val merged = mergeAccountHomeProfile(space.await(), publicProfile.await())
            if (owns()) { profile = merged; profileError = null }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            if (owns()) profileError = failure.message ?: "个人统计加载失败"
        }
    }
}

@Composable
internal fun rememberAccountHome(api: ContentApi, session: ContentSession, lifecycle: Lifecycle): AccountHomeState {
    val context = LocalContext.current
    val owner = api.imageCacheScope()
    val state = remember(context, api, owner, session.uid, session.authenticated, session.anonymous) {
        AccountHomeState(context, api, session)
    }
    LaunchedEffect(state, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            withFrameNanos { }
            if (!state.initialized) state.refresh(quiet = true)
        }
    }
    WarmAccountHomeAvatar(api, session, state, owner, lifecycle)
    return state
}

@Composable
private fun WarmAccountHomeAvatar(api: ContentApi, session: ContentSession, state: AccountHomeState, owner: String, lifecycle: Lifecycle) {
    val context = LocalContext.current
    val login = state.login
    val raw = state.profile.text("userAvatar", "avatar").ifEmpty {
        login?.text("userAvatar", "avatar").orEmpty().ifEmpty {
            (login?.optJSONObject("userInfo") ?: login?.optJSONObject("user_info"))?.text("userAvatar", "avatar").orEmpty()
        }
    }.ifEmpty { session.avatar }
    val url = remember(raw) { normalizeNetworkImageUrl(raw) }
    val size = with(LocalDensity.current) { 72.dp.roundToPx() }
    LaunchedEffect(state, url, size, lifecycle) {
        if (state.localOnly || url.isEmpty() || size <= 0) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            if (owner != api.imageCacheScope()) return@repeatOnLifecycle
            try { context.imageLoader.execute(contentImageRequest(context, api, url, owner).size(size).build()) }
            catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* The visible avatar retains its fallback. */ }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AccountOverview(api: ContentApi, session: ContentSession, state: AccountHomeState, onUser: (String) -> Unit,
    onList: (String, String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit = { _, _, _ -> }, onLike: (JSONObject) -> Unit = {}, onMore: (JSONObject) -> Unit = {},
    onAccountAction: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val scroll = rememberLazyListState()
    ReviewScrollActivity(scroll)
    val hidden = state.hidden
    var managing by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    var create by remember { mutableStateOf(false) }
    val profile = state.profile
    val login = state.login
    val loginError = state.loginError
    val profileError = state.profileError
    val localOnly = state.localOnly
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(state, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            if (localOnly && state.initialized) {
                try { state.readLocalFollowCount() }
                catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Pull refresh retains explicit error feedback. */ }
            } else if (state.initialized) state.loadMissingPreviews()
        }
    }
    val logged = session.anonymous || session.authenticated && login != null && loginError == null
    fun settings() = onAccountAction("settings")
    fun required() { AppToastState().showSnackbar(if (session.anonymous) "当前为匿名登录，无法使用此功能" else "请先登录") }
    fun openCard(index: Int) {
        if (state.canReadCard(index)) onList(accountHomeCards[index], state.route(index))
        else if (session.anonymous) required() else settings()
    }
    fun follows() { when { localOnly -> onList("本地关注", "/local/follows"); session.anonymous -> onList("我的关注", "/v6/user/followList?uid=${session.uid}"); logged -> onList("我的关注", "/v6/user/myFollowList"); else -> settings() } }
    fun fans() { when { localOnly -> required(); session.anonymous -> onList("我的粉丝", "/v6/user/userFansList?uid=${session.uid}"); logged -> onList("我的粉丝", "/v6/user/myFansList"); else -> settings() } }
    fun openItem(item: JSONObject, forcedType: String = "") {
        val type = forcedType.ifEmpty { item.text("entityType", "entity_type") }.lowercase()
        val url = item.text("url")
        val id = item.text(if (type.contains("user")) "uid" else "id", "feedId", "feed_id", "entityId", "collectionId", "productId", "uid", "tag", "tagName")
        when {
            type.contains("history") && url.isNotEmpty() -> onLink(url)
            type.contains("feed") && url.contains("/feed/") -> onLink(url)
            type.contains("topic") || type.contains("tag") -> onLink("/t/${Uri.encode(item.text("tag", "tagName", "title").ifEmpty { id })}")
            type.contains("user") && id.isNotEmpty() -> onUser(id)
            type.contains("feed") && id.isNotEmpty() -> onLink("/feed/$id")
            type.contains("collection") && id.isNotEmpty() -> onLink("/collection/$id")
            (type.contains("product") || type.contains("rating")) && id.isNotEmpty() -> onLink("/product/$id")
            (type.contains("apk") || type.contains("app")) && id.isNotEmpty() -> onLink("/apk/${Uri.encode(item.text("apkname", "packageName").ifEmpty { id })}")
            url.isNotEmpty() -> onLink(url)
        }
    }
    fun refresh() { scope.launch { state.refresh() } }
    val scheme = MaterialTheme.colorScheme
    val contentBottom = if (com.green.note.ui.LocalAppPreferences.current.floatingNavBar) 100.dp else 24.dp
    val displayedProfile = remember(login, profile) {
        JSONObject().also { merged -> listOfNotNull(login?.optJSONObject("userInfo") ?: login?.optJSONObject("user_info"), login, profile).forEach { source -> source.keys().forEach { key -> merged.put(key, source.opt(key)) } } }
    }
    Box(Modifier.fillMaxSize().background(if (scheme.surface.luminance() < .5f) Color(0xff101010) else scheme.surface), contentAlignment = Alignment.TopCenter) {
        ReviewRefreshBox(state.refreshing, onRefresh = ::refresh, modifier = Modifier.widthIn(max = 600.dp).fillMaxSize(), failed = loginError != null || profileError != null) {
            LazyColumn(Modifier.fillMaxSize(), state = scroll, contentPadding = PaddingValues(start = 8.dp, end = 8.dp, bottom = contentBottom)) {
                item { AccountHomeProfile(api, session, displayedProfile, logged, loginError, onAccountAction, onUser, ::settings) }
                item { AccountSurface {
                    if (profileError != null) ListItem(headlineContent = { Text("个人统计加载失败") }, supportingContent = { Text(profileError, maxLines = 2, overflow = TextOverflow.Ellipsis) }, trailingContent = { ContentIcon("refresh_rounded", "重试", ::refresh) })
                    else Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        val values = if (localOnly) listOf("0", "${state.localFollowCount}", "—") else listOf(profile.text("feed_num", "feedNum", "feednum", "feed_count", "feedCount", "feed_num_txt", "feedNumTxt"), profile.text("follow_num", "followNum", "follownum", "follow"), profile.text("fans_num", "fansNum", "fansnum", "fans"))
                        listOf("动态", "关注", "粉丝").forEachIndexed { index, label ->
                            Column(Modifier.weight(1f).clickable { when (index) { 0 -> if (localOnly) required() else if (logged) onList("我的动态", "/v6/user/feedList?uid=${session.uid}") else settings(); 1 -> follows(); 2 -> fans() } }.padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(if (logged) values[index].ifEmpty { "—" } else "—", style = MaterialTheme.typography.titleMedium); Text(label, style = MaterialTheme.typography.bodySmall)
                            }
                            if (index < 2) VerticalDivider(Modifier.height(24.dp), color = scheme.onSurface.copy(alpha = .04f))
                        }
                    }
                } }
                item { Spacer(Modifier.height(8.dp)); AccountSurface { Row {
                    AccountHomeShortcut("star_rounded", "我的收藏", Color(0xff2589e8), Modifier.weight(1f)) { if (localOnly) onList("本地收藏", "/local/favorites") else if (logged) onList("我的收藏", "/v6/collection/list?uid=${session.uid}&showDefault=1") else settings() }
                    AccountHomeShortcut("article_rounded", "我的图文", Color(0xffe94848), Modifier.weight(1f)) { if (localOnly) required() else if (logged) onList("我的图文", "/v6/user/htmlFeedList?uid=${session.uid}") else settings() }
                    AccountHomeShortcut("stay_current_portrait_rounded", "应用管理", Color(0xff9862e8), Modifier.weight(1f)) { onAccountAction("appmanager") }
                    AccountHomeShortcut("more_horiz_rounded", "更多", Color(0xff1db8c3), Modifier.weight(1f)) { more = true }
                } } }
                item { Spacer(Modifier.height(8.dp)); AccountSurface { Column {
                    AccountHomeHeader("酷回收订单", trailing = "官方客户端查看")
                    Row(Modifier.padding(bottom = 2.dp)) { listOf("inventory_2_outlined" to "待发货", "local_shipping_outlined" to "已发货", "verified_user_outlined" to "验机中", "receipt_long_outlined" to "待确认", "headset_mic_outlined" to "在线客服").forEach { (icon, label) -> AccountHomeShortcut(icon, label, scheme.onSurfaceVariant, Modifier.weight(1f), null) } }
                } } }
                item { Spacer(Modifier.height(8.dp)); AccountSurface { Row(Modifier.fillMaxWidth().clickable { onLink("https://m.coolapk.com/mp/do?c=help&m=questionNew") }.padding(horizontal = 12.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    MaterialGlyph("volume_up_rounded", size = 22.dp, color = Color(0xff2196f3)); Spacer(Modifier.width(10.dp)); Text("有疑惑请参考「酷安常见问题」 >>>", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium); MaterialGlyph("chevron_right_rounded", size = 20.dp)
                } } }
                item { Row(Modifier.padding(start = 12.dp, top = 2.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) { Text("我的卡片", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontSize = 16.sp, fontWeight = FontWeight.SemiBold); com.green.note.ui.ReviewTextButton(onClick = { managing = true }, enabled = state.preferencesReady) { Text("卡片管理", fontSize = 12.sp, color = scheme.onSurfaceVariant) } } }
                accountHomeCards.forEachIndexed { index, title -> if (state.preferencesReady && title !in hidden) item(key = title) {
                    val preview = state.previews[title]
                    Spacer(Modifier.height(8.dp)); AccountSurface { Column {
                        AccountHomeHeader(title, onClick = { openCard(index) })
                        when {
                            session.authenticated && loginError != null && login == null -> AccountHomeFailure("登录状态校验失败", loginError, ::refresh)
                            !state.canReadCard(index) && !session.authenticated -> AccountHomeMessage("登录后查看$title", Modifier.clickable { openCard(index) })
                            preview == null -> Box(Modifier.fillMaxWidth().padding(22.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress(Modifier.size(20.dp), strokeWidth = 2.dp) }
                            preview.error != null -> AccountHomeFailure("内容加载失败", preview.error, ::refresh)
                            preview.rows.isEmpty() -> AccountHomeMessage(listOf("还没有关注话题", "暂无最近访问内容", "暂无浏览记录", "还没有创建收藏单", "你还没有发布过问答")[index])
                            index < 2 -> Row(Modifier.padding(start = 6.dp, top = 2.dp, end = 6.dp, bottom = 14.dp)) {
                                preview.rows.take(4).forEach { row -> AccountHomeMini(api, row, index == 0, Modifier.weight(1f)) { openItem(row) } }
                                repeat((4 - preview.rows.size).coerceAtLeast(0)) { Spacer(Modifier.weight(1f)) }
                            }
                            else -> preview.rows.take(if (index == 2) 5 else if (index == 3) 3 else 4).forEach { row ->
                                if (index < 4) AccountHomeRow(api, row, index == 3) { openItem(row, if (index == 3) "collection" else "") }
                                else EntityRow(api, row, { openItem(it) }, onUser, onLink, onGallery, onLike, onMore)
                            }
                        }
                    } }
                } }
                item { Text("更多", Modifier.padding(start = 14.dp, top = 16.dp, bottom = 8.dp), style = MaterialTheme.typography.titleMedium); AccountSurface { ListItem(headlineContent = { Text("创建收藏夹") }, leadingContent = { MaterialGlyph("create_new_folder_outlined") }, modifier = Modifier.clickable { create = true }, colors = ListItemDefaults.colors(containerColor = Color.Transparent)) } }
            }
        }
    }
    if (managing) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { managing = false }) {
        Text("卡片管理", Modifier.align(Alignment.CenterHorizontally).padding(12.dp), fontSize = 18.sp)
        val cardScroll = rememberScrollState(); ReviewScrollActivity(cardScroll)
        Column(Modifier.weight(1f, fill = false).verticalScroll(cardScroll)) {
        accountHomeCards.forEach { title ->
        val change:(Boolean)->Unit = { visible -> scope.launch {
            if (saving) return@launch
            saving = true
            try { state.setCardVisible(title, visible) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { AppToastState().showSnackbar("卡片设置保存失败，请重试"); return@launch }
            finally { saving = false }
            if (visible) state.loadPreview(accountHomeCards.indexOf(title))
        } }
        com.green.note.ui.ReviewTileLayout(modifier=Modifier.toggleable(title !in hidden,enabled=!saving,role=androidx.compose.ui.semantics.Role.Switch,onValueChange=change),horizontalPadding=14.dp,
            trailing={com.green.note.ui.ReviewSwitch(title !in hidden,change,enabled=!saving,shrinkWrap=true)},
            title={Text(title,fontSize=15.sp,lineHeight=20.25.sp,fontWeight=com.green.note.ui.adjustedWeight(600),color=if(saving)MaterialTheme.colorScheme.onSurface.copy(alpha=.38f)else MaterialTheme.colorScheme.onSurface)})
        }
        }
        Spacer(Modifier.height(16.dp))
    }
    if (more) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { more = false }) {
        listOf(Triple("万物清单", "view_list_outlined", "/v6/user/productAlbumList"), Triple("我的看看号", "view_list_outlined", "/v6/user/dyhFollowList"), Triple("我的应用集", "view_list_outlined", "/v6/user/albumList"), Triple("设置", "settings_outlined", "settings"), Triple("我的关注", "people_outline_rounded", "follows"), Triple("我的粉丝", "person_add_alt_1_rounded", "fans")).forEach { (title, icon, path) -> ListItem(colors = ListItemDefaults.colors(containerColor = Color.Transparent), headlineContent = { Text(title) }, leadingContent = { MaterialGlyph(icon) }, modifier = Modifier.clickable { more = false; when(path) { "settings" -> settings(); "follows" -> follows(); "fans" -> fans(); else -> onList(title, "$path?uid=${session.uid}") } }) }
        if (session.anonymous) ListItem(colors = ListItemDefaults.colors(containerColor = Color.Transparent), headlineContent = { Text("编辑本地匿名资料") }, leadingContent = { MaterialGlyph("edit_outlined") }, modifier = Modifier.clickable { more = false; onAccountAction("local_profile") })
        if (session.anonymous && session.uid.isNotEmpty()) ListItem(colors = ListItemDefaults.colors(containerColor = Color.Transparent), headlineContent = { Text("取消公开主页身份") }, leadingContent = { MaterialGlyph("cloud_off_outlined") }, modifier = Modifier.clickable { more = false; onAccountAction("clear_public_identity") })
    }
    if (create) AccountHomeCreateDialog(api, onDismiss = { create = false }, onCreated = { create = false; refresh() })
}

@Composable
private fun AccountSurface(content: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Surface(shape = RoundedCornerShape(14.dp), color = if (scheme.surface.luminance() < .5f) Color(0xff1e1e1e) else scheme.surfaceContainerLow, content = content)
}

@Composable
private fun AccountHomeHeader(title: String, onClick: (() -> Unit)? = null, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).then(if (onClick == null) Modifier else Modifier.clickable(onClick = onClick)).padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        trailing?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Spacer(Modifier.width(4.dp)); MaterialGlyph("chevron_right_rounded", size = 20.dp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun AccountHomeShortcut(icon: String, label: String, color: Color, modifier: Modifier = Modifier, onClick: (() -> Unit)?) {
    Column(modifier.then(if (onClick == null) Modifier else Modifier.clickable(onClick = onClick)).padding(horizontal = 2.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        MaterialGlyph(icon, color = color, size = 24.dp); Spacer(Modifier.height(5.dp)); Text(label, style = MaterialTheme.typography.bodySmall, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun AccountHomeProfile(api: ContentApi, session: ContentSession, profile: JSONObject, logged: Boolean, error: String?, onAction: (String) -> Unit, onUser: (String) -> Unit, settings: () -> Unit) {
    val localOnly = session.anonymous && session.uid.isEmpty()
    val rawName = profile.text("username", "userName", "name").ifEmpty { session.username }
    val showAccount = logged || session.authenticated && error == null
    val name = rawName.ifEmpty { if (showAccount) "酷安用户" else "未登录" }
    val avatar = profile.text("userAvatar", "avatar").ifEmpty { session.avatar }
    val level = profile.text("level", "userLevel")
    val experience = profile.text("experience", "exp").toLongOrNull()
    val next = profile.text("next_level_experience", "nextLevelExperience").toLongOrNull()
    val progress = experience != null && next != null && next > 0
    val scheme = MaterialTheme.colorScheme
    fun open() { if (localOnly) onAction("local_profile") else if (logged && session.uid.isNotEmpty()) onUser(session.uid) else settings() }
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).clickable(onClick = ::open).padding(horizontal = 4.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        if (localOnly) com.green.note.account.LocalAvatar(session.avatar, name, Modifier.size(72.dp))
        else ContentAvatar(api, avatar, rawName, 72.dp, ::open)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(name, Modifier.weight(1f, fill = false), style = MaterialTheme.typography.titleLarge, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (session.anonymous && !localOnly) { Spacer(Modifier.width(6.dp)); MaterialGlyph("cloud_outlined", size = 19.dp, color = scheme.primary, contentDescription = "匿名登录 · 公开主页身份") }
            }
            if (level.isNotEmpty() || progress) {
                Spacer(Modifier.height(8.dp)); Row(verticalAlignment = Alignment.CenterVertically) {
                    if (level.isNotEmpty()) Text("Lv.$level", color = scheme.primary, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f)); if (progress) Text("$experience/$next", Modifier.weight(1f, fill = false), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (progress) { Spacer(Modifier.height(5.dp)); com.green.note.ui.ReviewLinearProgress(progress = { (experience!!.toFloat() / next!!).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(99.dp))) }
            } else {
                Spacer(Modifier.height(5.dp)); Text(when { session.anonymous && !localOnly -> "公开主页 · UID ${session.uid} · 只读"; localOnly -> "匿名账户 · 本地保存"; error != null -> error; session.uid.isNotEmpty() -> "UID ${session.uid}"; showAccount -> "酷安账户"; else -> "点击登录酷安" }, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.width(8.dp))
        if (session.anonymous) { com.green.note.ui.ReviewIconButton(onClick = { onAction("switch_anonymous") }) { MaterialGlyph("switch_account_outlined", size = 24.dp, contentDescription = "切换/管理匿名账户") }; Spacer(Modifier.width(4.dp)) }
        if (!session.anonymous && showAccount) com.green.note.ui.ReviewIconButton(onClick = { onAction("qr") }, enabled = logged && session.uid.isNotEmpty()) { MaterialGlyph("qr_code_2_rounded", size = 28.dp, contentDescription = "我的二维码名片") }
        else if (!session.anonymous || localOnly) { MaterialGlyph(if (localOnly) "edit_outlined" else "login_rounded", size = 28.dp); Spacer(Modifier.width(4.dp)) }
        MaterialGlyph("chevron_right_rounded", size = 28.dp)
    }
}

@Composable
private fun AccountHomeMessage(message: String, modifier: Modifier = Modifier) {
    Text(message, modifier.fillMaxWidth().padding(start = 12.dp, top = 20.dp, end = 12.dp, bottom = 26.dp), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun AccountHomeFailure(title: String, error: String, retry: () -> Unit) {
    ListItem(headlineContent = { Text(title) }, supportingContent = { Text(error, maxLines = 2, overflow = TextOverflow.Ellipsis) }, leadingContent = { MaterialGlyph("history_rounded") }, trailingContent = { ContentIcon("refresh_rounded", "重试", retry) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent))
}

@Composable
private fun AccountHomeThumbnail(api: ContentApi, item: JSONObject, size: Dp, collection: Boolean = false) {
    val image = item.text("logo", "pic", "cover_pic", "cover", "userAvatar", "avatar", "icon")
    val shape = RoundedCornerShape(8.dp)
    val fallback = if (collection) Modifier.background(Brush.linearGradient(listOf(Color(0xff10b8c5), Color(0xff24c4a0)))) else Modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest)
    var failed by remember(image, api.imageCacheScope()) { mutableStateOf(image.isEmpty()) }
    Box(Modifier.size(size).clip(shape).then(if (failed) fallback else Modifier), contentAlignment = Alignment.Center) {
        if (failed) MaterialGlyph(if (collection) "folder_outlined" else "image_outlined", size = size * if (collection) .6f else .45f, color = if (collection) Color.White else MaterialTheme.colorScheme.onSurfaceVariant)
        if (image.isNotEmpty()) ContentImage(api, image, null, Modifier.fillMaxSize(), heroCornerRadius = 8.dp, onError = { failed = true }, onDecoded = { _, _ -> failed = false })
    }
}

@Composable
private fun AccountHomeMini(api: ContentApi, item: JSONObject, followed: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val title = item.text("title", "username", "userName", "productName", "apkName", "tag").ifEmpty { "酷安内容" }
    val subtitle = if (followed) item.text("commentnum_txt", "commentNumTxt", "commentnumTxt", "comment_num_txt", "feedNumTxt", "feed_num_txt", "feednum_txt", "commentnum", "comment_num", "feednum", "feed_num", "feedNum", "feeds", "feed").let { if (it.isEmpty()) "" else "${it}条动态" } else accountCategory(item)
    Column(modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        AccountHomeThumbnail(api, item, 56.dp); Spacer(Modifier.height(7.dp)); Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
        if (subtitle.isNotEmpty()) { Spacer(Modifier.height(6.dp)); Text(subtitle, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 11.sp, lineHeight = 15.4.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun AccountHomeRow(api: ContentApi, item: JSONObject, collection: Boolean, onClick: () -> Unit) {
    val title = item.text("title", "username", "name").ifEmpty { "酷安内容" }
    val subtitle = item.text("subTitle", "description", "message").ifEmpty { if (collection) listOfNotNull(item.text("follownum", "followNum").takeIf(String::isNotEmpty)?.let { "${it}人关注" }, item.text("feednum", "feedNum", "itemnum").takeIf(String::isNotEmpty)?.let { "${it}个内容" }).joinToString("  ") else "" }
    val time = if (collection) "" else relativeTime(item.text("dateline", "time"))
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        AccountHomeThumbnail(api, item, if (collection) 60.dp else 48.dp, collection); Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f, fill = false), style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (!collection && item.text("typeName").isNotEmpty()) { Spacer(Modifier.width(6.dp)); Text(item.text("typeName"), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            if (subtitle.isNotEmpty()) { Spacer(Modifier.height(4.dp)); Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        if (time.isNotEmpty()) { Spacer(Modifier.width(8.dp)); Text(time, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun AccountHomeCreateDialog(api: ContentApi, onDismiss: () -> Unit, onCreated: () -> Unit) {
    var title by remember { mutableStateOf("") }; var description by remember { mutableStateOf("") }; var public by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    val owner = remember { api.imageCacheScope() }; val scope = rememberCoroutineScope()
    com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { if (!busy) onDismiss() }, title = { Text("新建收藏夹") }, text = { Column {
        val fieldColors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent)
        TextField(title, { title = it }, label = { Text("名称") }, textStyle = MaterialTheme.typography.bodyLarge, colors = fieldColors); TextField(description, { description = it }, label = { Text("说明") }, textStyle = MaterialTheme.typography.bodyLarge, colors = fieldColors)
        com.green.note.ui.ReviewTileLayout(modifier=Modifier.toggleable(public,role=androidx.compose.ui.semantics.Role.Switch,onValueChange={public=it}),horizontalPadding=0.dp,
            trailing={com.green.note.ui.ReviewSwitch(public,{public=it},shrinkWrap=true)},title={Text("公开收藏夹",fontSize=15.sp,lineHeight=20.25.sp,fontWeight=com.green.note.ui.adjustedWeight(600))})
    } }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = onDismiss, enabled = !busy) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(enabled = !busy, onClick = { if (title.isBlank()) { onDismiss(); return@ReviewButton }; scope.launch {
        busy = true
        try { check(owner == api.imageCacheScope()) { "账号已变化" }; api.submitMultipart("/v6/collection/create", mapOf("title" to title.trim(), "description" to description.trim(), "isOpen" to if (public) "1" else "0", "pic" to "", "sourceId" to "")); AppToastState().showSnackbar("收藏夹已创建"); onCreated() }
        catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { AppToastState().showSnackbar(error.message ?: "创建失败") } finally { busy = false }
    } }) { Text("创建") } })
}
