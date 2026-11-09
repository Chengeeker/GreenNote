package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.text.Html
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import com.green.note.ui.tapCombinedClickable as combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.TextFieldValue
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.distinctUntilChanged
import org.json.JSONObject
import java.io.File

internal data class MessagePartner(val uid: String, val name: String, val avatar: String)
internal fun messagePartner(row: JSONObject): MessagePartner {
    val user = row.optJSONObject("messageUserInfo") ?: row.optJSONObject("fromUserInfo") ?: JSONObject()
    return MessagePartner(row.text("messageUid", "fromuid", "toUid", "targetUid", "uid").ifEmpty { user.text("uid") },
        row.text("messageUsername", "fromusername", "username", "userName", "title").ifEmpty { user.text("username") },
        row.text("messageUserAvatar", "fromUserAvatar").ifEmpty { user.text("userAvatar") })
}
internal fun chatKind(row: JSONObject): String = when (val type = row.text("entityType", "entity_type")) {
    "messageExtra" -> when (row.text("entityTemplate", "entity_template")) { "float" -> "follow"; "time" -> "time"; else -> "notice" }
    "", "message" -> if (row.text("message", "content", "text", "message_pic", "messagePic", "pic", "picture", "image", "imageUrl").isEmpty()) "hidden" else "message"
    else -> "hidden"
}
internal fun chatKey(row: JSONObject): String = "${chatKind(row)}:${row.text("messageId", "message_id", "mid", "id", "ukey").takeUnless { it == "0" }.orEmpty().ifEmpty { "${row.text("entityId", "entity_id")}:${row.text("dateline")}:${row.text("title")}:${row.text("message")}" }}"
internal fun chatPicture(row: JSONObject): String {
    val private = row.text("message_pic", "messagePic")
    val id = row.text("id")
    if (private.isNotEmpty() && Regex("[1-9][0-9]*").matches(id)) return "https://api.coolapk.com/v6/message/showImage?id=$id&type=n"
    val url = com.green.note.network.normalizeNetworkImageUrl(private.ifEmpty { row.text("pic", "picture", "image", "imageUrl") })
    return url.takeIf { runCatching { java.net.URI(it).let { uri -> uri.scheme == "https" && !uri.host.isNullOrEmpty() } }.getOrDefault(false) }.orEmpty()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MessageSessionsScreen(api: ContentApi, onBack: () -> Unit, onChat: (MessagePartner, String) -> Unit) {
    val state = remember(api) { ContentListState { page, _, _ -> parsePage(api.request("/v6/message/list", query = mapOf("page" to "$page")), page) } }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val scroll = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    val owner = remember { api.imageCacheScope() }
    var selecting by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var deleting by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var singleDelete by remember { mutableStateOf<String?>(null) }
    fun toggle(key: String) { if (key.isNotEmpty()) selected = if (key in selected) selected - key else selected + key }
    BackHandler(selecting && !deleting) { selecting = false; selected = emptySet() }
    LaunchedEffect(state) { state.load() }
    LaunchedEffect(state, scroll) { snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { if (state.rows.isNotEmpty() && it >= state.rows.size - 4 && !state.busy && state.error == null) state.load() } }
    Column(Modifier.fillMaxSize()) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
            if (selecting) com.green.note.ui.ReviewTextButton(onClick = { selecting = false; selected = emptySet() }, enabled = !deleting, modifier = Modifier.width(56.dp)) { Text("取消", fontSize = 15.sp) }
            else ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp))
            Spacer(Modifier.width(16.dp))
            Text(if (selecting) if (selected.isEmpty()) "选择会话" else "已选择 ${selected.size} 项" else "私信", Modifier.weight(1f), fontSize = 19.sp, fontWeight = FontWeight.Bold)
            if (selecting) {
                val all = state.rows.map { it.text("ukey", "sessionKey", "session_id") }.filter(String::isNotEmpty).toSet()
                com.green.note.ui.ReviewTextButton(onClick = { selected = if (selected == all) emptySet() else all }, enabled = !deleting && all.isNotEmpty()) { Text(if (selected == all && all.isNotEmpty()) "取消全选" else "全选", fontSize = 15.sp) }
            } else com.green.note.ui.ReviewIconButton(onClick = { selecting = true; selected = emptySet() }, enabled = state.rows.isNotEmpty(), modifier = Modifier.size(40.dp)) { MaterialGlyph("delete_outline_rounded", size = 22.dp, contentDescription = "管理私信") }
            Spacer(Modifier.width(8.dp))
        }
        com.green.note.ui.ReviewRefreshBox(isRefreshing = state.refreshing, onRefresh = { scope.launch { state.load(true) } }, modifier = Modifier.weight(1f)) {
            if (state.busy && state.rows.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
            else {
            LazyColumn(state = scroll, modifier = Modifier.fillMaxSize()) {
                itemsIndexed(state.rows, key = { _, row -> row.text("ukey", "sessionKey", "session_id").ifEmpty { entityKey(row) } }) { index, row ->
                    val partner = messagePartner(row)
                    val key = row.text("ukey", "sessionKey", "session_id")
                    var menu by remember { mutableStateOf(false) }
                    Row(Modifier.fillMaxWidth().combinedClickable(onClick = { if (selecting) toggle(key) else if (key.isNotEmpty() || partner.uid.isNotEmpty()) onChat(partner, key) },
                        onLongClick = if (key.isEmpty()) null else { { selecting = true; toggle(key) } }).padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (selecting) { MaterialGlyph(if (key in selected) "check_circle_rounded" else "radio_button_unchecked", size = 22.dp, color = if (key in selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline.copy(alpha = .5f)); Spacer(Modifier.width(12.dp)) }
                        ContentAvatar(api, partner.avatar, partner.name, 44.dp)
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(partner.name.ifEmpty { "私信会话" }, Modifier.weight(1f), fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Spacer(Modifier.width(8.dp)); Text(messageTime(row.text("dateline", "created_at", "last_update", "time", "date", "last_time")), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .75f))
                                if (!selecting) Box {
                                    com.green.note.ui.ReviewIconButton(onClick = { menu = true }, modifier = Modifier.size(28.dp)) { MaterialGlyph("more_vert_rounded", size = 16.dp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .5f)) }
                                    com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) { com.green.note.ui.ReviewPopupMenuItem(text = { Text("删除会话") }, onClick = { menu = false; singleDelete = key; confirm = true }) }
                                }
                            }
                            Spacer(Modifier.height(5.dp))
                            Text(Html.fromHtml(row.text("lastMessage", "message", "description"), Html.FROM_HTML_MODE_COMPACT).toString(), fontSize = 13.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    if (index < state.rows.lastIndex || state.busy || state.error != null) HorizontalDivider(Modifier.padding(start = 74.dp), thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .25f))
                }
                item { if (state.busy) Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                    else if (state.error != null) {
                        if (state.rows.isEmpty()) com.green.note.ui.ReviewTileLayout(Modifier.clickable { scope.launch { state.load(true) } }, horizontalPadding = 14.dp) {
                            Text(state.error.orEmpty(), fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = com.green.note.ui.adjustedWeight(600))
                        } else Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load(false) } }) { Text("加载失败，点击重试：") }
                        }
                    }
                }
            }
            }
        }
        if (selecting) Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface)) {
            HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .15f))
            Box(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp)) {
            com.green.note.ui.ReviewButton(iconPadding = true, onClick = { singleDelete = null; confirm = true }, enabled = selected.isNotEmpty() && !deleting, modifier = Modifier.fillMaxWidth().height(42.dp), shape = RoundedCornerShape(21.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xffff5252), contentColor = Color.White)) {
                MaterialGlyph("delete_outline_rounded", size = 20.dp); com.green.note.ui.ReviewButtonIconGap(); Text(if (selected.isEmpty()) "删除" else "删除 (${selected.size})", fontSize = 15.sp, fontWeight = FontWeight.Bold)
            }
            }
        }
    }
    if (confirm) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { confirm = false }, title = { Text(if (singleDelete == null) "删除私信？" else "删除会话？") }, text = { Text(if (singleDelete == null) "确定要删除选中的 ${selected.size} 个会话吗？删除后不可撤销。" else "确定要删除此私信会话吗？删除后不可撤销。") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirm = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(colors = ButtonDefaults.buttonColors(containerColor = Color(0xffff5252)), onClick = {
            confirm = false; deleting = true
            val targets = singleDelete?.let(::listOf) ?: selected.toList()
            scope.launch {
                try { for (key in targets) { check(owner == api.imageCacheScope()) { "登录账号已改变" }; api.request("/v6/message/deleteChat", query = mapOf("ukey" to key)); selected = selected - key }; selecting = false; if (singleDelete == null) com.green.note.ui.AppToastState().showSnackbar("已删除 ${targets.size} 个会话") }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { com.green.note.ui.AppToastState().showSnackbar(error.message ?: "删除失败") }
                finally { deleting = false; state.load(true) }
            }
        }) { Text("删除") } })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MessageChatScreen(api: ContentApi, session: ContentSession, partner: MessagePartner, initialKey: String,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLink: (String) -> Unit, onBack: () -> Unit, onUser: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val scope = rememberCoroutineScope()
    val accountScope = remember { api.imageCacheScope() }
    var key by remember { mutableStateOf(initialKey) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var follow by remember { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    var initialBusy by remember { mutableStateOf(false) }
    var loadingOlder by remember { mutableStateOf(false) }
    var following by remember { mutableStateOf(false) }
    var options by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var page by remember { mutableIntStateOf(0) }
    var more by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var failures by remember { mutableIntStateOf(0) }
    var draft by rememberSaveable(stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue()) }
    val text = draft.text
    var imagePath by rememberSaveable { mutableStateOf("") }
    var uploaded by remember { mutableStateOf("") }
    var emojiSelection by remember { mutableStateOf<TextRange?>(null) }
    val keyboard = LocalSoftwareKeyboardController.current
    val scroll = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    suspend fun load(older: Boolean = false, silent: Boolean = false) {
        if (busy || older && !more || api.imageCacheScope() != accountScope) return
        busy = true
        initialBusy = !silent && !older; loadingOlder = older
        try {
            if (key.isEmpty()) {
                key = extractEntities(api.request("/v6/message/list", query = mapOf("page" to "1"))).firstOrNull { messagePartner(it).uid == partner.uid }?.text("ukey", "sessionKey", "session_id").orEmpty()
                if (key.isEmpty()) { more = false; return }
            }
            val next = if (older) page + 1 else 1
            val result = parsePage(api.request("/v6/message/chat", query = mapOf("ukey" to key, "page" to "$next")), next)
            if (api.imageCacheScope() != accountScope) return
            val incoming = result.rows.filter { chatKind(it) !in setOf("hidden", "follow") }.reversed()
            if (!older) follow = result.rows.firstOrNull { chatKind(it) == "follow" }
            rows = when { older -> rows + incoming; silent -> incoming + rows; else -> incoming }.distinctBy(::chatKey)
            if (!silent) { page = next; more = result.more && incoming.isNotEmpty() }
            failures = 0; error = null
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { failures = (failures + 1).coerceAtMost(4); error = "消息读取失败，请稍后重试" }
        finally { busy = false; initialBusy = false; loadingOlder = false }
    }
    LaunchedEffect(partner.uid, initialKey, accountScope) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            load(silent = rows.isNotEmpty())
            while (isActive) { delay(10_000L * (1L shl failures)); load(silent = true) }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null && !sending) scope.launch {
        try { val path = withContext(Dispatchers.IO) { cacheDraftImage(context, uri) }; if (imagePath.isNotEmpty()) withContext(Dispatchers.IO) { File(imagePath).delete() }; imagePath = path; uploaded = "" }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "无法选择图片" }
    } }
    fun send() {
        if (sending || initialBusy || text.isBlank() && imagePath.isEmpty() || !Regex("[1-9][0-9]*").matches(partner.uid)) return
        sending = true
        scope.launch {
            try {
                check(api.imageCacheScope() == accountScope) { "账号已变更" }
                if (imagePath.isNotEmpty() && uploaded.isEmpty()) uploaded = api.uploadMessageImage(withContext(Dispatchers.IO) { prepareUploadPng(File(imagePath)) }, partner.uid)
                check(api.imageCacheScope() == accountScope) { "账号已变更" }
                api.submitMultipart("/v6/message/send", mapOf("message" to text.trim(), "message_pic" to uploaded, "message_extra" to ""), mapOf("uid" to partner.uid, "quick_reply" to "1"))
                val path = imagePath; draft = TextFieldValue(); imagePath = ""; uploaded = ""
                if (path.isNotEmpty()) withContext(Dispatchers.IO) { File(path).delete() }
                load()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("发送失败，消息和图片已保留，可重试") }
            finally { sending = false }
        }
    }
    val dark = MaterialTheme.colorScheme.background.let { it.red + it.green + it.blue < 1.5f }
    val panel = if(dark)Color(0xff1e1e1e) else Color.White
    val name = partner.name.ifEmpty { rows.firstOrNull { chatKind(it)=="message" && it.text("fromuid","fromUid")!=session.uid }?.text("fromusername","username","fromName").orEmpty().ifEmpty { "私信" } }
    Column(Modifier.fillMaxSize().background(if(dark)Color(0xff101010) else Color(0xfffafafa)).imePadding()) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).background(panel),verticalAlignment=Alignment.CenterVertically) {
            ContentIcon("arrow_back","返回",onBack,Modifier.width(56.dp))
            Spacer(Modifier.width(16.dp))
            Text(name,Modifier.weight(1f),fontSize=18.sp,fontWeight=FontWeight.Bold)
            Box {
                ContentIcon("more_vert","会话选项",{options=true})
                com.green.note.ui.ReviewPopupMenu(options,{options=false}) {
                    com.green.note.ui.ReviewPopupMenuItem(text={Text("加载更早消息")},enabled=!initialBusy&&!loadingOlder&&more,onClick={options=false;scope.launch{load(older=true)}})
                    if(partner.uid.isNotEmpty())com.green.note.ui.ReviewPopupMenuItem(text={Text("查看个人主页")},onClick={options=false;onUser(partner.uid)})
                }
            }
        }
        follow?.let { tip ->
            Row(Modifier.fillMaxWidth().background(panel).clickable(enabled=!following) {
                following=true;scope.launch {
                    try { check(api.imageCacheScope()==accountScope){"账号已改变"};api.request("/v6/user/follow","POST",mapOf("uid" to partner.uid));follow=null }
                    catch(cancelled:CancellationException){throw cancelled}
                    catch(failure:Exception){com.green.note.ui.AppToastState().showSnackbar("关注失败：${failure.message}")}
                    finally{following=false}
                }
            }.padding(horizontal=14.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
                Text(org.jsoup.Jsoup.parseBodyFragment(tip.text("title","message")).text(),Modifier.weight(1f),fontSize=14.sp,color=Color(0xff009688),textAlign=androidx.compose.ui.text.style.TextAlign.Center)
                if(following)com.green.note.ui.ReviewCircularProgress(Modifier.size(18.dp),strokeWidth=2.dp) else MaterialGlyph("chevron_right")
            }
        }
        if(error!=null&&rows.isNotEmpty())com.green.note.ui.ReviewTextButton(onClick={scope.launch{load()}}){Text(error.orEmpty())}
        if(loadingOlder)com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth().height(2.dp))
        Box(Modifier.weight(1f).fillMaxWidth(),contentAlignment=Alignment.Center) {
            if(rows.isEmpty()) {
                if(initialBusy)com.green.note.ui.ReviewCircularProgress() else Column(horizontalAlignment=Alignment.CenterHorizontally) {
                    Text(error?:"还没有消息")
                    if(error!=null)com.green.note.ui.ReviewTextButton(onClick={scope.launch{load()}},enabled=!initialBusy){Text("重试")}
                }
            } else LazyColumn(state=scroll,modifier=Modifier.fillMaxSize(),reverseLayout=true,contentPadding=PaddingValues(vertical=12.dp)) {
                items(rows,key=::chatKey){row ->
                    val kind=chatKind(row)
                    if(kind in setOf("time","notice"))Box(Modifier.fillMaxWidth().padding(horizontal=56.dp,vertical=18.dp),contentAlignment=Alignment.Center) {
                        Box(if(kind=="notice")Modifier.background(if(dark)Color(0xff262626) else Color(0xfff0f0f0),RoundedCornerShape(6.dp)).padding(8.dp) else Modifier) {
                            ContentRichText(row.text("title","message","text"),onLink=onLink,fontSize=if(kind=="time")13.sp else 12.sp,lineHeight=if(kind=="time")16.9.sp else 15.6.sp,color=Color(0xff888888),textAlign=if(kind=="time")androidx.compose.ui.text.style.TextAlign.Center else androidx.compose.ui.text.style.TextAlign.Start)
                        }
                    } else ChatBubble(api,row,session,partner.copy(name=name),onGallery,onLink)
                }
            }
        }
        if(imagePath.isNotEmpty())Row(Modifier.padding(8.dp),verticalAlignment=Alignment.CenterVertically) {
            coil.compose.AsyncImage(File(imagePath),"待发送图片",Modifier.size(72.dp));Spacer(Modifier.width(12.dp));Text("图片将在点击发送后上传",Modifier.weight(1f))
            com.green.note.ui.ReviewIconButton(onClick={val path=imagePath;imagePath="";uploaded="";scope.launch(Dispatchers.IO){File(path).delete()}},enabled=!sending){MaterialGlyph("close",contentDescription="移除待发图片")}
        }
        Row(Modifier.fillMaxWidth().background(panel).navigationBarsPadding().padding(horizontal=8.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick={emojiSelection=draft.selection;keyboard?.hide()},enabled=!sending){MaterialGlyph("sentiment_satisfied_alt_outlined",size=28.dp,contentDescription="表情")}
            BasicTextField(draft,{draft=it},Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(if(dark)Color(0xff262626) else Color(0xfff3f3f3)).padding(horizontal=12.dp,vertical=10.dp),minLines=1,maxLines=5,
                textStyle=androidx.compose.ui.text.TextStyle(localeList=com.green.note.ui.ReviewTextLocales,fontSize=17.sp,color=MaterialTheme.colorScheme.onSurface),cursorBrush=androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox={field->Box { if(text.isEmpty())Text("写私信…",fontSize=17.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);field() }})
            com.green.note.ui.ReviewIconButton(onClick={picker.launch("image/*")},enabled=!sending){MaterialGlyph("add_circle_outline_rounded",size=28.dp,contentDescription="选择图片")}
            if(text.isNotBlank()||imagePath.isNotEmpty()||uploaded.isNotEmpty())com.green.note.ui.ReviewIconButton(onClick=::send,enabled=!sending&&!initialBusy) {
                if(sending)com.green.note.ui.ReviewCircularProgress(Modifier.size(20.dp),strokeWidth=2.dp) else MaterialGlyph("send_rounded",color=Color(0xff009688),contentDescription="发送私信")
            }
        }
    }
    emojiSelection?.let { selection ->
        com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { emojiSelection = null }) {
            ContentEmojiPicker(includeUnicode = true) { token ->
                draft = draft.copy(selection = selection).insertEmoji(token)
                emojiSelection = null
            }
        }
    }
}

