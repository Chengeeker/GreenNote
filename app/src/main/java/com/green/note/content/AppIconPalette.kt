// Wsmeans portions adapted from material_color_utilities 0.13.0.
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0:
// https://www.apache.org/licenses/LICENSE-2.0
// Distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.
// FlutterPaletteRandom is adapted from Dart SDK 3.13.1, revision
// 852b3e3608906afbe6102573cfd4407aeedd1b78, sdk/lib/_internal/vm/lib/math_patch.dart.
// Copyright 2012, the Dart project authors. BSD 3-Clause.
// Complete licenses ship in assets/licenses/{material-color-utilities-apache-2.0,dart-sdk-bsd-3-clause}.txt.
package com.green.note.content

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.ui.graphics.Color
import com.google.android.material.color.utilities.ColorUtils
import com.google.android.material.color.utilities.Hct
import com.google.android.material.color.utilities.SchemeFidelity
import com.google.android.material.color.utilities.Score
import java.nio.IntBuffer

internal data class AppIconSampleSize(val width: Float, val height: Float)

/** Flutter ColorScheme._imageProviderToScaled: full decode, max 112, no upscale, nearest sampling. */
internal fun appIconSampleSize(width: Int, height: Int): AppIconSampleSize {
    require(width > 0 && height > 0)
    val scale = minOf(1.0, 112.0 / maxOf(width, height))
    return AppIconSampleSize((width * scale).toFloat(), (height * scale).toFloat())
}

/** Premultiplied raw RGBA bytes interpreted as little-endian ints (ABGR), like ui.Image.toByteData. */
internal fun sampleAppIconPixels(source: Bitmap): IntArray {
    val size = appIconSampleSize(source.width, source.height)
    val width = size.width.toInt()
    val height = size.height.toInt()
    require(width > 0 && height > 0) { "Icon sampling produced an empty raster" }
    val sampled = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    try {
        Canvas(sampled).drawBitmap(source, null, RectF(0f, 0f, size.width, size.height), Paint().apply { isFilterBitmap = false })
        // Bitmap.Config.ARGB_8888 documents raw buffer packing as AABBGGRR. getPixels would
        // instead unpremultiply and reorder it, changing translucent edge populations.
        val raw = IntArray(sampled.byteCount / 4)
        sampled.copyPixelsToBuffer(IntBuffer.wrap(raw))
        val stride = sampled.rowBytes / 4
        return if (stride == width) raw else IntArray(width * height) { raw[(it / width) * stride + it % width] }
    } finally { sampled.recycle() } // Never recycle Coil's source bitmap.
}

internal data class AppIconColors(val seed: Int, val primary: Int, val onPrimary: Int)

internal fun appIconPalette(rgbaPixels: IntArray): Pair<Color, Color> = appIconPaletteColors(rgbaPixels).let {
    Color(it.primary) to Color(it.onPrimary)
}

@SuppressLint("RestrictedApi")
internal fun appIconPaletteColors(rgbaPixels: IntArray): AppIconColors {
    require(rgbaPixels.size <= 112 * 112) { "Palette input must be the bounded image sample" }
    // Flutter quantizes ABGR first and only swaps channels in the resulting color/count map.
    val colors = flutterCelebi(rgbaPixels).mapKeys { (color, _) -> swapIconRedBlue(color) }
    val seed = Score.score(colors, 1).first()
    val scheme = SchemeFidelity(Hct.fromInt(seed), false, 0.0)
    return AppIconColors(seed, scheme.primary, scheme.onPrimary)
}

internal fun swapIconRedBlue(color: Int): Int =
    (color and 0xff00ff00.toInt()) or ((color and 255) shl 16) or ((color ushr 16) and 255)

