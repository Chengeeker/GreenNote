// Adapted from Google material_color_utilities 0.13.0 quantizer_wu.dart.
// Copyright 2021 Google LLC. Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0
// Full license: assets/licenses/material-color-utilities-apache-2.0.txt.
package com.green.note.content

import kotlin.math.roundToInt

/** Dart Wu centroids round to nearest; Java MCU truncates and exposes no public box moments. */
internal fun flutterIconWu(pixels: IntArray): List<Int> = IconWuMoments(pixels).colors()

private class IconWuBox(val low: IntArray = IntArray(3), val high: IntArray = IntArray(3)) {
    val volume: Int get() = (high[0] - low[0]) * (high[1] - low[1]) * (high[2] - low[2])
}

private class IconWuMoments(pixels: IntArray) {
    // At most 112*112 pixels. All integer moments and their squares remain exact in Double.
    // channels: population, red sum, green sum, blue sum, squared-RGB sum.
    private val moment = Array(5) { DoubleArray(33 * 33 * 33) }
    private fun index(r: Int, g: Int, b: Int) = (r * 33 + g) * 33 + b

    init {
        for (pixel in pixels) {
            if (pixel ushr 24 != 255) continue // Dart QuantizerMap's Wu-only alpha filter.
            val r = (pixel ushr 16) and 255; val g = (pixel ushr 8) and 255; val b = pixel and 255
            val at = index((r shr 3) + 1, (g shr 3) + 1, (b shr 3) + 1)
            moment[0][at]++
            moment[1][at] += r; moment[2][at] += g; moment[3][at] += b
            moment[4][at] += r * r + g * g + b * b
        }
        // Integral histogram, equivalent to the Dart row/area accumulation. Values are integers
        // below 2^53, so the different loop factoring does not introduce floating-point rounding.
        for (r in 1..32) for (g in 1..32) for (b in 1..32) {
            val at = index(r, g, b)
            for (data in moment) data[at] += data[index(r - 1, g, b)] + data[index(r, g - 1, b)] + data[index(r, g, b - 1)] -
                data[index(r - 1, g - 1, b)] - data[index(r - 1, g, b - 1)] - data[index(r, g - 1, b - 1)] + data[index(r - 1, g - 1, b - 1)]
        }
    }

    private fun volume(box: IconWuBox, channel: Int, axis: Int = -1, cut: Int = 0): Double {
        val r0 = box.low[0]; val g0 = box.low[1]; val b0 = box.low[2]
        val r1 = if (axis == 0) cut else box.high[0]
        val g1 = if (axis == 1) cut else box.high[1]
        val b1 = if (axis == 2) cut else box.high[2]
        val data = moment[channel]
        return data[index(r1, g1, b1)] - data[index(r1, g1, b0)] - data[index(r1, g0, b1)] + data[index(r1, g0, b0)] -
            data[index(r0, g1, b1)] + data[index(r0, g1, b0)] + data[index(r0, g0, b1)] - data[index(r0, g0, b0)]
    }

    private fun variance(box: IconWuBox): Double {
        val r = volume(box, 1); val g = volume(box, 2); val b = volume(box, 3)
        return volume(box, 4) - (r * r + g * g + b * b) / volume(box, 0)
    }

    private fun cut(one: IconWuBox, two: IconWuBox): Boolean {
        val whole = DoubleArray(4) { volume(one, it) }
        val maxima = DoubleArray(3)
        val locations = IntArray(3) { -1 }
        for (axis in 0..2) for (position in one.low[axis] + 1 until one.high[axis]) {
            val weight = volume(one, 0, axis, position)
            if (weight == 0.0 || whole[0] - weight == 0.0) continue
            val r = volume(one, 1, axis, position); val g = volume(one, 2, axis, position); val b = volume(one, 3, axis, position)
            val rr = whole[1] - r; val gg = whole[2] - g; val bb = whole[3] - b
            val value = (r * r + g * g + b * b) / weight + (rr * rr + gg * gg + bb * bb) / (whole[0] - weight)
            if (value > maxima[axis]) { maxima[axis] = value; locations[axis] = position }
        }
        val axis = if (maxima[0] >= maxima[1] && maxima[0] >= maxima[2]) 0
            else if (maxima[1] >= maxima[0] && maxima[1] >= maxima[2]) 1 else 2
        if (locations[axis] < 0) return false
        one.low.copyInto(two.low); one.high.copyInto(two.high)
        one.high[axis] = locations[axis]; two.low[axis] = locations[axis]
        return true
    }

    fun colors(): List<Int> {
        val boxes = Array(128) { IconWuBox() }
        boxes[0].high.fill(32)
        val variances = DoubleArray(128)
        var next = 0
        var generated = 128
        var i = 1
        while (i < 128) {
            if (cut(boxes[next], boxes[i])) {
                variances[next] = if (boxes[next].volume > 1) variance(boxes[next]) else 0.0
                variances[i] = if (boxes[i].volume > 1) variance(boxes[i]) else 0.0
            } else { variances[next] = 0.0; i-- }
            next = 0
            var greatest = variances[0]
            for (j in 1..i) if (variances[j] > greatest) { greatest = variances[j]; next = j }
            if (greatest <= 0.0) { generated = i + 1; break }
            i++
        }
        val result = LinkedHashSet<Int>()
        for (box in boxes.take(generated)) {
            val weight = volume(box, 0)
            if (weight > 0.0) {
                val r = (volume(box, 1) / weight).roundToInt()
                val g = (volume(box, 2) / weight).roundToInt()
                val b = (volume(box, 3) / weight).roundToInt()
                result += 0xff000000.toInt() or (r shl 16) or (g shl 8) or b
            }
        }
        return result.toList()
    }
}
