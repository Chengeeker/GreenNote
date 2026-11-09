package com.green.note.content

import android.content.Context
import android.util.AtomicFile
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import okio.ByteString.Companion.encodeUtf8
import kotlin.math.roundToInt

private val homeCacheEpoch = MutableStateFlow(0L)
internal val homeCacheRevision = homeCacheEpoch.asStateFlow()
private val homeCacheLock = Mutex()
internal data class HeadlineSnapshot(val feeds: List<JSONObject>, val cards: List<JSONObject>)

internal fun decodeHeadlineSnapshot(raw: String?, scope: String): HeadlineSnapshot? = runCatching {
    if (raw == null || raw.length > 4 * 1024 * 1024) return null
    val root = JSONObject(raw)
    if (root.text("scope") != scope) return null
    val feeds = root.optJSONArray("feeds").objects().filter { it.text("id").isNotEmpty() }.distinctBy { it.text("id") }.take(20)
    feeds.takeIf { it.isNotEmpty() }?.let { HeadlineSnapshot(it, root.optJSONArray("banners").objects().take(5)) }
}.getOrNull()

internal class HomeHeadlineCache(context: Context) {
    private val app = context.applicationContext
    private fun file(scope: String) = AtomicFile(File(app.cacheDir, "compose-home/${scope.encodeUtf8().sha256().hex()}.json"))
    suspend fun read(scope: String): HeadlineSnapshot? = withContext(Dispatchers.IO) { homeCacheLock.withLock {
        val file = file(scope)
        if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) runCatching {
            file.openRead().use { stream ->
                if (stream.channel.size() in 1..4 * 1024 * 1024) decodeHeadlineSnapshot(stream.bufferedReader().readText(), scope) else null
            }
        }.getOrNull()?.let { return@withLock it }
        val prefs = app.getSharedPreferences("greennote_compose_content", Context.MODE_PRIVATE)
        val marker = "headline_import_${scope.encodeUtf8().sha256().hex()}"
        if (prefs.getBoolean("headline_import_disabled", false) || prefs.getBoolean(marker, false)) return@withLock null
        // The Flutter cache is read once; clearing Compose must never re-import the deleted snapshot.
        if (!prefs.edit().putBoolean(marker, true).commit()) return@withLock null
        runCatching { decodeHeadlineSnapshot(app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.cached_home_headline_v1", null), scope) }.getOrNull()
    } }
    suspend fun write(scope: String, snapshot: HeadlineSnapshot, epoch: Long) = withContext(Dispatchers.IO) { homeCacheLock.withLock {
        if (epoch != homeCacheEpoch.value) return@withLock
        val raw = JSONObject().put("scope", scope).put("feeds", JSONArray(snapshot.feeds.take(20))).put("banners", JSONArray(snapshot.cards.take(5))).toString()
        if (raw.length > 4 * 1024 * 1024) return@withLock
        val target = file(scope); check(target.baseFile.parentFile!!.mkdirs() || target.baseFile.parentFile!!.isDirectory)
        val stream = target.startWrite()
        try { stream.write(raw.toByteArray(Charsets.UTF_8)); target.finishWrite(stream) }
        catch (failure: Exception) { target.failWrite(stream); throw failure }
    } }
}

internal fun clearHomeCacheDirectory(root: File) {
    require(root.canonicalFile == root.absoluteFile) { "缓存目录无效" }
    val prefix = root.canonicalPath + File.separator
    fun remove(directory: File) {
        directory.listFiles()?.forEach { child ->
            require(child.canonicalPath.startsWith(prefix) && child.canonicalFile == child.absoluteFile) { "缓存路径越界" }
            if (child.isDirectory) remove(child)
            check(child.delete() || !child.exists()) { "部分缓存文件正在使用，请稍后重试" }
        }
    }
    remove(root)
}

internal suspend fun clearHomeFeedCache(context: Context) = withContext(Dispatchers.IO) { homeCacheLock.withLock {
    check(context.getSharedPreferences("greennote_compose_content", Context.MODE_PRIVATE).edit().putBoolean("headline_import_disabled", true).commit())
    try { clearHomeCacheDirectory(File(context.cacheDir.canonicalFile, "compose-home")) }
    finally { homeCacheEpoch.value += 1 }
} }

@Stable
internal class HomeFeedState(private val api: ContentApi, val channelId: String, route: String,
    private val cache: HomeHeadlineCache? = null) {
    val scroll = LazyListState()
    private val owner = api.imageCacheScope()
    private val cacheScope = api.headlineCacheScope()
    var route by mutableStateOf(route); private set
    var rows by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var cards by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var activeIndex by mutableStateOf(0); private set
    var busy by mutableStateOf(false); private set
    var refreshing by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var initialized by mutableStateOf(false); private set
    var more by mutableStateOf(true); private set
    private var activeRoute: String? = null
    private var buffered by mutableStateOf(emptyList<JSONObject>())
    val hasBuffer get() = buffered.isNotEmpty()
    val ranked get() = channelId == "hot" || route.contains("RANKING") || activeRoute?.contains("RANKING") == true
    private var page = 0
    private var first = ""
    private var last = ""
    private var pendingRefresh = false
    private var revision = homeCacheEpoch.value
    private fun owns() = owner == api.imageCacheScope()
    suspend fun initialize() {
        if (initialized || busy || !owns()) return
        if (channelId == "headline") {
            val epoch = homeCacheEpoch.value
            val snapshot = cache?.read(cacheScope)
            if (!owns()) return
            if (epoch == homeCacheEpoch.value && snapshot != null && rows.isEmpty()) {
                rows = snapshot.feeds; cards = snapshot.cards; initialized = true; revision = epoch
                try { cache?.write(cacheScope, snapshot, epoch) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { /* Restored content remains usable if the optional cache cannot be written. */ }
            }
        }
        if (rows.isEmpty()) load(true)
    }
    suspend fun resume() {
        if (pendingRefresh || revision != homeCacheEpoch.value) { pendingRefresh = false; revision = homeCacheEpoch.value; load(true) }
        else if (!initialized) initialize()
        else if (rows.isEmpty()) load(true)
    }
    suspend fun updateRoute(value: String) {
        if (value == route) return
        route = value
        if (channelId == "headline" && rows.isNotEmpty()) return
        activeRoute = null; activeIndex = 0; load(true)
    }
    suspend fun select(item: JSONObject, index: Int) {
        val target = item.text("url")
        if (target.isEmpty() || activeIndex == index && activeRoute == target) return
        activeIndex = index; activeRoute = target; load(true)
    }
    fun releaseBuffer() { if (buffered.isNotEmpty()) { rows = rows + buffered; buffered = emptyList() } }
    suspend fun load(refresh: Boolean = false) {
        if (!owns()) return
        if (busy) { if (refresh) pendingRefresh = true; return }
        if (!refresh && !more && buffered.isEmpty()) return
        if (!refresh && buffered.isNotEmpty()) { releaseBuffer(); return }
        busy = true; refreshing = refresh; error = null
        if (refresh) { page = 0; first = ""; last = ""; more = true; buffered = emptyList() }
        val target = activeRoute ?: route; val epoch = homeCacheEpoch.value
        var cardsNext = false
        try {
            val existing = if (refresh) emptyList() else rows
            val pending = buffered
            val nextPage = if (refresh) 1 else page + 1
            val firstCursor = first
            val lastCursor = last
            val (result, prepared) = withContext(Dispatchers.Default) {
                val result = ContentRepository(api).home(target, nextPage, firstCursor, lastCursor)
                val resultRoot = JSONObject().put("data", JSONArray(result.rows))
                val feeds = extractFeeds(resultRoot)
                val banners = extractHomeCards(resultRoot)
                val seen = (existing.asSequence() + pending.asSequence()).map { it.text("id") }.toMutableSet()
                result to Triple(feeds.isNotEmpty(), banners, feeds.filter { seen.add(it.text("id")) })
            }
            currentCoroutineContext().ensureActive()
            if (!owns()) return
            check(target == (activeRoute ?: route)) { "频道筛选已变化" }
            if (epoch != homeCacheEpoch.value) { pendingRefresh = true; kotlin.error("缓存已清理") }
            val (hadFeeds, banners, extra) = prepared
            if (refresh && (extra.isNotEmpty() || rows.isEmpty())) rows = emptyList()
            if (refresh && (cards.isEmpty() || activeRoute == null) && banners.isNotEmpty()) cards = banners
            if (channelId == "headline" || extra.size <= 4) rows = rows + extra
            else { val count = (extra.size * .6).roundToInt().coerceIn(1, extra.size); rows = rows + extra.take(count); buffered = extra.drop(count) }
            val repeated = !refresh && extra.isEmpty() && hadFeeds && result.last == last
            page = result.page; first = result.first.ifEmpty { first }; last = result.last.ifEmpty { last }
            more = result.more && !repeated
            cardsNext = extra.isEmpty() && banners.isNotEmpty() && result.more && page == 1
            if (rows.isEmpty() && buffered.isEmpty() && !cardsNext) more = false
            initialized = true
            if (channelId == "headline" && refresh && extra.isNotEmpty()) {
                try { cache?.write(cacheScope, HeadlineSnapshot(extra, cards), epoch) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { /* A cache write must not hide successfully loaded feeds. */ }
            }
        } catch (cancelled: CancellationException) { if (refresh) pendingRefresh = true; throw cancelled }
        catch (failure: Exception) { if (owns() && target == (activeRoute ?: route)) { error = failure.message ?: "加载失败"; initialized = true } }
        finally { busy = false; refreshing = false }
        if (pendingRefresh) { pendingRefresh = false; load(true) }
        else if (cardsNext) load()
    }
}
