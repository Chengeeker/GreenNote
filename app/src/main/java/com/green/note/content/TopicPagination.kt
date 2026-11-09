package com.green.note.content

import com.green.note.network.CaptchaRequired
import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import kotlin.math.roundToLong

internal fun topicHeat(row: JSONObject): Long {
    if (row.text("is_top", "istop", "isTop") in setOf("1", "true")) return 1_000_000_000
    fun count(vararg keys: String): Long {
        val text = row.text(*keys).lowercase().trim(); val multiplier = when { text.endsWith("万") || text.endsWith("w") -> 10_000; text.endsWith("k") -> 1000; else -> 1 }
        return ((if (multiplier == 1) text else text.dropLast(1)).toDoubleOrNull()?.takeIf(Double::isFinite)?.times(multiplier) ?: 0.0).roundToLong()
    }
    val rank = row.text("rank_score", "heat").toDoubleOrNull()?.takeIf(Double::isFinite) ?: 0.0
    return (rank * 10).roundToLong() + count("likenum", "likeNum", "like_num") * 2 + count("replynum", "replyNum", "reply_num", "commentnum") * 3 + count("favnum", "favNum", "fav_num") * 2 + count("forwardnum", "forwardNum", "forward_num", "share_num") * 3
}

internal fun topicFeedComparator(hot: Boolean): Comparator<JSONObject> = Comparator { a, b ->
    val topA = a.text("is_top", "istop", "isTop") in setOf("1", "true"); val topB = b.text("is_top", "istop", "isTop") in setOf("1", "true")
    when { topA != topB -> if (topA) -1 else 1; hot && topicHeat(a) != topicHeat(b) -> topicHeat(b).compareTo(topicHeat(a)); else -> (b.text("dateline").toLongOrNull() ?: 0).compareTo(a.text("dateline").toLongOrNull() ?: 0) }
}

internal suspend fun topicPage(api: ContentApi, request: ContentRequest, page: Int, first: String, last: String): ContentPage {
    val repo = ContentRepository(api); val owner = api.imageCacheScope()
    val hot = request.query["listType"] in setOf("hot", "hot_desc", "rank_score") || request.query["sort"] == "hot"
    var result = repo.page(request, page, first, last)
    if (hot && page == 1 && result.more && result.last.isNotEmpty()) {
        try { val second = repo.page(request, 2, result.first, result.last); if (second.rows.isNotEmpty()) result = second.copy(rows = (result.rows + second.rows).distinctBy(::entityKey), first = result.first) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { if (error is CaptchaRequired || owner != api.imageCacheScope()) throw error }
    }
    check(owner == api.imageCacheScope()) { "账号已切换" }
    return if (hot || request.query["listType"] == "dateline_desc") result.copy(rows = result.rows.sortedWith(topicFeedComparator(hot))) else result
}
