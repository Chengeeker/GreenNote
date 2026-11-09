package com.green.note.ui

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance

/** Matches officialHomeTheme in home_destination_page.dart without overriding control foregrounds. */
@Composable
fun OfficialHomeTheme(content: @Composable () -> Unit) {
    val base = MaterialTheme.colorScheme
    val dark = base.surface.luminance() < .5f
    val scheme = if (dark) base.copy(
        primary = Color(0xff009688), onSurface = Color(0xffcccccc), onSurfaceVariant = Color(0xff999999),
    ) else base
    val typography = MaterialTheme.typography
    // The original local theme recolors every text style, including the two secondary styles.
    val localTypography = if (dark) typography.copy(
        bodySmall = typography.bodySmall.copy(color = Color.Unspecified),
        titleSmall = typography.titleSmall.copy(color = Color.Unspecified),
    ) else typography
    MaterialTheme(colorScheme = scheme, typography = localTypography) {
        CompositionLocalProvider(LocalContentColor provides scheme.onSurface, content = content)
    }
}