@Composable
private fun ChatBubble(api: ContentApi, row: JSONObject, session: ContentSession, partner: MessagePartner,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLink: (String) -> Unit) {
    val mine = session.uid.isNotEmpty() && row.text("fromuid", "fromUid", "uid") == session.uid
    val avatar = row.text("fromUserAvatar", "userAvatar").ifEmpty { row.optJSONObject("fromUserInfo")?.text("userAvatar").orEmpty() }.ifEmpty { if (mine) session.avatar else partner.avatar }
    val dark = MaterialTheme.colorScheme.background.let { it.red + it.green + it.blue < 1.5f }
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp)) {
    val bubbleWidth = chatBubbleWidth(maxWidth.value).dp
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        if (!mine) { ContentAvatar(api, avatar, partner.name.ifEmpty { "酷友" }, 44.dp); Spacer(Modifier.width(12.dp)) }
        Column(Modifier.widthIn(max=bubbleWidth).clip(RoundedCornerShape(topStart = if (mine) 18.dp else 4.dp, topEnd = if (mine) 4.dp else 18.dp, bottomStart = 18.dp, bottomEnd = 18.dp))
            .background(if (mine) Color(0xff009688) else if(dark)Color(0xff1e1e1e) else Color(0xfff1f1f1)).padding(horizontal = 14.dp, vertical = 12.dp)) {
            val picture = chatPicture(row)
            if (picture.isNotEmpty()) {
                var failed by remember(picture, api.imageCacheScope()) { mutableStateOf(false) }
                var imageRatio by remember(picture, api.imageCacheScope()) { mutableStateOf<Float?>(null) }
                if (failed) Text("图片加载失败", color = if (mine) Color.White else Color(0xff888888))
                else ContentImage(api, picture, "私信图片", Modifier.height(180.dp)
                    .then(imageRatio?.let { Modifier.width(chatImageWidth(bubbleWidth.value, it).dp) } ?: Modifier)
                    .clip(RoundedCornerShape(8.dp)).clickable { onGallery(listOf(picture), 0, null) }, androidx.compose.ui.layout.ContentScale.Fit,
                    onDecoded = { width, height -> if (width > 0 && height > 0) imageRatio = width.toFloat() / height }, onError = { failed = true })
            }
            val message = row.text("message", "content", "text")
            if (message.isNotEmpty()) { if (picture.isNotEmpty()) Spacer(Modifier.height(8.dp)); ContentRichText(message,onLink=onLink,fontSize=17.sp,lineHeight=24.65.sp,color=if(mine)Color.White else if(dark)Color(0xffcccccc) else Color(0xff222222)) }
        }
        if (mine) { Spacer(Modifier.width(12.dp)); ContentAvatar(api, avatar, session.username.ifEmpty { "我" }, 44.dp) }
    }
    }
}

internal fun chatBubbleWidth(available: Float): Float = minOf(available * .76f, (available - 56f).coerceAtLeast(0f))
internal fun chatImageWidth(bubbleWidth: Float, ratio: Float): Float = minOf(180f * ratio, (bubbleWidth - 28f).coerceAtLeast(0f))


