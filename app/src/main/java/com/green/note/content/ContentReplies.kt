package com.green.note.content

import com.green.note.network.ApiException
import com.green.note.network.CaptchaRequired
import com.green.note.network.ReplyDiagnostics
import com.green.note.network.UnsupportedCaptcha
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference

internal val embeddedReplyFields = listOf("topReplyRows", "top_reply_rows", "replyMeRows", "reply_me_rows", "replyRows", "reply_rows")

internal fun embeddedReplies(feed: JSONObject, feedId: String, authorOnly: Boolean): List<JSONObject> {
    val author = replyAuthor(feed).uid
    return embeddedReplyFields.flatMap { feed.optJSONArray(it).objects() }
        .filter { visibleReply(it) && replyMatchesFeed(it, feedId) &&
            (!authorOnly || author.isNotEmpty() && replyAuthor(it).uid == author) }
        .distinctBy(::replyId)
        .map { normalizeReply(it, feedId) }
}

private val replyTypes = setOf("feed_reply", "reply", "feedreply")
private val nonReplyTypes = setOf("card", "header", "card_title", "banner", "placeholder", "feed_detail_reply_sponsor_card")
private val blankReplyHtml = Regex("""(?:<br\s*/?>|</?p\b[^>]*>|&nbsp;|\s|\u200b)+""", RegexOption.IGNORE_CASE)

internal fun replyId(row: JSONObject): String = sequenceOf("id", "replyId", "reply_id").map { row.text(it) }
    .firstOrNull { (it.toLongOrNull() ?: 0) > 0 }.orEmpty()
private fun replyType(row: JSONObject) = row.text("entityType", "entity_type", "type").lowercase()
internal fun replyMessage(row: JSONObject) = row.text("message", "description", "content")
    .takeUnless { blankReplyHtml.matches(it) }.orEmpty()

internal data class ReplyAuthor(val uid: String, val name: String, val avatar: String)
internal fun replyAuthor(row: JSONObject): ReplyAuthor {
    val authors = listOfNotNull(row.optJSONObject("userInfo"), row.optJSONObject("user_info"), row.optJSONObject("user"), row.optJSONObject("author"))
    fun authorField(vararg keys: String) = authors.firstNotNullOfOrNull { it.text(*keys).takeIf { value -> value.isNotEmpty() && value != "0" } }.orEmpty()
    return ReplyAuthor(
        row.text("uid", "fromuid", "from_uid").takeUnless { it == "0" }.orEmpty()
            .ifEmpty { authorField("uid", "id") },
        row.text("username", "fromusername", "user_name", "userName").ifEmpty { authorField("username", "user_name", "userName", "name") },
        row.text("userAvatar", "user_avatar", "avatar").ifEmpty { authorField("userAvatar", "user_avatar", "avatar") },
    )
}

private fun replyEntry(row: JSONObject): Boolean = replyType(row) !in nonReplyTypes &&
    !row.text("entityTemplate", "entity_template").equals("feed_detail_reply_sponsor_card", true) &&
    !replyMessage(row).equals("FEED_DETAIL_REPLY_SPONSOR_CARD", true)

private fun replyRecord(row: JSONObject): Boolean = replyId(row).isNotEmpty() && replyEntry(row)
private fun replyChildren(row: JSONObject) = listOfNotNull(row.optJSONArray("replyRows"), row.optJSONArray("reply_rows"))
    .firstOrNull { it.length() > 0 }.objects()
private fun replyHasBody(row: JSONObject) = replyMessage(row).isNotEmpty() || feedImages(row).isNotEmpty()
internal fun visibleReply(row: JSONObject): Boolean = replyRecord(row) &&
    (replyHasBody(row) || replyChildren(row).any { replyEntry(it) && replyHasBody(it) })
internal fun visibleReplyChildren(row: JSONObject) = replyChildren(row).filter { replyEntry(it) && replyHasBody(it) }

internal fun normalizeReply(row: JSONObject, feedId: String): JSONObject {
    val author = replyAuthor(row)
    return JSONObject(row, row.keys().asSequence().toList().toTypedArray()).apply {
        put("id", replyId(row))
        put("entityType", "feed_reply")
        put("feedid", feedId.ifEmpty { row.text("feedid", "feedId", "feed_id", "fid") })
        put("uid", author.uid)
        put("username", author.name)
        put("userAvatar", author.avatar)
        put("message", replyMessage(row))
        put("dateline", row.text("dateline", "createTime", "create_time"))
    }
}

