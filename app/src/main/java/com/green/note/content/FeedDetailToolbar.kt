package com.green.note.content

import android.content.Intent
import com.green.note.ui.ReviewText as Text

import com.green.note.ui.tapClickable as clickable
import com.green.note.ui.tapCombinedClickable as combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
private fun DetailCapsule(modifier: Modifier, content: @Composable BoxScope.() -> Unit) {
    val scheme = MaterialTheme.colorScheme; val dark = scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
    if (LocalAppPreferences.current.liquidGlassNavBar) GlassSurface(modifier.height(44.dp), 24.dp, liquid = true, interactive = false, material = GlassMaterial.NAVIGATION, content = content)
    else Surface(modifier.height(44.dp), shape = RoundedCornerShape(24.dp),
        color = if (dark) Color(0xFF262626) else scheme.surfaceContainerHighest.copy(alpha = .92f),
        shadowElevation = 2.dp, border = androidx.compose.foundation.BorderStroke(
            if (dark) 1.dp else .6.dp, if (dark) Color.White.copy(alpha = .34f) else scheme.outlineVariant.copy(alpha = .35f)
        )) { Box(content = content) }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
internal fun FeedDetailToolbar(api: ContentApi, row: JSONObject, session: ContentSession, onLogin: () -> Unit, onCompose: () -> Unit,
    onComments: () -> Unit, modifier: Modifier = Modifier, xianyu: XianyuDestination? = null) {
    val context = LocalContext.current
    val trade = xianyu != null
    val scope = rememberCoroutineScope(); val toast = remember { AppToastState() }
    var liked by remember(row) { mutableStateOf(row.optJSONObject("userAction")?.text("like") in setOf("1", "true") || row.text("isLike", "is_like", "is_liked", "liked") in setOf("1", "true")) }
    var favorited by remember(row, api.imageCacheScope()) { mutableStateOf(api.isFeedFavorited(row)) }
    var likes by remember(row) { mutableIntStateOf(row.text("likenum", "likeNum").toIntOrNull() ?: 0) }
    var favorites by remember(row) { mutableIntStateOf(row.text("favnum", "favNum").toIntOrNull() ?: 0) }
    var busy by remember { mutableStateOf(false) }; var collections by remember { mutableStateOf(false) }; var forward by remember { mutableStateOf(false) }; var message by remember { mutableStateOf("") }
    val identity = remember { api.imageCacheScope() }
    fun changeFavorite(value: Boolean) { if (value != favorited) favorites = (favorites + if (value) 1 else -1).coerceAtLeast(0); favorited = value }
    fun action(anonymous: Boolean = false, requiresAccount: Boolean = false, block: suspend () -> Unit) {
        if (busy) return
        if ((session.anonymous && !anonymous) || (requiresAccount && !session.authenticated && !session.anonymous)) { toast.showSnackbar(session.loginRequiredMessage); return }
        scope.launch { busy = true; try { check(identity == api.imageCacheScope()) { "账号已切换" }; block() } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } finally { busy = false } }
    }
    @Composable fun RowScope.Action(icon: String, text: String, color: Color = MaterialTheme.colorScheme.onSurfaceVariant, long: (() -> Unit)? = null, click: () -> Unit) {
        Column(Modifier.weight(1f).fillMaxHeight().combinedClickable(enabled = !busy, onClick = click, onLongClick = long), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            MaterialGlyph(icon, size = 20.dp, color = color); Spacer(Modifier.height(1.dp)); Text(text, fontSize = 10.sp, lineHeight = 12.sp, color = color, maxLines = 1)
        }
    }
    val horizontal = if (trade) 20.dp else 14.dp
    Row(modifier.fillMaxWidth().navigationBarsPadding().padding(start = horizontal, top = 4.dp, end = horizontal, bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        if (!trade) {
            DetailCapsule(Modifier.weight(9f)) { Row(Modifier.fillMaxSize().clickable(onClick = onCompose).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) { MaterialGlyph("edit_outlined", size = 16.dp, color = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(8.dp)); Text("写评论", fontSize = 13.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
            Spacer(Modifier.width(10.dp))
        }
        DetailCapsule(Modifier.weight(if (trade) 175f else 12f)) { Row(Modifier.fillMaxSize().padding(horizontal = 4.dp)) {
            Action(if (liked) "thumb_up_rounded" else "thumb_up_outlined", if (likes > 0) "$likes" else if (trade) "点赞" else "赞", if (liked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) { action { api.request(if (liked) "/v6/feed/unlike" else "/v6/feed/like", "POST", query = mapOf("id" to row.text("id"))); liked = !liked; likes = (likes + if (liked) 1 else -1).coerceAtLeast(0) } }
            val replyCount = row.text("replynum", "replyNum").takeIf { it.isNotEmpty() && it != "0" }
            Action("chat_bubble_outline_rounded", if (trade) "评论" else replyCount ?: "评论",
                long = if (trade) onCompose else null, click = if (trade && replyCount == null) onCompose else onComments)
            Action(if (favorited) "star_rounded" else "star_outline_rounded", if (session.anonymous || favorites == 0) "收藏" else "$favorites", if (favorited) Color(0xFFFFA000) else MaterialTheme.colorScheme.onSurfaceVariant, long = { val denied = collectionPickerDenied(session); if (denied == null) collections = true else toast.showSnackbar(denied) }) {
                action(anonymous = true, requiresAccount = true) {
                    if (session.anonymous) changeFavorite(api.toggleLocalFavorite(row)) else {
                        val rows = api.feedCollections(row.text("id")); val selected = rows.filter { it.selected }.map { it.id }
                        val default = rows.firstOrNull { it.isDefault } ?: rows.firstOrNull { it.title.lowercase() in setOf("默认收藏夹", "默认收藏单", "default") }
                        if (selected.isEmpty() && default == null) error("未找到默认收藏夹，请长按选择收藏夹")
                        check(identity == api.imageCacheScope()) { "账号已切换" }
                        api.updateFeedCollections(row, if (selected.isEmpty()) listOf(default!!.id) else emptyList(), selected); changeFavorite(selected.isEmpty())
                    }
                    toast.showSnackbar(if (favorited) "已添加至收藏" else "已取消收藏")
                }
            }
            if (trade) Action("share_outlined", "分享") {
                try {
                    val intent = Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, "https://www.coolapk.com/feed/${android.net.Uri.encode(row.text("id"))}")
                    context.startActivity(Intent.createChooser(intent, null))
                } catch (_: Exception) { toast.showSnackbar("无法打开分享面板") }
            } else Action("repeat_rounded", row.text("forwardnum", "forwardNum").takeIf { it.isNotEmpty() && it != "0" } ?: "转发") { forward = true }
        } }
        if (xianyu != null) {
            val lifecycle = LocalLifecycleOwner.current.lifecycle
            val currentDestination by rememberUpdatedState(xianyu)
            var opening by remember { mutableStateOf(false) }
            Spacer(Modifier.weight(37f))
            DetailCapsule(Modifier.weight(108f)) {
                Row(Modifier.fillMaxSize().clickable(enabled = !opening) {
                    opening = true
                    scope.launch {
                        try {
                            val target = resolveXianyuItem(xianyu)
                            if (currentDestination != xianyu || !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return@launch
                            if (target == null) toast.showSnackbar("暂时无法解析闲鱼商品链接")
                            else if (!openXianyu(context, target)) toast.showSnackbar("无法打开闲鱼，请确认已安装")
                        } finally {
                            opening = false
                        }
                    }
                }, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically) {
                    XianyuMark(18.dp)
                    Text("去闲鱼", fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurface, maxLines = 1)
                }
            }
        }
    }
    if (collections) CollectionPicker(api, row, { collections = false }) { changeFavorite(it); collections = false }
    if (forward) ReviewAlertDialog(appDialog = true, onDismissRequest = { forward = false }, title = { Text("转发动态") }, text = { CommunityFormField(message, { message = it }, "", lines = 4, minimumLines = 1, hint = "说点什么…") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { forward = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { forward = false; action { api.request("/v6/feed/forward", "POST", body = mapOf("id" to row.text("id"), "message" to message.trim())); toast.showSnackbar("已提交转发") } }) { Text("转发") } })
}
