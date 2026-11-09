package com.green.note.media

import android.app.DownloadManager
import android.text.format.Formatter
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.green.note.content.ContentApi
import com.green.note.network.ApiException
import com.green.note.ui.*
import com.green.note.ui.ReviewText as Text
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val USER_PAUSED = 32
private const val QUEUED = DownloadManager.STATUS_PENDING
private const val RUNNING = DownloadManager.STATUS_RUNNING
private const val SYSTEM_PAUSED = DownloadManager.STATUS_PAUSED
private const val COMPLETE = DownloadManager.STATUS_SUCCESSFUL
private const val FAILED = DownloadManager.STATUS_FAILED

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun DownloadScreen(api: ContentApi, onBack: () -> Unit, packages: Boolean = false, showAppBar: Boolean = true, active: Boolean = true) {
    val context = LocalContext.current
    val legacy = remember(context) { AppDownloads(context) }
    val scope = rememberCoroutineScope()
    val scroll = rememberLazyListState()
    ReviewScrollActivity(scroll)
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val visible = active && lifecycle.isAtLeast(Lifecycle.State.RESUMED)
    var store by remember { mutableStateOf<StoreDownloads?>(null) }
    var storeTasks by remember { mutableStateOf(emptyList<StoreDownload>()) }
    var legacyRows by remember { mutableStateOf<List<DownloadItem>?>(null) }
    var error by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    var filter by rememberSaveable { mutableIntStateOf(0) }
    var remove by remember { mutableStateOf<DownloadItem?>(null) }
    val working = remember { mutableStateMapOf<String, Boolean>() }

    suspend fun load() {
        if (loading) return
        loading = true
        try {
            legacyRows = if (packages) legacy.packages() else legacy.list()
            error = false
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            error = true
        } finally {
            loading = false
        }
    }

    LaunchedEffect(visible) {
        if (!visible) return@LaunchedEffect
        val downloads = withContext(Dispatchers.IO) { StoreDownloads.get(context) }
        store = downloads
        downloads.tasks.collect { tasks ->
            storeTasks = if (packages) tasks.filter { it.state == StoreDownloadState.COMPLETE } else tasks
        }
    }
    LaunchedEffect(visible, packages) {
        if (!visible) return@LaunchedEffect
        load()
        while (!packages) {
            delay(3000)
            if (legacyRows.orEmpty().any { !it.ended }) load()
        }
    }

    fun action(item: DownloadItem, operation: suspend () -> Unit) {
        if (working.put(item.key, true) == true) return
        scope.launch {
            try {
                operation()
                if (item.storeId.isEmpty()) load()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: ApiException) {
                AppToastState().showSnackbar(failure.message ?: "无法获取下载地址，请重试")
            } catch (failure: IllegalStateException) {
                AppToastState().showSnackbar(failure.message ?: "操作失败，请重试")
            } catch (_: Exception) {
                AppToastState().showSnackbar("操作失败，请重试")
            } finally {
                working.remove(item.key)
            }
        }
    }

    val rows = remember(store, storeTasks, legacyRows, packages, filter) {
        val downloads = store
        val internal = if (downloads == null) emptyList() else storeTasks.map { task ->
            DownloadItem(0, task.name, when (task.state) {
                StoreDownloadState.QUEUED -> QUEUED
                StoreDownloadState.DOWNLOADING -> RUNNING
                StoreDownloadState.PAUSED -> USER_PAUSED
                StoreDownloadState.COMPLETE -> COMPLETE
                StoreDownloadState.FAILED -> FAILED
            }, task.bytes, task.total, path = if (task.state == StoreDownloadState.COMPLETE) downloads.apk(task.id).path else "",
                version = task.version, storeId = task.id, speed = task.speed, error = task.error)
        }
        (internal + legacyRows.orEmpty()).filter { packages || filter == 0 || if (filter == 1) !it.ended else it.ended }
    }
    Column(Modifier.fillMaxSize().then(if (showAppBar) Modifier.statusBarsPadding().navigationBarsPadding() else Modifier)) {
        if (showAppBar) {
            ReviewToolbarIcons {
                Row(Modifier.fillMaxWidth().heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
                    ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) {
                        MaterialGlyph("arrow_back", contentDescription = "返回")
                    }
                    Text(if (packages) "安装包" else "下载管理", Modifier.padding(horizontal = 16.dp),
                        fontSize = 18.sp, fontWeight = adjustedWeight(700))
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .24f))
        }
        if (!packages) {
            FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("全部", "进行中", "已结束").forEachIndexed { index, label ->
                    ReviewChoiceChip(selected = filter == index, onClick = { filter = index }, label = { Text(label) })
                }
            }
        }
        if (error) ReviewTextButton(onClick = { scope.launch { load() } }) { Text("无法读取旧下载记录，点击重试") }
        if (rows.isEmpty() && !error && (legacyRows == null || store == null)) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { ReviewCircularProgress() }
        } else {
            PullToRefreshBox(isRefreshing = refreshing, onRefresh = {
                scope.launch {
                    refreshing = true
                    try { load() } finally { refreshing = false }
                }
            }, modifier = Modifier.weight(1f)) {
                LazyColumn(Modifier.fillMaxSize(), state = scroll, contentPadding = PaddingValues(bottom = 12.dp)) {
                    if (rows.isEmpty()) item { EmptyDownloads(packages, filter) }
                    items(rows, key = DownloadItem::key) { item ->
                        val enabled = item.key !in working
                        val internal = item.storeId.isNotEmpty()
                        Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 14.dp)) {
                            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.medium) {
                                    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                                        MaterialGlyph(if (item.status == COMPLETE) "install_mobile" else "download_rounded",
                                            color = MaterialTheme.colorScheme.onSecondaryContainer, size = 22.dp)
                                    }
                                }
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text(item.title, style = MaterialTheme.typography.titleMedium)
                                    val size = Formatter.formatFileSize(context, item.bytes.coerceAtLeast(0))
                                    val details = if (packages) listOf(item.version, size)
                                    else listOf(status(item.status), if (item.total > 0) "$size / ${Formatter.formatFileSize(context, item.total)}" else size,
                                        if (item.speed > 0) "${Formatter.formatFileSize(context, item.speed)}/s" else "",
                                        if (!internal) "系统下载" else "")
                                    Text(details.filter(String::isNotBlank).joinToString(" · "),
                                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    if (item.error.isNotEmpty()) Text(item.error, style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error)
                                }
                            }
                            if (!packages && (item.status == RUNNING || item.status == USER_PAUSED && item.bytes > 0)) {
                                Spacer(Modifier.height(12.dp))
                                if (item.total > 0) ReviewLinearProgress(
                                    progress = { (item.bytes.toFloat() / item.total).coerceIn(0f, 1f) }, Modifier.fillMaxWidth())
                                else if (item.status == RUNNING) ReviewLinearProgress(Modifier.fillMaxWidth())
                            }
                            FlowRow(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                if (item.status == COMPLETE) {
                                    ReviewFilledTonalButton(iconPadding = true, enabled = enabled,
                                        onClick = { action(item) { legacy.install(item) } }) {
                                        MaterialGlyph("install_mobile"); ReviewButtonIconGap(); Text("安装")
                                    }
                                }
                                if (!packages && internal && item.status in setOf(QUEUED, RUNNING)) {
                                    ReviewTextButton(iconPadding = true, enabled = enabled,
                                        onClick = { action(item) { store?.pause(item.storeId) } }) {
                                        MaterialGlyph("pause_rounded"); ReviewButtonIconGap(); Text("暂停")
                                    }
                                }
                                if (!packages && (item.status == USER_PAUSED || item.status == FAILED)) {
                                    ReviewTextButton(iconPadding = true, enabled = enabled, onClick = {
                                        action(item) { if (internal) store?.resume(item.storeId, api) else legacy.retry(item.id) }
                                    }) {
                                        MaterialGlyph(if (item.status == USER_PAUSED) "play_arrow_rounded" else "refresh")
                                        ReviewButtonIconGap()
                                        Text(if (item.status == USER_PAUSED) "继续" else "重试")
                                    }
                                }
                                if (!packages) ReviewTextButton(enabled = enabled, onClick = { remove = item }) {
                                    Text(if (item.ended || item.status == USER_PAUSED) "移除" else "取消下载")
                                }
                            }
                            HorizontalDivider(Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.outlineVariant)
                        }
                    }
                }
            }
        }
    }
    remove?.let { target ->
        ReviewAlertDialog(appDialog = true, onDismissRequest = { remove = null }, title = { Text("移除下载？") },
            text = { Text("「${target.title}」的下载记录及文件将被移除。") },
            dismissButton = { ReviewTextButton(onClick = { remove = null }) { Text("取消") } },
            confirmButton = { ReviewTextButton(onClick = {
                remove = null
                action(target) {
                    if (target.storeId.isNotEmpty()) store?.remove(target.storeId) else legacy.cancel(target.id)
                }
            }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("移除") } })
    }
}

@Composable
private fun EmptyDownloads(packages: Boolean, filter: Int) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MaterialGlyph(if (packages) "install_mobile" else "download_rounded", size = 34.dp, color = MaterialTheme.colorScheme.primary)
        Text(if (packages) "暂无安装包" else when (filter) {
            1 -> "暂无进行中的下载"
            2 -> "暂无已结束的下载"
            else -> "暂无下载任务"
        }, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Text(if (packages) "下载完成的安装包会显示在这里" else "在应用商店选择「应用内下载」开始",
            color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center)
    }
}

private val DownloadItem.ended get() = status == COMPLETE || status == FAILED
private val DownloadItem.key get() = storeId.ifEmpty { path.ifEmpty { id.toString() } }
private fun status(value: Int) = when (value) {
    QUEUED -> "排队中"
    RUNNING -> "下载中"
    SYSTEM_PAUSED -> "等待系统恢复"
    USER_PAUSED -> "已暂停"
    COMPLETE -> "下载完成"
    FAILED -> "下载失败"
    else -> "未知状态"
}
