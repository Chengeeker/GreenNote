package com.green.note.content

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

internal val LocalPhotoStatusBars = staticCompositionLocalOf<MutableMap<Any, Unit>?> { null }

/** A Row with the original AppBar icon scope, without adding layout or padding. */
@Composable
internal fun ContentToolbarRow(
    modifier: Modifier = Modifier,
    horizontalArrangement: Arrangement.Horizontal = Arrangement.Start,
    verticalAlignment: Alignment.Vertical = Alignment.Top,
    color: Color = MaterialTheme.colorScheme.onSurface,
    content: @Composable RowScope.() -> Unit,
) {
    com.green.note.ui.ReviewToolbarIcons(color) {
        Row(modifier, horizontalArrangement, verticalAlignment, content)
    }
}
