package com.green.note.content

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** Current Flutter app_theme ListTileTheme: dense, 14h, 4 minimum vertical padding. */
@Composable
internal fun ContentListTile(
    headlineContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    supportingContent: (@Composable () -> Unit)? = null,
    leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
    horizontalPadding: Dp = 14.dp,
) {
    val colors = MaterialTheme.colorScheme
    val titleStyle = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp, lineHeight = 1.35.em, fontWeight = com.green.note.ui.adjustedWeight(600), color = colors.onSurface)
    val subtitleStyle = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, lineHeight = 1.4.em, fontWeight = com.green.note.ui.adjustedWeight(400), color = colors.onSurfaceVariant)
    com.green.note.ui.ReviewTileLayout(modifier, horizontalPadding = horizontalPadding,
        leading = leadingContent?.let { { CompositionLocalProvider(LocalContentColor provides colors.onSurfaceVariant, com.green.note.ui.LocalMaterialGlyphColor provides colors.onSurfaceVariant, com.green.note.ui.LocalIconButtonColor provides colors.onSurfaceVariant) { it() } } },
        trailing = trailingContent?.let { { CompositionLocalProvider(LocalContentColor provides colors.onSurfaceVariant, com.green.note.ui.LocalMaterialGlyphColor provides colors.onSurfaceVariant, com.green.note.ui.LocalIconButtonColor provides colors.onSurfaceVariant) { it() } } },
        subtitle = supportingContent?.let { { ProvideTextStyle(subtitleStyle) { it() } } },
    ) { ProvideTextStyle(titleStyle) { headlineContent() } }
}
