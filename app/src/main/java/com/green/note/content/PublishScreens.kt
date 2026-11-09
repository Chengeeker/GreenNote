package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.ReviewTextField as TextField

import com.green.note.ui.rememberReviewScrollState
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import com.green.note.ui.tapCombinedClickable as combinedClickable
import com.green.note.ui.tapToggleable as toggleable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.DpOffset
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

private data class PublishType(val label: String, val type: String, val icon: String, val start: Long, val end: Long, val badge: Boolean = false)
private val publishTypes = listOf(
    PublishType("动态", "feed", "chat_bubble_rounded", 0xFF6DC83E, 0xFF7CD84C),
    PublishType("图文", "article", "article_rounded", 0xFF2B9DF4, 0xFF43B6FC),
    PublishType("点评广场", "rating", "forum_rounded", 0xFF2C6CE8, 0xFF4488FA, true),
    PublishType("二手", "ershou", "swap_horiz_rounded", 0xFFF59E0B, 0xFFFBBF24),
    PublishType("酷图", "picture", "landscape_rounded", 0xFFF97316, 0xFFFB923C),
    PublishType("清单", "collection", "bookmark_rounded", 0xFF9333EA, 0xFFB066FC, true),
    PublishType("天梯榜", "rank", "military_tech_rounded", 0xFFDC2626, 0xFFF04B4B, true),
    PublishType("投票", "vote", "how_to_vote_rounded", 0xFFE11D48, 0xFFF84F75),
)

