package com.green.note.ui

import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import kotlin.math.*

// Same duration/bounce conversion and anchored stretch as the retained glass renderer.
internal fun glassSpring(milliseconds: Int, bounce: Float): SpringSpec<Float> =
    spring(
        dampingRatio = if (bounce > 0) 1 - bounce else 1 / (1 + bounce),
        stiffness = (4 * PI * PI / (milliseconds / 1000.0).pow(2)).toFloat(),
    )

internal fun navigationWaterHeld(touching: Boolean, longPressed: Boolean): Boolean =
    touching && longPressed

internal fun navigationFrostWeight(pressure: Float): Float = 1f - pressure.coerceIn(0f, 1f)

internal fun navigationWaterSpec(held: Boolean): androidx.compose.animation.core.AnimationSpec<Float> =
    if (held) glassSpring(300, .15f)
    else androidx.compose.animation.core.tween(240, easing = androidx.compose.animation.core.FastOutSlowInEasing)

internal const val PublishNavigationSlot = 2

internal fun navigationSlot(x: Float, width: Float): Int =
    floor(x / width * navLabels.size).toInt().coerceIn(0, navLabels.lastIndex)

internal fun navigationLensTarget(x: Float, width: Float): Float =
    (x / width * navLabels.size - .5f).coerceIn(0f, navLabels.lastIndex.toFloat())

internal fun navigationDragChoice(selected: Int, slot: Int, speed: Float): Int? {
    if (slot == PublishNavigationSlot) return null
    if (slot != selected) return slot
    if (abs(speed) < 800f) return null
    val direction = if (speed > 0) 1 else -1
    val adjacent = selected + direction
    val next = if (adjacent == PublishNavigationSlot) adjacent + direction else adjacent
    return next.takeIf { it in navLabels.indices }
}

internal fun jellyScale(velocity: Float, pressure: Float = 1f): FloatArray {
    val distortion =
        if (velocity.isFinite()) (abs(velocity) / 10).coerceIn(0f, 1f) * .8f * .7f * pressure
        else 0f
    return floatArrayOf(1 - distortion * .5f, 1 + distortion * .3f)
}
