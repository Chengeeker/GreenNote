package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.gestures.ScrollableDefaults
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.*
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontStyle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.currentStateAsState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Constraints
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import org.json.JSONObject

internal val darkProfileAccent = Color(0xFF429488)
internal val darkProfilePanel = Color(0xFF1C1C1E)

internal fun profileFlingVelocity(velocity: Float, density: Float): Float {
    val limit = 3600f * density
    return limit * kotlin.math.tanh(velocity / limit)
}

internal fun profileChips(row: JSONObject, now: Long = System.currentTimeMillis()): List<Pair<String, String>> = buildList {
    val gender = when (row.text("gender", "sex")) { "1", "男", "男生" -> "♂"; "0", "女", "女生" -> "♀"; else -> "" }
    val birthYear = row.text("birth_year", "birthYear").toIntOrNull() ?: row.text("birth", "birthday").take(4).toIntOrNull()
    val currentYear = java.util.Calendar.getInstance().apply { timeInMillis = now }.get(java.util.Calendar.YEAR)
    val era = row.text("era", "age_group", "generation").ifEmpty { if (birthYear != null && birthYear > 1940 && birthYear <= currentYear) "${((birthYear % 100) / 5 * 5).toString().padStart(2, '0')}后" else "" }
    listOf(gender, era).filter(String::isNotEmpty).joinToString(" ").takeIf(String::isNotEmpty)?.let { add(it to when (gender) { "♂" -> "male"; "♀" -> "female"; else -> "" }) }
    listOf(row.text("province", "user_province"), row.text("city", "user_city")).filter(String::isNotEmpty).distinct().joinToString(" ").takeIf(String::isNotEmpty)?.let { add(it to "") }
    row.text("astro", "constellation").takeIf(String::isNotEmpty)?.let { add(it to "") }
    val active = row.text("logintime", "login_time", "last_login_time", "active_time")
    if (active.isNotEmpty() && active != "0") {
        val stamp = active.toLongOrNull()
        val label = if (stamp == null) if (active.contains("活跃")) active else "${active}活跃" else {
            val age = (now - if (stamp > 10_000_000_000) stamp else stamp * 1000) / 60000
            when { age < 5 -> "刚刚活跃"; age < 60 -> "${age}分钟前活跃"; age < 1440 -> "${age / 60}小时前活跃"; age < 43200 -> "${age / 1440}天前活跃"; age / 43200 < 12 -> "${age / 43200}个月前活跃"; else -> "${age / 525600}年前活跃" }
        }
        add(label to "")
    }
}

