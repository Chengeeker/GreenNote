package com.green.note.content

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

internal fun followFilterRoute(route: String, type: String): String = runCatching {
    val uri = URI(route)
    val query = linkedMapOf<String, String>()
    uri.rawQuery.orEmpty().split('&').filter(String::isNotEmpty).forEach { value ->
        query[URLDecoder.decode(value.substringBefore('='), "UTF-8")] = URLDecoder.decode(value.substringAfter('=', ""), "UTF-8")
    }
    query.remove("type")
    if (type.isNotEmpty()) query["type"] = type
    val encoded = query.entries.joinToString("&") { URLEncoder.encode(it.key, "UTF-8") + "=" + URLEncoder.encode(it.value, "UTF-8") }
    route.substringBefore('#').substringBefore('?') + (if (encoded.isEmpty()) "" else "?$encoded") + (uri.rawFragment?.let { "#$it" } ?: "")
}.getOrDefault(route)

internal fun followingAuthor(feed: JSONObject): Boolean = feed.text("isFollow") in setOf("1", "true") ||
    feed.optJSONObject("userInfo")?.text("isFollow") in setOf("1", "true") || feed.optJSONObject("userAction")?.text("follow") in setOf("1", "true")

internal fun recentFollowingUsers(cards: List<JSONObject>, feeds: List<JSONObject>): List<JSONObject> {
    val users = mutableListOf<JSONObject>()
    fun visit(row: JSONObject, depth: Int) {
        if (depth > 32) return
        if (row.text("entityType").lowercase() in setOf("user", "user_follow")) users += relationUser(row, false)
        row.optJSONArray("entities").objects().forEach { visit(it, depth + 1) }
    }
    cards.forEach { card ->
        val template = card.text("entityTemplate").lowercase()
        if (card.text("title").contains("最近更新") || template.contains("userfollow") || template.contains("useravatar") || template == "iconminiscrollcard") visit(card, 0)
    }
    if (users.isEmpty()) feeds.sortedByDescending { it.text("dateline").toLongOrNull() ?: 0L }.forEach { feed ->
        val info = feed.optJSONObject("userInfo") ?: JSONObject()
        users += JSONObject(info.toString()).put("uid", feed.text("uid").ifEmpty { info.text("uid") })
            .put("username", feed.text("username").ifEmpty { info.text("username") })
            .put("userAvatar", feed.text("userAvatar", "user_avatar").ifEmpty { info.text("userAvatar") })
    }
    return users.filter { it.text("uid").isNotEmpty() }.distinctBy { it.text("uid") }.take(30)
}

internal data class FollowFeedPage(val feeds: List<JSONObject>, val cards: List<JSONObject>, val page: Int, val first: String, val last: String, val more: Boolean)
private fun followCards(root: JSONObject): List<JSONObject> = root.optJSONArray("data").objects().filter { row ->
    val type = row.text("entityType", "entity_type").lowercase(); val template = row.text("entityTemplate", "entity_template").lowercase()
    val children = row.optJSONArray("entities")
    type != "feed" && (type == "card" || template.contains("card") || template.startsWith("image") || type == "image_1" || children != null && children.length() > 0) &&
        !(children != null && children.length() == 0 && !template.contains("banner") && type != "image_1")
}
private suspend fun homeFollowPage(api: ContentApi, route: String, page: Int, first: String, last: String): FollowFeedPage {
    val request = contentRequest(route)
    val root = api.request(request.path, query = request.query + mapOf("page" to "$page", "firstItem" to first, "lastItem" to last))
    val feeds = extractFeeds(root)
    val parsed = parseHomePage(root, page, feeds)
    return FollowFeedPage(feeds, if (page == 1) followCards(root) else emptyList(), page, parsed.first, parsed.last, parsed.more)
}

