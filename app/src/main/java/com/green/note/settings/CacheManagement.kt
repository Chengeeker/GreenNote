package com.green.note.settings

import com.green.note.ui.ReviewText as Text

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.imageLoader
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

data class CacheStats(val images: Long = 0, val network: Long = 0, val system: Long = 0) {
    val total get() = images + network + system
    fun segmentWeight(bytes: Long): Float = if (bytes <= 0L || total <= 0L) 0f
        else (bytes.toDouble() / total * 1000).toInt().coerceIn(1, 1000).toFloat()
    companion object {
        fun format(bytes: Long): String {
            if (bytes <= 0) return "0 B"
            var count = bytes.toDouble(); var index = 0
            while (count >= 1024 && index < 4) { count /= 1024; index++ }
            return String.format(Locale.ROOT, if (index == 0) "%.0f %s" else "%.2f %s", count, listOf("B", "KB", "MB", "GB", "TB")[index])
        }
    }
}

@OptIn(coil.annotation.ExperimentalCoilApi::class)
class ComposeCacheManager(context: Context) {
    private val app = context.applicationContext
    private val cacheRoot = app.cacheDir.canonicalFile
    private val root = File(cacheRoot, "compose_images")
    private val shares = File(cacheRoot, "compose-share")
    private val home = File(cacheRoot, "compose-home")

    suspend fun stats(): CacheStats = withContext(Dispatchers.IO) { CacheStats(images = safeSize(root),network=safeSize(shares)+safeSize(home)) }

    suspend fun clear(): Long = withContext(Dispatchers.IO) {
        val before = safeSize(root)+safeSize(shares)+safeSize(home)
        com.green.note.content.clearHomeFeedCache(app)
        app.imageLoader.memoryCache?.clear()
        com.green.note.content.clearPreparedTopics()
        com.green.note.content.clearContentTextCache()
        com.green.note.content.clearContentDeviceCache()
        val diskCache = app.imageLoader.diskCache
        if (diskCache?.directory?.toFile()?.canonicalFile == root.canonicalFile) diskCache.clear()
        else {
            require(root.canonicalFile == root.absoluteFile) { "缓存目录无效" }
            removeChildren(root, root.canonicalPath + File.separator)
        }
        require(shares.canonicalFile==shares.absoluteFile) { "缓存目录无效" }
        removeChildren(shares,shares.canonicalPath+File.separator)
        (before-safeSize(root)-safeSize(shares)-safeSize(home)).coerceAtLeast(0)
    }

    suspend fun clearIfNeeded(thresholdMb: Int) {
        if (thresholdMb > 0 && stats().total >= thresholdMb.toLong() * 1024 * 1024) clear()
    }

    private fun safeSize(file: File): Long {
        if (!file.exists() || file.canonicalFile != file.absoluteFile) return 0
        return if (file.isFile) file.length() else file.listFiles()?.sumOf(::safeSize) ?: 0
    }

    private fun removeChildren(directory: File, prefix: String) {
        directory.listFiles()?.forEach { child ->
            require(child.canonicalPath.startsWith(prefix) && child.canonicalFile == child.absoluteFile) { "缓存路径越界" }
            if (child.isDirectory) removeChildren(child, prefix)
            check(child.delete() || !child.exists()) { "部分缓存文件正在使用，请稍后重试" }
        }
    }
}

