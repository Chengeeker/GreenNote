package com.green.note.content

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder

internal fun JSONObject.text(vararg names: String): String = names.firstNotNullOfOrNull { name ->
    opt(name)?.takeUnless { it == JSONObject.NULL }?.toString()?.trim()?.takeIf(String::isNotEmpty)
} ?: ""

internal fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else
    (0 until length()).mapNotNull(::optJSONObject)

data class ContentRequest(val path: String, val query: Map<String, String> = emptyMap())

fun contentRequest(route: String): ContentRequest {
    if (route.startsWith('#') || !route.startsWith('/')) {
        require(!route.contains("://")) { "不支持的页面地址" }
        return ContentRequest("/v6/page/dataList", mapOf("url" to route))
    }
    require(!route.startsWith("//")) { "不支持的页面地址" }
    val uri = URI(route.replace(" ", "%20"))
    val query = uri.rawQuery.orEmpty().split('&').filter(String::isNotEmpty).associate {
        val pair = it.split('=', limit = 2)
        URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
    }
    if (uri.path == "/page") return ContentRequest("/v6/page/dataList", query)
    if (uri.path in setOf("/v6/topic/myFollowTopicList", "/topic/myFollowTopicList")) {
        return ContentRequest("/v6/page/dataList", query + ("url" to "#/topic/userFollowTagList?&title=我关注的话题"))
    }
    return ContentRequest(if (uri.path.startsWith("/v6/")) uri.path else "/v6${uri.path}", query)
}

internal fun entityKey(row: JSONObject): String {
    fun identity(item: JSONObject) = item.text("id", "uid", "entityId", "entity_id", "url", "pic").takeUnless { it == "0" }.orEmpty()
    val id = identity(row).ifEmpty { row.optJSONArray("entities").objects().joinToString("|") { identity(it) } }
    return "${row.text("entityType", "entity_type")}:${row.text("entityTemplate", "entity_template")}:$id:${row.text("title")}"
}

internal fun extractEntities(root: JSONObject): List<JSONObject> = collectEntities(root) { false }.distinctBy(::entityKey)

internal fun collectEntities(root: JSONObject, extraRow: (JSONObject) -> Boolean): List<JSONObject> {
    val rows = mutableListOf<JSONObject>()
    val containers = listOf("data", "entities", "rows", "list", "items", "cardRows", "card_rows", "entityList", "entity_list")
    fun visit(value: Any?, depth: Int) {
        if (depth > 32) return
        when (value) {
            is JSONArray -> (0 until value.length()).forEach { visit(value.opt(it), depth + 1) }
            is JSONObject -> {
                val type = value.text("entityType", "entity_type")
                if (type.isNotEmpty() || listOf("id", "title", "message", "username").any(value::has) || extraRow(value)) rows.add(value)
                if (type.equals("card", true)) return
                containers.forEach { visit(value.opt(it), depth + 1) }
            }
        }
    }
    visit(root.opt("data"), 0)
    return rows
}

internal fun extractFeeds(root: JSONObject): List<JSONObject> {
    val result = mutableListOf<JSONObject>()
    fun visit(value: Any?, depth: Int) {
        if (depth > 32) return
        when (value) {
            is JSONArray -> (0 until value.length()).forEach { visit(value.opt(it), depth + 1) }
            is JSONObject -> {
                if (value.text("entityType", "entity_type").lowercase() !in setOf("card", "header", "card_title", "banner") &&
                    listOf("message", "username", "userInfo", "user_info").any(value::has) && value.text("id").isNotEmpty()) result.add(value)
                visit(value.opt("entities"), depth + 1)
            }
        }
    }
    visit(root.opt("data"), 0)
    return result.distinctBy { it.text("id") }
}

data class ContentPage(
    val rows: List<JSONObject>,
    val page: Int,
    val first: String,
    val last: String,
    val more: Boolean,
    // Partial rows may be displayed, but a failed page must be retried before its cursor is committed.
    val error: Exception? = null,
    // Missing body, or missing author identity required by the selected author-only filter.
    val pendingReplyCount: Int = 0,
)

class ContentRepository(private val api: ContentApi) {
    suspend fun page(request: ContentRequest, page: Int, first: String = "", last: String = ""): ContentPage {
        val root = api.request(request.path, query = request.query + mapOf("page" to "$page", "firstItem" to first, "lastItem" to last))
        val replies = request.path in setOf("/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/album/replyList")
        val result = parsePage(root, page, allowShort = replies)
        return if (replies) result.copy(first = root.text("firstItem").ifEmpty { first.ifEmpty { result.first } }) else result
    }

