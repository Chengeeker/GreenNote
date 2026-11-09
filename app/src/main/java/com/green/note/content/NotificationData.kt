package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import java.net.URI
import java.net.URLDecoder

internal data class NotificationTarget(val feedId: String = "", val replyId: String = "", val url: String = "")
internal data class NotificationActor(val name: String, val uid: String, val avatar: String)
internal data class NotificationText(val sender: String, val action: String, val content: String, val system: Boolean)
internal fun notificationData(root: JSONObject): JSONObject = when (val data = root.opt("data")) {
    is JSONObject -> data
    is JSONArray -> data.optJSONObject(0) ?: JSONObject()
    else -> root
}
internal fun notificationActor(item: JSONObject, path: String): NotificationActor {
    val like = path.endsWith("/feedLikeList")
    val user = if (like) item.optJSONObject("likeUserInfo") else item.optJSONObject("fromUserInfo") ?: item.optJSONObject("userInfo")
    return NotificationActor((if (like) item.text("likeUsername") else item.text("fromusername", "username")).ifEmpty { user?.text("username").orEmpty() },
        (if (like) item.text("likeUid", "likeuid") else item.text("fromuid", "uid")).ifEmpty { user?.text("uid").orEmpty() },
        (if (like) item.text("likeAvatar", "likeUserAvatar") else item.text("fromUserAvatar", "userAvatar")).ifEmpty { user?.text("userAvatar").orEmpty() })
}
internal fun notificationText(item: JSONObject, path: String): NotificationText {
    val actor = notificationActor(item, path)
    val like = path.endsWith("/feedLikeList")
    val system = !like && actor.name.isEmpty() && actor.uid in setOf("", "0")
    val note = item.text("note", "infoHtml", "description")
    val fragment = Jsoup.parseBodyFragment(note).body()
    fragment.selectFirst("a")?.takeIf { actor.name.isNotEmpty() && it.text().trim() == actor.name }?.remove()
    var content = fragment.html().trim()
    var action = Regex("^(评论了你的动态|回复了你的评论|回复了你|在动态中提到了你|在评论中提到了你|提到了你|赞了你的动态|赞了你的评论|关注了你)").find(fragment.text().trim())?.value.orEmpty()
    if (action.isNotEmpty()) content = content.replaceFirst(action, "").replaceFirst(Regex("^[\\s：:]+"), "")
    if (item.text("message").isNotEmpty()) content = item.text("message")
    if (content.isEmpty() && action.isEmpty()) content = note
    val body = Jsoup.parseBodyFragment(content).body()
    body.select("a[href]").filter { Regex("/feed/[1-9][0-9]*").containsMatchIn(it.attr("href")) }.forEach { it.unwrap() }
    content = body.html()
    if (like) { val type = Jsoup.parseBodyFragment(item.text("feedTypeName", "infoHtml")).text(); action = "赞了你的${type.ifEmpty { "动态" }}"; content = item.text("message") }
    if (action.isEmpty() && path.contains("contactsFollowList")) action = "关注了你"
    return NotificationText(if (system) "系统消息" else actor.name.ifEmpty { "酷友" }, action, content, system)
}
internal fun notificationTarget(data: JSONObject): NotificationTarget {
    val target = data.optJSONObject("targetRow") ?: JSONObject()
    val feed = data.optJSONObject("feedInfo") ?: data.optJSONObject("targetFeed") ?: JSONObject()
    var feedId = ""; var replyId = ""; var url = ""
    for (source in listOf(data, target, feed)) {
        for (field in listOf("note", "message", "infoHtml", "url", "targetUrl")) {
            val value = source.text(field).replace("&amp;", "&")
            val links = Jsoup.parseBodyFragment(value).select("a[href]").map { it.attr("href") }.toMutableList()
            if (field in setOf("url", "targetUrl")) links += value
            for (link in links) {
                if (link.isEmpty() || link.length > 8192) continue
                val uri = runCatching { URI(link) }.getOrNull() ?: continue
                if (uri.userInfo != null) continue
                if (url.isEmpty() && uri.scheme in setOf("http", "https")) url = link
                val official = uri.scheme == "coolmarket" || uri.rawAuthority == null && link.startsWith('/') || uri.host?.let { it == "coolapk.com" || it.endsWith(".coolapk.com") } == true
                if (!official) continue
                if (url.isEmpty()) url = link
                val path = if (uri.scheme == "coolmarket") "/${uri.host.orEmpty()}${uri.path.orEmpty()}" else uri.path.orEmpty()
                val foundFeed = Regex("/feed/([1-9][0-9]*)(?:/|$)").find(path)?.groupValues?.get(1)
                if (feedId.isEmpty() && foundFeed != null) { feedId = foundFeed; url = link }
                val params = uri.rawQuery.orEmpty().split('&').mapNotNull { part ->
                    val parts = part.split('=', limit = 2)
                    runCatching { URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8") }.getOrNull()
                }.toMap()
                val reply = listOf("rrid", "rid", "replyId", "reply_id").firstNotNullOfOrNull(params::get)
                    ?: Regex("(?:/feed/reply/|/reply/)([1-9][0-9]*)").find(path)?.groupValues?.get(1).orEmpty()
                if (replyId.isEmpty() && reply.matches(Regex("[1-9][0-9]*"))) { replyId = reply; url = link }
            }
        }
        if (replyId.isEmpty()) replyId = source.text("replyId", "reply_id")
        if (replyId.isEmpty() && source.text("entityType") == "feed_reply") replyId = source.text("id")
        if (feedId.isEmpty()) feedId = source.text("feedId", "feed_id", "fid")
        if (feedId.isEmpty() && source.text("entityType") == "feed") feedId = source.text("id")
    }
    if (feedId.isEmpty()) feedId = feed.text("id")
    if (replyId.isEmpty() && Regex("reply|comment").containsMatchIn(data.text("targetType", "target_type"))) replyId = data.text("targetId", "target_id")
    return NotificationTarget(feedId.takeIf { it.matches(Regex("[1-9][0-9]*")) }.orEmpty(), replyId.takeIf { it.matches(Regex("[1-9][0-9]*")) }.orEmpty(), url)
}

internal suspend fun clearInboxNotifications(api: ContentApi, owner: String): Int {
    val ids = linkedSetOf<String>()
    val repository = ContentRepository(api)
    var first = ""; var last = ""; var page = 1
    fun checkOwner() { check(owner == api.imageCacheScope()) { "登录账号已改变，请重新打开通知中心" } }
    while (true) {
        check(page <= 100) { "通知超过单次处理范围，未执行删除" }; checkOwner()
        val response = repository.page(ContentRequest("/v6/notification/list"), page, first, last)
        checkOwner()
        val before = ids.size
        response.rows.forEach { item -> val id = item.text("id", "notificationId", "nid"); check(id.matches(Regex("[1-9][0-9]*"))) { "通知标识无效，未执行清除" }; ids += id }
        if (!response.more || response.rows.isEmpty()) break
        check(before != ids.size) { "通知分页重复，未执行清除" }
        if (response.first.isNotEmpty()) first = response.first
        last = response.last; page++
    }
    for (id in ids) { checkOwner(); api.request("/v6/notification/delete", "POST", mapOf("id" to id)); checkOwner() }
    return ids.size
}
