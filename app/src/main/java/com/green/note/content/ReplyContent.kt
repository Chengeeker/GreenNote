package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.ReviewOutlinedTextField as OutlinedTextField

import com.green.note.ui.rememberReviewScrollState
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import com.green.note.ui.tapCombinedClickable as combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

@Stable
internal class ReplyDraft {
    var message by mutableStateOf("")
    var image by mutableStateOf("")
    var uploaded by mutableStateOf("")
    var forward by mutableStateOf(false)
    var sending by mutableStateOf(false)
}

internal class ReplyReactionStore {
    val values = mutableStateMapOf<String, Pair<Boolean, Int>>()
}
internal val LocalReplyReactions = staticCompositionLocalOf<ReplyReactionStore?> { null }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReplyComposer(api: ContentApi, feedId: String, replyId: String, draft: ReplyDraft, onDismiss: () -> Unit, onSent: () -> Unit, actionScope: kotlinx.coroutines.CoroutineScope) {
    val session = LocalContentSession.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val owner = remember { api.imageCacheScope() }
    var target by remember(replyId) { mutableStateOf(replyId) }
    val busy = draft.sending
    val toast = remember { com.green.note.ui.AppToastState() }
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(error) { error?.let { toast.showSnackbar(it); error = null } }
    var picking by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) scope.launch {
        picking = true
        var newFile = ""; var committed = false
        try { newFile = withContext(Dispatchers.IO) { cacheDraftImage(context, uri) }; val old = draft.image; draft.image = newFile; draft.uploaded = ""; committed = true; if (old.isNotEmpty()) withContext(Dispatchers.IO) { File(old).delete() } }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "无法选择图片，请重试" }
        finally { if (!committed && newFile.isNotEmpty()) withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) { File(newFile).delete() }; picking = false }
    } }
    com.green.note.ui.ReviewModalBottomSheet(
        onDismissRequest = { if (!busy) onDismiss() }, sheetState = sheet,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        val keyboard = LocalSoftwareKeyboardController.current
        LaunchedEffect(sheet, focus) {
            snapshotFlow { sheet.currentValue }.first { it == SheetValue.Expanded }
            focus.requestFocus()
            keyboard?.show()
        }
        // The dialog already reserves IME insets. Scroll only when the form exceeds that viewport.
        Column(Modifier.fillMaxWidth().verticalScroll(rememberReviewScrollState()).padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (target.isEmpty()) "发表评论" else "回复评论", Modifier.weight(1f), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                if (target.isNotEmpty()) com.green.note.ui.ReviewTextButton(onClick = { target = "" }, enabled = !busy) { Text("取消回复指定人") }
                ContentIcon("close_rounded", "关闭", { if (!busy) onDismiss() })
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(draft.message, { draft.message = it }, Modifier.fillMaxWidth().then(Modifier.focusRequester(focus)), enabled = !busy, textStyle = MaterialTheme.typography.bodyLarge, minLines = 2, maxLines = 5, placeholder = { Text(if (target.isEmpty()) "说点什么吧…" else "回复这条评论…") }, shape = RoundedCornerShape(12.dp))
            Spacer(Modifier.height(10.dp))
            if (draft.image.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
                coil.compose.AsyncImage(File(draft.image), "评论图片", Modifier.size(72.dp).clip(RoundedCornerShape(8.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                ContentIcon("close", "移除评论图片", { if (!busy) { val path = draft.image; draft.image = ""; draft.uploaded = ""; scope.launch(Dispatchers.IO) { File(path).delete() } } })
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                ContentIcon("image_outlined", "从相册选择图片", { if (!busy && !picking) picker.launch("image/*") })
                com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { draft.forward = !draft.forward }, enabled = !busy) {
                    MaterialGlyph(if (draft.forward) "check_box_rounded" else "check_box_outline_blank_rounded", size = 18.dp)
                    com.green.note.ui.ReviewButtonIconGap(); Text("同时转发", fontSize = 12.sp)
                }
                Spacer(Modifier.weight(1f))
                com.green.note.ui.ReviewButton(enabled = !busy, onClick = {
                    onDismiss()
                    if (draft.message.isBlank() && draft.image.isEmpty()) return@ReviewButton
                    if (!session.authenticated) { toast.showSnackbar("请重新登录后发送评论"); return@ReviewButton }
                    draft.sending = true
                    actionScope.launch { try {
                        check(owner == api.imageCacheScope()) { "账号已变更" }
                        if (draft.image.isNotEmpty() && draft.uploaded.isEmpty()) draft.uploaded = api.uploadFeedImage(withContext(Dispatchers.IO) { prepareUploadPng(File(draft.image)) })
                        check(owner == api.imageCacheScope()) { "账号已变更" }
                        val body = mutableMapOf("id" to target.ifEmpty { feedId }, "type" to if (target.isEmpty()) "feed" else "reply", "message" to draft.message.trim())
                        if (draft.uploaded.isNotEmpty()) body["pic"] = draft.uploaded
                        if (draft.forward) body["replyAndForward"] = "1"
                        api.request("/v6/feed/reply", "POST", body = body)
                        val path = draft.image; draft.image = ""; draft.message = ""; draft.uploaded = ""; draft.forward = false
                        if (path.isNotEmpty()) withContext(Dispatchers.IO) { File(path).delete() }
                        onSent(); toast.showSnackbar("评论已提交")
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: Exception) { toast.showSnackbar(failure.message ?: "发送失败，内容已保留") }
                    finally { draft.sending = false } }
                }) { Text("发送") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReplyRow(api: ContentApi, row: JSONObject, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, nested: Boolean = false, authorUid: String = "", onFilterAuthor: (() -> Unit)? = null, onReplyRequest: ((JSONObject) -> Unit)? = null, onDeleteRequest: ((JSONObject) -> Unit)? = null, onCloseAllThreads: (() -> Unit)? = null) {
    if (!remember(row) { visibleReply(row) }) return
    val session = LocalContentSession.current; val login = LocalContentLogin.current
    val scope = rememberCoroutineScope(); val toast = remember { com.green.note.ui.AppToastState() }
    var localLiked by remember(row) { mutableStateOf(row.optJSONObject("userAction")?.optInt("like") == 1 || row.text("isLike", "is_like", "is_liked") in setOf("1", "true")) }
    var localLikes by remember(row) { mutableIntStateOf(row.optInt("likenum")) }
    val reactions = LocalReplyReactions.current
    val reaction = reactions?.values?.get(row.text("id"))
    val liked = reaction?.first ?: localLiked
    val likes = reaction?.second ?: localLikes
    var working by remember { mutableStateOf(false) }; var composer by remember { mutableStateOf(false) }
    var thread by remember { mutableStateOf(false) }; var menu by remember { mutableStateOf(false) }
    var replyTarget by remember { mutableStateOf(row.text("id")) }
    var delete by remember { mutableStateOf(false) }; var deleteTarget by remember { mutableStateOf(row) }; var deleted by remember { mutableStateOf(false) }
    val draft = remember { ReplyDraft() }
    if (deleted) return
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
    val nameColor = if (dark) Color(0xFF26A69A) else Color(0xFF00897B)
    val (uid, name, avatar) = remember(row) { replyAuthor(row) }
    val id = replyId(row)
    val message = remember(row) { replyMessage(row) }
    val children = remember(row) { visibleReplyChildren(row) }
    val count = row.text("replyRowsMore", "replynum").toIntOrNull() ?: children.size
    val replyCount = row.text("replynum").toIntOrNull() ?: 0
    @Composable fun AuthorBadge() { Text("楼主", Modifier.clip(RoundedCornerShape(3.dp)).background(scheme.primary.copy(alpha = .12f)).clickable(enabled = onFilterAuthor != null) { onFilterAuthor?.invoke() }.padding(horizontal = 4.dp, vertical = 1.dp), fontSize = 9.5.sp, fontWeight = FontWeight.Bold, color = scheme.primary) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.Top) {
        ContentAvatar(api, avatar, name, 36.dp, onClick = if (uid.isNotEmpty()) ({ onUser(uid) }) else null)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(name.ifEmpty { "酷安用户" }, Modifier.weight(1f, fill = false).clickable(enabled = uid.isNotEmpty()) { onUser(uid) }, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = nameColor)
                if (uid.isNotEmpty() && uid == authorUid) { Spacer(Modifier.width(5.dp)); AuthorBadge() }
            }
            Spacer(Modifier.height(5.dp)); if (message.isNotEmpty()) ContentRichText(message, onLink = onLink, lineHeight = 23.2.sp)
            val images = feedImages(row)
            if (images.isNotEmpty()) { Spacer(Modifier.height(8.dp)); FeedImages(api, images, detail = true, raw = row) { urls, index -> onGallery(urls, index, JSONObject(row.toString()).put("_composeGalleryUseDeclaredDimensions", true)) } }
            if (!nested && (children.isNotEmpty() || count > 0)) Column(Modifier.padding(top = 8.dp, bottom = 4.dp).fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(if (dark) Color(0xFF1E1E1E) else scheme.surfaceContainerHighest.copy(alpha = .45f)).padding(9.dp)) {
                children.take(3).forEach { child ->
                    ReplySubLine(api, child, row, authorUid, nameColor, onUser, onLink, onGallery)
                    Spacer(Modifier.height(4.dp))
                }
                if (count > 0) Text(if (children.isEmpty() || count > 3 || row.optInt("replyRowsMore") > 0) "共 $count 条回复 >" else "查看对话 >", Modifier.clickable { thread = true }.padding(top = 2.dp), color = nameColor, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(relativeTime(row.text("dateline", "createTime", "create_time")), fontSize = 11.5.sp, color = scheme.onSurfaceVariant.copy(alpha = .7f)); Spacer(Modifier.weight(1f))
                Row(Modifier.clickable(enabled = !working) {
                    if (session.anonymous) toast.showSnackbar(session.loginRequiredMessage) else { working = true; scope.launch { try { api.request(if (liked) "/v6/feed/unLikeReply" else "/v6/feed/likeReply", "POST", mapOf("id" to id)); localLikes = (likes + if (liked) -1 else 1).coerceAtLeast(0); localLiked = !liked; reactions?.values?.set(id, localLiked to localLikes) } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } finally { working = false } } }
                }.padding(horizontal = 6.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                    val color = if (liked) scheme.primary else scheme.onSurfaceVariant.copy(alpha = .8f)
                    MaterialGlyph(if (liked) "thumb_up_rounded" else "thumb_up_outlined", size = 15.dp, color = color)
                    if (likes > 0) { Spacer(Modifier.width(4.dp)); Text("$likes", fontSize = 12.sp, color = color) }
                }
                Spacer(Modifier.width(10.dp))
                Row(Modifier.clickable { if (onReplyRequest != null) onReplyRequest(row) else { replyTarget = id; composer = true } }.padding(horizontal = 6.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                    MaterialGlyph("chat_bubble_outline_rounded", size = 15.dp, color = scheme.onSurfaceVariant.copy(alpha = .8f))
                    if (replyCount > 0) { Spacer(Modifier.width(4.dp)); Text("$replyCount", fontSize = 12.sp, color = scheme.onSurfaceVariant.copy(alpha = .8f)) }
                }
                Box {
                    Box(Modifier.size(48.dp).clickable { menu = true }, contentAlignment = Alignment.Center) { MaterialGlyph("more_horiz_rounded", size = 18.dp, color = scheme.onSurfaceVariant.copy(alpha = .6f)) }
                    com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) {
                        if (!nested) com.green.note.ui.ReviewPopupMenuItem(text = { Text("查看楼中楼回复") }, onClick = { menu = false; thread = true })
                        com.green.note.ui.ReviewPopupMenuItem(text = { Text("评论详情") }, onClick = { menu = false; onLink("/v6/feed/replyDetail?id=$id") })
                        if (session.authenticated && uid == session.uid) com.green.note.ui.ReviewPopupMenuItem(text = { Text("删除评论") }, onClick = { menu = false; if (onDeleteRequest != null) onDeleteRequest(row) else { deleteTarget = row; delete = true } })
                    }
                }
            }
        }
    }
    if (composer) ReplyComposer(api, row.text("feedid", "feedId"), replyTarget, draft, { composer = false }, { composer = false }, actionScope = scope)
    if (thread) ReplyThread(api, row, onUser, onLink, onGallery, authorUid,
        onReplyRequest = { child -> thread = false; if (onReplyRequest != null) onReplyRequest(child) else { replyTarget = child.text("id"); composer = true } },
        onDeleteRequest = { child -> thread = false; if (onDeleteRequest != null) onDeleteRequest(child) else { deleteTarget = child; delete = true } },
        onCloseAll = { thread = false; onCloseAllThreads?.invoke() }, close = { thread = false })
    if (delete) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { delete = false }, title = { Text("删除这条评论？") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { delete = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
        delete = false; scope.launch { try { api.request("/v6/feed/deleteReply", "POST", mapOf("id" to deleteTarget.text("id"))); if (deleteTarget.text("id") == id) deleted = true } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } }
    }) { Text("删除") } })
}

@Composable
private fun ReplySubLine(api: ContentApi, child: JSONObject, parent: JSONObject, authorUid: String, nameColor: Color,
    onUser: (String) -> Unit, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val author = remember(child) { replyAuthor(child) }
    val parentAuthor = remember(parent) { replyAuthor(parent) }
    val recipient = child.text("ruid").ifEmpty { if (child.text("rusername") == parentAuthor.name) parentAuthor.uid else "" }
    val badgeStyle = LocalTextStyle.current.copy(fontSize = 9.5.sp, fontWeight = FontWeight.Bold)
    val badgeSize = androidx.compose.ui.text.rememberTextMeasurer().measure("楼主", badgeStyle, softWrap = false, maxLines = 1).size
    val density = LocalDensity.current
    val badgeWidth = with(density) { (badgeSize.width + 2 * 3.dp.roundToPx()).toSp() }
    val badgeHeight = with(density) { (badgeSize.height + 2 * 1.dp.roundToPx()).toSp() }
    val inline = mapOf("reply-author-badge" to androidx.compose.foundation.text.InlineTextContent(androidx.compose.ui.text.Placeholder(badgeWidth, badgeHeight, androidx.compose.ui.text.PlaceholderVerticalAlign.AboveBaseline)) {
        Text("楼主", Modifier.clip(RoundedCornerShape(3.dp)).background(scheme.primary.copy(alpha = .12f)).padding(horizontal = 3.dp, vertical = 1.dp),
            style = badgeStyle, softWrap = false, maxLines = 1, color = scheme.primary)
    })
    val prefix = androidx.compose.ui.text.buildAnnotatedString {
        fun username(name: String, uid: String) {
            val start = length; append(name)
            addStyle(androidx.compose.ui.text.SpanStyle(color = nameColor, fontWeight = FontWeight.Bold), start, length)
            if (uid.isNotEmpty()) addLink(androidx.compose.ui.text.LinkAnnotation.Clickable("user:$uid") { onUser(uid) }, start, length)
            if (uid.isNotEmpty() && uid == authorUid) { append(" "); appendInlineContent("reply-author-badge", "楼主") }
        }
        username(author.name.ifEmpty { "酷安用户" }, author.uid)
        if (child.text("rusername").isNotEmpty()) { val start = length; append(" 回复 "); addStyle(androidx.compose.ui.text.SpanStyle(color = scheme.onSurfaceVariant), start, length); username(child.text("rusername"), recipient) }
        val start = length; append(": "); addStyle(androidx.compose.ui.text.SpanStyle(fontWeight = FontWeight.Bold), start, length)
    }
    ContentRichText(replyMessage(child), prefix = prefix, prefixInline = inline, onLink = onLink, fontSize = 16.sp, lineHeight = 21.6.sp)
    val images = feedImages(child)
    if (images.isNotEmpty()) { Spacer(Modifier.height(6.dp)); FeedImages(api, images, detail = true, raw = child) { urls, index -> onGallery(urls, index, JSONObject(child.toString()).put("_composeGalleryUseDeclaredDimensions", true)) } }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReplyThread(api: ContentApi, root: JSONObject, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, authorUid: String, onReplyRequest: (JSONObject) -> Unit, onDeleteRequest: (JSONObject) -> Unit, onCloseAll: () -> Unit, close: () -> Unit) {
    val feedId = root.text("feedid", "feedId", "feed_id", "fid")
    val state = remember(api, root) { ContentListState(visibleReplyChildren(root).filter(::visibleReply).distinctBy(::replyId).map { normalizeReply(it, feedId) }) { page, first, last ->
        val request = ContentRequest("/v6/feed/replyList", mapOf("id" to replyId(root), "feedType" to "feed_reply", "discussMode" to "1", "listType" to "lastupdate_desc"))
        loadReplyPage(api, request, feedId, page, first, last)
    } }
    com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = close, containerColor = Color.Transparent) {
        Surface(shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.height(with(LocalDensity.current) { (LocalWindowInfo.current.containerSize.height * .64f).toDp() })) {
            val dark = MaterialTheme.colorScheme.surface.red + MaterialTheme.colorScheme.surface.green + MaterialTheme.colorScheme.surface.blue < 1.5f
            Row(Modifier.fillMaxWidth().height(64.dp).background(if (dark) Color(0xFF1E1E1E) else MaterialTheme.colorScheme.surfaceContainerLow), verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.ReviewIconButton(onClick = close) { MaterialGlyph("close_rounded", size = 28.dp, contentDescription = "关闭回复") }; Text("回复(${root.text("replyRowsMore", "replynum").ifEmpty { "0" }})", Modifier.weight(1f), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                com.green.note.ui.ReviewTextButton(onClick = onCloseAll) { Text("查看原动态") }; Spacer(Modifier.width(8.dp))
            }
            HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .35f))
            ContentList(api, state, {}, onUser, onLink, onGallery, {}, {}, itemContent = { row -> ReplyRow(api, row, onUser, onLink, onGallery, authorUid = authorUid, onReplyRequest = onReplyRequest, onDeleteRequest = onDeleteRequest, onCloseAllThreads = onCloseAll) }, header = {
                Surface(color = if (dark) Color(0xFF2A2A2A) else MaterialTheme.colorScheme.surfaceContainerHigh) { ReplyRow(api, root, onUser, onLink, onGallery, nested = true, authorUid = authorUid, onReplyRequest = onReplyRequest, onDeleteRequest = onDeleteRequest, onCloseAllThreads = onCloseAll) }
            })
        }
    }
    }
}
