package com.green.note.media

import android.graphics.Bitmap
import android.graphics.BitmapRegionDecoder
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import coil.disk.DiskCache
import coil.imageLoader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.floor

private data class OriginalTile(val bitmap: Bitmap, val region: android.graphics.Rect, val width: Int, val height: Int)
private class OriginalRegions(private val snapshot: DiskCache.Snapshot, private val decoder: BitmapRegionDecoder) {
    private val lock = Any()
    private val closed = AtomicBoolean(false)
    fun tile(viewport: IntSize, zoom: Float, offset: Offset): OriginalTile? = synchronized(lock) {
        if (closed.get() || viewport.width <= 0 || viewport.height <= 0) return@synchronized null
        val width = decoder.width; val height = decoder.height
        val factor = minOf(viewport.width.toFloat() / width, viewport.height.toFloat() / height) * zoom
        val left = (viewport.width - width * factor) / 2 + offset.x
        val top = (viewport.height - height * factor) / 2 + offset.y
        val region = android.graphics.Rect(floor(-left / factor).toInt().coerceIn(0, width - 1), floor(-top / factor).toInt().coerceIn(0, height - 1),
            ceil((viewport.width - left) / factor).toInt().coerceIn(1, width), ceil((viewport.height - top) / factor).toInt().coerceIn(1, height))
        if (region.width() <= 0 || region.height() <= 0) return@synchronized null
        var sample = 1
        while (factor * sample * 2 <= 1f || region.width().toLong() * region.height() / sample / sample > 6_000_000) sample *= 2
        val bitmap = decoder.decodeRegion(region, android.graphics.BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }) ?: return@synchronized null
        OriginalTile(bitmap, region, width, height)
    }
    fun close() { if (closed.compareAndSet(false, true)) cleanup.execute { synchronized(lock) { decoder.recycle(); snapshot.close() } } }
    companion object {
        private val cleanup = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "gallery-region-cleanup").apply { isDaemon = true } }
        fun open(snapshot: DiskCache.Snapshot): OriginalRegions? = try {
            @Suppress("DEPRECATION") val decoder = BitmapRegionDecoder.newInstance(snapshot.data.toFile().path, false)
            if (decoder == null) { snapshot.close(); null } else OriginalRegions(snapshot, decoder)
        } catch (_: Exception) { snapshot.close(); null }
    }
}

/** Decodes only visible original pixels. Long-image zoom never allocates the whole original. */
@Composable
internal fun TiledOriginalImage(url: String, cacheScope: String, loaded: Boolean, enabled: Boolean, viewport: IntSize, zoom: Float, offset: Offset, modifier: Modifier) {
    if (!loaded || !enabled || zoom <= 1.05f || url.contains(".gif", true)) return
    val context = LocalContext.current
    var source by remember(url, cacheScope) { mutableStateOf<OriginalRegions?>(null) }
    var tile by remember(url, cacheScope) { mutableStateOf<OriginalTile?>(null) }
    LaunchedEffect(url, cacheScope) {
        var candidate: OriginalRegions? = null
        try {
            candidate = withContext(Dispatchers.IO) {
                val cache = context.imageLoader.diskCache ?: return@withContext null
                val snapshot = cache.openSnapshot("$cacheScope|$url") ?: cache.openSnapshot("$cacheScope:$url") ?: return@withContext null
                OriginalRegions.open(snapshot).also { candidate = it }
            }
            source = candidate
        } catch (cancelled: CancellationException) { candidate?.close(); throw cancelled }
    }
    DisposableEffect(source) { val owner = source; onDispose { owner?.close() } }
    LaunchedEffect(source, viewport, zoom, offset) {
        val owner = source ?: return@LaunchedEffect
        try { tile = withContext(Dispatchers.IO) { owner.tile(viewport, zoom, offset) } }
        catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Keep the base image if region decoding is unsupported. */ }
    }
    tile?.let { value -> Canvas(modifier) {
        val factor = minOf(size.width / value.width, size.height / value.height) * zoom
        val left = (size.width - value.width * factor) / 2 + offset.x + value.region.left * factor
        val top = (size.height - value.height * factor) / 2 + offset.y + value.region.top * factor
        drawImage(value.bitmap.asImageBitmap(), dstOffset = IntOffset(left.toInt(), top.toInt()), dstSize = IntSize((value.region.width() * factor).toInt().coerceAtLeast(1), (value.region.height() * factor).toInt().coerceAtLeast(1)))
    } }
}
