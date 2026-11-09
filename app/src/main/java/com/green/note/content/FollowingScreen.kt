package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun relationUser(row: JSONObject, fans: Boolean): JSONObject {
    val nested = if (fans) row.optJSONObject("userInfo") else row.optJSONObject("fUserInfo") ?: row.optJSONObject("userInfo")
    return JSONObject(row.toString()).apply {
        nested?.keys()?.forEach { key -> put(key, nested.opt(key)) }
        put("uid", nested?.text("uid").orEmpty().ifEmpty { if (fans) row.text("uid") else row.text("fuid", "uid") })
        put("username", nested?.text("username", "displayUsername", "displayUserName").orEmpty().ifEmpty { if (fans) row.text("username") else row.text("fusername", "username") })
        put("userAvatar", nested?.text("userAvatar", "avatar").orEmpty().ifEmpty { if (fans) row.text("userAvatar") else row.text("fUserAvatar", "userAvatar") })
    }
}
internal fun relationQuery(uid: String, tab: Int): Map<String, String> = mapOf("uid" to uid) + when (tab) {
    0 -> mapOf("isSpecialFollow" to "-1", "isFriend" to "0")
    1 -> mapOf("isSpecialFollow" to "1")
    2 -> mapOf("isFriend" to "1")
    else -> emptyMap()
}