internal fun replyMatchesFeed(row: JSONObject, feedId: String, parentReplyId: String = ""): Boolean =
    feedId.isEmpty() || row.text("feedid", "feedId", "feed_id", "fid").let { it.isEmpty() || it == feedId || it == parentReplyId }

private data class ReplyDetails(
    val rows: List<JSONObject>,
    val failures: Map<String, Exception>,
    val challenge: Exception?,
)

private suspend fun fetchReplyDetails(api: ContentApi, ids: List<String>, feedId: String, owner: String, parentReplyId: String = ""): ReplyDetails = coroutineScope {
    val rows = mutableListOf<JSONObject>()
    val failures = mutableMapOf<String, Exception>()
    val challenge = AtomicReference<Exception?>(null)
    // Schedule at most three at a time. A challenge stops later work without cancelling successful siblings.
    for (batch in ids.distinct().chunked(3)) {
        if (challenge.get() != null) break
        val results = batch.map { id -> async {
            challenge.get()?.let { return@async id to Result.failure<JSONObject>(it) }
            try {
                check(owner == api.imageCacheScope()) { "账号已变化" }
                val response = api.request("/v6/feed/replyDetail", query = mapOf("id" to id))
                check(owner == api.imageCacheScope()) { "账号已变化" }
                val row = response.optJSONObject("data") ?: response
                if (replyId(row) != id || !replyMatchesFeed(row, feedId, parentReplyId) || !visibleReply(row)) {
                    throw ApiException("评论详情暂未完整返回，请重试")
                }
                id to Result.success(row)
            } catch (error: Exception) {
                if (error is CancellationException || owner != api.imageCacheScope()) throw error
                if (error is CaptchaRequired || error is UnsupportedCaptcha) challenge.compareAndSet(null, error)
                id to Result.failure<JSONObject>(error)
            }
        } }.awaitAll()
        for ((id, result) in results) {
            result.getOrNull()?.let(rows::add)
            (result.exceptionOrNull() as? Exception)?.let { failures[id] = it }
        }
    }
    ReplyDetails(rows, failures, challenge.get())
}

private fun missingReplyValue(value: Any?): Boolean = when (value) {
    null, JSONObject.NULL -> true
    is String -> value.isBlank()
    is JSONArray -> value.length() == 0
    is JSONObject -> value.length() == 0
    else -> false
}

private fun mergeReplyDetail(row: JSONObject, detail: JSONObject?, feedId: String): JSONObject {
    val normalized = normalizeReply(row, feedId)
    if (detail != null) {
        val full = normalizeReply(detail, feedId)
        full.keys().forEach { key ->
            if (missingReplyValue(normalized.opt(key))) normalized.put(key, full.opt(key))
        }
    }
    return normalized
}

internal fun recentReplyIds(feed: JSONObject?): List<String> = feed?.text("recent_reply_ids", "recentReplyIds").orEmpty()
    .trim('[', ']').split(',').map { it.trim().trim('"') }
    .filter { (it.toLongOrNull() ?: 0) > 0 }.distinct().take(15)

internal suspend fun loadRecentReplyPreview(api: ContentApi, ids: List<String>, feedId: String): List<JSONObject> {
    val owner = api.imageCacheScope()
    return try {
        val details = fetchReplyDetails(api, ids, feedId, owner)
        if (owner == api.imageCacheScope()) details.rows.map { normalizeReply(it, feedId) } else emptyList()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        emptyList()
    }
}

