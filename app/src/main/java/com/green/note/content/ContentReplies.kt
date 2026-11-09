package com.green.note.content

import com.green.note.network.CaptchaRequired
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

internal fun embeddedReplies(feed: JSONObject?): List<JSONObject> = listOf("topReplyRows", "top_reply_rows", "replyMeRows", "reply_me_rows", "replyRows", "reply_rows")
    .flatMap { feed?.optJSONArray(it).objects() }.filter(::visibleReply).distinctBy(::replyId)

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
            if (error is CancellationException || error is CaptchaRequired || owner != api.imageCacheScope()) throw error
            null
        }
    } } }.awaitAll().filterNotNull() }
}

internal suspend fun loadReplyPage(api: ContentApi, request: ContentRequest, feedId: String, page: Int, first: String, last: String): ContentPage {
    val owner = api.imageCacheScope()
    val parentReplyId = request.query["id"].orEmpty().takeIf { request.query["feedType"] == "feed_reply" }.orEmpty()
    suspend fun requestPage(number: Int, before: String, after: String): ContentPage {
        val root = api.request(request.path, query = request.query + mapOf("page" to "$number", "firstItem" to before, "lastItem" to after))
        val raw = collectEntities(root, ::replyRecord)
        val pageData = parsePage(root, number, raw)
        val records = raw.filter(::replyRecord)
        return pageData.copy(
            first = root.text("firstItem").ifEmpty { records.firstOrNull()?.let(::replyId) ?: pageData.first },
            last = root.text("lastItem").ifEmpty { records.lastOrNull()?.let(::replyId) ?: pageData.last },
        )
    }
    var result = requestPage(page, first, last)
    // A page can contain only service rows. Follow an advancing server cursor, within a bounded window.
    for (attempt in 0 until 2) {
        if (result.rows.any { replyRecord(it) && (visibleReply(it) || replyType(it) in replyTypes) } ||
            !result.more || result.last.isEmpty() || result.last == last) break
        val next = requestPage(result.page + 1, result.first, result.last)
        if (next.last == result.last) break
        result = next
    }
    val records = result.rows.filter { replyRecord(it) && replyMatchesFeed(it, feedId, parentReplyId) }
    val unresolved = records.filter { if (visibleReply(it)) replyAuthor(it).name.isEmpty() else replyType(it) in replyTypes }
        .map(::replyId).distinct().take(6)
    val details = try { fetchReplyDetails(api, unresolved, feedId, owner, parentReplyId).associateBy(::replyId) }
        catch (_: CaptchaRequired) { emptyMap() }
    check(owner == api.imageCacheScope()) { "账号已变化" }
    val replies = records.map { row ->
        val normalized = normalizeReply(row, feedId)
        details[replyId(row)]?.let { detail ->
            val full = normalizeReply(detail, feedId)
            full.keys().forEach { key -> if (normalized.text(key).isEmpty()) normalized.put(key, full.opt(key)) }
        }
        normalized
    }.filter(::visibleReply).distinctBy(::replyId)
    return result.copy(rows = replies)
}

internal suspend fun loadContentReplies(api: ContentApi, feed: JSONObject?, id: String, order: Int, authorOnly: Boolean, page: Int, first: String, last: String): ContentPage {
    val scope = api.imageCacheScope()
    val author = feed?.let(::replyAuthor)?.uid.orEmpty()
    val query = mapOf("id" to id, "listType" to if (order >= 2) "dateline_desc" else "lastupdate_desc", "discussMode" to "1", "feedType" to "feed", "blockStatus" to "0", "fromFeedAuthor" to if (authorOnly) "1" else "0")
    suspend fun request(hot: Boolean): ContentPage = loadReplyPage(api, ContentRequest(if (hot) "/v6/feed/hotReplyList" else "/v6/feed/replyList", query), id, page, first, last)
    fun guard(error: Exception) { if (error is CancellationException || error is CaptchaRequired || scope != api.imageCacheScope()) throw error }
    var failure: Exception? = null
    var result = try { request(order == 1) } catch (error: Exception) { guard(error); failure = error; ContentPage(emptyList(), page, "", "", false) }
    if (page == 1 && result.rows.isEmpty() && !authorOnly) {
        if (failure != null && order != 1) try { result = request(true) } catch (error: Exception) { guard(error) }
        if (result.rows.isEmpty()) {
            val recent = feed?.text("recent_reply_ids").orEmpty().split(',').map(String::trim).filter { it.toLongOrNull()?.let { n -> n > 0 } == true }.distinct().take(15)
            val fetched = fetchReplyDetails(api, recent, id, scope)
            if (fetched.isNotEmpty()) result = ContentPage(fetched, 1, replyId(fetched.first()), replyId(fetched.last()), false)
        }
        if (result.rows.isEmpty() && order == 1) try { result = request(false) } catch (error: Exception) { guard(error) }
    }
    if (result.rows.isEmpty() && page == 1) {
        val embedded = embeddedReplies(feed).filter { replyMatchesFeed(it, id) && (!authorOnly || author.isNotEmpty() && replyAuthor(it).uid == author) }
        if (embedded.isNotEmpty()) result = ContentPage(embedded, page, replyId(embedded.first()), replyId(embedded.last()), false)
        else if (failure != null) throw failure
    }
    check(scope == api.imageCacheScope()) { "账号已变化" }
    return result.copy(rows = result.rows.filter { visibleReply(it) && (!authorOnly || author.isNotEmpty() && replyAuthor(it).uid == author) }
        .map { if (it.text("entityType") == "feed_reply" && it.text("feedid") == id && it.text("id").isNotEmpty()) it else normalizeReply(it, id) })
}
