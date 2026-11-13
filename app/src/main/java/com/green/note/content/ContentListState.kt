package com.green.note.content

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.green.note.network.CaptchaRequired
import com.green.note.network.UnsupportedCaptcha
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONObject

@Stable
internal class ContentListState(initialRows: List<JSONObject> = emptyList(), private var loader: ContentPageLoader? = null) {
    var rows by mutableStateOf(initialRows)
        private set
    var busy by mutableStateOf(false)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var verifying by mutableStateOf(false)
        private set
    private var failure by mutableStateOf<Exception?>(null)
    val error get() = failure?.let { it.message ?: "加载失败，请重试" }
    val accessRestricted get() = failure is CaptchaRequired || isContentAccessError(error)
    val captchaRequired get() = failure is CaptchaRequired || failure is UnsupportedCaptcha
    val verificationChallenge get() = (failure as? CaptchaRequired)?.takeIf { it.canVerifyComment }
    var pendingReplyCount by mutableStateOf(0)
        private set
    var more by mutableStateOf(true)
        private set
    var appliedSource by mutableStateOf<Any?>(null)
        private set
    private var page = 0
    val needsInitialLoad get() = page == 0
    private var first = ""
    private var last = ""
    private var source: Any? = null
    private var pendingLoader: ContentPageLoader? = null
    private var generation = 0
    private var retryPage: IncompletePage? = null

    private data class PageRequest(
        val page: Int, val first: String, val last: String, val restart: Boolean,
        val load: ContentPageLoader, val replacement: ContentPageLoader?,
    )
    private data class IncompletePage(val request: PageRequest, val provisionalKeys: Set<String> = emptySet())

    fun remove(row: JSONObject) {
        val key = entityKey(row)
        rows = rows.filterNot { entityKey(it) == key }
    }

    /** Only hydrate the exact retained card; a refresh/source replacement must win over late work. */
    fun replaceRow(expected: JSONObject, replacement: JSONObject) {
        if (rows.none { it === expected }) return
        rows = rows.map { if (it === expected) replacement else it }
    }

    suspend fun bind(newSource: Any, loadPage: ContentPageLoader) {
        if (source == newSource) {
            if (pendingLoader != null && error == null) load()
            return
        }
        source = newSource
        pendingLoader = loadPage
        retryPage = null
        pendingReplyCount = 0
        generation++
        busy = false
        verifying = false
        load()
    }

    /** Verification is exclusively user initiated; it resumes the saved page, never the next page. */
    suspend fun verify(api: ContentApi) {
        val challenge = verificationChallenge ?: return
        if (busy) return
        val requestGeneration = generation
        busy = true
        verifying = true
        try {
            api.verifyCommentRequest(challenge)
            currentCoroutineContext().ensureActive()
            if (requestGeneration != generation) return
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) {
            if (requestGeneration == generation) failure = error
            return
        } finally {
            if (requestGeneration == generation) { busy = false; verifying = false }
        }
        if (requestGeneration == generation) load()
    }

    suspend fun load(refresh: Boolean = false) {
        if (busy) return
        val incomplete = retryPage.takeUnless { refresh }
        val replacement = pendingLoader
        val loadPage = replacement ?: loader ?: return
        val restart = refresh || replacement != null
        if (incomplete == null && !restart && !more) return
        val request = incomplete?.request ?: PageRequest(
            if (restart) 1 else page + 1, if (restart) "" else first, if (restart) "" else last,
            restart, loadPage, replacement,
        )
        val requestGeneration = generation
        retryPage = incomplete ?: IncompletePage(request)
        busy = true
        refreshing = refresh
        failure = null
        try {
            val result = request.load(request.page, request.first, request.last)
            currentCoroutineContext().ensureActive()
            if (requestGeneration != generation) return
            var added: Set<String>
            while (true) {
                val prior = rows
                val replaceSource = request.replacement != null && appliedSource != source && result.rows.isNotEmpty()
                val prepared = withContext(Dispatchers.Default) {
                    val incoming = result.rows.distinctBy(::entityKey)
                    val previousPartial = incomplete?.provisionalKeys.orEmpty()
                    val base = when {
                        request.restart && (result.error == null || replaceSource) -> emptyList()
                        request.restart -> prior
                        else -> prior.filterNot { entityKey(it) in previousPartial }
                    }
                    val baseKeys = base.map(::entityKey).toSet()
                    val extraKeys = incoming.map(::entityKey).filterNot { it in baseKeys }.toSet()
                    val incomingByKey = incoming.associateBy(::entityKey)
                    val merged = if (request.restart) {
                        // A refresh can preserve readable old rows until the replacement page completes.
                        incoming + base.filterNot { entityKey(it) in incomingByKey }
                    } else {
                        val ordered = base.map { incomingByKey[entityKey(it)] ?: it } + incoming.filter { entityKey(it) !in baseKeys }
                        // Keep prior successes while retrying; a complete page supplies authoritative order.
                        if (result.error == null) ordered else ordered + prior.filter {
                            val key = entityKey(it)
                            key in previousPartial && key !in incomingByKey
                        }
                    }
                    extraKeys to merged
                }
                currentCoroutineContext().ensureActive()
                if (requestGeneration != generation) return
                // A removal or hydration may run while the page is prepared off the UI thread.
                if (rows !== prior) continue
                added = prepared.first
                rows = prepared.second
                break
            }
            if (request.replacement != null && result.rows.isNotEmpty()) appliedSource = source
            pendingReplyCount = result.pendingReplyCount
            if (result.error != null) {
                retryPage = IncompletePage(request, incomplete?.provisionalKeys.orEmpty() + added)
                failure = result.error
                return
            }
            page = result.page
            first = result.first.ifEmpty { if (request.restart) "" else first }
            last = result.last
            more = result.more && result.rows.isNotEmpty() && (request.restart || added.isNotEmpty())
            retryPage = null
            if (request.replacement != null) {
                loader = request.replacement
                pendingLoader = null
                appliedSource = source
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { if (requestGeneration == generation) failure = error }
        finally { if (requestGeneration == generation) { busy = false; refreshing = false } }
    }
}

internal typealias ContentPageLoader = suspend (Int, String, String) -> ContentPage