internal suspend fun loadReplyPage(api: ContentApi, request: ContentRequest, feedId: String, page: Int, first: String, last: String, authorUid: String? = null): ContentPage {
    val owner = api.imageCacheScope()
    val parentReplyId = request.query["id"].orEmpty().takeIf { request.query["feedType"] == "feed_reply" }.orEmpty()
    suspend fun requestPage(number: Int, before: String, after: String): ContentPage {
        val query = request.query + buildMap {
            put("page", "$number")
            if (request.path != "/v6/feed/hotReplyList") {
                if (before.isNotEmpty()) put("firstItem", before)
                if (after.isNotEmpty()) put("lastItem", after)
            }
        }
        val root = api.request(request.path, query = query)
        val raw = collectEntities(root, ::replyRecord)
        val pageData = parsePage(root, number, raw, allowShort = true)
        val records = raw.filter(::replyRecord)
        return pageData.copy(
            first = root.text("firstItem").ifEmpty { before.ifEmpty { records.firstOrNull()?.let(::replyId) ?: pageData.first } },
            last = root.text("lastItem").ifEmpty { records.lastOrNull()?.let(::replyId) ?: pageData.last },
        )
    }
    var result = requestPage(page, first, last)
    var previousCursor = last
    repeat(3) { attempt ->
        val records = result.rows.filter { replyRecord(it) && replyMatchesFeed(it, feedId, parentReplyId) }
            .filter { authorUid == null || replyAuthor(it).uid.let { uid -> uid.isEmpty() || uid == authorUid } }
            .distinctBy(::replyId)
        // A readable child is a partial preview, not proof that its parent's body was loaded.
        val missingBodies = records.filter { !replyHasBody(it) && (replyType(it) in replyTypes || visibleReply(it)) }.map(::replyId)
        val missingAuthorIds = if (authorUid == null) emptyList() else records.filter {
            replyAuthor(it).uid.isEmpty() && (replyType(it) in replyTypes || visibleReply(it))
        }.map(::replyId)
        val missingAuthors = records.filter { replyHasBody(it) && replyAuthor(it).name.isEmpty() }.map(::replyId)
        val details = fetchReplyDetails(api, missingBodies + missingAuthorIds + missingAuthors, feedId, owner, parentReplyId)
        check(owner == api.imageCacheScope()) { "账号已变化" }
        val byId = details.rows.associateBy(::replyId)
        val normalized = records.map { mergeReplyDetail(it, byId[replyId(it)], feedId) }
        val missingBodyCount = normalized.count { replyId(it) in missingBodies && !replyHasBody(it) }
        val pending = normalized.filter {
            replyId(it) in missingBodies && !replyHasBody(it) || replyId(it) in missingAuthorIds && replyAuthor(it).uid.isEmpty()
        }
        val replies = normalized.filter { visibleReply(it) && (authorUid == null || authorUid.isNotEmpty() && replyAuthor(it).uid == authorUid) }
        ReplyDiagnostics.page(request.path, sourceCount = records.size, visibleCount = replies.size,
            missingBodyCount = missingBodyCount, hydrationCount = details.rows.size, partial = pending.isNotEmpty())
        if (pending.isNotEmpty()) {
            val failure = details.challenge ?: pending.firstNotNullOfOrNull { details.failures[replyId(it)] }
                ?: ApiException("评论暂未加载完整，请重试")
            return result.copy(rows = replies, error = failure, pendingReplyCount = pending.size)
        }
        if (replies.isNotEmpty()) return result.copy(rows = replies)
        if (!result.more) return result.copy(rows = emptyList())
        // Filtered service rows are not the end of the comments; keep the retry bounded.
        check(attempt < 2 && result.last.isNotEmpty() && result.last != previousCursor) { "评论暂未加载完整，请重试" }
        previousCursor = result.last
        result = requestPage(result.page + 1, result.first, result.last)
    }
    error("评论暂未加载完整，请重试")
}

internal suspend fun loadContentReplies(api: ContentApi, feed: JSONObject?, id: String, order: Int, authorOnly: Boolean, page: Int, first: String, last: String): ContentPage {
    val scope = api.imageCacheScope()
    val author = feed?.let(::replyAuthor)?.uid.orEmpty()
    val query = mapOf("id" to id, "listType" to if (order >= 2) "dateline_desc" else "lastupdate_desc", "discussMode" to "1", "feedType" to "feed", "blockStatus" to "0", "fromFeedAuthor" to if (authorOnly) "1" else "0")
    val request = if (order == 1) ContentRequest("/v6/feed/hotReplyList", mapOf("id" to id, "discussMode" to "1"))
        else ContentRequest("/v6/feed/replyList", query)
    val result = loadReplyPage(api, request, id, page, first, last, author.takeIf { authorOnly })
    check(scope == api.imageCacheScope()) { "账号已变化" }
    return result
}
