package com.green.note.media

import android.graphics.drawable.Drawable
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import coil.ImageLoader
import coil.request.ImageRequest
import coil.request.CachePolicy
import coil.request.SuccessResult
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Headers.Companion.toHeaders

/** One encoded fetch per identity; cancellation only stops work after its last reader leaves. */
internal class GalleryRequestPool<K, V>(private val scope: CoroutineScope, private val capacity: Int = 12) {
    private data class Entry<V>(val value: Deferred<Result<V>>, var readers: Int = 0)
    private val lock = Mutex()
    private val entries = linkedMapOf<K, Entry<V>>()
    suspend fun load(key: K, fetch: suspend () -> V): V {
        val entry = lock.withLock {
            val value = entries.remove(key)?.takeUnless { it.value.isCancelled }
                ?: Entry(scope.async(Dispatchers.IO, start = CoroutineStart.LAZY) {
                    // Do not let an individual image failure cancel a regular parent Job.
                    try { Result.success(fetch()) }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: Exception) { Result.failure(failure) }
                })
            value.readers++
            entries[key] = value
            value
        }
        var failed = false
        try { val result = entry.value.await(); failed = result.isFailure; return result.getOrThrow() }
        finally { withContext(NonCancellable) { lock.withLock {
            entry.readers--
            if (entry.readers == 0 && (!entry.value.isCompleted || entry.value.isCancelled || failed)) {
                entry.value.cancel()
                if (entries[key] === entry) entries.remove(key)
            }
            while (entries.size > capacity) {
                val unused = entries.entries.firstOrNull { it.value.readers == 0 } ?: break
                unused.value.value.cancel(); entries.remove(unused.key)
            }
        } } }
    }
}

internal data class GalleryPreview(val drawable: Drawable? = null, val error: Throwable? = null)
internal data class GalleryRequestIdentity(val scope: String, val url: String, val headers: List<Pair<String, String>>, val retry: Int)

@Composable
internal fun galleryPreview(url: String, cacheScope: String, headers: Map<String, String>, retry: Int,
                            loader: ImageLoader, pool: GalleryRequestPool<GalleryRequestIdentity, Drawable>, enabled: Boolean = true): State<GalleryPreview> {
    val context = LocalContext.current
    val identity = remember(url, cacheScope, headers, retry) {
        GalleryRequestIdentity(cacheScope, url, headers.entries.map { it.key.lowercase() to it.value }.sortedBy { it.first }, retry)
    }
    return produceState(GalleryPreview(), identity, loader, pool, enabled) {
        value = GalleryPreview()
        if (!enabled) return@produceState
        try {
            val drawable = pool.load(identity) {
                val request = ImageRequest.Builder(context).data(url).size(160, 160)
                    .memoryCacheKey("$cacheScope|preview|$url").diskCacheKey("$cacheScope|$url")
                    .headers(headers.toHeaders()).memoryCachePolicy(if (retry > 0) CachePolicy.WRITE_ONLY else CachePolicy.ENABLED).apply {
                        if (!url.substringBefore('?').endsWith(".gif", true)) addHeader("Accept", "image/jpeg,image/*;q=.8")
                    }.build()
                when (val result = loader.execute(request)) {
                    is SuccessResult -> result.drawable
                    is coil.request.ErrorResult -> throw result.throwable
                }
            }
            value = GalleryPreview(drawable)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { value = GalleryPreview(error = failure) }
    }
}
