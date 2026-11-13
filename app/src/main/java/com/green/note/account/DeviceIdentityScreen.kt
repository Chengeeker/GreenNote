package com.green.note.account

import com.green.note.ui.ReviewText as Text

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.green.note.network.OfficialDeviceIdentity
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewPage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DeviceIdentityScreen(deviceCode: String, importIdentity: suspend (String) -> Unit, restoreIdentity: suspend () -> Unit, onBack: () -> Unit,
    onImported: (() -> Unit)? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var restore by remember { mutableStateOf(false) }
    var guide by remember { mutableStateOf(false) }
    val imported = OfficialDeviceIdentity.fields(deviceCode) != null
    fun recognize(value: String) {
        try { pending = OfficialDeviceIdentity.parse(value); text = ""; status = "已识别数盟 ID，点击“保存并应用”生效"; failed = false }
        catch (failure: Exception) { pending = null; failed = true; status = failure.message }
    }
    BackHandler(busy || guide) { if (guide) guide = false }
    if (guide) {
        ReviewPage("设备标识导入教程", { guide = false }, topPadding = 16.dp, contentHorizontalPadding = 20.dp, bottomPadding = 20.dp) {
            Column(Modifier.widthIn(max = 560.dp).align(Alignment.CenterHorizontally)) {
                SelectionContainer {
                    Column {
                        Text("操作说明已保存在应用内，可离线阅读。")
                        deviceGuideSections.forEach { (title, body) ->
                            Spacer(Modifier.height(24.dp)); Text(title, style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.height(8.dp)); Text(body)
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
                com.green.note.ui.ReviewButton(onClick = { guide = false }, modifier = Modifier.fillMaxWidth()) { Text("返回导入页") }
            }
        }
        return
    }
    ReviewPage("导入官方设备标识", { if (!busy) onBack() }, topPadding = 16.dp, contentHorizontalPadding = 20.dp, bottomPadding = 20.dp) {
        Column(Modifier.widthIn(max = 560.dp).align(Alignment.CenterHorizontally)) {
            Text(if (imported) "当前已使用导入的设备标识" else "当前使用本机原设备码", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(12.dp))
            Text("可尝试改善反复人机验证的情况，有效期与验证要求仍由酷安服务端决定。此功能不代替账号登录。")
            Spacer(Modifier.height(16.dp))
            Text("1. 打开官方酷安的“检查日志和测试”页。\n2. 在同一页面累计点击“复制 OAID”5次。\n3. 返回此处粘贴完整内容，识别后保存。")
            Spacer(Modifier.height(12.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { com.green.note.ui.ReviewOutlinedButton(iconPadding = true, onClick = {
                try {
                    context.packageManager.getApplicationInfo("com.coolapk.market", 0)
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("coolmarket://www.coolapk.com/native/testSettings")).setPackage("com.coolapk.market"))
                } catch (_: PackageManager.NameNotFoundException) { status = "请先安装官方酷安，再打开其“检查日志和测试”页面"; failed = true }
                catch (_: Exception) { status = "无法打开官方页面，请在官方酷安中手动进入"; failed = true }
            }, enabled = !busy) { MaterialGlyph("open_in_new"); com.green.note.ui.ReviewButtonIconGap(); Text("打开酷安 OAID 界面") }
            com.green.note.ui.ReviewTextButton(onClick = { guide = true }, enabled = !busy) { Text("查看操作教程") }
            }
            Spacer(Modifier.height(16.dp))
            Text("实际使用的是 ShuzlmID（数盟 ID），不是 OAID、AndroidID 或 UUID。仅保存所需设备编码，其余复制字段会丢弃；不会后台读取剪贴板，不会加入 WebDAV 备份。")
            Spacer(Modifier.height(16.dp))
            PrivateTextInput { AccountTextField(text, { text = it; pending = null; status = null }, Modifier.fillMaxWidth(), enabled = !busy, singleLine = false, minLines = 3, maxLines = 5,
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false),
                label = "官方复制内容", placeholder = "粘贴包含 ShuzlmID 的完整文本") }
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = {
                    try {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val copied = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                        if (copied.isNullOrBlank()) { status = "剪贴板没有文本，请先在官方酷安完成复制"; failed = true } else recognize(copied)
                    } catch (_: Exception) { status = "无法读取剪贴板，请在下方输入框长按粘贴后识别"; failed = true }
                }, enabled = !busy) { MaterialGlyph("content_paste"); com.green.note.ui.ReviewButtonIconGap(); Text("粘贴并识别") }
                com.green.note.ui.ReviewTextButton(onClick = { recognize(text) }, enabled = !busy) { Text("识别输入内容") }
            }
            status?.let { Text(it, Modifier.padding(vertical = 12.dp), color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface) }
            if (busy) com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            com.green.note.ui.ReviewButton(enabled = !busy && pending != null, modifier = Modifier.fillMaxWidth(), onClick = { scope.launch {
                val id = pending ?: return@launch
                busy = true
                var saved = false
                try {
                    importIdentity("ShuzlmID: $id")
                    currentCoroutineContext().ensureActive()
                    pending = null; text = ""; failed = false; saved = true
                    status = if (onImported == null) "已保存并用于后续请求，请返回内容页刷新" else "已保存，正在返回评论"
                }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { status = "保存失败，设备标识未应用，请重试"; failed = true }
                finally { busy = false }
                if (saved) onImported?.invoke()
            } }) { Text("保存并应用") }
            if (imported && onImported == null) com.green.note.ui.ReviewTextButton(onClick = { restore = true }, enabled = !busy) { Text("恢复原设备码") }
        }
    }
    if (restore) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { restore = false }, title = { Text("恢复原设备码？") },
        text = { Text("将移除导入的设备标识，恢复本机原先的设备码。账号登录、匿名资料和收藏会保留。") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { restore = false }) { Text("取消") } }, confirmButton = {
            com.green.note.ui.ReviewButton(onClick = { restore = false; scope.launch {
                busy = true
                try { restoreIdentity(); pending = null; text = ""; status = "已恢复原设备码，请返回内容页刷新"; failed = false }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { status = "恢复失败，原有配置保持不变，请重试"; failed = true }
                finally { busy = false }
            } }) { Text("恢复") }
        })
}