@Composable
fun CacheManagementScreen(manager: ComposeCacheManager, preferences: AppPreferences,
    onChange: ((AppPreferences) -> AppPreferences) -> Unit, onBack: () -> Unit,
) {
    var stats by remember { mutableStateOf(CacheStats()) }; var loading by remember { mutableStateOf(true) }
    var clearing by remember { mutableStateOf(false) }; var confirm by remember { mutableStateOf(false) }
    var threshold by remember { mutableStateOf(false) };val toast=remember{AppToastState()}
    val scope = rememberCoroutineScope()
    LaunchedEffect(manager) {
        try { stats = manager.stats() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { toast.showSnackbar(error.message ?: "读取缓存占用失败，请稍后重试") }
        finally { loading = false }
    }
    ReviewPage("缓存管理", onBack) {
        SectionCard {
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(56.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                    MaterialGlyph("cleaning_services_rounded", size = 30.dp, color = MaterialTheme.colorScheme.onPrimaryContainer)
                }
                Spacer(Modifier.height(16.dp))
                if (loading) com.green.note.ui.ReviewCircularProgress(Modifier.padding(vertical = 8.dp).size(24.dp), strokeWidth = 2.5.dp)
                else Text(CacheStats.format(stats.total), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp)); Text("当前应用缓存占用", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(24.dp))
                Row(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest)) {
                    if (stats.images > 0) Spacer(Modifier.weight(stats.segmentWeight(stats.images)).fillMaxHeight().background(MaterialTheme.colorScheme.primary))
                    if (stats.network > 0) Spacer(Modifier.weight(stats.segmentWeight(stats.network)).fillMaxHeight().background(MaterialTheme.colorScheme.tertiary))
                    if (stats.system > 0) Spacer(Modifier.weight(stats.segmentWeight(stats.system)).fillMaxHeight().background(MaterialTheme.colorScheme.secondary))
                }
                Spacer(Modifier.height(20.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                    listOf(Triple("图片与媒体", stats.images, MaterialTheme.colorScheme.primary), Triple("网络与临时", stats.network, MaterialTheme.colorScheme.tertiary), Triple("系统运行时", stats.system, MaterialTheme.colorScheme.secondary)).forEach { (name, size, color) ->
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).background(color, CircleShape)); Spacer(Modifier.width(6.dp)); Text(name, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            Spacer(Modifier.height(4.dp)); Text(CacheStats.format(size), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        SectionCard {
            com.green.note.ui.ReviewButton(iconPadding = true, onClick = { if (stats.total == 0L) toast.showSnackbar("当前没有可清理的缓存") else confirm = true },
                enabled = !loading && !clearing, modifier = Modifier.padding(16.dp).fillMaxWidth().heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp)) {
                if (clearing) com.green.note.ui.ReviewCircularProgress(Modifier.size(18.dp), strokeWidth = 2.dp, color = androidx.compose.ui.graphics.Color.White) else MaterialGlyph("delete_sweep_rounded")
                ReviewButtonIconGap(); Text(if (clearing) "正在深度清理..." else "一键清理所有缓存")
            }
        }
        Spacer(Modifier.height(24.dp)); SectionHeading("自动清理规则"); Spacer(Modifier.height(12.dp))
        SectionCard { PreferenceRow("自动清理缓存阈值", "达到设定阈值并在启动时检测到将自动静默清理", "auto_delete_outlined", onClick = { threshold = true },
            trailing = { Text(thresholdLabel(preferences.autoClearCacheThresholdMb), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary) }) }
        Spacer(Modifier.height(24.dp)); SectionHeading("物理清理保障"); Spacer(Modifier.height(12.dp))
        SectionCard {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                MaterialGlyph("verified_outlined", color = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text("真实物理清理", fontSize = 14.sp, fontWeight = FontWeight.Bold); Spacer(Modifier.height(6.dp))
                    Text("清空 Compose 版本缓存，保留 Flutter 回退数据", fontSize = 13.sp, lineHeight = 18.85.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(32.dp))
    }
    if (confirm) com.green.note.ui.ReviewAlertDialog(appDialog=true,onDismissRequest = { confirm = false }, title = { Text("清理所有缓存？") },
        text = { Text("清空 Compose 版本缓存，保留 Flutter 回退数据（共计 ${CacheStats.format(stats.total)}）。") },
        confirmButton = { com.green.note.ui.ReviewButton(onClick = {
            confirm = false; clearing = true
            scope.launch {
                try { val freed = manager.clear(); stats = manager.stats(); toast.showSnackbar("缓存清理完毕，已释放 ${CacheStats.format(freed)} 空间") }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { toast.showSnackbar(error.message ?: "缓存清理失败，请稍后重试") }
                finally { clearing = false }
            }
        }) { Text("立即清理") } }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirm = false }) { Text("取消") } })
    if (threshold) ReviewSelectionDialog("选择自动清理阈值",{threshold=false}) {
        AppPreferences.thresholds.forEach { value -> ChoiceRow(if(value>=1024)"${value/1024} GB ($value MB)" else thresholdLabel(value),
            preferences.autoClearCacheThresholdMb==value,{onChange{it.copy(autoClearCacheThresholdMb=value)};threshold=false;toast.showSnackbar(if(value==0)"已关闭自动清理" else "已设置缓存阈值为 ${thresholdLabel(value)}")},
            horizontalPadding=14.dp,verticalPadding=0.dp,titleSize=13f,allowReselect=true) }
    }
}

private fun thresholdLabel(value: Int) = when { value <= 0 -> "不限制（从不自动清理）"; value >= 1024 -> "${value / 1024} GB"; else -> "$value MB" }