@Stable
internal class OfficialHomeFollowState(private val api: ContentApi, val route: String, private val owner: String,
    private val now: () -> Long = System::currentTimeMillis) {
    val scroll = LazyListState()
    var rows by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var selected by mutableStateOf("circle"); private set
    var cards by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var recentCards by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var recentFeeds by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var busy by mutableStateOf(false); private set
    var refreshing by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var initialized = false; private set
    var more = true; private set
    private var buffered = emptyList<JSONObject>()
    val hasBuffer get() = buffered.isNotEmpty()
    private var page = 0
    private var first = ""
    private var last = ""
    private var recentAt: Long? = null
    private var recentBusy = false
    private var refreshPending = false
    private var loadedTarget: String? = null
    private fun owns() = owner == api.imageCacheScope()
    suspend fun resume() {
        if (busy) return
        if (refreshPending || !initialized || loadedTarget != followFilterRoute(route, selected)) {
            refreshPending = false
            load(true)
        }
    }
    suspend fun select(type: String) {
        if (type == selected) return
        selected = type
        load(true)
    }
    fun releaseBuffer() {
        if (buffered.isNotEmpty()) { rows = rows + buffered; buffered = emptyList() }
    }
    private suspend fun loadRecent() {
        if (recentBusy || selected == "circle" || recentAt?.let { now() - it < 60_000 } == true) return
        recentBusy = true
        try {
            val result = homeFollowPage(api, followFilterRoute(route, "circle"), 1, "", "")
            currentCoroutineContext().ensureActive()
            if (owns()) { recentFeeds = result.feeds.take(100); recentCards = result.cards; recentAt = now() }
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Optional authors strip; main timeline remains authoritative. */ }
        finally { recentBusy = false }
    }
    suspend fun load(refresh: Boolean = false) {
        if (busy) { if (refresh) refreshPending = true; return }
        if (!refresh && !more && buffered.isEmpty()) return
        if (!refresh && buffered.isNotEmpty()) { releaseBuffer(); return }
        coroutineScope {
            if (refresh) launch { loadRecent() }
            busy = true; refreshing = refresh; error = null
            if (refresh) { page = 0; first = ""; last = ""; more = true; buffered = emptyList() }
            val target = followFilterRoute(route, selected)
            var loadCardsNext = false
            try {
                check(owns()) { "账号已变更" }
                val result = homeFollowPage(api, target, if (refresh) 1 else page + 1, first, last)
                currentCoroutineContext().ensureActive()
                if (!owns()) return@coroutineScope
                check(target == followFilterRoute(route, selected)) { "关注筛选已变化" }
                val seen = (if (refresh) emptyList() else rows + buffered).map { it.text("id") }.toMutableSet()
                val extra = result.feeds.filter { seen.add(it.text("id")) }.map { JSONObject(it.toString()).put("_composeOfficialLayout", true) }
                if (refresh && (extra.isNotEmpty() || rows.isEmpty())) rows = emptyList()
                if (refresh && cards.isEmpty() && result.cards.isNotEmpty()) cards = result.cards
                val friends = selected == "circle"
                val updates = result.feeds.filter { friends || followingAuthor(it) }
                recentFeeds = (updates + if (refresh && friends) emptyList() else recentFeeds).distinctBy { it.text("id") }.take(100)
                if (extra.size <= 4) rows = rows + extra else {
                    val visible = kotlin.math.round(extra.size * .6).toInt().coerceIn(1, extra.size)
                    rows = rows + extra.take(visible); buffered = buffered + extra.drop(visible)
                }
                val repeated = !refresh && extra.isEmpty() && result.feeds.isNotEmpty() && result.last == last
                page = result.page; first = result.first.ifEmpty { first }; last = result.last.ifEmpty { last }
                more = result.more && !repeated
                loadCardsNext = extra.isEmpty() && result.cards.isNotEmpty() && result.more && page == 1
                if (rows.isEmpty() && buffered.isEmpty() && !loadCardsNext) more = false
                loadedTarget = target
                initialized = true
            } catch (cancelled: CancellationException) {
                // A hidden/disposed pager cancels its effect. Keep a pending filter/refresh
                // until RESUMED instead of showing the preceding filter indefinitely.
                if (refresh && owns()) refreshPending = true
                throw cancelled
            }
            catch (failure: Exception) { if (owns() && target == followFilterRoute(route, selected)) error = failure.message ?: "加载失败" }
            finally { busy = false; refreshing = false }
            if (refreshPending) { refreshPending = false; load(true) }
            else if (loadCardsNext) load(false)
        }
    }
}

