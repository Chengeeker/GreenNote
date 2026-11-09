package com.green.note.media

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.widget.ImageView
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import coil.imageLoader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import kotlin.math.sqrt

internal object HdrImageDetection {
    fun hasMetadata(bytes: ByteArray): Boolean {
        if (bytes.size < 16) return false
        val header = String(bytes, 0, minOf(bytes.size, 131072), Charsets.ISO_8859_1).lowercase()
        return listOf("hdrgm", "gainmap", "21496:1", "21496:-1", "hdr-gain-map", "ultrahdr").any(header::contains)
    }
}

object HdrImageRegistry {
    private val mutable = kotlinx.coroutines.flow.MutableStateFlow<Set<String>>(emptySet())
    val known: kotlinx.coroutines.flow.StateFlow<Set<String>> = mutable
    @Synchronized fun mark(url: String) {
        val normalized = com.green.note.network.normalizeNetworkImageUrl(url).takeIf { it.isNotEmpty() } ?: return
        mutable.value = (mutable.value.filterNot { it == normalized }.takeLast(255) + normalized).toSet()
    }
    @Synchronized fun clear() { mutable.value = emptySet() }
}

private fun Context.hdrActivity(): Activity? = when (this) { is Activity -> this; is ContextWrapper -> baseContext.hdrActivity(); else -> null }

/** Android's ImageView preserves Ultra HDR gain maps which a flattened SDR bitmap cannot. */
@Composable
internal fun NativeHdrImage(url: String, cacheScope: String, sourceLoaded: Boolean, active: Boolean, modifier: Modifier, onHdr: (Boolean) -> Unit) {
    if (Build.VERSION.SDK_INT < 34 || !sourceLoaded || !active) return
    val context = LocalContext.current
    var decoded by remember(url, cacheScope) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(url, cacheScope, sourceLoaded) {
        try {
            decoded = withContext(Dispatchers.IO) {
                val cache = context.imageLoader.diskCache ?: return@withContext null
                val snapshot = cache.openSnapshot("$cacheScope|$url") ?: cache.openSnapshot("$cacheScope:$url") ?: return@withContext null
                snapshot.use {
                    val path = it.data.toFile()
                    if (path.length() !in 16..(64L * 1024 * 1024)) return@withContext null
                    val header = path.inputStream().use { input -> val bytes = ByteArray(minOf(path.length(), 131072).toInt()); var read = 0; while (read < bytes.size) { val count = input.read(bytes, read, bytes.size - read); if (count <= 0) break; read += count }; bytes.copyOf(read) }
                    if (!HdrImageDetection.hasMetadata(header)) return@withContext null
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(path)) { decoder, info, _ ->
                        decoder.allocator = ImageDecoder.ALLOCATOR_HARDWARE
                        decoder.isMutableRequired = false
                        val pixels = info.size.width.toLong() * info.size.height
                        if (pixels > 24_000_000) { val ratio = sqrt(24_000_000.0 / pixels); decoder.setTargetSize((info.size.width * ratio).toInt().coerceAtLeast(1), (info.size.height * ratio).toInt().coerceAtLeast(1)) }
                    }.takeIf { bitmap -> bitmap.hasGainmap() }
                }
            }
            onHdr(decoded != null)
            if (decoded != null) HdrImageRegistry.mark(url)
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { onHdr(false) }
    }
    decoded?.let { bitmap ->
        val activity = context.hdrActivity()
        DisposableEffect(activity, bitmap) {
            val original = activity?.window?.colorMode
            activity?.window?.colorMode = ActivityInfo.COLOR_MODE_HDR
            onDispose { original?.let { activity.window.colorMode = it } }
        }
        AndroidView(factory = { ImageView(it).apply { isForceDarkAllowed = false; scaleType = ImageView.ScaleType.FIT_CENTER; setBackgroundColor(android.graphics.Color.TRANSPARENT) } },
            modifier = modifier, update = { it.setImageBitmap(bitmap) }, onRelease = { it.setImageDrawable(null) })
    }
}