@Composable
internal fun PublishPicker(onDismiss: () -> Unit, onSelected: (String, String) -> Unit) {
    val colors = MaterialTheme.colorScheme
    val dark = colors.surface.red + colors.surface.green + colors.surface.blue < 1.5f
    val background = if (dark) Color(0xFF202023) else Color.White
    Column(Modifier.fillMaxWidth().background(background, RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)).navigationBarsPadding().padding(start = 16.dp, top = 26.dp, end = 16.dp, bottom = 12.dp)) {
        publishTypes.chunked(4).forEachIndexed { index, row ->
        if (index != 0) Spacer(Modifier.height(22.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
            row.forEach { type -> Column(Modifier.clickable { onSelected(type.label, type.type) }, horizontalAlignment = Alignment.CenterHorizontally) {
                Box {
                    Box(Modifier.size(56.dp).dropShadow(RoundedCornerShape(17.dp), Shadow(radius = 10.dp, color = Color(type.start).copy(alpha = .35f), offset = DpOffset(0.dp, 4.dp))).clip(RoundedCornerShape(17.dp)).background(Brush.linearGradient(listOf(Color(type.start), Color(type.end)))), contentAlignment = Alignment.Center) {
                        MaterialGlyph(type.icon, size = 28.dp, color = Color.White)
                    }
                    if (type.badge) Text("NEW", Modifier.align(Alignment.TopEnd).offset(6.dp, (-5).dp).clip(RoundedCornerShape(8.dp)).background(Color(0xFFEF4444)).then(Modifier.border(1.5.dp, background, RoundedCornerShape(8.dp))).padding(horizontal = 6.5.dp, vertical = 3.dp), fontSize = 8.5.sp, lineHeight = 9.35.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
                Spacer(Modifier.height(8.dp)); Text(type.label, fontSize = 13.5.sp, fontWeight = FontWeight.Normal, color = if (dark) Color(0xFFE2E2E6) else Color(0xFF333333))
            } }
        } }
        Spacer(Modifier.height(26.dp))
        Box(Modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(24.dp)).background(if (dark) Color(0xFF2E2E32) else Color(0xFFF1F1F3)).clickable(onClick = onDismiss), contentAlignment = Alignment.Center) { Text("取消", fontSize = 15.5.sp, fontWeight = FontWeight.Medium, color = if (dark) Color(0xFFCCCCCC) else Color(0xFF444444)) }
        Spacer(Modifier.height(4.dp))
    }
}

@Composable
internal fun PublishScreen(api: ContentApi, type: String, onDone: () -> Unit) {
    var message by rememberSaveable(type) { mutableStateOf("") }
    var title by rememberSaveable(type) { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val canSend = message.isNotBlank() && (type in listOf("feed", "article") || type.startsWith("forward:")) && (type != "article" || title.isNotBlank())
    BackHandler(message.isNotEmpty() || title.isNotEmpty() || busy) { if (!busy) confirmDiscard = true }
    Column(Modifier.fillMaxSize().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.End) {
            com.green.note.ui.ReviewOutlinedButton(enabled = canSend && !busy, onClick = {
                busy = true; error = null
                scope.launch {
                    try {
                        if (type.startsWith("forward:")) api.request("/v6/feed/forward", "POST", body = mapOf("id" to type.substringAfter(':'), "message" to message.trim()))
                        else api.request("/v6/feed/createFeed", "POST", body = buildMap {
                            put("message", message.trim()); put("type", type)
                            if (type == "article") { put("extra_title", title.trim()); put("message_title", title.trim()) }
                        })
                        onDone()
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: Exception) { error = failure.message }
                    finally { busy = false }
                }
            }, shape = RoundedCornerShape(2.dp)) { Text(if (busy) "发布中" else "发布", fontSize = 15.sp) }
        }
        if (type == "article") TextField(title, { title = it }, Modifier.fillMaxWidth(), placeholder = { Text("请输入标题") }, enabled = !busy)
        TextField(message, { message = it }, Modifier.weight(1f).fillMaxWidth(), placeholder = { Text("分享你的新鲜事…") }, enabled = !busy,
            colors = TextFieldDefaults.colors(unfocusedContainerColor = Color.Transparent, focusedContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent))
        error?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
    }
    if (confirmDiscard) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { confirmDiscard = false }, title = { Text("放弃编辑？") }, text = { Text("当前未发布的内容将被丢弃。") },
        confirmButton = { com.green.note.ui.ReviewTextButton(onClick = onDone) { Text("放弃") } }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirmDiscard = false }) { Text("继续编辑") } })
}

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
internal fun FeedMoreSheet(api: ContentApi, row: JSONObject, session: ContentSession, onDismiss: () -> Unit, onLogin: () -> Unit,
    onForward: () -> Unit, onLink: (String) -> Unit) {
    val context = LocalContext.current
    val url = "https://www.coolapk.com/feed/${row.text("id")}"
    val scope = rememberCoroutineScope(); val toast = remember { com.green.note.ui.AppToastState() }
    val surface = MaterialTheme.colorScheme.surface
    val dark = surface.red + surface.green + surface.blue < 1.5f
    var collectionsOpen by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }
    var menuVisible by remember { mutableStateOf(true) }
    var favorited by remember(row, api.imageCacheScope()) { mutableStateOf(api.isFeedFavorited(row)) }
    var forward by remember { mutableStateOf(false) }; var draft by remember { mutableStateOf("") }
    val foreground = if (dark) Color.White.copy(alpha = .85f) else Color(0xFF333333)
    fun notice(message: String) { toast.showSnackbar(message); onDismiss() }
    fun copy(message: String) { (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("动态链接", url)); notice(message) }
    fun toggle() {
        if (busy) return
        menuVisible = false
        if (!session.authenticated && !session.anonymous) { notice(session.loginRequiredMessage); return }
        busy = true; val identity = api.imageCacheScope()
        scope.launch {
            try {
                if (session.anonymous) favorited = api.toggleLocalFavorite(row)
                else {
                    val folders = api.feedCollections(row.text("id")); val selected = folders.filter { it.selected }.map { it.id }
                    val default = folders.firstOrNull { it.isDefault } ?: folders.firstOrNull { it.title.lowercase() in setOf("默认收藏夹", "默认收藏单", "default") }
                    if (selected.isEmpty() && default == null) error("未找到默认收藏夹，请长按选择收藏夹")
                    check(identity == api.imageCacheScope()) { "账号已切换" }
                    api.updateFeedCollections(row, if (selected.isEmpty()) listOf(default!!.id) else emptyList(), selected)
                    favorited = selected.isEmpty()
                }
                notice(if (favorited) "已添加至收藏" else "已取消收藏")
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { notice(failure.message ?: "操作失败") }
            finally { busy = false }
        }
    }
    @Composable fun Circle(label: String, icon: String, green: Boolean, iconSize: Int = 24, color: Color? = null, longClick: (() -> Unit)? = null, action: () -> Unit) {
        Column(Modifier.width(60.dp).combinedClickable(enabled = !busy, onClick = action, onLongClick = longClick), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(56.dp).clip(androidx.compose.foundation.shape.CircleShape).background(if (green) if (dark) Color(0xFF1B3D2F) else Color(0xFFE2F7EB) else if (dark) Color(0xFF2C2C2E) else Color(0xFFF0F0F2)), contentAlignment = Alignment.Center) { MaterialGlyph(icon, size = iconSize.dp, color = color ?: if (green) Color(0xFF00C06D) else foreground) }
            Spacer(Modifier.height(8.dp)); Text(label, fontSize = 12.sp, lineHeight = 14.4.sp, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, color = if (dark) Color.White.copy(alpha = .75f) else Color(0xFF555555))
        }
    }
    if (menuVisible) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }, containerColor = if (dark) Color(0xFF1E1E1E) else Color.White, shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp), sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.navigationBarsPadding()) {
            Spacer(Modifier.height(10.dp)); Box(Modifier.align(Alignment.CenterHorizontally).size(36.dp, 4.dp).clip(RoundedCornerShape(2.dp)).background(if (dark) Color.White.copy(alpha = .2f) else Color.Black.copy(alpha = .15f))); Spacer(Modifier.height(18.dp))
            Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Circle(if (favorited) "已收藏" else "收藏", if (favorited) "star_rounded" else "star_outline_rounded", false, color = if (favorited) Color(0xFFFFC107) else null, longClick = { menuVisible = false; val denied = collectionPickerDenied(session); if (denied == null) collectionsOpen = true else notice(denied) }, action = ::toggle)
                Circle("屏蔽", "visibility_off_outlined", false) { notice("此入口尚未接入对应服务") }
                Circle("举报", "crisis_alert_outlined", false) { notice("此入口尚未接入对应服务") }
            }
            Spacer(Modifier.height(22.dp)); Row(Modifier.padding(horizontal = 20.dp)) { Circle("推荐上头条", "military_tech_outlined", true, 26) { notice("此入口尚未接入对应服务") } }
            Spacer(Modifier.height(22.dp)); Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Circle("动态", "edit_note_rounded", true, 26) { menuVisible = false; forward = true }
                Circle("私信", "mail_outline_rounded", true) { notice("请在消息列表中选择要分享的好友") }
                Circle("生成分享图", "image_outlined", true) { notice("此入口尚未接入对应服务") }
                Circle("看看号", "podcasts_outlined", true) { notice("此入口尚未接入对应服务") }
                Circle("微信", "chat_bubble_rounded", true) { copy("已复制动态链接，可前往微信粘贴分享") }
                Circle("朋友圈", "motion_photos_on_outlined", true) { copy("已复制动态链接，可前往朋友圈粘贴分享") }
                Circle("QQ", "forum_outlined", true) { copy("已复制动态链接，可前往QQ粘贴分享") }
                Circle("复制链接", "link_rounded", true) { copy("动态链接已复制到剪贴板") }
                Circle("更多", "more_horiz_rounded", true) { copy("已复制动态链接") }
            }
            Spacer(Modifier.height(24.dp)); Box(Modifier.fillMaxWidth().height(50.dp).clickable(enabled = !busy, onClick = onDismiss), contentAlignment = Alignment.Center) { Text("取消", color = foreground, fontSize = 16.sp) }; Spacer(Modifier.height(8.dp))
        }
    }
    if (collectionsOpen) CollectionPicker(api, row, onDismiss = onDismiss, onSaved = { favorited = it; collectionsOpen = false; onDismiss() })
    if (forward) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = onDismiss, title = { Text("转发动态") }, text = { CommunityFormField(draft, { draft = it }, "", lines = 4, minimumLines = 1, hint = "说点什么…") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = onDismiss) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
        forward = false
        if (session.anonymous) { notice(session.loginRequiredMessage); return@ReviewButton }
        busy = true; scope.launch { try { api.request("/v6/feed/forward", "POST", body = mapOf("id" to row.text("id"), "message" to draft.trim())); notice("已提交转发") } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { notice(failure.message ?: "转发失败") } finally { busy = false } }
    }) { Text("转发") } })
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CollectionPicker(api: ContentApi, feed: JSONObject, onDismiss: () -> Unit, onSaved: (Boolean) -> Unit) {
    var collections by remember { mutableStateOf<List<ContentCollection>?>(null) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(api, feed, attempt) {
        error = null
        try { collections = api.feedCollections(feed.text("id")); selected = collections.orEmpty().filter { it.selected }.map { it.id }.toSet() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message }
    }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { it != SheetValue.Hidden })
    com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { if (!saving) onDismiss() }, sheetState = sheet, dragHandle = null) {
        Column(Modifier.fillMaxWidth().height(with(LocalDensity.current) { (LocalWindowInfo.current.containerSize.height * .65f).toDp() }).navigationBarsPadding()) {
            Text("选择收藏夹", Modifier.padding(start = 24.dp, top = 20.dp, end = 24.dp, bottom = 12.dp), style = MaterialTheme.typography.titleLarge)
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                val rows = collections
                if (rows == null) {
                    if (error == null) com.green.note.ui.ReviewCircularProgress() else Column(Modifier.padding(24.dp).verticalScroll(rememberReviewScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(error.orEmpty()); com.green.note.ui.ReviewTextButton(onClick = { attempt++ }) { Text("重试") }
                    }
                } else if (rows.isEmpty()) Text("暂无可用收藏夹，请先在“我的收藏”中新建")
                else LazyColumn(Modifier.fillMaxSize(), state = com.green.note.ui.rememberReviewLazyListState()) { items(rows, key = { it.id }) { collection ->
                    ContentListTile(headlineContent = { Text(collection.title) }, supportingContent = if (collection.isDefault) ({ Text("默认收藏夹") }) else null,
                        trailingContent = { com.green.note.ui.ReviewCheckbox(collection.id in selected, onCheckedChange = null, enabled = !saving, shrinkWrap = true) },
                        modifier = Modifier.toggleable(collection.id in selected, enabled = !saving, role = androidx.compose.ui.semantics.Role.Checkbox) { checked -> selected = if (checked) selected + collection.id else selected - collection.id })
                } }
            }
            if (collections != null && error != null) Text(error.orEmpty(), Modifier.padding(horizontal = 24.dp), color = MaterialTheme.colorScheme.error)
            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.ReviewTextButton(onClick = onDismiss, enabled = !saving) { Text("取消") }
                Spacer(Modifier.weight(1f))
                com.green.note.ui.ReviewButton(enabled = !saving && !collections.isNullOrEmpty(), onClick = {
                    saving = true; error = null
                    scope.launch {
                        try { api.updateFeedCollections(feed, selected.toList(), collections.orEmpty().filter { it.selected && it.id !in selected }.map { it.id }); onSaved(selected.isNotEmpty()) }
                        catch (cancelled: CancellationException) { throw cancelled }
                        catch (failure: Exception) { error = failure.message }
                        finally { saving = false }
                    }
                }) { Text(if (saving) "保存中…" else "完成") }
            }
        }
    }
}
