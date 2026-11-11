package com.green.note.settings

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.account.AccountRepository
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun WebDavBackupScreen(settings: SettingsStore, accounts: AccountRepository, validateCookie: suspend (String) -> JSONObject, onBack: () -> Unit) {
    var url by remember { mutableStateOf("") }; var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }; var directory by remember { mutableStateOf("GreenNote") }
    var includeCredentials by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }; var status by remember { mutableStateOf<String?>(null) }
    var statusTitle by remember { mutableStateOf("WebDAV 提示") }
    var restoreDialog by remember { mutableStateOf(false) }
    var restoredLocal by remember { mutableStateOf<String?>(null) }
    val account by accounts.state.collectAsState()
    var fieldErrors by remember {mutableStateOf<Map<String,String>>(emptyMap())}
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val service = remember { WebDavService() }
    val backups = remember(settings, accounts) { WebDavBackups(settings, accounts, validateCookie) }
    LaunchedEffect(settings, accounts) {
        try {
            val config = settings.readWebDavConfig(); url = config.url; username = config.username; directory = config.directory
            password = accounts.readSecret(WebDavBackups.PASSWORD_KEY).orEmpty()
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { status = "无法读取本机 WebDAV 配置，请重新填写。" }
        finally { loading = false }
    }
    fun execute(operation: String) {
        if (busy.isNotEmpty() || loading) return
        focus.clearFocus()
        status = null
        statusTitle = when (operation) { "test" -> "连接测试结果"; "backup" -> "备份结果"; else -> "恢复结果" }
        restoredLocal = null
        fieldErrors=webDavFieldErrors(url,username,password,directory)
        if(fieldErrors.isNotEmpty()) { status = fieldErrors.values.distinct().joinToString("\n"); return }
        val config = try {
            WebDavConfig(WebDavAddress.normalize(url).toString(), username.trim(), WebDavAddress.segments(directory).joinToString("/"))
        } catch (error: IllegalArgumentException) { status = error.message; return }
        busy = operation
        scope.launch {
            try {
                settings.saveWebDavConfig(config)
                accounts.writeSecret(WebDavBackups.PASSWORD_KEY, password.ifEmpty { null })
                when (operation) {
                    "test" -> { status = if (service.test(config, password)) "连接成功。" else "连接失败，请检查服务器地址、账号、密码和 WebDAV 权限。" }
                    "backup" -> {
                        status = if (service.upload(config, password, backups.export(config, includeCredentials))) {
                            if (includeCredentials) "全量备份已上传，包含账号凭据与 WebDAV 密码。" else "全量安全备份已上传，未包含 Cookie、Token 与 WebDAV 密码。"
                        } else "备份失败，请检查连接、目录权限和服务器空间。"
                    }
                    "restore" -> {
                        val data = service.download(config, password)
                        if (data == null) status = "未找到备份文件（404，已兼容检查旧版路径），请核对服务器地址和备份文件夹是否与原手机一致：\n${WebDavAddress.backupUrl(config).encodedPath}"
                        else {
                            val (restored, message) = backups.restore(data)
                            url = restored.url; username = restored.username; directory = restored.directory
                            password = accounts.readSecret(WebDavBackups.PASSWORD_KEY).orEmpty(); status = message
                            if (data.has("localAccount")) restoredLocal = accounts.state.value.localJson
                        }
                    }
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { status = error.message ?: "操作失败，请检查 WebDAV 配置。" }
            finally { busy = "" }
        }
    }
    val enabled = !loading && busy.isEmpty()
    ReviewPage("WebDAV备份", onBack, topPadding = 14.dp, bottomPadding = 14.dp) {
        SectionCard {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                MaterialGlyph("cloud_sync_outlined", color = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("备份内容", fontWeight = adjustedWeight(700), color = MaterialTheme.colorScheme.primary, fontSize = 16.sp)
                    Spacer(Modifier.height(4.dp)); Text("备份应用设置、匿名资料、关注和收藏，不含图片及视频文件。新备份会覆盖云端旧备份。", fontSize = 14.sp, lineHeight = 19.6.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        SectionCard {
            Column(Modifier.selectableGroup()) {
                listOf(false to "全量安全备份", true to "全量备份").forEach { (full, label) ->
                    val selected = includeCredentials == full
                    val choose = rememberHapticClick { if (!selected) includeCredentials = full }
                    Row(
                        Modifier.fillMaxWidth().selectable(selected, enabled = enabled, role = Role.RadioButton,
                            interactionSource = null, indication = null, onClick = choose)
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(label, style = MaterialTheme.typography.titleMedium)
                            val note = if (full) "含登录凭据及 WebDAV 密码" else "不含登录凭据及 WebDAV 密码"
                            Text(note, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                            if (full) Text("含明文凭据，请妥善保管", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        }
                        ReviewRadioButton(selected, onClick = null, enabled = enabled, shrinkWrap = true)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        SectionCard {
            Column(Modifier.padding(16.dp)) {
                Text("WebDAV 服务器配置", fontWeight = adjustedWeight(600), fontSize = 16.sp); Spacer(Modifier.height(16.dp))
                WebDavField("服务器 URL", url, { url = it }, "link_rounded", enabled, "例如: https://dav.jianguoyun.com/dav/",error=fieldErrors["url"])
                Spacer(Modifier.height(12.dp)); WebDavField("账号 / 邮箱", username, { username = it }, "person_outline_rounded", enabled,error=fieldErrors["username"])
                Spacer(Modifier.height(12.dp)); WebDavField("应用密码 / Token", password, { password = it }, "lock_outline_rounded", enabled, secret = true,error=fieldErrors["password"])
                Spacer(Modifier.height(12.dp)); WebDavField("备份文件夹名称", directory, { directory = it }, "folder_outlined", enabled,"默认: GreenNote",error=fieldErrors["directory"])
                Spacer(Modifier.height(16.dp))
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                    com.green.note.ui.ReviewOutlinedButton(enabled = enabled, onClick = { execute("test") },modifier=Modifier.fillMaxWidth(),iconPadding=true) {
                        if (busy == "test") com.green.note.ui.ReviewCircularProgress(Modifier.size(16.dp), strokeWidth = 2.dp) else MaterialGlyph("wifi_tethering_rounded", size = 18.dp)
                        Spacer(Modifier.width(8.dp)); Text(if (busy == "test") "正在测试连接..." else "测试服务器连接")
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        SectionCard {
            Column(Modifier.padding(16.dp)) {
                Text("云端备份与还原操作", fontWeight = adjustedWeight(600), fontSize = 16.sp); Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    com.green.note.ui.ReviewButton(enabled = enabled, onClick = { execute("backup") }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(vertical = 12.dp)) {
                        if (busy == "backup") com.green.note.ui.ReviewCircularProgress(Modifier.size(16.dp), strokeWidth = 2.dp,color=androidx.compose.ui.graphics.Color.White) else MaterialGlyph("cloud_upload_rounded", size = 18.dp)
                        ReviewButtonIconGap(); Text(if (busy == "backup") "正在上传..." else "立即备份到云端",Modifier.weight(1f,fill=false))
                    }
                    com.green.note.ui.ReviewFilledTonalButton(enabled = enabled, onClick = { restoreDialog = true }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(vertical = 12.dp)) {
                        if (busy == "restore") com.green.note.ui.ReviewCircularProgress(Modifier.size(16.dp), strokeWidth = 2.dp) else MaterialGlyph("cloud_download_rounded", size = 18.dp)
                        ReviewButtonIconGap(); Text(if (busy == "restore") "正在拉取..." else "从云端恢复备份",Modifier.weight(1f,fill=false))
                    }
                }
            }
        }
    }
    if (enabled) status?.let { message ->
        val canActivate = restoredLocal != null && account.localJson == restoredLocal && account.mode == com.green.note.account.AccountMode.GUEST
        ReviewAlertDialog(appDialog = true, onDismissRequest = { status = null },
            title = { Text(statusTitle) },
            text = { Text(message, Modifier.verticalScroll(rememberScrollState())
                .semantics { liveRegion = androidx.compose.ui.semantics.LiveRegionMode.Polite }) },
            confirmButton = {
                ReviewButton(onClick = {
                    status = null
                    if (canActivate) {
                        busy = "activate"
                        scope.launch {
                            try { accounts.activateAnonymous(); status = "已进入恢复的匿名账户。" }
                            catch (cancelled: CancellationException) { throw cancelled }
                            catch (_: Exception) { status = "匿名账户启用失败，已恢复的资料保留，请重试。" }
                            finally { busy = "" }
                        }
                    }
                }) { Text(if (canActivate) "使用已恢复的匿名账户" else "知道了") }
            },
            dismissButton = if (canActivate) { { ReviewTextButton(onClick = { status = null }) { Text("暂不启用") } } } else null,
        )
    }
    if (restoreDialog) com.green.note.ui.ReviewAlertDialog(appDialog=true,onDismissRequest = { restoreDialog = false }, title = { Text("恢复 WebDAV 备份？") },
        text = { Text("将恢复设置、匿名资料和备份中记录的匿名登录状态，原匿名资料会留存。全量备份还会恢复 WebDAV 密码，账号凭据验证通过后才会恢复账号登录。") },
        confirmButton = { com.green.note.ui.ReviewButton(onClick = { restoreDialog = false; execute("restore") }) { Text("恢复设置") } },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { restoreDialog = false }) { Text("取消") } })
}

@Composable
private fun WebDavField(label: String, value: String, onValue: (String) -> Unit, icon: String, enabled: Boolean, hint: String? = null, secret: Boolean = false,error:String?=null) {
    WebDavOutlineField(label,value,onValue,icon,enabled,hint,secret,error)
}

internal fun webDavFieldErrors(url:String,username:String,password:String,directory:String):Map<String,String> = buildMap {
    try {WebDavAddress.normalize(url)}catch(_:IllegalArgumentException){put("url","请输入 HTTPS 地址（本机回环可使用 HTTP）")}
    if(username.trim().isEmpty())put("username","请输入账号")
    if(password.trim().isEmpty())put("password","请输入密码或授权 Token")
    try {WebDavAddress.segments(directory)}catch(error:IllegalArgumentException){put("directory",error.message?:"备份文件夹名称无效")}
}
