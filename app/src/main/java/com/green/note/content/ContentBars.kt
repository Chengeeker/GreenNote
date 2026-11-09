package com.green.note.content

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.dp

@Composable
internal fun Modifier.contentToolbarBorder(enabled: Boolean = true): Modifier {
    val color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .24f)
    return if (!enabled) this else drawBehind { val width = .5.dp.toPx(); drawLine(color, Offset(0f, size.height - width / 2), Offset(size.width, size.height - width / 2), width) }
}