// Wsmeans compatibility with material_color_utilities 0.13.0 (Google LLC, Apache-2.0).
// Java MCU's Celebi uses a different initializer, iteration count and movement threshold.
// Reuse its public Lab/Score/Fidelity utilities; retain Dart's five-iteration refinement.
@SuppressLint("RestrictedApi")
private fun flutterCelebi(pixels: IntArray): Map<Int, Int> {
    val populations = linkedMapOf<Int, Int>()
    for (pixel in pixels) populations[pixel] = (populations[pixel] ?: 0) + 1
    if (populations.isEmpty()) return emptyMap()
    val points = populations.keys.map(ColorUtils::labFromArgb)
    val counts = populations.values.toIntArray()
    val count = minOf(128, points.size)
    val clusters = flutterIconWu(pixels).map(ColorUtils::labFromArgb).toMutableList()
    if (clusters.size < count) {
        val random = FlutterPaletteRandom(0x42688L)
        val selected = HashSet<Int>()
        repeat(count - clusters.size) {
            var index = random.nextInt(points.size)
            while (!selected.add(index)) index = random.nextInt(points.size)
            clusters += points[index].copyOf()
        }
    }
    val indices = IntArray(points.size) { it % count }
    val distances = Array(count) { DoubleArray(count) }
    val sums = IntArray(count)
    fun distance(a: DoubleArray, b: DoubleArray): Double {
        val l = a[0] - b[0]; val x = a[1] - b[1]; val y = a[2] - b[2]
        return l * l + x * x + y * y
    }
    for (iteration in 0 until 5) {
        for (i in 0 until count) {
            for (j in i + 1 until count) {
                val value = distance(clusters[i], clusters[j])
                distances[j][i] = value; distances[i][j] = value
            }
            distances[i].sort()
        }
        var moved = 0
        for (i in points.indices) {
            val previous = indices[i]
            val previousDistance = distance(points[i], clusters[previous])
            var minimum = previousDistance
            var next = -1
            for (j in 0 until count) {
                // Preserve the Dart implementation's sorted-distance pruning and cluster order.
                if (distances[previous][j] >= 4 * previousDistance) continue
                val value = distance(points[i], clusters[j])
                if (value < minimum) { minimum = value; next = j }
            }
            if (next != -1) { moved++; indices[i] = next }
        }
        if (moved == 0 && iteration > 0) break
        sums.fill(0)
        val components = Array(count) { DoubleArray(3) }
        for (i in points.indices) {
            val cluster = indices[i]
            sums[cluster] += counts[i]
            for (axis in 0..2) components[cluster][axis] += points[i][axis] * counts[i]
        }
        for (i in 0 until count) clusters[i] = if (sums[i] == 0) DoubleArray(3) else DoubleArray(3) { components[i][it] / sums[i] }
    }
    val result = linkedMapOf<Int, Int>()
    for (i in 0 until count) {
        if (sums[i] == 0) continue
        val color = ColorUtils.argbFromLab(clusters[i][0], clusters[i][1], clusters[i][2])
        // Dart skips duplicate output centroids rather than merging their populations.
        if (!result.containsKey(color)) result[color] = sums[i]
    }
    return result
}

/** Dart VM seeded Random: Wang 64-bit mix followed by multiply-with-carry, only for missing Wu seeds. */
private class FlutterPaletteRandom(seed: Long) {
    private var state = seed.let {
        var n = it.inv() + (it shl 21)
        n = n xor (n ushr 24); n *= 265
        n = n xor (n ushr 14); n *= 21
        n = n xor (n ushr 28); n += n shl 31
        if (n == 0L) 0x5a17L else n
    }
    init { repeat(4) { advance() } }
    private fun advance() { state = 0xffffda61L * (state and 0xffffffffL) + (state ushr 32) }
    fun nextInt(max: Int): Int {
        if (max and -max == max) { advance(); return (state and (max - 1).toLong()).toInt() }
        while (true) {
            advance()
            val value = state and 0xffffffffL
            val result = value % max
            if (value - result + max <= 0x100000000L) return result.toInt()
        }
    }
}
