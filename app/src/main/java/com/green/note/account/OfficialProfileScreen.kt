package com.green.note.account

import com.green.note.ui.ReviewText as Text

import com.green.note.content.communityTextLimit

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import com.green.note.content.ContentApi
import com.green.note.content.ContentAvatar
import com.green.note.ui.LocalScaffoldColor
import com.green.note.ui.ReviewScrollActivity
import com.green.note.ui.adjustedWeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewPage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import okio.ByteString.Companion.decodeBase64
import org.json.JSONObject

@Composable
fun OfficialProfileScreen(repository: AccountRepository,
                          request: suspend (String, String, Map<String, String>, Map<String, String>?) -> JSONObject,
                          uploadAvatar: suspend (ByteArray) -> Unit, onBack: () -> Unit, imageApi: ContentApi) {
    val state by repository.state.collectAsState()
    val expectedCookie = remember { state.requestCookie }
    val expectedUid = remember { state.uid }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var data by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf<String?>(null) }
    val busy = working != null
    var edit by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    var savedDraft by remember { mutableStateOf<String?>(null) }
    var invalidDraft by remember { mutableStateOf(false) }
    var pendingAvatar by remember { mutableStateOf<ByteArray?>(null) }
    fun checkSession() { check(repository.state.value.authenticated && repository.state.value.requestCookie == expectedCookie && repository.state.value.uid == expectedUid) { "账号已变更，请重新打开页面" } }
    suspend fun load() {
        try {
            checkSession()
            val root = request("/v6/user/profile", "GET", mapOf("uid" to expectedUid), null)
            checkSession()
            val body = root.optJSONObject("data") ?: root
            data = body.optJSONObject("userInfo") ?: body
            repository.refreshOfficialProfile(data!!, expectedCookie, expectedUid)
            error = null
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "读取个人资料失败，点击重试" }
    }
    fun action(key: String, operation: suspend () -> Unit) { scope.launch {
        if (busy) return@launch
        working = key
        try { checkSession(); operation(); load() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("操作失败，请确认登录有效、网络正常后重试") }
        finally { working = null }
    } }
    LaunchedEffect(Unit) { if (state.authenticated) load() }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) scope.launch {
            try { pendingAvatar = readAvatar(context, uri).decodeBase64()?.toByteArray() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("无法读取头像，请选择其他图片") }
        }
    }
    val scroll = rememberScrollState()
    ReviewScrollActivity(scroll)
    Column(Modifier.fillMaxSize().background(LocalScaffoldColor.current).statusBarsPadding()) {
        val toolbarBorder=MaterialTheme.colorScheme.outlineVariant.copy(alpha=.24f)
        com.green.note.ui.ReviewToolbarIcons() { Row(Modifier.fillMaxWidth().height(52.dp).drawWithContent { drawContent(); val stroke=.5.dp.toPx(); drawRect(toolbarBorder, topLeft=androidx.compose.ui.geometry.Offset(0f,size.height-stroke), size=androidx.compose.ui.geometry.Size(size.width,stroke)) }, verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", contentDescription = "返回") }
            Spacer(Modifier.width(16.dp))
            Text("酷安个人资料", fontSize = 18.sp, fontWeight = adjustedWeight(700))
        } }
        Box(Modifier.weight(1f).fillMaxWidth().navigationBarsPadding(), contentAlignment = Alignment.Center) {
            when {
                !state.authenticated -> Text("请先使用酷安账号登录")
                data == null -> if (error == null) com.green.note.ui.ReviewCircularProgress() else com.green.note.ui.ReviewTextButton(onClick = { scope.launch { load() } }) { Text(error.orEmpty()) }
                else -> Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(16.dp)) {
                    val profile = data!!
                    val avatar = profile.optString("userAvatar").ifBlank { profile.optString("avatar") }
                    val bio = profile.optString("bio").ifBlank { profile.optString("intro") }
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { ContentAvatar(imageApi, avatar, "", 96.dp) }
                    Spacer(Modifier.height(16.dp))
                    com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { picker.launch("image/*") }, enabled = !busy, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                        MaterialGlyph(if (working == "avatar") "hourglass_empty" else "photo_outlined"); com.green.note.ui.ReviewButtonIconGap(); Text(if (working == "avatar") "处理中…" else "更换头像")
                    }
                    listOf("昵称" to profile.optString("username"), "UID" to expectedUid, "个性签名" to bio).forEach { (label, value) ->
                        com.green.note.ui.ReviewTileLayout(horizontalPadding = 14.dp,
                            subtitle = { Text(value, fontSize = 12.sp, lineHeight = 1.4.em, fontWeight = adjustedWeight(400), color = MaterialTheme.colorScheme.onSurfaceVariant) }) {
                            Text(label, fontSize = 13.sp, lineHeight = 1.35.em, fontWeight = adjustedWeight(600), color = MaterialTheme.colorScheme.onSurface)
                        }
                    }
                    com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { draft = savedDraft ?: bio; invalidDraft = false; edit = true }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                        MaterialGlyph(if (working == "bio") "hourglass_empty" else "edit_outlined"); com.green.note.ui.ReviewButtonIconGap(); Text(if (working == "bio") "处理中…" else "修改签名")
                    }
                    Spacer(Modifier.height(16.dp))
                    Text("性别：${when (profile.optString("gender")) { "1" -> "男"; "0" -> "女"; else -> "未设置" }}")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        mapOf("1" to "男", "0" to "女").forEach { (value, label) ->
                            com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { action("gender$value") { request("/v6/account/changeProfile", "POST", emptyMap(), mapOf("key" to "gender", "value" to value)) } }, enabled = !busy) {
                                MaterialGlyph(if (working == "gender$value") "hourglass_empty" else "person_outline"); com.green.note.ui.ReviewButtonIconGap(); Text(if (working == "gender$value") "处理中…" else "设为$label")
                            }
                        }
                    }
                    Spacer(Modifier.height(24.dp))
                    Text("修改直接保存到酷安官方账号，不影响本机匿名资料。")
                    error?.let { com.green.note.ui.ReviewTextButton(onClick = { scope.launch { load() } }) { Text(it) } }
                }
            }
        }
    }
    if (edit) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { if (!busy) edit = false }, title = { Text("修改签名") }, text = {
        AccountTextField(draft, { draft = communityTextLimit(it, 60).text; invalidDraft = false }, Modifier.padding(bottom = 12.dp), label = "内容", outlined = false, singleLine = false, minLines = 5, maxLines = 5, isError = invalidDraft,
            supportingText = { Row(Modifier.fillMaxWidth()) { if (invalidDraft) Text("请填写内容"); Spacer(Modifier.weight(1f)); Text("${communityTextLimit(draft, Int.MAX_VALUE).characters}/60") } })
    }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { edit = false }, enabled = !busy) { Text("取消") } }, confirmButton = {
        com.green.note.ui.ReviewButton(enabled = !busy, onClick = { if (draft.isBlank()) invalidDraft = true else { savedDraft = draft.trim(); edit = false; action("bio") {
            request("/v6/account/changeProfile", "POST", emptyMap(), mapOf("key" to "bio", "value" to savedDraft.orEmpty()))
            savedDraft = null; draft = ""
        } } }) { Text("确认") }
    })
    pendingAvatar?.let { bytes -> com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { if (!busy) pendingAvatar = null }, title = { Text("更换官方账号头像？") },
        text = { Text("所选图片将上传到酷安并替换你的账号头像。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { pendingAvatar = null }, enabled = !busy) { Text("取消") } },
        confirmButton = { com.green.note.ui.ReviewButton(onClick = { action("avatar") { uploadAvatar(bytes); pendingAvatar = null } }, enabled = !busy) { Text("确认") } }) }
}
