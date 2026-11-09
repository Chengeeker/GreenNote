package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.jsoup.Jsoup

@Composable
internal fun NotificationCenterScreen(api: ContentApi, onBack: () -> Unit, onList: (String, String) -> Unit, onMessages: () -> Unit,
    onFeed: (String, String) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit, onThread: (String) -> Unit) {
    val session = LocalContentSession.current
    val owner = remember { api.imageCacheScope() }
    var counts by remember { mutableStateOf(JSONObject()) }
    var working by remember { mutableStateOf(false) }
    var clearConfirm by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    suspend fun loadCounts() {
        if (!session.authenticated) return
        try { val data = notificationData(api.request("/v6/notification/checkCount")); if (api.imageCacheScope() == owner) counts = data }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { }
    }
    LaunchedEffect(api, lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { loadCounts() } }
    fun action(clear: Boolean) {
        if (working || !session.authenticated) return
        working = true
        scope.launch {
            try {
                check(owner == api.imageCacheScope()) { "登录账号已改变，请重新打开通知中心" }
                if (clear) { val count = clearInboxNotifications(api, owner); AppToastState().showSnackbar(if (count == 0) "暂无可清除的通知" else "已清除 $count 条通知") }
                else { api.request("/v6/notification/clearCount", "POST", mapOf("type" to "all")); counts = JSONObject(); AppToastState().showSnackbar("已设为全部已读") }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { AppToastState().showSnackbar("${if (clear) "清除未完成" else "设为已读失败"}：${failure.message}") }
            finally { working = false; revision++; loadCounts() }
        }
    }
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.red + scheme.background.green + scheme.background.blue < 1.5f
    val background = if (dark) Color(0xff1e1e1e) else Color.White
    MaterialTheme(colorScheme = scheme.copy(surface = background, onSurface = if (dark) Color(0xffcccccc) else Color(0xff292929), onSurfaceVariant = if (dark) Color(0xffbbbbbb) else Color(0xff666666))) {
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
        Column(Modifier.fillMaxSize().background(background)) {
            com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
                ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp))
                Spacer(Modifier.width(16.dp))
                Text("通知中心", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontSize = 19.sp, fontWeight = FontWeight.Bold, color = if (dark) Color(0xffd1d1d1) else Color(0xff222222))
                com.green.note.ui.ReviewIconButton(onClick = { action(false) }, enabled = !working && session.authenticated, modifier = Modifier.size(40.dp)) { MaterialGlyph("done_all_rounded", size = 22.dp, contentDescription = "设为全部已读") }
                com.green.note.ui.ReviewIconButton(onClick = { clearConfirm = true }, enabled = !working && session.authenticated, modifier = Modifier.size(40.dp)) { MaterialGlyph("delete_outline_rounded", size = 22.dp, contentDescription = "清除通知") }
                Spacer(Modifier.width(8.dp))
            }
            if (working) com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth().height(2.dp))
            key(revision) { NotificationListScreen(api, "/v6/notification/list", onFeed, onUser, onLink, onThread, header = {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, top = 2.dp, end = 16.dp, bottom = 10.dp)) {
                    NotificationShortcut("点赞", "thumb_up_alt_rounded", Color(0xffe53935), if (dark) Color(0xff332020) else Color(0xffffebee), counts.optInt("feedlike")) { onList("收到的赞", "/v6/notification/feedLikeList") }
                    NotificationShortcut("关注", "person_rounded", Color(0xff2196f3), if (dark) Color(0xff1b2838) else Color(0xffe3f2fd), counts.optInt("contacts_follow")) { onList("关注", "/v6/notification/contactsFollowList") }
                    NotificationShortcut("私信", "mail_rounded", Color(0xfffb8c00), if (dark) Color(0xff362817) else Color(0xfffff3e0), counts.optInt("message"), onMessages)
                }
            }) }
        }
        }
    }
    if (clearConfirm) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { clearConfirm = false }, title = { Text("清除通知") },
        text = { Text("清除通知中心的全部系统消息和评论回复通知？此操作无法撤销，不会删除评论、动态或私信。") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { clearConfirm = false }) { Text("取消") } },
        confirmButton = { com.green.note.ui.ReviewButton(onClick = { clearConfirm = false; action(true) }) { Text("确认") } })
}

