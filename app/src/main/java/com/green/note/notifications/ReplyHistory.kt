package com.green.note.notifications

import okio.ByteString.Companion.encodeUtf8
import org.json.JSONArray
import org.json.JSONObject

data class ReplyItem(val data: JSONObject) {
    private fun first(vararg keys: String): Any? = keys.firstNotNullOfOrNull { data.opt(it)?.takeUnless { value -> value == JSONObject.NULL } }
    val id: String = first("id", "notificationId", "nid")?.toString()?.takeIf { it.isNotEmpty() && it != "0" } ?: JSONArray(listOf(
            first("uid", "fromuid"), first("dateline", "lastupdate"),
            first("note", "message", "description"), first("url"),
        )).toString().encodeUtf8().sha256().hex()
    val timestamp: Long = first("dateline", "lastupdate", "timestamp")
        ?.toString()?.toLongOrNull()?.let { if (it > 100000000000) it / 1000 else it.coerceAtLeast(0) } ?: 0
    val preview: String get() {
        val plain = org.jsoup.Jsoup.parseBodyFragment(first("note", "message", "description")?.toString().orEmpty()).text().replace(Regex("\\s+"), " ").trim()
        return plain.substring(0, plain.offsetByCodePoints(0, minOf(160, plain.codePointCount(0, plain.length))))
    }

    companion object {
        fun parse(root: JSONObject): List<ReplyItem> {
            val data = root.opt("data")
            val raw = if (data is JSONObject) data.opt("list") ?: data.opt("items") ?: data.opt("data") else data
            require(raw is JSONArray && (0 until raw.length()).all { raw.opt(it) is JSONObject }) { "回复通知数据格式无效" }
            // shortcut: only the latest page is checked; paginate if high-volume accounts need full catch-up.
            return (0 until minOf(raw.length(), 50)).map { ReplyItem(raw.getJSONObject(it)) }
        }
    }
}

data class ReplyHistory(val scope: String = "", val seen: List<String> = emptyList(), val watermark: Long = 0) {
    fun merge(current: String, items: List<ReplyItem>): Pair<ReplyHistory, List<ReplyItem>> {
        val same = scope.isNotEmpty() && scope == current
        val known = if (same) seen.toMutableSet() else mutableSetOf()
        val fresh = mutableListOf<ReplyItem>()
        var newest = if (same) watermark else 0L
        for (item in items) {
            if (same && item.id !in known && (item.timestamp == 0L || item.timestamp >= watermark)) fresh += item
            known += item.id
            newest = maxOf(newest, item.timestamp)
        }
        val ordered = ((if (same) seen else emptyList()) + items.asReversed().map { it.id }).distinct().takeLast(200)
        return ReplyHistory(current, ordered, newest) to fresh
    }
    fun json() = JSONObject().put("scope", scope).put("seen", JSONArray(seen)).put("watermark", watermark)
    companion object {
        fun parse(root: JSONObject): ReplyHistory {
            val seen = root.optJSONArray("seen") ?: JSONArray()
            return ReplyHistory(root.optString("scope"), (0 until minOf(seen.length(), 200)).mapNotNull { seen.opt(it) as? String }, root.optLong("watermark"))
        }
    }
}
