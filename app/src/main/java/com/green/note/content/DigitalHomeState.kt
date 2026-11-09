package com.green.note.content

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** One retained default-channel state; no disk cache, extra channels or image-download gate. */
internal class DigitalHomeState(private val api: ContentApi, private val session: ContentSession) {
    val content = ContentListState()
    private val repository = ContentRepository(api)

    suspend fun bind(sorting: Pair<String, String>?) {
        val request = contentRequest(sorting?.first ?: "V10_DIGITAL_HOME")
        content.bind(request to sorting) { page, first, last ->
            val result = repository.page(request, page, first, last)
            withContext(Dispatchers.Default) {
                val cards = result.rows.toMutableList()
                if (page == 1) {
                    val old = cards.firstOrNull { it.text("title") == "我的关注" || it.text("entityTemplate").contains("follow", true) }
                    cards.remove(old)
                    val pending = session.anonymous || session.authenticated && old == null
                    val followed = if (session.authenticated) old?.optJSONArray("entities").objects() else emptyList()
                    cards.add(0, JSONObject().put("entityType", "card").put("entityTemplate", "followCard")
                        .put("title", "我的关注").put("entities", JSONArray(followed))
                        .put("_digitalFollowPending", pending).put("_emptyText", if (pending) "加载中…" else ""))
                }
                val previous = content.rows
                val sortIndex = previous.indexOfFirst { it.text("title").contains("动态区") || it.text("entityTemplate").equals("sortSelectCard", true) }
                val prefix = if (sorting != null && page == 1 && sortIndex >= 0) previous.take(sortIndex + 1) else emptyList()
                val rows = if (prefix.isEmpty()) cards else prefix + cards.filterNot { row ->
                    row.text("entityTemplate").equals("sortSelectCard", true) && prefix.any { it.text("entityTemplate").equals("sortSelectCard", true) }
                }
                result.copy(rows = normalizeSpecializedCards(rows.map { JSONObject(it.toString())
                    .put("_composeCardContext", "digital_home").put("_selectedSortTitle", sorting?.second.orEmpty())
                    .put("_composeSelectedRoute", sorting?.first.orEmpty()) }))
            }
        }
    }

    suspend fun resolveFollow(expected: JSONObject) {
        var failure = ""
        val followed = try {
            if (session.anonymous) api.localLibrary("productFollows")
            else repository.page(ContentRequest("/v6/page/dataList", mapOf("url" to "#/product/followProductList")), 1)
                .rows.filter { it.text("entityType") == "product" }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { failure = "关注加载失败，点击重试"; emptyList() }
        content.replaceRow(expected, JSONObject(expected.toString()).put("entities", JSONArray(followed))
            .put("_digitalFollowPending", false).put("_emptyText", "").put("_followError", failure))
    }
}

/** Hosted by ContentApp, outside the selected page: switching tabs does not cancel first-page work. */
@Composable
internal fun rememberDigitalHomeState(api: ContentApi, session: ContentSession, sorting: Pair<String, String>?): ContentListState {
    val owner = api.imageCacheScope()
    val retained = remember(api, owner) { DigitalHomeState(api, session) }
    LaunchedEffect(retained, sorting) { retained.bind(sorting) }
    val follow = retained.content.rows.firstOrNull { it.optBoolean("_digitalFollowPending") }
    LaunchedEffect(retained, follow) { if (follow != null) retained.resolveFollow(follow) }
    return retained.content
}