@Composable
private fun RowScope.NotificationShortcut(title: String, icon: String, color: Color, background: Color, count: Int, onClick: () -> Unit) {
    Column(Modifier.weight(1f).clickable(onClick = onClick).padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        NotificationBadge(count) {
            Box(Modifier.size(52.dp).background(background, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) { MaterialGlyph(icon, size = 25.dp, color = color) }
        }
        Spacer(Modifier.height(7.dp)); Text(title, fontSize = 13.sp, fontWeight = FontWeight.Normal)
    }
}

internal fun notificationBadgeOffset(width: Float, badgeHeight: Float, rtl: Boolean): Pair<Float, Float> =
    (if (rtl) -4f else width - 12f) to (4f - badgeHeight / 2f)

@Composable
private fun NotificationBadge(count: Int, content: @Composable () -> Unit) {
    val colors = MaterialTheme.colorScheme
    androidx.compose.ui.layout.Layout(content = {
        Box { content() }
        if (count > 0) Box(Modifier.background(colors.error, RoundedCornerShape(50)).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) {
            Text(if (count > 99) "99+" else "$count", style = MaterialTheme.typography.labelSmall, color = colors.onError)
        }
    }, measurePolicy = NotificationBadgeMeasurePolicy)
}

@Composable
internal fun NotificationListScreen(api: ContentApi, path: String, onFeed: (String, String) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onThread: (String) -> Unit, header: (@Composable () -> Unit)? = null) {
    val repository = remember(api) { ContentRepository(api) }
    val state = remember(api, path) { ContentListState { page, first, last -> repository.page(ContentRequest(path), page, first, last) } }
    ContentList(api, state, {}, onUser, onLink, { _, _, _ -> }, {}, {}, header = header,
        itemContent = { row -> NotificationRow(api, row, path, onFeed, onUser, onLink, onThread) })
}

@Composable
private fun NotificationRow(api: ContentApi, row: JSONObject, path: String, onFeed: (String, String) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onThread: (String) -> Unit) {
    val owner = remember { api.imageCacheScope() }
    val target = remember(row) { notificationTarget(row) }
    val actor = remember(row, path) { notificationActor(row, path) }
    val parts = remember(row, path) { notificationText(row, path) }
    val targetRow = row.optJSONObject("targetRow") ?: JSONObject()
    val preview = row.optJSONObject("feedInfo") ?: row.optJSONObject("targetFeed") ?: targetRow.optJSONObject("feed") ?: row.optJSONObject("feed") ?: targetRow
    val quote = row.optJSONObject("replyRow") ?: targetRow.optJSONObject("replyRow")
    val previewText = remember(row) { Jsoup.parseBodyFragment(preview.text("message", "title", "description")).text() }
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var liked by remember(row) { mutableStateOf(row.optString("isLiked") in setOf("true", "1")) }
    val replyId = target.replyId.ifEmpty { if (targetRow.text("entityType") == "feed_reply") targetRow.text("id") else "" }
    val dark = MaterialTheme.colorScheme.background.let { it.red + it.green + it.blue < 1.5f }
    val color = if (dark) Color(0xffcccccc) else Color(0xff292929)
    val muted = if (dark) Color(0xff8c8c8c) else Color(0xff888888)
    fun open() { scope.launch {
        try {
            var feedId = target.feedId
            if (feedId.isEmpty() && target.replyId.isNotEmpty()) {
                val data = notificationData(api.request("/v6/feed/replyDetail", query = mapOf("id" to target.replyId)))
                feedId = data.text("feedId", "feed_id", "fid"); check(feedId.matches(Regex("[1-9][0-9]*"))) { "未返回原帖信息，无法定位评论" }
            }
            check(owner == api.imageCacheScope()) { "登录账号已改变" }
            if (feedId.isNotEmpty()) onFeed(feedId, target.replyId) else if (target.url.isNotEmpty()) onLink(target.url)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { AppToastState().showSnackbar("无法打开通知：${error.message}") }
    } }
    Row(Modifier.fillMaxWidth().clickable { open() }.padding(start = 14.dp, top = 10.dp, end = 14.dp), verticalAlignment = Alignment.Top) {
        if (parts.system) Box(Modifier.size(38.dp).background(Color(0xffa767ff), CircleShape), contentAlignment = Alignment.Center) { MaterialGlyph("notifications_rounded", size = 21.dp, color = Color.White) }
        else ContentAvatar(api, actor.avatar, parts.sender, 38.dp) { if (actor.uid.isNotEmpty()) onUser(actor.uid) }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(buildAnnotatedString {
                        withStyle(SpanStyle(color = color, fontSize = 14.5.sp, fontWeight = FontWeight.Medium)) { append(parts.sender) }
                        if (parts.action.isNotEmpty()) withStyle(SpanStyle(color = muted, fontSize = 13.5.sp, fontWeight = FontWeight.Normal)) { append(" ${parts.action}") }
                    }, lineHeight = 18.85.sp)
                    if (parts.content.isNotEmpty()) { Spacer(Modifier.height(5.dp)); ContentRichText(parts.content, maxLines = if (parts.system) 2 else 4, onLink = onLink, fontSize = 14.sp, lineHeight = 18.9.sp, color = color) }
                    if (quote != null && quote.length() > 0) Row(Modifier.padding(top = 5.dp).height(IntrinsicSize.Min)) {
                        Box(Modifier.width(2.5.dp).fillMaxHeight().background(muted.copy(alpha = .3f))); Spacer(Modifier.width(8.dp))
                        ContentRichText(quote.text("message", "note"), maxLines = 1, secondary = true, onLink = onLink, fontSize = 13.sp, lineHeight = 17.55.sp, color = muted)
                    }
                }
                if (!parts.system && previewText.isNotEmpty()) Text(previewText, Modifier.padding(start = 10.dp).width(68.dp), maxLines = 3, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.End, color = muted, fontSize = 11.5.sp, lineHeight = 14.375.sp)
            }
            Spacer(Modifier.height(5.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(relativeTime(row.text("dateline", "lastupdate", "timestamp")), Modifier.weight(1f), fontSize = 12.sp, color = muted)
                if (!parts.system && replyId.matches(Regex("[1-9][0-9]*")) && !path.endsWith("/feedLikeList")) {
                    com.green.note.ui.ReviewIconButton(onClick = { if (!busy) { busy = true; scope.launch {
                        try { check(owner == api.imageCacheScope()) { "登录账号已改变" }; api.request(if (liked) "/v6/feed/unLikeReply" else "/v6/feed/likeReply", "POST", mapOf("id" to replyId)); liked = !liked }
                        catch (cancelled: CancellationException) { throw cancelled }
                        catch (error: Exception) { AppToastState().showSnackbar("点赞失败：${error.message}") }
                        finally { busy = false }
                    } } }, enabled = !busy, modifier = Modifier.size(28.dp)) { MaterialGlyph(if (liked) "thumb_up_alt_rounded" else "thumb_up_alt_outlined", size = 18.dp, color = if (liked) MaterialTheme.colorScheme.primary else muted, contentDescription = if (liked) "取消点赞评论" else "点赞评论") }
                    Spacer(Modifier.width(8.dp))
                    com.green.note.ui.ReviewIconButton(onClick = { onThread(replyId) }, modifier = Modifier.size(28.dp)) { MaterialGlyph("chat_outlined", size = 18.dp, color = muted, contentDescription = "回复评论") }
                    Spacer(Modifier.width(4.dp))
                }
            }
            Spacer(Modifier.height(10.dp)); HorizontalDivider(thickness = 1.dp, color = muted.copy(alpha = .13f))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun NotificationReplyThread(api: ContentApi, id: String, onFeed: (String, String) -> Unit, onThread: (String) -> Unit, onLink: (String) -> Unit) {
    val session = LocalContentSession.current
    val owner = remember { api.imageCacheScope() }
    var data by remember(id) { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var editing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    var invalid by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val repository = remember(api) { ContentRepository(api) }
    LaunchedEffect(id, attempt) {
        try { val value = notificationData(api.request("/v6/feed/replyDetail", query = mapOf("id" to id))); check(owner == api.imageCacheScope()) { "登录账号已改变" }; data = value; error = null }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "评论详情加载失败，点击重试" }
    }
    val detail = data
    if (detail == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (error == null) com.green.note.ui.ReviewCircularProgress() else com.green.note.ui.ReviewTextButton(onClick = { attempt++ }) { Text(error.orEmpty()) }
    } else key(id, attempt) {
        val list = remember { ContentListState { page, first, last -> repository.page(ContentRequest("/v6/feed/replyList", mapOf("id" to id, "feedType" to "feed_reply")), page, first, last) } }
        ContentList(api, list, {}, {}, onLink, { _, _, _ -> }, {}, {}, header = {
            Column(Modifier.padding(16.dp)) {
                Text(detail.text("username"), style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(12.dp)); ContentRichText(detail.text("message", "note"), onLink = onLink)
                Spacer(Modifier.height(16.dp)); FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = {
                        if (!session.authenticated || session.anonymous) AppToastState().showSnackbar("请先使用酷安账号登录")
                        else { draft = ""; invalid = false; busy = true; editing = true }
                    }, enabled = !busy) { MaterialGlyph(if (busy) "hourglass_empty" else "reply"); ReviewButtonIconGap(); Text(if (busy) "处理中…" else "回复这条评论") }
                    val feedId = detail.text("feedId", "feed_id", "fid")
                    if (feedId.isNotEmpty()) com.green.note.ui.ReviewOutlinedButton(onClick = { onFeed(feedId, "") }) { Text("查看原动态") }
                }
            }
        }, itemContent = { row ->
            ReviewTileLayout(Modifier.clickable { onThread(row.text("id")) }, horizontalPadding = 14.dp,
                subtitle = { ContentRichText(row.text("message"), onLink = onLink, fontSize = 12.5.sp, lineHeight = 17.5.sp, secondary = true) }) {
                Text(row.text("username"), fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = adjustedWeight(600))
            }
        })
    }
    if (editing) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { editing = false; busy = false }, title = { Text("回复评论") }, text = {
        Column(Modifier.verticalScroll(rememberReviewScrollState()).padding(bottom = 12.dp)) {
            CommunityFormField(draft, { draft = it; invalid = false }, "内容", lines = 5, limit = 5000, error = if (invalid) "请填写内容" else null)
        }
    }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { editing = false; busy = false }) { Text("取消") } }, confirmButton = {
        com.green.note.ui.ReviewButton(onClick = {
            if (draft.isBlank()) invalid = true else { val message = draft.trim(); editing = false; scope.launch {
                try {
                    check(owner == api.imageCacheScope()) { "登录账号已改变" }
                    api.request("/v6/feed/reply", "POST", body = mapOf("id" to id, "type" to "reply", "message" to message))
                    draft = ""; attempt++
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { AppToastState().showSnackbar("操作失败，请确认登录有效、网络正常后重试") }
                finally { busy = false }
            } }
        }) { Text("确认") }
    })
}

