package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.format.Formatter
import android.util.LruCache

import androidx.compose.foundation.Image
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.background
import com.green.note.ui.tapToggleable as toggleable
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewScrollActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

internal data class InstalledApp(val packageName: String, val label: String, val version: String, val versionCode: Long,
    val system: Boolean, val enabled: Boolean, val updated: Long, val size: Long, val canLaunch: Boolean)

internal class InstalledAppsRepository(private val context: Context) {
    private var signature: List<String>? = null
    suspend fun load(onlyIfChanged: Boolean): List<InstalledApp>? {
        val previous = signature
        val result = withContext(Dispatchers.IO) {
            val pm = context.packageManager
            @Suppress("DEPRECATION") val packages = pm.getInstalledPackages(0)
            val current = packages.map { "${it.packageName}:${it.lastUpdateTime}:${it.applicationInfo?.enabled}" }.sorted()
            if (onlyIfChanged && previous == current) return@withContext null
            val apps = packages.mapNotNull { info ->
                val app = info.applicationInfo ?: return@mapNotNull null
                try {
                    @Suppress("DEPRECATION") val versionCode = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    InstalledApp(info.packageName, pm.getApplicationLabel(app).toString(), info.versionName.orEmpty(), versionCode,
                        app.flags and ApplicationInfo.FLAG_SYSTEM != 0, app.enabled, info.lastUpdateTime,
                        (listOfNotNull(app.sourceDir) + app.splitSourceDirs.orEmpty()).distinct().sumOf { File(it).length() }, app.enabled && pm.getLaunchIntentForPackage(info.packageName) != null)
                } catch (_: android.content.pm.PackageManager.NameNotFoundException) { null }
            }
            current to apps
        } ?: return null
        signature = result.first
        return result.second
    }
}

private class InstalledAppIcons(private val context: Context) {
    private data class Key(val packageName: String, val updated: Long)
    private val icons = LruCache<Key, ImageBitmap>(96)
    private val dispatcher = Dispatchers.IO.limitedParallelism(2)

    fun cached(app: InstalledApp): ImageBitmap? = icons.get(Key(app.packageName, app.updated))

    suspend fun load(app: InstalledApp): ImageBitmap? = withContext(dispatcher) {
        val key = Key(app.packageName, app.updated)
        icons.get(key) ?: try {
            val drawable = context.packageManager.getApplicationIcon(app.packageName).mutate()
            val image = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, image.width, image.height)
            drawable.draw(Canvas(image))
            image.asImageBitmap().also { icons.put(key, it) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }
}

internal class AppManagementState(context: Context) {
    private val repository = InstalledAppsRepository(context.applicationContext)
    var apps by mutableStateOf<List<InstalledApp>>(emptyList())
        private set
    var loading by mutableStateOf(false)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var updateCheck by mutableStateOf(AppUpdateCheck(emptyList()))
        private set
    var loaded = false
        private set

