package com.green.note.content

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.MainActivity
import com.green.note.media.StoreDownloadSource
import com.green.note.media.StoreDownloads
import com.green.note.media.checkedStoreUrl
import com.green.note.media.downloadManagerIntent
import com.green.note.network.ApiException
import com.green.note.ui.AppToastState
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewButton
import com.green.note.ui.ReviewButtonIconGap
import com.green.note.ui.ReviewLinearProgress
import com.green.note.ui.ReviewModalBottomSheet
import com.green.note.ui.ReviewText as Text
import com.green.note.ui.ReviewTextButton
import com.green.note.ui.tapClickable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

private enum class DownloadChoice { INTERNAL, EXTERNAL, SHARE }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun NativeAppDownload(api: ContentApi, data: JSONObject, modifier: Modifier = Modifier, compact: Boolean = false) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val source = StoreDownloadSource(data.text("apkname", "packageName", "package_name", "apk_name", "pn"),
        data.text("id", "apkId", "aid"), data.text("apkversioncode", "versionCode", "vc"))
    val name = data.text("title", "cardTitle", "name").ifBlank { source.packageName.ifBlank { "应用" } }
    fun choose(choice: DownloadChoice) {
        if (busy) return
        busy = true
        error = null
        scope.launch {
            try {
                val owner = api.imageCacheScope()
                val raw = data.text("downloadUrl", "download_url", "apkDownloadUrl", "apk_download_url", "url")
                val direct = runCatching { checkedStoreUrl(raw) }.getOrNull()
                val url = direct ?: checkedStoreUrl(source.resolve(api))
                check(owner == api.imageCacheScope()) { "账号已变更，请重新下载" }
                when (choice) {
                    DownloadChoice.INTERNAL -> {
                        val downloads = withContext(Dispatchers.IO) { StoreDownloads.get(context) }
                        downloads.enqueue(url.toString(), name, source)
                        AppToastState().showSnackbar("可在「下载管理」查看任务")
                    }
                    DownloadChoice.EXTERNAL -> {
                        val target = Intent(Intent.ACTION_VIEW, Uri.parse(url.toString()))
                        val ownActivity = ComponentName(context, MainActivity::class.java)
                        if (context.packageManager.queryIntentActivities(target, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                                .none { it.activityInfo.packageName != context.packageName }) {
                            throw ActivityNotFoundException()
                        }
                        context.startActivity(Intent.createChooser(target, "用其他应用打开")
                            .putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(ownActivity)))
                    }
                    DownloadChoice.SHARE -> {
                        val share = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, url.toString())
                        context.startActivity(Intent.createChooser(share, "分享下载链接"))
                    }
                }
                open = false
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: ActivityNotFoundException) {
                error = "没有可用的应用，请选择应用内下载"
            } catch (failure: ApiException) {
                error = failure.message ?: "暂时无法获取下载地址，请重试"
            } catch (failure: IllegalStateException) {
                error = failure.message ?: "暂时无法开始下载，请重试"
            } catch (failure: IllegalArgumentException) {
                error = failure.message ?: "暂时无法获取下载地址，请重试"
            } catch (_: Exception) {
                error = "暂时无法获取下载地址，请重试"
            } finally {
                busy = false
            }
        }
    }
    fun show() { error = null; open = true }
    if (compact) {
        ReviewButton(onClick = ::show, modifier = modifier.widthIn(min = 56.dp).heightIn(min = 30.dp),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xff009688), contentColor = Color.White)) {
            Text("下载", fontSize = 13.sp)
        }
    } else {
        ReviewButton(iconPadding = true, onClick = ::show, modifier = modifier) {
            MaterialGlyph("download_rounded")
            ReviewButtonIconGap()
            Text("下载应用")
        }
    }
    if (!open) return
    ReviewModalBottomSheet(onDismissRequest = { if (!busy) open = false }, sheetMaxWidth = 560.dp,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 16.dp)) {
            Text("下载应用", style = MaterialTheme.typography.headlineSmall)
            Text(name, Modifier.padding(top = 4.dp), color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(20.dp))
            DownloadOption("download_rounded", "应用内下载", "后台下载，支持暂停和继续", !busy, primary = true) {
                choose(DownloadChoice.INTERNAL)
            }
            Spacer(Modifier.height(8.dp))
            DownloadOption("open_in_new_rounded", "用其他应用打开", "选择浏览器或支持此链接的下载器", !busy) {
                choose(DownloadChoice.EXTERNAL)
            }
            if (busy) {
                Text("正在获取下载地址…", Modifier.padding(top = 12.dp).semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.bodySmall)
                ReviewLinearProgress(Modifier.fillMaxWidth().padding(top = 8.dp))
            }
            error?.let {
                Text(it, Modifier.padding(top = 12.dp).semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
            }
            FlowRow(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                ReviewTextButton(onClick = { choose(DownloadChoice.SHARE) }, enabled = !busy) { Text("分享下载链接") }
                ReviewTextButton(onClick = { open = false; context.startActivity(downloadManagerIntent(context)) },
                    enabled = !busy) { Text("下载管理") }
            }
        }
    }
}

@Composable
private fun DownloadOption(
    glyph: String,
    title: String,
    subtitle: String,
    enabled: Boolean,
    primary: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    val container = if (primary) colors.primaryContainer else colors.surfaceContainerHigh
    val foreground = if (primary) colors.onPrimaryContainer else colors.onSurface
    Surface(color = container, contentColor = foreground, shape = RoundedCornerShape(20.dp)) {
        Row(Modifier.fillMaxWidth().tapClickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            MaterialGlyph(glyph, color = foreground, size = 24.dp)
            Column(Modifier.weight(1f).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = foreground, style = MaterialTheme.typography.titleMedium)
                Text(subtitle, color = if (primary) foreground else colors.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium)
            }
            MaterialGlyph("chevron_right", color = foreground, size = 20.dp)
        }
    }
}