@Composable
internal fun FollowingScreen(api: ContentApi, uid: String, initialTab: Int, onBack: () -> Unit, onUser: (String) -> Unit, onChat: (MessagePartner) -> Unit) {
    var tab by rememberSaveable(uid) { mutableIntStateOf(initialTab.coerceIn(0, 3)) }
    var revision by remember { mutableIntStateOf(0) }
    var confirm by remember { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    val session = LocalContentSession.current
    val toast = remember { com.green.note.ui.AppToastState() }
    val scope = rememberCoroutineScope()
    val owner = remember { api.imageCacheScope() }
    val repo = remember(api) { ContentRepository(api) }
    val state = remember(api, uid, tab, revision) { ContentListState { page, first, last -> repo.page(ContentRequest(if (tab == 3) "/v6/user/fansList" else "/v6/user/followList", relationQuery(uid, tab)), page, first, last) } }
    val scheme = MaterialTheme.colorScheme
    val dark=scheme.background.let{it.red+it.green+it.blue<1.5f}
    com.green.note.ui.OfficialHomeTheme {
    Column(Modifier.fillMaxSize().background(if(dark)Color(0xff1e1e1e) else scheme.background)) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp),verticalAlignment=Alignment.CenterVertically){
            ContentIcon("arrow_back","返回",onBack,Modifier.width(56.dp));Spacer(Modifier.width(16.dp))
            Text("酷友列表", style = if (dark) MaterialTheme.typography.titleLarge else androidx.compose.ui.text.TextStyle(
                localeList = com.green.note.ui.ReviewTextLocales, fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700),
                platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)))
        }
        val wide=LocalDensity.current.fontScale*16>20
        Row(Modifier.height(48.dp).then(if(wide)Modifier.horizontalScroll(rememberScrollState()) else Modifier.fillMaxWidth())) {
            listOf("关注", "特别关注", "互相关注", "粉丝").forEachIndexed{index,label->
                Box((if(wide)Modifier else Modifier.weight(1f)).fillMaxHeight().clickable{tab=index}.padding(horizontal=8.dp),contentAlignment=Alignment.Center){
                    Column(Modifier.width(IntrinsicSize.Max).fillMaxHeight(),horizontalAlignment=Alignment.CenterHorizontally){
                        Box(Modifier.weight(1f),contentAlignment=Alignment.Center){Text(label,fontSize=16.sp,fontWeight=com.green.note.ui.adjustedWeight(if(tab==index)600 else 400),color=if(tab==index)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)}
                        Box(Modifier.fillMaxWidth().padding(horizontal=12.dp).height(3.dp).background(if(tab==index)Color(0xff009688) else Color.Transparent))
                    }
                }
            }
        }
        ContentList(api, state, {}, onUser, {}, { _, _, _ -> }, {}, {}, itemContent = { raw ->
            val user = relationUser(raw, tab == 3)
            val target = user.text("uid")
            var menu by remember { mutableStateOf(false) }
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, end = 8.dp, bottom = 12.dp), verticalAlignment = Alignment.Top) {
                Box(Modifier.size(44.dp)) {
                    ContentAvatar(api, user.text("userAvatar"), "", 44.dp) { if(target.isNotEmpty())onUser(target) }
                    if(user.text("verify_status") in setOf("1","true"))Box(Modifier.align(Alignment.BottomEnd).size(15.4.dp).background(if(user.optInt("verify_show_type")==0)Color(0xffffc107) else Color(0xff448aff),CircleShape).border(1.5.dp,MaterialTheme.colorScheme.surface,CircleShape),contentAlignment=Alignment.Center){com.green.note.ui.MaterialGlyph("check_rounded",size=11.dp,color=Color.White)}
                }
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f).clickable { onUser(target) }) {
                    Text(user.text("username"), style = MaterialTheme.typography.titleMedium, fontSize = 17.sp, fontWeight=com.green.note.ui.adjustedWeight(600), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(6.dp))
                    val active = user.text("lastlogin_text", "lastLoginText", "activeTime", "active_time_text").ifEmpty { relativeTime(user.text("lastlogin", "lastLogin", "logintime")).let { if (it.isNotEmpty()) "${it}活跃" else "" } }
                    Text(listOf(user.text("follow", "follow_num").takeIf(String::isNotEmpty)?.let { "${it}关注" }, user.text("fans", "fans_num").takeIf(String::isNotEmpty)?.let { "${it}粉丝" }, active).filterNotNull().filter(String::isNotEmpty).joinToString("  "), fontSize = 13.sp, maxLines = 2, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    user.text("bio", "signature", "description").takeIf(String::isNotEmpty)?.let { Spacer(Modifier.height(7.dp)); Text(it, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                Spacer(Modifier.width(6.dp))
                com.green.note.ui.ReviewOutlinedButton(onClick = { if (session.authenticated && owner==api.imageCacheScope()) onChat(MessagePartner(target, user.text("username"), user.text("userAvatar"))) else toast.showSnackbar("请先使用酷安账号登录") }, enabled=target.isNotEmpty(), modifier=Modifier.defaultMinSize(minWidth=64.dp,minHeight=30.dp),border=BorderStroke(1.dp,MaterialTheme.colorScheme.primary),colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.primary), contentPadding = PaddingValues(horizontal = 12.dp)) { Text("私信", fontSize = 14.sp) }
                if (uid == session.uid && session.authenticated && tab != 3) Box {
                    ContentIcon("more_horiz", "更多关注操作", { menu = true })
                    com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) {
                        val special = user.text("isSpecialFollow") in setOf("1", "true")
                        com.green.note.ui.ReviewPopupMenuItem(text = { Text(if (special) "取消特别关注" else "设为特别关注") }, enabled = !busy, onClick = { menu = false; busy = true; scope.launch { try {
                            check(owner == api.imageCacheScope()) { "账号已变更" }; api.request("/v6/user/specialFollowUser", "POST", mapOf("uid" to target, "special" to if (special) "0" else "1")); revision++
                        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } finally { busy = false } } })
                        com.green.note.ui.ReviewPopupMenuItem(text = { Text("取消关注") }, enabled = !busy, onClick = { menu = false; confirm = user })
                    }
                }
            }
        })
    }
    }
    confirm?.let { user -> com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { confirm = null }, title = { Text("取消关注？") }, text = { Text("将不再关注这位酷友。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirm = null }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
        confirm = null; busy = true; scope.launch { try { check(owner == api.imageCacheScope()) { "账号已变更" }; api.followUser(user, true); revision++ } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } finally { busy = false } }
    }) { Text("确认") } }) }
}

