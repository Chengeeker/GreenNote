package com.green.note.media

import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.sqrt

/** Original video_player_page.dart 623–631: the middle 30% toggles playback. */
internal fun videoDoubleTapSeconds(x: Float, width: Float): Int = when {
    x < width * .35f -> -10
    x > width * .65f -> 10
    else -> 0
}

/** extended_image 8.3.1: a 400 logical-pixel/s threshold and fixed 120dp direction. */
internal fun galleryInertiaDelta(vx: Float, vy: Float, density: Float): Pair<Float, Float> {
    val magnitude = hypot(vx.toDouble(), vy.toDouble())
    if (density <= 0f || magnitude < 400.0 * density) return 0f to 0f
    val distance = 120f * density
    return (vx / magnitude * distance).toFloat() to (vy / magnitude * distance).toFloat()
}

/** Flutter AnimationController.fling: mass 1, stiffness 500, critical damping,
 * target upperBound + .01, ending when its distance from that target is <= .01. */
internal fun gallerySpringFraction(seconds: Float, velocity: Float = .4f): Float {
    val w = sqrt(500.0)
    val t = seconds.coerceAtLeast(0f).toDouble()
    return (1.01 + (-1.01 + (velocity - 1.01 * w) * t) * exp(-w * t)).toFloat().coerceIn(0f, 1f)
}