internal fun followTimestamp(feed: JSONObject): Long {
    val value = listOf("dateline", "createTime", "create_time").firstNotNullOfOrNull { feed.opt(it)?.takeUnless { value -> value == JSONObject.NULL } }
    if (value is Number) return value.toLong()
    val raw = value?.toString().orEmpty()
    raw.toLongOrNull()?.let { return it }
    // java.time is unavailable on the retained Android 7 baseline; parse ISO dates with
    // platform java.text instead, preserving Dart's millisecond value for date strings.
    val normalized = raw.replace(' ', 'T')
    for (pattern in listOf("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd")) {
        val parser = java.text.SimpleDateFormat(pattern, java.util.Locale.ROOT)
        val position = java.text.ParsePosition(0)
        val date = parser.parse(normalized, position)
        if (date != null && position.index == normalized.length) return date.time
    }
    return 0
}

@Stable
internal class LocalHomeFollowState(private val api: ContentApi, val source: LocalFollowSource,
    private val now: () -> Long = System::currentTimeMillis) {
    val scroll = LazyListState()
    var rows by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var userIds by mutableStateOf(source.userIds); private set
    var loading by mutableStateOf(false); private set
    var loadingMore by mutableStateOf(false); private set
    var readingFollowing by mutableStateOf(false); private set
    var sourceError by mutableStateOf<String?>(null); private set
    var progress by mutableIntStateOf(0); private set
    var total by mutableIntStateOf(0); private set
    var failed by mutableIntStateOf(0); private set
    var hasMore by mutableStateOf(false); private set
    var initialized = false; private set
    private var generation = 0
    private val byId = linkedMapOf<String, JSONObject>()
    private val pages = linkedMapOf<String, Int>()
    private val more = linkedMapOf<String, Boolean>()
    private val first = linkedMapOf<String, String>()
    private val last = linkedMapOf<String, String>()
    private var cachedFollowIds: List<String>? = null
    private var cachedAt: Long? = null
    fun invalidate() { generation++; rows = emptyList(); cachedFollowIds = null; cachedAt = null }
    private suspend fun checkGeneration(expected: Int) { currentCoroutineContext().ensureActive(); if (generation != expected) throw CancellationException("关注来源已变更") }
    private suspend fun publicFollowIds(expected: Int): List<String> {
        cachedFollowIds?.takeIf { cachedAt?.let { now() - it < 300_000 } == true }?.let { return it }
        val ids = linkedSetOf<String>()
        var page = 1; var firstCursor = ""; var lastCursor = ""
        while (true) {
            checkGeneration(expected)
            val root = api.request("/v6/user/followList", query = mapOf("uid" to source.publicUid, "page" to "$page") +
                (if (firstCursor.isNotEmpty()) mapOf("firstItem" to firstCursor) else emptyMap()) + (if (lastCursor.isNotEmpty()) mapOf("lastItem" to lastCursor) else emptyMap()))
            checkGeneration(expected)
            val result = parsePage(root, page)
            val before = ids.size
            result.rows.forEach { it.text("uid", "userId").takeIf(String::isNotEmpty)?.let(ids::add) }
            check(result.rows.isEmpty() || page != 1 || ids.size != before) { "无法从公开关注列表中读取用户 UID" }
            if (!result.more || result.rows.isEmpty() || ids.size == before) break
            firstCursor = result.first; lastCursor = result.last; page++
        }
        return ids.toList().also { cachedFollowIds = it; cachedAt = now() }
    }
    suspend fun refresh() {
        if (loading || loadingMore) return
        val expected = ++generation
        loading = true; readingFollowing = source.publicUid.isNotEmpty(); sourceError = null
        byId.clear(); pages.clear(); more.clear(); first.clear(); last.clear(); progress = 0; failed = 0; hasMore = false
        userIds = if (source.publicUid.isEmpty()) source.userIds else emptyList(); total = userIds.size
        try {
            val ids = if (source.publicUid.isEmpty()) source.userIds else publicFollowIds(expected)
            checkGeneration(expected)
            userIds = ids; total = ids.size; readingFollowing = false
            if (ids.isEmpty()) rows = emptyList()
            loadPages(ids.associateWith { 1 }, expected, countProgress = true)
            checkGeneration(expected); initialized = true
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { if (expected == generation) sourceError = failure.message ?: "读取失败" }
        finally { if (expected == generation) { loading = false; readingFollowing = false } }
    }
    suspend fun loadMore() {
        if (loading || loadingMore) return
        val next = userIds.filter { more[it] == true }.associateWith { (pages[it] ?: 1) + 1 }
        if (next.isEmpty()) return
        val expected = generation
        loadingMore = true
        try { loadPages(next, expected) }
        finally { if (expected == generation) loadingMore = false }
    }
    private suspend fun loadPages(requests: Map<String, Int>, expected: Int, countProgress: Boolean = false) {
        val entries = requests.entries.toList(); val hadRows = rows.isNotEmpty()
        for ((batchIndex, batch) in entries.chunked(3).withIndex()) {
            checkGeneration(expected)
            val results = coroutineScope { batch.map { (uid, page) -> async {
                val result = try {
                    val root = api.request("/v6/user/feedList", query = mapOf("uid" to uid, "page" to "$page", "firstItem" to first[uid].orEmpty(), "lastItem" to last[uid].orEmpty()))
                    Result.success(parsePage(root, page, extractFeeds(root)))
                } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { Result.failure(failure) }
                Triple(uid, page, result)
            } }.awaitAll() }
            checkGeneration(expected)
            results.forEach { (uid, page, result) ->
                val loaded = result.getOrNull()
                if (loaded == null) { failed++; more[uid] = false }
                else {
                    pages[uid] = page; more[uid] = loaded.more; first[uid] = loaded.first; last[uid] = loaded.last
                    loaded.rows.forEach { feed -> if (feed.text("id").isNotEmpty()) byId[feed.text("id")] = feed }
                }
            }
            if (countProgress) progress += batch.size
            if ((!hadRows && rows.isEmpty()) || (batchIndex + 1) * 3 >= entries.size) {
                if (byId.isNotEmpty() || failed == 0) rows = byId.values.sortedWith(compareByDescending<JSONObject>(::followTimestamp).thenByDescending { it.text("id") })
            }
            hasMore = more.values.any { it }
        }
    }
}

internal class HomeFollowStore(private val api: ContentApi) {
    private var official: OfficialHomeFollowState? = null
    private var officialKey = ""
    private var local: LocalHomeFollowState? = null
    fun official(route: String): OfficialHomeFollowState {
        val key = api.imageCacheScope() + route
        if (key != officialKey) { officialKey = key; official = OfficialHomeFollowState(api, route, api.imageCacheScope()) }
        return requireNotNull(official)
    }
    fun local(source: LocalFollowSource): LocalHomeFollowState {
        val current = local?.source
        if (current == null || current.profileId != source.profileId || current.publicUid != source.publicUid || source.publicUid.isEmpty() && current.userIds != source.userIds) {
            local?.invalidate(); local = LocalHomeFollowState(api, source)
        }
        return requireNotNull(local)
    }
}