    suspend fun load(quiet: Boolean) {
        if (loading) return
        loading = true
        refreshing = !quiet && loaded
        try {
            repository.load(quiet)?.let { snapshot ->
                val targets = snapshot.filterNot(InstalledApp::system)
                if (targets != apps.filterNot(InstalledApp::system)) updateCheck = AppUpdateCheck(targets)
                apps = snapshot
            }
            loaded = true
            error = null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            if (!loaded) error = failure.message ?: "读取本机应用失败"
        } finally {
            loading = false
            refreshing = false
        }
    }
}

@Composable
internal fun rememberAppManagement(api: ContentApi, lifecycle: Lifecycle, fast: Boolean = false): AppManagementState {
    val context = LocalContext.current.applicationContext
    val state = remember(context, api, api.imageCacheScope()) { AppManagementState(context) }
    val fastNow by rememberUpdatedState(fast)
    LaunchedEffect(state, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            if (!state.loaded && !fastNow) withTimeoutOrNull(1200) { snapshotFlow { fastNow }.first { it } }
            state.load(quiet = true)
        }
    }
    val check = state.updateCheck
    val request = check.requestId
    LaunchedEffect(api, check, lifecycle, request) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { check.run(api) { request == 0 && !fastNow } }
    }
    return state
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AppManagementScreen(state: AppManagementState, onBack: () -> Unit, onApp: (String) -> Unit, downloads: @Composable (Boolean, Boolean) -> Unit) {
    val context = LocalContext.current
    val icons = remember { InstalledAppIcons(context.applicationContext) }
    val scope = rememberCoroutineScope()
    val apps = state.apps
    val error = state.error
    var system by rememberSaveable { mutableStateOf(false) }
    var sort by rememberSaveable { mutableStateOf("recent") }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val pager = rememberPagerState(initialPage = tab) { 4 }
    LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { tab = it } }
    var sortOpen by remember { mutableStateOf(false) }
    LaunchedEffect(state) { state.load(quiet = true) }
    val visible = remember(apps, system, sort) {
        val filtered = apps.filter { system || !it.system }
        when (sort) { "name" -> filtered.sortedBy { it.label.lowercase() }; "size" -> filtered.sortedByDescending { it.size }; else -> filtered.sortedByDescending { it.updated } }
    }
    Column(Modifier.fillMaxSize()) {
        ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp)); Text("应用管理", Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
            Box { ContentIcon("filter_list_rounded", "排序方式", { sortOpen = true }); com.green.note.ui.ReviewPopupMenu(sortOpen, { sortOpen = false }) {
                listOf("recent" to "最近更新", "name" to "按名称", "size" to "按大小").forEach { (value, label) -> com.green.note.ui.ReviewPopupMenuItem(text = { Text(label) }, trailingIcon = if(sort==value){{MaterialGlyph("check_rounded", size = 18.dp, color = Color(0xFF00A993))}}else null,iconSpacing=0.dp, onClick = { sort = value; sortOpen = false }) }
            } }
        }
        TabRow(selectedTabIndex = tab, containerColor = Color.Transparent, indicator = { positions -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(positions[tab]), height = 3.dp, color = Color(0xFF00A993)) }) {
            listOf("应用(${visible.size})", "更新", "下载管理", "安装包").forEachIndexed { index, title ->
                Tab(selected = tab == index, onClick = com.green.note.ui.rememberHapticClick { scope.launch { pager.animateScrollToPage(index) } }, modifier = Modifier.height(with(LocalDensity.current) { (48 * (14.sp.toDp().value / 14).coerceAtLeast(1f)).dp })) {
                    Text(title, Modifier.padding(horizontal = 4.dp), fontSize = 14.sp, maxLines = 2, textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = if (tab == index) Color(0xFF00A993) else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        HorizontalPager(pager, Modifier.weight(1f)) { page -> com.green.note.ui.ActivePage(page == tab) { when (page) {
            0 -> {
                val scroll = rememberLazyListState()
                ReviewScrollActivity(scroll)
                Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("显示系统预装应用", Modifier.weight(1f), fontSize = 14.sp)
                    val thumb = androidx.compose.animation.core.animateFloatAsState(if (system) 1f else 0f, label = "System apps switch").value
                    Box(Modifier.size(59.dp, 48.dp).toggleable(system, role = androidx.compose.ui.semantics.Role.Switch, onValueChange = { system = it }), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(33.dp, 14.dp).background(if (system) Color(0xFF00A993) else MaterialTheme.colorScheme.onSurface.copy(alpha = .32f), androidx.compose.foundation.shape.CircleShape))
                        Surface(Modifier.offset(x = ((thumb - .5f) * 20).dp).size(20.dp), shape = androidx.compose.foundation.shape.CircleShape, shadowElevation = 2.dp, color = if (system) MaterialTheme.colorScheme.primary else if (MaterialTheme.colorScheme.surface.red + MaterialTheme.colorScheme.surface.green + MaterialTheme.colorScheme.surface.blue < 1.5f) Color(0xFFBDBDBD) else Color(0xFFFAFAFA)) {}
                    }
                }
                PullToRefreshBox(isRefreshing = state.refreshing, onRefresh = { scope.launch { state.load(false) } }, modifier = Modifier.weight(1f)) {
                    if (state.loading && apps.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                    else if (error != null) Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) { Text(error, textAlign = androidx.compose.ui.text.style.TextAlign.Center); Spacer(Modifier.height(12.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = { scope.launch { state.load(false) } }) { Text("重试") } }
                    else if (visible.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("没有找到本机应用") }
                    else LazyColumn(state = scroll, contentPadding = PaddingValues(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(visible, key = { it.packageName }) { app -> InstalledAppRow(app, icons, onApp) }
                    }
                }
                }
            }
            1 -> UpdateAppsScreen(state.updateCheck, icons, onApp)
            2 -> downloads(false, tab == 2)
            3 -> downloads(true, tab == 3)
        } } }
    }
}

@Composable
private fun InstalledAppRow(app: InstalledApp, icons: InstalledAppIcons, onApp: (String) -> Unit) {
    val context = LocalContext.current
    var options by remember { mutableStateOf(false) }
    val fontScale = LocalDensity.current.fontScale.coerceIn(1f, 2f)
    Row(Modifier.fillMaxWidth().height((68 * fontScale).dp).clickable { onApp(app.packageName) }.padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        InstalledAppIcon(app, icons)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) { Text(app.label, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis); Spacer(Modifier.height(3.dp)); Text("${app.version}  ${formatApkSize(app.size)}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        Box { ContentIcon("more_vert_rounded", "应用选项", { options = true }); com.green.note.ui.ReviewPopupMenu(options, { options = false }) {
            com.green.note.ui.ReviewPopupMenuItem(text = { Text("应用详情") }, onClick = { options = false; try { context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${app.packageName}"))) } catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("无法打开应用详情") } })
        } }
        Spacer(Modifier.width(4.dp))
        com.green.note.ui.ReviewButton(onClick = { try { context.packageManager.getLaunchIntentForPackage(app.packageName)?.let(context::startActivity) ?: error("无法打开") } catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("打开应用失败") } }, enabled = app.canLaunch,
            modifier = Modifier.size(56.dp, 28.dp), contentPadding = PaddingValues(0.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF009F91), contentColor = Color.White, disabledContainerColor = Color(0xFF454545))) { Text("打开", fontSize = 13.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Normal) }
    }
}

@Composable
private fun InstalledAppIcon(app: InstalledApp, icons: InstalledAppIcons) {
    val bitmap by produceState(icons.cached(app), icons, app.packageName, app.updated) {
        value = icons.load(app)
    }
    Box(Modifier.size(40.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(9.dp)), contentAlignment = Alignment.Center) {
        val image = bitmap
        if (image != null) Image(image, null, Modifier.fillMaxSize())
        else Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHighest), contentAlignment = Alignment.Center) {
            MaterialGlyph("android_rounded")
        }
    }
}

