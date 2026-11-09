package com.green.note.ui

import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.Indication
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.selection.toggleable
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role

internal class HapticGate {
    private var last = Long.MIN_VALUE
    fun claim(now: Long, tick: Boolean = false): Boolean {
        if (last != Long.MIN_VALUE && now - last < if (tick) 12 else 40) return false
        last = now
        return true
    }
}

object AppHaptics {
    private val gate = HapticGate()
    fun light(view: View, enabled: Boolean) {
        if (enabled && gate.claim(SystemClock.elapsedRealtime())) view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
    }
    fun selection(view: View, enabled: Boolean, tick: Boolean = false) {
        if (enabled && gate.claim(SystemClock.elapsedRealtime(), tick = tick)) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }
}

@Composable
internal fun Modifier.tapClickable(enabled: Boolean = true, onClickLabel: String? = null, role: Role? = null,
    onClick: () -> Unit): Modifier = clickable(enabled = enabled, onClickLabel = onClickLabel,
    role = role, onClick = rememberHapticClick(onClick))

@Composable
internal fun Modifier.tapClickable(interactionSource: MutableInteractionSource?, indication: Indication?,
    enabled: Boolean = true, onClickLabel: String? = null, role: Role? = null, onClick: () -> Unit): Modifier =
    clickable(interactionSource, indication, enabled, onClickLabel, role, rememberHapticClick(onClick))

@Composable
internal fun Modifier.tapCombinedClickable(enabled: Boolean = true, onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit): Modifier = combinedClickable(enabled = enabled, onLongClick = onLongClick,
    hapticFeedbackEnabled = false, onClick = rememberHapticClick(onClick))

@Composable
internal fun Modifier.tapToggleable(value: Boolean, enabled: Boolean = true, role: Role? = null,
    onValueChange: (Boolean) -> Unit): Modifier {
    val feedback = rememberHapticClick {}
    return toggleable(value, enabled, role) { feedback(); onValueChange(it) }
}