internal fun profileTabs(uid: String, mine: Boolean): List<Pair<String, ContentRequest?>> = listOf(
    "主页" to null, "动态" to ContentRequest("/v6/user/feedList"),
    "点评" to ContentRequest("/v6/page/dataList", mapOf("url" to "#/feed/nodeRatingList?uid=$uid&targetType=all&parseRatingToFeed=1")),
    "图文" to ContentRequest("/v6/user/htmlFeedList"), "问答" to ContentRequest("/v6/user/questionAndAnswerList"),
    "酷图" to ContentRequest("/v6/user/pictureList"),
    "二手" to ContentRequest("/v6/page/dataList", mapOf("url" to "#/feed/userErshouList?fragmentTemplate=flex&ershouStatus=userAll")),
    "回复" to ContentRequest("/v6/user/replyList"), "图集" to ContentRequest("/v6/user/albumList"), "收藏" to ContentRequest("/v6/collection/list"),
    "好物榜" to ContentRequest("/v6/goodsList/list"), "店铺" to ContentRequest("/v6/goods/goodsStoreItemList"),
    "开发者应用" to ContentRequest("/v6/apk/developerAppList"), "关注应用" to ContentRequest("/v6/user/apkFollowList"),
    "发现" to ContentRequest("/v6/user/discoveryList"), "关注列表" to ContentRequest("/v6/user/followList"),
    "酷图流" to ContentRequest("/v6/page/dataList", mapOf("url" to "#/feed/userCoolPictureFeedList?fragmentTemplate=flex")),
    "好物动态" to ContentRequest("/v6/page/dataList", mapOf("url" to "#/goods/goodsFeedList?type=default&fragmentTemplate=flex")),
) + if (mine) listOf("回收站" to ContentRequest("/v6/page/dataList", mapOf("url" to "#/feed/userDeleteFeedList"))) else emptyList()

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun UserScreen(api: ContentApi, uid: String, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    session: ContentSession, onBack: () -> Unit, onAccountAction: (String) -> Unit, onChat: (MessagePartner) -> Unit, onLogin: () -> Unit) {
    var profile by remember(uid) { mutableStateOf<JSONObject?>(null) }
    var tab by rememberSaveable(uid) { mutableIntStateOf(1) }
    var revision by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    var topMenu by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var confirmation by remember { mutableStateOf<String?>(null) }
    var remark by remember { mutableStateOf<String?>(null) }
    var editingProfile by remember { mutableStateOf(false) }
    var following by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    var ignored by remember { mutableStateOf(false) }
    var special by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    val pageState by lifecycle.currentStateAsState()
    val photoStatusBars = LocalPhotoStatusBars.current
    val statusOwner = remember { Any() }
    val colors = MaterialTheme.colorScheme
    val dark = colors.surface.luminance() < .5f
    val pageColor = if (dark) Color(0xFF101010) else colors.surface
    val railColor = if (dark) darkProfilePanel else colors.surfaceContainerLowest
    val scope = rememberCoroutineScope()
    val toast = remember { com.green.note.ui.AppToastState() }
    val identity = api.imageCacheScope()
    val mine = uid == session.uid
    val tabs = remember(uid, mine) { profileTabs(uid, mine) }
    val repository = remember(api) { ContentRepository(api) }
    LaunchedEffect(editingProfile, lifecycle) {
        if (editingProfile) {
            lifecycle.currentStateFlow.first { !it.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) }
            lifecycle.currentStateFlow.first { it.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) }
            editingProfile = false; revision++
        }
    }
    fun flag(row: JSONObject, vararg keys: String) = keys.any { row.text(it) in setOf("1", "true") }
    suspend fun action(path: String, method: String = "POST", query: Map<String, String> = emptyMap(), body: Map<String, String>? = null): Boolean {
        if (working) return false
        if (!session.authenticated) { toast.showSnackbar(session.loginRequiredMessage); return false }
        working = true
        return try { check(identity == api.imageCacheScope()) { "账号已变更" }; api.request(path, method, query + ("uid" to uid), body); true }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败"); false }
        finally { working = false }
    }
    fun handleMenu(selectedAction: String) {
        topMenu = false
        when (selectedAction) {
            "uid", "link" -> { (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("主页", if (selectedAction == "uid") uid else "https://www.coolapk.com/u/$uid")); toast.showSnackbar(if (selectedAction == "uid") "已复制 UID: $uid" else "已复制主页链接") }
            "identity" -> if (!mine) confirmation = "identity"
            "block" -> if (blocked) scope.launch { if (action("/v6/user/removeFromBlackList", "GET")) blocked = false } else confirmation = "block"
            "ignore" -> scope.launch { if (action(if (ignored) "/v6/user/removeFromIgnoreList" else "/v6/user/addToIgnoreList", "GET")) ignored = !ignored }
            "special" -> scope.launch { if (action("/v6/user/specialFollowUser", query = mapOf("special" to if (special) "0" else "1"))) special = !special }
            "remark" -> remark = profile?.text("remark", "userRemark").orEmpty()
        }
    }
    LaunchedEffect(api, uid, revision, identity) {
        try {
            val data = coroutineScope {
                val space = async { api.request("/v6/user/space", query = mapOf("uid" to uid)).optJSONObject("data") ?: JSONObject() }
                val details = async { try { api.request("/v6/user/profile", query = mapOf("uid" to uid)).optJSONObject("data") ?: JSONObject() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { JSONObject() } }
                val first = space.await(); val second = details.await()
                JSONObject().apply {
                    listOf(first.optJSONObject("userInfo"), second.optJSONObject("userInfo"), second, first).filterNotNull().forEach { part ->
                        part.keys().forEach { key -> if (part.text(key).isNotEmpty()) put(key, part.opt(key)) }
                    }
                    put("uid", uid)
                }
            }
            profile = data; following = api.isUserFollowed(data); blocked = flag(data, "isBlackList", "is_blocked", "blocked"); ignored = flag(data, "isIgnore", "isIgnored", "isBlocked", "is_block"); special = flag(data, "isSpecialFollow", "is_special_follow"); error = null
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "加载失败" }
    }
    val pager = rememberPagerState(initialPage = tab) { tabs.size }
    val lists = remember(api, uid, identity) { mutableMapOf<Int, ContentListState>() }
    LaunchedEffect(pager) { snapshotFlow { pager.settledPage }.collect { tab = it } }
    var collapsed by rememberSaveable(uid) { mutableFloatStateOf(0f) }; var headerHeight by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    val barHeight = with(density) { (52.dp + statusTop).toPx() }
    val defaultFling = ScrollableDefaults.flingBehavior()
    val profileFling = remember(defaultFling, density.density) {
        object : FlingBehavior {
            override suspend fun ScrollScope.performFling(initialVelocity: Float): Float =
                with(defaultFling) { performFling(profileFlingVelocity(initialVelocity, density.density)) }
        }
    }
    val coverCollapsed = headerHeight > 0 && collapsed >= headerHeight - barHeight - 1
    val photoStatus = profile != null && !coverCollapsed && pageState.isAtLeast(Lifecycle.State.STARTED)
    DisposableEffect(photoStatusBars, statusOwner, photoStatus) {
        if (photoStatus) photoStatusBars?.put(statusOwner, Unit)
        onDispose { if (photoStatus) photoStatusBars?.remove(statusOwner) }
    }
    val nested = remember(barHeight) { object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (available.y >= 0) return Offset.Zero
            val delta = (-available.y).coerceAtMost((headerHeight - barHeight - collapsed).coerceAtLeast(0f)); collapsed += delta; return Offset(0f, -delta)
        }
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (available.y <= 0) return Offset.Zero
            val delta = available.y.coerceAtMost(collapsed); collapsed -= delta; return Offset(0f, delta)
        }
    } }
    @Composable fun ProfileMenu() {
        com.green.note.ui.ReviewPopupMenu(topMenu, { topMenu = false }) {
            if (session.anonymous) com.green.note.ui.ReviewPopupMenuItem(text = { Text(if (mine) "已设为我的公开资料" else "这是我") }, enabled = !mine, onClick = { handleMenu("identity") })
            listOf((if (blocked) "取消拉黑" else "拉黑用户") to "block", (if (ignored) "取消屏蔽" else "屏蔽用户") to "ignore", (if (special) "取消特别关注" else "特别关注") to "special", "设置备注" to "remark", "复制 UID" to "uid", "复制主页链接" to "link").forEach { (label, value) -> com.green.note.ui.ReviewPopupMenuItem(text = { Text(label) }, onClick = { handleMenu(value) }) }
        }
    }
    Column(Modifier.fillMaxSize()) {
        if (profile == null) {
            ContentToolbarRow(Modifier.statusBarsPadding().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) { ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.weight(1f)); ContentIcon("search_rounded", "搜索", { onLink("/search") }); Box { ContentIcon("more_vert_rounded", "主页操作", { topMenu = true }); ProfileMenu() } }
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { if (error == null) com.green.note.ui.ReviewCircularProgress() else Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(if (isContentAccessError(error)) "暂无内容" else error.orEmpty(), textAlign = androidx.compose.ui.text.style.TextAlign.Center); if (!isContentAccessError(error)) { Spacer(Modifier.height(12.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = { revision++ }) { Text("重试") } } } }
        } else {
            @Composable fun Header() {
                val row = profile!!
                val name = row.text("username", "userName", "name")
                val avatar = row.text("userAvatar", "avatar", "user_avatar")
                val cover = row.text("userCover", "cover", "cover_url", "bg", "background", "background_url", "backgroundUrl")
                Box(Modifier.fillMaxWidth().background(Color(0xFF1F2B26))) {
                    if (cover.isNotEmpty()) ContentImage(api, cover, "主页封面", Modifier.matchParentSize().clickable { onGallery(listOf(cover), 0, null) }, showDefaultError = false)
                    Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = .24f)))
                    Column(Modifier.padding(start = 16.dp, top = statusTop + 52.dp, end = 16.dp, bottom = 16.dp)) {
                        Row(Modifier.height(96.dp), verticalAlignment = Alignment.CenterVertically) {
                            ProfileAvatar(api, avatar, row.text("avatarFrame", "avatar_frame", "userAvatarFrame", "user_avatar_frame"), name, 84.dp, 104.dp) {
                                if (avatar.isNotEmpty()) onGallery(listOf(avatar), 0, null)
                            }
                            Spacer(Modifier.weight(1f))
                            if (mine) {
                                ProfileButton("编辑资料") { editingProfile = true; onAccountAction(if (session.authenticated) "profile" else "local_profile") }
                                Spacer(Modifier.width(10.dp))
                                ProfileRoundIcon("qr_code_2_rounded", "二维码") { onAccountAction("qr") }
                            } else {
                                ProfileButton(if (following) "已关注" else "关注", filled = !following, working = working) {
                                    if (!working) scope.launch { working = true; try { following = api.followUser(row, following) } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "关注失败") } finally { working = false } }
                                }
                                Spacer(Modifier.width(10.dp))
                                ProfileRoundIcon("mail_outline_rounded", "私信") { if (session.authenticated) onChat(MessagePartner(uid, name, avatar)) else toast.showSnackbar("请先使用酷安账号登录") }
                            }
                        }
                        Spacer(Modifier.height(17.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(name.ifEmpty { "酷安用户" }, Modifier.weight(1f, fill = false), fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            row.text("level", "userLevel", "user_level").takeIf(String::isNotEmpty)?.let { level ->
                                Spacer(Modifier.width(7.dp))
                                Text(if (level.startsWith("Lv.", true)) level else "Lv.$level",
                                    Modifier.background(Color(0xFFEC6337), RoundedCornerShape(50)).padding(horizontal = 9.dp),
                                    fontSize = 11.sp, lineHeight = 16.sp, fontStyle = FontStyle.Italic, fontWeight = FontWeight.Medium, color = Color.White)
                            }
                        }
                        val bio = row.text("bio", "subTitle", "sign", "signature", "intro", "description")
                        if (bio.isNotEmpty()) {
                            Spacer(Modifier.height(17.dp))
                            Row {
                                MaterialGlyph("local_offer_outlined", Modifier.padding(top = 2.dp, end = 9.dp), size = 15.dp, color = Color.White)
                                Text(bio, Modifier.weight(1f), fontSize = 14.sp, lineHeight = 20.sp, color = Color.White)
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            listOf(
                                Triple("获赞", row.text("be_like_num", "feed_like_num", "beLikeNum", "feedLikeNum", "like_num", "likeNum", "likenum"), ""),
                                Triple("关注", row.text("follow_num", "followNum", "follownum", "follow"), if (mine) "myFollowList" else "followList"),
                                Triple("粉丝", row.text("fans_num", "fansNum", "fansnum", "fans"), if (mine) "myFansList" else "userFansList"),
                            ).forEach { (label, count, route) ->
                                Row(Modifier.clickable(enabled = route.isNotEmpty()) { onLink("/v6/user/$route?uid=$uid") }, verticalAlignment = Alignment.Bottom) {
                                    Text(count.ifEmpty { "0" }, Modifier.alignByBaseline(), fontSize = 16.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                                    Spacer(Modifier.width(4.dp))
                                    Text(label, Modifier.alignByBaseline(), fontSize = 16.sp, lineHeight = 20.sp, color = Color.White)
                                }
                            }
                        }
                        val chips = remember(row) { profileChips(row) }
                        if (chips.isNotEmpty()) {
                            Spacer(Modifier.height(12.dp))
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                chips.forEach { (label, gender) ->
                                    val background = when (gender) {
                                        "male" -> Color(0xFF4288D4).copy(alpha = .65f)
                                        "female" -> Color(0xFFB4479A).copy(alpha = .65f)
                                        else -> Color.White.copy(alpha = .28f)
                                    }
                                    Text(label, Modifier.background(background, RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 2.dp),
                                        fontSize = 12.sp, lineHeight = 16.sp, color = Color.White)
                                }
                            }
                        }
                    }
                }
            }
            Box(Modifier.fillMaxSize().background(pageColor)) {
                Column(Modifier.fillMaxSize().nestedScroll(nested)) {
                    Box(Modifier.clipToBounds().layout { measurable, constraints ->
                        val child = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
                        headerHeight = child.height
                        val shift = collapsed.coerceIn(0f, (child.height - barHeight).coerceAtLeast(0f)).toInt()
                        val height = (child.height - shift).coerceAtMost((constraints.maxHeight - 120.dp.roundToPx()).coerceAtLeast(0))
                        layout(child.width, height) { child.placeRelative(0, -shift) }
                    }) { Header() }
                    ProfileTabs(tabs.map { it.first }, pager.currentPage, railColor, dark) { index -> scope.launch { pager.animateScrollToPage(index) } }
                    HorizontalPager(pager, Modifier.weight(1f)) { index ->
                        if (index == 0) {
                            val cards = profile?.optJSONArray("homeTabCardRows").objects().filter { item -> listOf("关注的人", "关注的板块", "热门动态").none { item.text("title", "name").contains(it) } }
                            val scroll = rememberLazyListState()
                            com.green.note.ui.ReviewScrollActivity(scroll)
                            LazyColumn(Modifier.fillMaxSize(), state = scroll, flingBehavior = profileFling, contentPadding = PaddingValues(start = 8.dp, top = 10.dp, end = 8.dp, bottom = 24.dp)) {
                                item {
                                    ContentListTile(headlineContent = { Text(if (mine) "我的装备" else "TA的装备") },
                                        leadingContent = { MaterialGlyph("devices_other_rounded") },
                                        trailingContent = { MaterialGlyph("chevron_right_rounded") },
                                        modifier = Modifier.clickable {
                                            onLink("/v6/page/dataList?url=" + android.net.Uri.encode("/feed/nodeRatingList?uid=$uid&targetType=all&parseRatingToFeed=1") +
                                                "&title=" + android.net.Uri.encode(if (mine) "我的装备" else "TA的装备") + "&pageContext=user_space")
                                        })
                                }
                                items(cards) { card -> Box(Modifier.padding(bottom = 8.dp)) { EntityRow(api, card, onOpen, onUser, onLink, onGallery, onLike, onMore) } }
                            }
                        } else {
                            val request = tabs[index].second!!
                            val query = request.query + buildMap { put("uid", uid); if (request.query.containsKey("url")) { put("title", tabs[index].first); put("subTitle", ""); put("pageContext", "user_space") }; if (tabs[index].first == "收藏") put("showDefault", "1") }
                            val state = lists.getOrPut(index) { ContentListState { page, first, last -> repository.page(request.copy(query = query), page, first, last) } }
                            val isFeed = index == 1
                            val feedCount = profile?.text("feed_num", "feedNum", "feednum", "feeds").orEmpty()
                            ContentList(api, state, onOpen, onUser, onLink, onGallery, onLike, onMore, flingBehavior = profileFling,
                                header = if (isFeed) ({
                                    Text(if (feedCount.isEmpty()) "全部动态" else "全部动态 ($feedCount)",
                                        Modifier.padding(start = 16.dp, top = 6.dp, bottom = 2.dp), fontSize = 12.sp, lineHeight = 16.sp,
                                        color = if (dark) Color(0xFF898989) else colors.onSurfaceVariant)
                                }) else null,
                                itemContent = if (isFeed) ({ item ->
                                    if (item.text("entityType", "entity_type").lowercase() in setOf("feed", "article", "feedarticle", "feed_article") ||
                                        item.text("entityType", "entity_type").isEmpty() && item.has("message")) {
                                        NativeFeedCard(api, item, false, onOpen, onUser, onLink, onGallery, onLike, onMore, null,
                                            profileCard = true, profileAvatarFrame = profile?.text("avatarFrame", "avatar_frame", "userAvatarFrame", "user_avatar_frame").orEmpty()
                                                .takeIf { item.text("uid").ifEmpty { item.optJSONObject("userInfo")?.text("uid").orEmpty() } == uid }.orEmpty())
                                    } else EntityRow(api, item, onOpen, onUser, onLink, onGallery, onLike, onMore)
                                }) else null)
                        }
                    }
                }
                ContentToolbarRow(Modifier.fillMaxWidth().background(if (coverCollapsed) railColor else Color.Transparent).statusBarsPadding().height(52.dp).contentToolbarBorder(coverCollapsed), verticalAlignment = Alignment.CenterVertically, color = if (coverCollapsed) colors.onSurface else Color.White.copy(alpha = .88f)) {
                    ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp), size = 24.dp); Spacer(Modifier.width(16.dp))
                    Text(if (coverCollapsed) profile?.text("username", "name").orEmpty() else "", Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
                    ContentIcon("search_rounded", "搜索", { onLink("/search") })
                    Box { ContentIcon("more_vert_rounded", "主页操作", { topMenu = true }); ProfileMenu() }
                }
            }
        }
    }
    confirmation?.let { choice -> com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { confirmation = null }, title = { Text(if (choice == "identity") "设为我的公开资料？" else "拉黑这位用户？") }, text = { Text(if (choice == "identity") "只会在本机及匿名账户备份中保存这个公开主页的 UID、名称和头像。酷安不会验证你是否拥有该账号；这不会建立 Cookie 登录，也不会开放发帖、评论等操作。" else "拉黑会影响你在酷安看到的相关内容。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirmation = null }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { confirmation = null; scope.launch {
        if (choice == "identity") try { profile?.let { api.setPublicIdentity(it) } } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
        else if (action("/v6/user/addToBlackList", "GET")) blocked = true
    } }) { Text(if (choice == "identity") "确认这是我" else "拉黑") } }) }
    if (remark != null) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { remark = null }, title = { Text("修改备注") }, text = { CommunityFormField(remark.orEmpty(), { remark = it }, "备注") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { remark = null }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { val value = remark.orEmpty().trim(); remark = null; scope.launch { action("/v6/user/updateRemark", body = mapOf("uid" to uid, "name" to value)) } }) { Text("保存") } })
}

@Composable
internal fun ProfileAvatar(api: ContentApi, url: String, frame: String, name: String, size: androidx.compose.ui.unit.Dp, frameSize: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        ContentAvatar(api, url, name, size, onClick)
        if (frame.isNotEmpty()) ContentImage(api, frame, null, Modifier.requiredSize(frameSize),
            androidx.compose.ui.layout.ContentScale.Fit, showDefaultError = false, showLoading = false)
    }
}

@Composable
private fun ProfileRoundIcon(icon: String, description: String, onClick: () -> Unit) {
    Box(Modifier.size(36.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = .24f))
        .clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        MaterialGlyph(icon, size = 24.dp, color = Color.White, contentDescription = description)
    }
}

@Composable
private fun ProfileButton(title: String, filled: Boolean = false, working: Boolean = false, action: () -> Unit) {
    Box(Modifier.width(100.dp).height(36.dp).clip(RoundedCornerShape(50))
        .background(if (filled) darkProfileAccent else Color.White.copy(alpha = .24f))
        .clickable(enabled = !working, role = Role.Button, onClick = action), contentAlignment = Alignment.Center) {
        if (working) com.green.note.ui.ReviewCircularProgress(Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
        else Text(title, color = Color.White, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)
    }
}
