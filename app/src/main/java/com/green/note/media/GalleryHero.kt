package com.green.note.media

import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import java.lang.ref.WeakReference

data class GalleryHeroSource(val url: String, val bounds: Rect, val bitmap: Bitmap, val crop: Boolean, val cornerRadiusPx: Float? = null)

/** In-memory display references only; never persist screenshots or account-dependent imagery. */
object GalleryHeroRegistry {
    private data class Entry(val bounds: Rect, val drawable: WeakReference<Drawable>, val crop: Boolean, val time: Long, val cornerRadiusPx: Float?)
    private val entries = linkedMapOf<String, Entry>()
    private var pressed: Pair<String, Entry>? = null
    @Synchronized fun record(url: String, bounds: Rect, drawable: Drawable, scale: ContentScale, cornerRadiusPx: Float? = null) {
        if (url.isEmpty() || bounds.width <= 0 || bounds.height <= 0) return
        entries.remove(url); entries[url] = Entry(bounds, WeakReference(drawable), scale == ContentScale.Crop, System.currentTimeMillis(), cornerRadiusPx?.coerceAtLeast(0f))
        while (entries.size > 80) entries.remove(entries.keys.first())
    }
    @Synchronized fun claim(url: String) { entries[url]?.let { pressed = url to it } }
    @Synchronized fun source(url: String, initial: Boolean = false): GalleryHeroSource? {
        val entry = if (initial && pressed?.first == url) pressed?.second else entries[url]
        if (entry == null || System.currentTimeMillis() - entry.time > 300000) return null
        val drawable = entry.drawable.get() ?: return null
        val bitmap = (drawable as? BitmapDrawable)?.bitmap ?: drawableFrame(drawable) ?: return null
        if (bitmap.isRecycled) return null
        return GalleryHeroSource(url, entry.bounds, bitmap, entry.crop, entry.cornerRadiusPx)
    }
    @Synchronized fun clear() { entries.clear(); pressed = null }

    // Animated Coil drawables have no BitmapDrawable backing. Capture only the currently
    // displayed frame for a flight, bounded to 1 MP; never decode the complete animation.
    private fun drawableFrame(drawable: Drawable): Bitmap? {
        val width = drawable.intrinsicWidth; val height = drawable.intrinsicHeight
        if (width <= 0 || height <= 0) return null
        val scale = minOf(1.0, 1024.0 / maxOf(width, height))
        val frame = Bitmap.createBitmap(maxOf(1, (width * scale).toInt()), maxOf(1, (height * scale).toInt()), Bitmap.Config.ARGB_8888)
        val before = android.graphics.Rect(drawable.bounds)
        return try {
            drawable.setBounds(0, 0, frame.width, frame.height)
            drawable.draw(android.graphics.Canvas(frame)); frame
        } catch (_: RuntimeException) { frame.recycle(); null }
        finally { drawable.bounds = before }
    }
}

internal fun galleryHeroProgress(routeProgress: Float, returning: Boolean, returnStart: Float): Float {
    val progress = routeProgress.coerceIn(0f, 1f)
    if (!returning) return FastOutSlowInEasing.transform(progress)
    val start = returnStart.coerceIn(0f, 1f)
    if (start == 0f) return 0f
    val elapsed = (1f - progress / start).coerceIn(0f, 1f)
    return FastOutSlowInEasing.transform(start) * (1f - FastOutSlowInEasing.transform(elapsed))
}

/** The full bitmap plane and the clipping viewport travel independently, as in the Flutter Hero. */
@Composable
internal fun GalleryHeroFlight(source: GalleryHeroSource, viewport: Rect, progress: () -> Float, modifier: Modifier, original: Bitmap? = null,
    targetScale: Float = 1f, targetOffset: Offset = Offset.Zero) {
    Canvas(modifier) {
        val bitmap = (original ?: source.bitmap).takeUnless { it.isRecycled } ?: return@Canvas
        val width = bitmap.width.toFloat(); val height = bitmap.height.toFloat()
        val factor = minOf(viewport.width / width, viewport.height / height) * targetScale
        val target = Rect((viewport.width - width * factor) / 2 + targetOffset.x, (viewport.height - height * factor) / 2 + targetOffset.y, (viewport.width + width * factor) / 2 + targetOffset.x, (viewport.height + height * factor) / 2 + targetOffset.y)
        val sourceBounds = source.bounds.translate(-viewport.topLeft)
        val sourceFit = if (source.crop) maxOf(sourceBounds.width / width, sourceBounds.height / height)
            else minOf(sourceBounds.width / width, sourceBounds.height / height)
        val from = Rect(sourceBounds.center.x - width * sourceFit / 2, sourceBounds.center.y - height * sourceFit / 2,
            sourceBounds.center.x + width * sourceFit / 2, sourceBounds.center.y + height * sourceFit / 2)
        val fraction = progress()
        val plane = lerp(from, target, fraction)
        val clip = lerp(sourceBounds, viewport.translate(-viewport.topLeft), fraction)
        val destination = android.graphics.RectF(plane.left, plane.top, plane.right, plane.bottom)
        val clippingBounds = android.graphics.RectF(clip.left, clip.top, clip.right, clip.bottom)
        drawIntoCanvas { canvas ->
            val native = canvas.nativeCanvas
            native.save()
            val radius = (source.cornerRadiusPx ?: (8f * density)) * (1 - fraction)
            native.clipPath(android.graphics.Path().apply { addRoundRect(clippingBounds, radius, radius, android.graphics.Path.Direction.CW) })
            native.drawBitmap(bitmap, null, destination, android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.FILTER_BITMAP_FLAG))
            native.restore()
        }
    }
}