private fun formatApkSize(bytes: Long): String = when {
    bytes <= 0 -> "大小未知"
    bytes >= 1024L * 1024 * 1024 -> "%.2fG".format(bytes / (1024.0 * 1024 * 1024))
    bytes >= 1024 * 1024 -> "%.2fM".format(bytes / (1024.0 * 1024))
    else -> "%.0fK".format(bytes / 1024.0)
}

internal data class AppUpdate(val app: InstalledApp, val versionName: String, val versionCode: Long, val apkSize: String)

internal class AppUpdateCheck(private val apps: List<InstalledApp>) {
    var updates by mutableStateOf<List<AppUpdate>>(emptyList())
        private set
    var failures by mutableIntStateOf(0)
        private set
    private var checked = 0
    private var requested by mutableStateOf(true)
    var requestId by mutableIntStateOf(0)
        private set
    val available get() = apps.isNotEmpty()
    var complete by mutableStateOf(false)
        private set
    val pending get() = available && requested && !complete

    fun stop() { requested = false; requestId++ }

    fun restart() {
        checked = 0
        failures = 0
        complete = false
        requested = true
        requestId++
    }

    suspend fun run(api: ContentApi, quiet: () -> Boolean = { false }) {
        val request = requestId
        while (pending && request == requestId) {
            val batch = apps.subList(checked, minOf(checked + if (quiet()) 1 else 3, apps.size))
            val results = coroutineScope {
                batch.map { app -> async {
                    try {
                        val detail = api.request("/v6/apk/detail", query = mapOf("id" to app.packageName))
                            .optJSONObject("data") ?: error("无详情")
                        val remotePackage = detail.text("apkname", "packageName", "package_name", "apk_name", "pn")
                        check(remotePackage.isEmpty() || remotePackage == app.packageName)
                        val code = detail.text("apkversioncode", "versionCode").toLongOrNull()?.takeIf { it > 0 }
                            ?: error("无版本号")
                        val update = if (code > app.versionCode) AppUpdate(app, detail.text("apkversionname", "versionName"),
                            code, detail.text("apksize", "apkSize", "size")) else null
                        update to false
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (_: Exception) {
                        null to true
                    }
                } }.awaitAll()
            }
            currentCoroutineContext().ensureActive()
            if (!requested || request != requestId) break
            val byPackage = updates.associateByTo(mutableMapOf()) { it.app.packageName }
            batch.forEachIndexed { index, app ->
                val update = results[index].first
                if (update == null) byPackage.remove(app.packageName) else byPackage[app.packageName] = update
            }
            updates = apps.mapNotNull { byPackage[it.packageName] }
            failures += results.count { it.second }
            checked += batch.size
            complete = checked == apps.size
            if (quiet() && pending) withTimeoutOrNull(220) { snapshotFlow { quiet() }.first { !it } }
        }
    }
}

@Composable
private fun UpdateAppsScreen(check: AppUpdateCheck, icons: InstalledAppIcons, onApp: (String) -> Unit) {
    val context = LocalContext.current
    val scroll = rememberLazyListState()
    ReviewScrollActivity(scroll)
    Column(Modifier.fillMaxSize().navigationBarsPadding()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = scroll, contentPadding = PaddingValues(vertical = 4.dp)) {
            items(check.updates, key = { it.app.packageName }) { update ->
                val app = update.app
                ContentListTile(
                    headlineContent = { Text(app.label) },
                    leadingContent = { InstalledAppIcon(app, icons) },
                    supportingContent = {
                        val installed = app.version.ifBlank { app.versionCode.toString() }
                        val latest = update.versionName.ifBlank { update.versionCode.toString() }
                        val size = remember(context, update.apkSize) { updateApkSize(context, update.apkSize) }
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("$installed → $latest")
                            Text("版本号 ${update.versionCode} · $size")
                        }
                    },
                    trailingContent = { MaterialGlyph("chevron_right") },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 68.dp).clickable { onApp(app.packageName) },
                    horizontalPadding = 18.dp,
                )
            }
            if (check.complete && (check.updates.isEmpty() || check.failures > 0)) {
                item {
                    Text(if (check.failures > 0) "${check.failures} 项应用未能确认更新" else "暂无可用更新",
                        Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), contentAlignment = Alignment.Center) {
            com.green.note.ui.ReviewButton(
                onClick = { if (check.pending) check.stop() else check.restart() },
                enabled = check.available,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(if (check.pending) "停止检查" else "检查更新") }
        }
    }
}

private val apkSizeLabel = Regex("""\d+(?:\.\d+)?\s*(?:[KMGT](?:i?B)?|B)""", RegexOption.IGNORE_CASE)

private fun updateApkSize(context: Context, raw: String): String {
    val bytes = raw.toLongOrNull()
    return when {
        bytes != null && bytes > 0 -> Formatter.formatShortFileSize(context, bytes)
        apkSizeLabel.matches(raw) -> raw
        else -> "安装包大小未知"
    }
}
