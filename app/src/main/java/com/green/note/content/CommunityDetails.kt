package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.rememberReviewScrollState
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun communityKind(row: JSONObject): String? {
    val type = row.text("entityType", "entity_type").lowercase()
    val feed = row.text("feedType", "feed_type").lowercase()
    val all = "$type $feed ${row.text("targetType").lowercase()}"
    return when {
        all.contains("answer") -> null
        all.contains("question") -> "question"
        type == "live" || all.contains("livecard") -> "live"
        all.contains("productalbum") || all.contains("anylist") -> "anylist"
        type == "goodslist" || feed == "goodslist" || all.contains("goodsrank") || feed.isEmpty() && row.optJSONObject("goodsListInfo")?.let { it.has("title") || it.has("item_num") || it.has("is_open_vote") } == true -> "goods"
        all.contains("collection") -> "collection"
        all.contains("dyh") && !all.contains("article") -> "dyh"
        type == "album" -> "album"
        else -> null
    }
}
internal fun communityTitle(kind: String): String = when (kind) { "question" -> "问题详情"; "live" -> "直播详情"; "collection" -> "收藏单"; "dyh" -> "看看号"; "album" -> "应用集"; "goods" -> "好物榜单"; else -> "万物清单" }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun CommunityDetailScreen(api: ContentApi, kind: String, id: String, onBack: () -> Unit,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    initial: JSONObject? = null, onComments: () -> Unit = {}) {
    if (kind in setOf("goods", "collection")) com.green.note.ui.OfficialHomeTheme {
        CommunityDetailContent(api, kind, id, onBack, onOpen, onUser, onLink, onGallery, onLike, onMore, initial, onComments)
    } else CommunityDetailContent(api, kind, id, onBack, onOpen, onUser, onLink, onGallery, onLike, onMore, initial, onComments)
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun CommunityDetailContent(api: ContentApi, kind: String, id: String, onBack: () -> Unit,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    initial: JSONObject?, onComments: () -> Unit) {
    var data by remember(kind, id) { mutableStateOf(initial?.let { JSONObject(it.toString()) }) }
    var complete by remember(kind, id) { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var challenge by remember(kind, id) { mutableStateOf<com.green.note.network.CaptchaRequired?>(null) }
    var requestedVerification by remember(kind, id) { mutableStateOf<com.green.note.network.CaptchaRequired?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var sort by rememberSaveable { mutableStateOf("reply") }
    var search by rememberSaveable { mutableStateOf("") }
    var query by rememberSaveable { mutableStateOf("") }
    val requests = remember { mutableStateMapOf<String, Boolean>() }
    var menu by remember { mutableStateOf(false) }
    var goodsMenu by remember { mutableStateOf(false) }
    var edit by remember { mutableStateOf(false) }
    var answering by remember { mutableStateOf(false) }
    var answer by rememberSaveable { mutableStateOf("") }
    var editTitle by rememberSaveable { mutableStateOf<String?>(null) }; var editDescription by rememberSaveable { mutableStateOf<String?>(null) }
    var delete by remember { mutableStateOf(false) }
    var removeItem by remember { mutableStateOf<JSONObject?>(null) }; var confirmRemove by remember { mutableStateOf(false) }
    val session = LocalContentSession.current
    val login = LocalContentLogin.current
    val scope = rememberCoroutineScope()
    val identity = remember { api.imageCacheScope() }
    val video = LocalContentVideo.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val toast = remember { com.green.note.ui.AppToastState() }
    val repo = remember(api) { ContentRepository(api) }
    LaunchedEffect(api, kind, id, revision) {
        val verification = requestedVerification
        requestedVerification = null
        challenge = null
        failure = null
        try {
            val path = when (kind) { "question", "goods", "anylist" -> "/v6/feed/detail"; "live" -> "/v6/live/detail"; "collection" -> "/v6/collection/detail"; "dyh" -> "/v6/dyh/detail"; else -> "/v6/album/detail" }
            val response = if (verification != null && path == "/v6/feed/detail") api.verifyFeedDetail(id, verification)
                else api.request(path, query = mapOf((if (kind == "dyh") "dyhId" else "id") to id))
            val loaded = response.optJSONObject("data") ?: error("详情为空")
            if (kind == "live") (loaded.optJSONObject("live") ?: loaded.optJSONObject("liveInfo") ?: loaded.optJSONObject("live_info"))?.let { nested -> nested.keys().forEach { loaded.put(it, nested.opt(it)) } }
            data = loaded; complete = true
        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { challenge = error as? com.green.note.network.CaptchaRequired; failure = error.message ?: "详情加载失败" }
    }
    fun retryDetail() { requestedVerification = challenge; revision++ }
    suspend fun write(path: String, method: String = "GET", query: Map<String, String> = emptyMap(), body: Map<String, String>? = null, multipart: Boolean = false, actionKey: String = path): Boolean {
        if (requests[actionKey] == true) return false
        if (!session.authenticated) { toast.showSnackbar("请先使用酷安账号登录"); return false }
        requests[actionKey] = true
        return try { check(api.imageCacheScope() == identity) { "账号已变更" }; if (multipart) api.submitMultipart(path, body.orEmpty(), query) else api.request(path, method, query, body); true }
        catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { toast.showSnackbar("操作失败，请确认登录有效、网络正常后重试"); false }
        finally { requests.remove(actionKey) }
    }
    val request = when (kind) {
        "question" -> ContentRequest("/v6/question/answerList", mapOf("id" to id, "sort" to sort))
        "collection" -> ContentRequest("/v6/collection/itemlist", mapOf("id" to id, "listType" to listOf("allFeedType", "feed", "feedArticle")[tab]))
        "dyh" -> if (query.isEmpty()) ContentRequest("/v6/dyhArticle/list", mapOf("dyhId" to id, "type" to if (tab == 0) "all" else "square")) else ContentRequest("/v6/search", mapOf("searchValue" to query, "type" to "feed", "pageType" to "tag", "pageParam" to data?.text("title").orEmpty().ifEmpty { id }))
        "album" -> ContentRequest("/v6/album/replyList", mapOf("id" to id))
        "anylist" -> ContentRequest("/v6/goodsList/list", mapOf("uid" to data?.text("uid").orEmpty().ifEmpty { session.uid }, "goodsId" to id))
        else -> ContentRequest("/v6/feed/replyList", mapOf("id" to id, "feedType" to "feed"))
    }
    val state = remember(kind, id, tab, query, revision) { ContentListState { page, first, last -> repo.page(request, page, first, last) } }
    LaunchedEffect(state, request, data != null) {
        if (kind == "question" && data != null) {
            state.bind(request) { page, first, last -> repo.page(request, page, first, last) }
        }
    }
    val row = data
    val owner = row != null && session.authenticated && row.text("uid", "userId") == session.uid
    val followed = row?.let { it.text("isFollow", "is_follow") in setOf("1", "true") || it.optJSONObject("userAction")?.optInt("follow") == 1 } == true
    fun follow() { scope.launch { val prefix = if (kind in setOf("question", "live", "collection", "dyh")) kind else "album"
        if (write("/v6/$prefix/${if (followed) "unFollow" else "follow"}", query = mapOf((if (kind == "dyh") "dyhId" else "id") to id), actionKey = "follow")) revision++ }
    }
    @Composable fun Actions(includeRefresh: Boolean = false) {
        @Composable fun Action(label: String, icon: String = "add", danger: Boolean = false, busy: Boolean = false, click: () -> Unit) {
            com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { if (!session.authenticated) toast.showSnackbar("请先使用酷安账号登录") else click() }, enabled = !busy, colors = if (danger) ButtonDefaults.filledTonalButtonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer) else ButtonDefaults.filledTonalButtonColors()) { com.green.note.ui.MaterialGlyph(if (busy) "hourglass_empty" else icon); com.green.note.ui.ReviewButtonIconGap(); Text(if (busy) "处理中…" else label) }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (includeRefresh) Action("刷新详情", "refresh") { menu = false; revision++ }
            if (kind in setOf("question", "collection", "dyh") && !(kind == "collection" && owner)) Action(if (followed) "已关注 · 取消" else "关注", busy = requests["follow"] == true, click = ::follow)
            if (kind == "question") Action("添加回答", "edit_outlined", busy = answering || requests["answer"] == true) { if (session.authenticated) answering = true else login() }
            if (kind == "collection" && owner) {
                Action("编辑", "edit_outlined", busy = edit || requests["edit"] == true) { edit = true }
                if (row?.text("isDefault", "is_default") !in setOf("1", "true")) Action("删除收藏单", "delete_outline", true, busy = delete || requests["delete"] == true) { delete = true }
                Action(if (row?.text("isOpen", "is_open") in setOf("1", "true")) "设为私密" else "设为公开", "lock_outline", busy = requests["visibility"] == true) { scope.launch { if (write("/v6/collection/update", "POST", body = mapOf("id" to id, "title" to row!!.text("title"), "description" to row.text("description"), "pic" to row.text("pic"), "isOpen" to if (row.text("isOpen", "is_open") in setOf("1", "true")) "0" else "1"), actionKey = "visibility")) revision++ } }
            }
        }
    }
    @Composable fun Header() {
        if (row == null) return
        if (kind == "collection") {
            Column(Modifier.background(if (MaterialTheme.colorScheme.surface.red + MaterialTheme.colorScheme.surface.green + MaterialTheme.colorScheme.surface.blue < 1.5f) androidx.compose.ui.graphics.Color(0xFF1E1E1E) else MaterialTheme.colorScheme.surface).padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 16.dp)) {
                Text(row.text("title"), fontSize = 23.sp, fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(20.dp))
                val user = row.optJSONObject("userInfo") ?: row
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ContentAvatar(api, row.text("userAvatar").ifEmpty { user.text("userAvatar") }, row.text("username").ifEmpty { user.text("username") }, 32.dp) { onUser(row.text("uid", "userId")) }
                    Spacer(Modifier.width(10.dp)); Text("${row.text("username").ifEmpty { user.text("username") }}  ${relativeTime(row.text("lastupdate", "dateline"))}更新", Modifier.weight(1f), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                    row.text("follow_num", "followNum", "follownum").takeIf(String::isNotEmpty)?.let { Spacer(Modifier.width(12.dp)); Text("${it}人关注", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                if (row.text("description").isNotEmpty()) { Spacer(Modifier.height(12.dp)); ContentRichText(row.text("description"), onLink = onLink) }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf("全部", "动态${row.text("feed_num", "feedNum").let { if (it.isNotEmpty()) "($it)" else "" }}", "图文${row.text("article_num", "articleNum", "feedArticle_num").let { if (it.isNotEmpty()) "($it)" else "" }}").forEachIndexed { index, label -> com.green.note.ui.ReviewChoiceChip(tab == index, { tab = index }, label = { Text(label) }, showCheckmark = false, shape = androidx.compose.foundation.shape.CircleShape, side = null, padding = PaddingValues(horizontal = 8.dp, vertical = 8.dp), selectedColor = androidx.compose.ui.graphics.Color(0xFF009688), backgroundColor = if (MaterialTheme.colorScheme.surface.red + MaterialTheme.colorScheme.surface.green + MaterialTheme.colorScheme.surface.blue < 1.5f) androidx.compose.ui.graphics.Color(0xFF1E1E1E) else MaterialTheme.colorScheme.surfaceContainer, labelStyle = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, color = if (tab == index) androidx.compose.ui.graphics.Color.White else MaterialTheme.colorScheme.onSurface)) } }
        } else {
            Column(Modifier.padding(16.dp)) {
                Text(if (kind == "live") when ((row.optJSONObject("live") ?: row.optJSONObject("liveInfo") ?: row.optJSONObject("live_info") ?: row).text("liveStatus", "live_status", "status")) { "0" -> "即将开始"; "1" -> "直播中"; else -> "直播详情" } else communityTitle(kind), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge); Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.Top) {
                    val image = row.text("cover", "pic", "logo", "icon", "cover_pic")
                    if (image.isNotEmpty()) { ContentImage(api, image, null, Modifier.size(80.dp).clip(RoundedCornerShape(12.dp)), heroCornerRadius = 12.dp); Spacer(Modifier.width(16.dp)) }
                    Text(row.text("extra_title", "title", "name", "message_title", "goods_title").ifEmpty { communityTitle(kind) }, Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall)
                }
                row.text("username", "userName").takeIf(String::isNotEmpty)?.let { Spacer(Modifier.height(8.dp)); Text(it, Modifier.clickable { onUser(row.text("uid")) }) }
                row.text("description", "intro", "message").takeIf(String::isNotEmpty)?.let { Spacer(Modifier.height(12.dp)); ContentRichText(it, onLink = onLink) }
                Spacer(Modifier.height(12.dp)); FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    mapOf("follownum" to "关注", "replynum" to "回复", "answernum" to "回答", "apknum" to "应用", "itemnum" to "内容").forEach { (field, label) -> if (row.has(field)) Text("${row.text(field)} $label") }
                }
                if (kind in setOf("question", "dyh")) { Spacer(Modifier.height(16.dp)); Actions() }
                if (kind == "question") FlowRow(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf("热门" to "reply", "高赞" to "like", "最新" to "dateline").forEach { (label, value) -> com.green.note.ui.ReviewChoiceChip(sort == value, { sort = value }, label = { Text(label) }) } }
                if (kind in setOf("dyh", "album")) FlowRow(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { (if (kind == "dyh") listOf("精选", "广场") else listOf("应用", "评论")).forEachIndexed { index, label -> com.green.note.ui.ReviewChoiceChip(tab == index, { tab = index }, label = { Text(label) }) } }
                if (kind == "dyh") CommunityFormField(search, { search = it }, "搜索号内内容", Modifier.padding(top = 12.dp), suffixIcon = "search", onSubmit = { query = it.trim() })
                if (kind == "live") {
                    val live = row.optJSONObject("live") ?: row.optJSONObject("liveInfo") ?: row.optJSONObject("live_info") ?: row
                    FlowRow(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (live.text("liveStatus", "live_status", "status") == "0") com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = ::follow, enabled = requests["follow"] != true) { com.green.note.ui.MaterialGlyph(if (requests["follow"] == true) "hourglass_empty" else "add"); com.green.note.ui.ReviewButtonIconGap(); Text(if (requests["follow"] == true) "处理中…" else if (followed) "取消预约" else "预约直播") }
                    val url = live.text("videoLiveUrl", "video_live_url", "videoPlaybackUrl", "video_playback_url", "videoUrl", "video_url", "playUrl", "play_url", "liveUrl")
                    if (url.isNotEmpty()) com.green.note.ui.ReviewButton(iconPadding = true, onClick = { video(JSONObject().put("url", url).put("title", row.text("title"))) }) { com.green.note.ui.MaterialGlyph("play_arrow"); com.green.note.ui.ReviewButtonIconGap(); Text("播放") }
                    val web = live.text("url", "liveUrl", "live_url", "webUrl").ifEmpty { "https://www.coolapk.com/live/$id" }
                    if (validWebUrl(web)) com.green.note.ui.ReviewOutlinedButton(iconPadding = true, onClick = { try { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(web))) } catch (_: Exception) { toast.showSnackbar("无法打开链接") } }) { com.green.note.ui.MaterialGlyph("open_in_browser"); com.green.note.ui.ReviewButtonIconGap(); Text("浏览器打开") }
                    }
                }
            }
        }
        failure?.let { com.green.note.ui.ReviewTextButton(onClick = ::retryDetail) { Text(if (challenge == null) it else "完成验证并重试") } }
    }
    if (kind in setOf("goods", "anylist") && row != null) {
        Box(Modifier.fillMaxSize()) {
            GoodsRankingContent(api, row, complete = complete, error = failure, onReload = ::retryDetail, onComments = onComments, onUser = onUser, onLink = onLink)
            ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
                ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.weight(1f))
                Box { ContentIcon("more_vert", "更多榜单操作", { goodsMenu = true }); com.green.note.ui.ReviewPopupMenu(goodsMenu, { goodsMenu = false }) {
                    com.green.note.ui.ReviewPopupMenuItem(text = { Text("刷新榜单") }, onClick = { goodsMenu = false; revision++ })
                    com.green.note.ui.ReviewPopupMenuItem(text = { Text("在官方网页查看") }, onClick = { goodsMenu = false; try { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("https://www.coolapk.com/feed/$id"))) } catch (_: Exception) { toast.showSnackbar("无法打开链接") } })
                } }
            }
        }
        return
    }
    val dark = MaterialTheme.colorScheme.surface.red + MaterialTheme.colorScheme.surface.green + MaterialTheme.colorScheme.surface.blue < 1.5f
    Column(Modifier.fillMaxSize().background(if (kind in setOf("collection", "goods") && dark) androidx.compose.ui.graphics.Color(0xFF101010) else com.green.note.ui.LocalScaffoldColor.current)) {
        ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).background(if (kind == "collection" && dark) androidx.compose.ui.graphics.Color(0xFF1E1E1E) else com.green.note.ui.LocalScaffoldColor.current).contentToolbarBorder(kind !in setOf("goods", "collection")), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp)); Text(if (kind in setOf("goods", "collection")) "" else communityTitle(kind), Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
            if (kind == "collection") ContentIcon("more_vert_rounded", "收藏单操作", { menu = true })
            else ContentIcon("refresh", "刷新详情", { revision++ })
        }
        when {
            row == null && failure == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
            row == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(failure.orEmpty(), textAlign = androidx.compose.ui.text.style.TextAlign.Center); Spacer(Modifier.height(12.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = ::retryDetail) { Text(if (challenge == null) "重试" else "完成验证并重试") } } }
            kind == "goods" || kind == "anylist" -> GoodsRankingContent(api, row, complete = complete, error = failure, onReload = ::retryDetail, onComments = onComments, onUser = onUser, onLink = onLink)
            kind == "live" -> Column(Modifier.verticalScroll(rememberReviewScrollState())) { Header() }
            kind == "album" && tab == 0 -> Column(Modifier.verticalScroll(rememberReviewScrollState())) { Header(); (row.optJSONArray("apkRows") ?: row.optJSONArray("apkList") ?: row.optJSONArray("apks")).objects().forEach { EntityRow(api, it, onOpen, onUser, onLink, onGallery, onLike, onMore) } }
            else -> ContentList(api, state, onOpen, onUser, onLink, onGallery, onLike, onMore, itemContent = if (kind == "collection") ({ item ->
                Box(Modifier.pointerInput(item.text("itemId", "item_id"), owner) { if (owner && item.text("itemId", "item_id").isNotEmpty()) detectTapGestures(onLongPress = { removeItem = item }) }) {
                    EntityRow(api, JSONObject(item.toString()).put("_composeOfficialLayout", true), onOpen, onUser, onLink, onGallery, onLike, onMore)
                }
            }) else if (kind == "question") ({ item ->
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    Text(item.text("username"), style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(12.dp))
                    ContentRichText(item.text("message"), onLink = onLink, maxLines = 8); Spacer(Modifier.height(8.dp))
                    Text("${item.text("likenum").ifEmpty { "0" }} 赞 · ${item.text("replynum").ifEmpty { "0" }} 条评论")
                    com.green.note.ui.ReviewTextButton(onClick = { onOpen(JSONObject(item.toString()).put("_composeQuestionId", id)) }) { Text("查看完整回答") }
                    HorizontalDivider()
                }
            }) else if (kind == "album") ({ item ->
                ContentListTile(headlineContent = { Text(item.text("username", "fromusername")) }, supportingContent = { ContentRichText(item.text("message", "note"), onLink = onLink) }, trailingContent = { com.green.note.ui.MaterialGlyph("chevron_right") }, modifier = Modifier.clickable { onOpen(JSONObject(item.toString()).put("entityType", "feed_reply")) })
            }) else null, loadInitially = kind != "question", header = { Header() })
        }
    }
    if (menu) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { menu = false }) { Column(Modifier.padding(16.dp)) { Actions(includeRefresh = true) } }
    if (removeItem != null) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { if (requests["remove"] != true) removeItem = null }) { com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { confirmRemove = true }, enabled = !confirmRemove && requests["remove"] != true, modifier = Modifier.padding(16.dp)) { com.green.note.ui.MaterialGlyph(if (confirmRemove || requests["remove"] == true) "hourglass_empty" else "remove_circle_outline"); com.green.note.ui.ReviewButtonIconGap(); Text(if (confirmRemove || requests["remove"] == true) "处理中…" else "移出收藏单") } }
    if (confirmRemove) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { confirmRemove = false }, title = { Text("移出收藏单？") }, text = { Text("此内容将从当前收藏单移除。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirmRemove = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
        val itemId = removeItem?.text("itemId", "item_id").orEmpty()
        confirmRemove = false
        if (itemId.isNotEmpty()) scope.launch { if (write("/v6/collection/removeItem", "POST", body = mapOf("itemId" to itemId), actionKey = "remove")) { removeItem = null; revision++ } }
    }) { Text("确认") } })
    if (delete) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { delete = false }, title = { Text("删除收藏单？") }, text = { Text("收藏单及其中内容的归属将被移除，此操作无法撤销。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { delete = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { delete = false; scope.launch { if (write("/v6/collection/delete", "POST", body = mapOf("id" to id), actionKey = "delete")) onBack() } }) { Text("确认") } })
    if (edit && row != null) {
        var title by remember { mutableStateOf(editTitle ?: row.text("title")) }; var description by remember { mutableStateOf(editDescription ?: row.text("description")) }
        var validated by remember { mutableStateOf(false) }
        com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { edit = false }, title = { Text("编辑收藏单") }, text = {
            Column(Modifier.verticalScroll(rememberReviewScrollState())) {
                CommunityFormField(title, { title = it }, "标题", Modifier.padding(bottom = 12.dp), limit = 100, error = if (validated && title.isBlank()) "请填写标题" else null)
                CommunityFormField(description, { description = it }, "说明", Modifier.padding(bottom = 12.dp), lines = 5)
            }
        }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { edit = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
            validated = true
            if (title.isNotBlank()) { editTitle = title.trim(); editDescription = description.trim(); edit = false; scope.launch {
                if (write("/v6/collection/update", "POST", body = mapOf("id" to id, "title" to title.trim(), "description" to description.trim(), "pic" to row.text("pic", "cover"), "isOpen" to if (row.text("isOpen", "is_open") in setOf("1", "true")) "1" else "0"), actionKey = "edit")) { editTitle = null; editDescription = null; revision++ }
            } }
        }) { Text("确认") } })
    }
    if (answering) { var draft by remember { mutableStateOf(answer) }; var validated by remember { mutableStateOf(false) }
    com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { answering = false }, title = { Text("添加回答") }, text = { Column(Modifier.verticalScroll(rememberReviewScrollState())) { CommunityFormField(draft, { draft = it }, "内容", Modifier.padding(bottom = 12.dp), lines = 5, limit = 10000, error = if (validated && draft.isBlank()) "请填写内容" else null) } }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { answering = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { validated = true; if (draft.isBlank()) return@ReviewButton; answer = draft.trim(); answering = false; scope.launch {
        val form = mutableMapOf<String, String>()
        "id,pic,location,long_location,media_url,media_pic,message_title,message_brief,extra_title,extra_url,extra_key,extra_pic,extra_info,message_cover,forwardid,dyhId,targetType,productId,targetId,location_city,location_country,media_info,goods_list_id".split(',').forEach { form[it] = "" }
        "publish_status,media_type,original_type,is_editInDyh,disallow_reply,vote_score,replyWithForward,insert_product_media,is_ks_doc,is_html_article".split(',').forEach { form[it] = "0" }
        form.putAll(mapOf("message" to answer, "type" to "answer", "fid" to id, "status" to "1", "latitude" to "0.0", "longitude" to "0.0"))
        if (write("/v6/feed/createFeed", body = form, multipart = true, actionKey = "answer")) { answer = ""; answering = false; revision++ }
    } }) { Text("确认") } })
    }
}
