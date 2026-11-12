package com.green.note.content

import com.green.note.network.CaptchaRequired
import com.green.note.network.UnsupportedCaptcha
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

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
private fun replyChildren(row: JSONObject) = (row.optJSONArray("replyRows") ?: row.optJSONArray("reply_rows")).objects()
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

private suspend fun fetchReplyDetails(api: ContentApi, ids: List<String>, feedId: String, owner: String, parentReplyId: String = ""): List<JSONObject> {
    val limit = Semaphore(3)
    return coroutineScope { ids.map { id -> async { limit.withPermit {
        try {
            check(owner == api.imageCacheScope()) { "账号已变化" }
            val response = api.request("/v6/feed/replyDetail", query = mapOf("id" to id))
            val row = response.optJSONObject("data") ?: response
            row.takeIf { replyId(it) == id && replyMatchesFeed(it, feedId, parentReplyId) && visibleReply(it) }
        } catch (error: Exception) {
            if (error is CancellationException || error is CaptchaRequired || error is UnsupportedCaptcha || owner != api.imageCacheScope()) throw error
            null
        }
    } } }.awaitAll().filterNotNull() }
}

internal fun recentReplyIds(feed: JSONObject?): List<String> = feed?.text("recent_reply_ids", "recentReplyIds").orEmpty()
    .trim('[', ']').split(',').map { it.trim().trim('"') }
    .filter { (it.toLongOrNull() ?: 0) > 0 }.distinct().take(15)

internal suspend fun loadRecentReplyPreview(api: ContentApi, ids: List<String>, feedId: String): List<JSONObject> {
    val owner = api.imageCacheScope()
    return try {
        val rows = fetchReplyDetails(api, ids, feedId, owner)
        if (owner == api.imageCacheScope()) rows.map { normalizeReply(it, feedId) } else emptyList()
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
        val unresolved = records.filter { if (visibleReply(it)) replyAuthor(it).name.isEmpty() else replyType(it) in replyTypes }
            .map(::replyId).distinct().take(6)
        var challenge: Exception? = null
        val details = try { fetchReplyDetails(api, unresolved, feedId, owner, parentReplyId).associateBy(::replyId) }
            catch (error: Exception) {
                if (error !is CaptchaRequired && error !is UnsupportedCaptcha) throw error
                challenge = error
                emptyMap()
            }
        check(owner == api.imageCacheScope()) { "账号已变化" }
        val replies = records.map { row ->
            val normalized = normalizeReply(row, feedId)
            details[replyId(row)]?.let { detail ->
                val full = normalizeReply(detail, feedId)
                full.keys().forEach { key -> if (normalized.text(key).isEmpty()) normalized.put(key, full.opt(key)) }
            }
            normalized
        }.filter { visibleReply(it) && (authorUid == null || authorUid.isNotEmpty() && replyAuthor(it).uid == authorUid) }.distinctBy(::replyId)
        if (replies.isNotEmpty()) return result.copy(rows = replies)
        challenge?.let { throw it }
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