    suspend fun home(route: String, page: Int, first: String = "", last: String = ""): ContentPage {
        val headline = route in setOf("/v6/main/headline", "/main/headline", "/v6/main/indexV8", "/main/indexV8")
        if (!headline) {
            val request = if (route.startsWith("/page") || route.startsWith("/v6/")) contentRequest(route)
                else ContentRequest("/v6/page/dataList", mapOf("url" to route))
            val root = api.request(request.path, query = request.query + mapOf("page" to "$page", "firstItem" to first, "lastItem" to last))
            val feeds = extractFeeds(root)
            return parseHomePage(root, page, feeds).copy(rows = (if (page == 1) extractHomeCards(root) else emptyList()) + feeds)
        }
        val query = mapOf("page" to "$page", "firstLaunch" to "0", "installTime" to "0", "firstItem" to first, "lastItem" to last, "ids" to "")
        if (page > 1) {
            val root = api.request("/v6/main/indexV8", query = query)
            return parseHomePage(root, page, extractFeeds(root), true)
        }
        return coroutineScope {
            suspend fun fetch(path: String): Result<JSONObject> = try { Result.success(api.request(path, query = query)) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { Result.failure(error) }
            val index = async { fetch("/v6/main/indexV8") }
            val headlineResult = async {
                try { Result.success(api.request("/v6/main/headline", query = mapOf("page" to "$page", "firstItem" to first, "lastItem" to last))) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { Result.failure(error) }
            }
            val indexResult = index.await()
            val otherResult = headlineResult.await()
            if (indexResult.isFailure && otherResult.isFailure) throw indexResult.exceptionOrNull()!!
            val indexRoot = indexResult.getOrNull() ?: JSONObject()
            val otherRoot = otherResult.getOrNull() ?: JSONObject()
            val feeds = (extractFeeds(otherRoot) + extractFeeds(indexRoot)).distinctBy { it.text("id") }
            val indexCards = extractHomeCards(indexRoot)
            val cards = indexCards.ifEmpty { extractHomeCards(otherRoot) }
            val parsed = parseHomePage(indexRoot, page, feeds, true)
            parsed.copy(rows = cards + feeds, last = indexRoot.text("lastItem").ifEmpty { extractFeeds(indexRoot).lastOrNull()?.text("id").orEmpty() }.ifEmpty { parsed.last }, more = feeds.isNotEmpty())
        }
    }
}

internal fun parseHomePage(root: JSONObject, page: Int, feeds: List<JSONObject>, allowShort: Boolean = false): ContentPage {
    val value = listOf("hasMore", "has_more", "hasNextPage").firstNotNullOfOrNull { root.opt(it)?.takeUnless { value -> value == JSONObject.NULL } }
    val more = when (value) {
        is Boolean -> value
        is Number -> value.toDouble() != 0.0
        "1", "true" -> true
        "0", "false" -> false
        else -> if (allowShort) feeds.isNotEmpty() else feeds.size >= 10
    }
    return ContentPage(feeds, page, root.text("firstItem").ifEmpty { feeds.firstOrNull()?.text("id").orEmpty() },
        root.text("lastItem").ifEmpty { feeds.lastOrNull()?.text("id").orEmpty() }, more)
}

internal fun extractHomeCards(root: JSONObject): List<JSONObject> = root.optJSONArray("data").objects().filter { row ->
    val type = row.text("entityType", "entity_type").lowercase(); val template = row.text("entityTemplate", "entity_template").lowercase()
    val children = row.optJSONArray("entities")
    type != "feed" && (type == "card" || template.contains("card") || template.startsWith("image") || type == "image_1" || children != null && children.length() > 0) &&
        !(children != null && children.length() == 0 && !template.contains("banner") && type != "image_1")
}

internal fun parsePage(root: JSONObject, page: Int, rows: List<JSONObject> = extractEntities(root), allowShort: Boolean = false): ContentPage {
    fun cursor(first: Boolean): String {
        val ordered = if (first) rows else rows.reversed()
        for (row in ordered) {
            val children = row.optJSONArray("entities").objects().let { if (first) it else it.reversed() }
            for (child in children) child.text("id", "uid").takeIf(String::isNotEmpty)?.let { return it }
            row.text("id", "uid").takeIf(String::isNotEmpty)?.let { return it }
        }
        return ""
    }
    val count = rows.sumOf { 1 + it.optJSONArray("entities").objects().size }
    val value = root.opt("hasMore") ?: root.opt("has_more") ?: root.opt("hasNextPage")
    val more = when (value) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        "1", "true" -> true
        "0", "false" -> false
        else -> if (allowShort) count > 0 else count >= 10
    }
    return ContentPage(rows, page, root.text("firstItem").ifEmpty { cursor(true) }, root.text("lastItem").ifEmpty { cursor(false) }, more)
}
