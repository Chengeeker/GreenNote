package com.green.note.content

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.util.concurrent.atomic.AtomicLong

private val topicCacheRevision = AtomicLong()
fun clearPreparedTopics() { topicCacheRevision.incrementAndGet() }

internal data class PreparedTopic(val detail: JSONObject, var firstPage: ContentPage?, val firstRoute: String)
internal val LocalTopicPreparation = staticCompositionLocalOf<TopicPreparation?> { null }

/** Session-owned memory snapshots. Opening does not consume them or start an expiry timer. */
internal class TopicPreparation(private val api: ContentApi, private val scope: CoroutineScope, private val warmImage: suspend (String) -> Unit = {}) {
    private val pending = LinkedHashMap<String, Deferred<PreparedTopic>>()
    private val gate = Semaphore(1)
    private var owner = api.imageCacheScope()
    private var revision = topicCacheRevision.get()

    @OptIn(ExperimentalCoroutinesApi::class)
    @Synchronized fun ready(tag: String): PreparedTopic? = if (owner != api.imageCacheScope() || revision != topicCacheRevision.get()) null else pending[tag]?.takeIf { it.isCompleted && !it.isCancelled }?.let { runCatching { it.getCompleted() }.getOrNull() }

    @Synchronized fun prepare(tag: String, refresh: Boolean = false): Deferred<PreparedTopic> {
        val session = api.imageCacheScope(); val epoch = topicCacheRevision.get()
        if (owner != session || revision != epoch) { val stale = pending.values.toList(); pending.clear(); stale.forEach { it.cancel() }; owner = session; revision = epoch }
        if (!refresh) pending.remove(tag)?.let { pending[tag] = it; return it }
        else pending.remove(tag)?.cancel()
        val work = CompletableDeferred<PreparedTopic>()
        val task = scope.launch(start = CoroutineStart.LAZY) {
            try { work.complete(gate.withPermit {
                fun checkOwner() { check(session == api.imageCacheScope() && epoch == topicCacheRevision.get()) { "账号或缓存已变化，请重新打开话题" } }
                checkOwner()
                val response = api.request("/v6/topic/newTagDetail", query = mapOf("tag" to tag))
                val detail = response.optJSONObject("data") ?: response
                checkOwner(); check(detail.length() > 0) { "话题数据为空" }
                val tabs = detail.optJSONArray("tabList").objects()
                val activity = tabs.any { it.text("title") in setOf("活动详情", "有奖活动") } || tag == "人像摄影"
                val selected = tabs.firstOrNull { it.text("page_name") == detail.text("selectedTab") } ?: tabs.firstOrNull()
                val route = if (activity) selected?.text("url").orEmpty() else ""
                val image = async { withTimeoutOrNull(900) { try { warmImage(detail.text("logo")) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {} } }
                val page = if (route.isNotEmpty() && !isActivityDocument(route)) ContentRepository(api).page(contentRequest(route), 1, "", "") else null
                image.await(); checkOwner()
                PreparedTopic(JSONObject(detail.toString()), page, route)
            }) } catch (cancelled: CancellationException) { work.cancel(cancelled) } catch (failure: Exception) { work.completeExceptionally(failure) }
        }
        pending[tag] = work
        while (pending.size > 12) pending.remove(pending.keys.first())
        work.invokeOnCompletion { failure -> if (failure != null) { task.cancel(); synchronized(this) { if (pending[tag] === work) pending.remove(tag) } } }
        task.invokeOnCompletion { if (!work.isCompleted) work.cancel() }
        task.start(); return work
    }

    @Synchronized fun following(tag: String, following: Boolean) {
        if (owner != api.imageCacheScope() || revision != topicCacheRevision.get()) return
        val work = pending[tag] ?: return
        scope.launch { try { val item = work.await(); synchronized(this@TopicPreparation) { if (pending[tag] === work) item.detail.put("userAction", (item.detail.optJSONObject("userAction") ?: JSONObject()).put("follow", if (following) 1 else 0)) } } catch (_: CancellationException) {} catch (_: Exception) {} }
    }

    @Synchronized fun rememberPage(tag: String, route: String, page: ContentPage) {
        if (owner != api.imageCacheScope() || revision != topicCacheRevision.get()) return
        val work = pending[tag] ?: return
        scope.launch { try { val item = work.await(); synchronized(this@TopicPreparation) { if (pending[tag] === work && item.firstRoute == route) item.firstPage = page } } catch (_: CancellationException) {} catch (_: Exception) {} }
    }
}

internal fun carouselTopicTag(row: JSONObject): String {
    val route = row.text("url")
    val uri = runCatching { URI(route) }.getOrNull()
    val path = uri?.path.orEmpty()
    val routeTag = when { path.contains("/t/") -> path.substringAfter("/t/"); path.startsWith("/topic/") -> path.removePrefix("/topic/"); else -> "" }.substringBefore('/').replace("#", "").trim().takeUnless { it.toLongOrNull() != null }.orEmpty()
    val queryTag = uri?.rawQuery.orEmpty().split('&').firstOrNull { it.startsWith("tag=") }?.substringAfter('=').orEmpty()
    val type = row.text("entityType", "entity_type").lowercase()
    return (routeTag.ifEmpty { runCatching { URLDecoder.decode(queryTag, "UTF-8") }.getOrDefault("") }.ifEmpty {
        if (type.contains("topic") || type.contains("tag")) sequenceOf("tag", "tagName", "title", "name").map { row.text(it) }.firstOrNull { it.isNotEmpty() && it.toLongOrNull() == null }.orEmpty() else ""
    }).replace("#", "").trim()
}

@Composable
internal fun WarmCurrentTopic(row: JSONObject) {
    val cache = LocalTopicPreparation.current ?: return
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val tag = carouselTopicTag(row)
    LaunchedEffect(cache, tag, lifecycle) {
        if (tag.isNotEmpty()) lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            try { cache.prepare(tag).await() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {}
            awaitCancellation()
        }
    }
}
