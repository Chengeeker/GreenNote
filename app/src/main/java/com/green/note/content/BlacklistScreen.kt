package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BlacklistScreen(api: ContentApi, session: ContentSession, onBack: () -> Unit, onUser: (String) -> Unit) {
    val labels = listOf("黑名单管理", "屏蔽管理", "限制名单")
    val routes = listOf("/v6/user/blackList", "/v6/user/ignoreList", "/v6/user/limitList")
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var menu by remember { mutableStateOf(false) }
    var total by remember(tab) { mutableStateOf<Int?>(null) }
    var removal by remember { mutableStateOf<String?>(null) }
    var removing by remember { mutableStateOf(emptySet<String>()) }
    val toast=remember{com.green.note.ui.AppToastState()}
    val scope = rememberCoroutineScope()
    val identity = remember{api.imageCacheScope()}
    val state = remember(api, tab, identity) { ContentListState { page, _, _ ->
        val result = api.request(routes[tab], query = mapOf("uid" to session.uid, "page" to "$page"))
        (result.opt("total") ?: result.optJSONObject("data")?.opt("total"))?.toString()?.toIntOrNull()?.let { total = it }
        parsePage(result, page)
    } }
    val scheme=MaterialTheme.colorScheme
    val dark=scheme.background.let{it.red+it.green+it.blue<1.5f}
    val panel=if(dark)Color(0xff1e1e1e) else scheme.surface
    com.green.note.ui.OfficialHomeTheme {
    Column(Modifier.fillMaxSize().background(if(dark)Color(0xff101010) else scheme.background)) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).background(panel), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp))
            Spacer(Modifier.width(16.dp))
            val count = total?.toString() ?: "${state.rows.size}${if (state.more) "+" else ""}"
            val title = "${labels[tab]} ($count${if (tab == 0) "/500" else ""})"
            val measurer = androidx.compose.ui.text.rememberTextMeasurer()
            val style = if (dark) MaterialTheme.typography.titleLarge else androidx.compose.ui.text.TextStyle(
                localeList = com.green.note.ui.ReviewTextLocales, fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700),
                platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false))
            BoxWithConstraints(Modifier.weight(1f)) {
                val naturalWidth = measurer.measure(title, style, softWrap = false).size.width
                val width = with(androidx.compose.ui.platform.LocalDensity.current) { maxWidth.toPx() }
                Text(title, style = style.copy(fontSize = style.fontSize * (width / naturalWidth.coerceAtLeast(1)).coerceAtMost(1f)), maxLines = 1)
            }
            Box { ContentIcon("more_vert_rounded", "切换名单", { menu = true }); com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) { labels.forEachIndexed { index, label -> com.green.note.ui.ReviewPopupMenuItem(text = { Text(label) }, onClick = { menu = false; tab = index }) } } }
        }
        ContentList(api, state, {}, onUser, {}, { _, _, _ -> }, {}, {},
            modifier = Modifier.fillMaxSize().padding(start = 8.dp, end = 8.dp, top = 8.dp).clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp)).background(panel),
            itemContent = { row ->
                    val info = row.optJSONObject("userInfo")
                    val uid = row.text("uid", "id")
                    val name = row.text("username", "title").ifEmpty { info?.text("username").orEmpty() }
                    val avatar = row.text("userAvatar", "avatar").ifEmpty { info?.text("userAvatar").orEmpty() }
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        ContentAvatar(api, avatar, name, 44.dp) { onUser(uid) }
                        Spacer(Modifier.width(18.dp)); Text(name, Modifier.weight(1f).clickable { onUser(uid) }, fontSize = 17.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (tab < 2) { Spacer(Modifier.width(12.dp)); com.green.note.ui.ReviewOutlinedButton(onClick = { removal = uid }, enabled = uid !in removing, contentPadding = PaddingValues(horizontal = 14.dp), modifier = Modifier.height(32.dp).widthIn(min=60.dp),border=androidx.compose.foundation.BorderStroke(1.dp,Color(0xff009688)), colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xff009688))) { Text(if(uid in removing) "处理中" else "取消") } }
                    }
            })
    }
    }
    removal?.let { uid -> com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { removal = null }, title = { Text("移出名单？") }, text = { Text("将解除对该用户的${if (tab == 0) "拉黑" else "屏蔽"}。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { removal = null }) { Text("取消") } }, confirmButton = {
        com.green.note.ui.ReviewButton(onClick = { removal = null; removing = removing + uid
            scope.launch { try {
                check(identity == api.imageCacheScope()) { "账号已变更" }
                api.request(if (tab == 0) "/v6/user/removeFromBlackList" else "/v6/user/removeFromIgnoreList", query = mapOf("uid" to uid))
                state.load(true)
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { toast.showSnackbar("操作失败，请确认登录有效、网络正常后重试") } finally { removing = removing - uid } }
        }) { Text("确认") }
    }) }
}

