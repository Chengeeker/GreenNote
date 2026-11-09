package com.green.note.ui

import androidx.compose.material3.*
import androidx.compose.ui.graphics.Color
import com.google.android.material.color.utilities.Hct
import com.google.android.material.color.utilities.SchemeTonalSpot
import com.google.android.material.color.utilities.MaterialDynamicColors

// Flutter's ColorScheme.fromSeed uses Tonal Spot with standard contrast.
// Dependency version is pinned; cross-language palette fixtures protect its role mapping.
@Suppress("RestrictedApi")
internal fun seedColorScheme(seed:Long,dark:Boolean):ColorScheme {
    val source=SchemeTonalSpot(Hct.fromInt(seed.toInt()),dark,0.0)
    val colors=MaterialDynamicColors()
    val base=if(dark)darkColorScheme() else lightColorScheme()
    return base.copy(
        background=Color(colors.surface().getArgb(source)),onBackground=Color(colors.onSurface().getArgb(source)),
        primary = Color(colors.primary().getArgb(source)),
        onPrimary = Color(colors.onPrimary().getArgb(source)),
        primaryContainer = Color(colors.primaryContainer().getArgb(source)),
        onPrimaryContainer = Color(colors.onPrimaryContainer().getArgb(source)),
        secondary = Color(colors.secondary().getArgb(source)),
        onSecondary = Color(colors.onSecondary().getArgb(source)),
        secondaryContainer = Color(colors.secondaryContainer().getArgb(source)),
        onSecondaryContainer = Color(colors.onSecondaryContainer().getArgb(source)),
        tertiary = Color(colors.tertiary().getArgb(source)),
        onTertiary = Color(colors.onTertiary().getArgb(source)),
        tertiaryContainer = Color(colors.tertiaryContainer().getArgb(source)),
        onTertiaryContainer = Color(colors.onTertiaryContainer().getArgb(source)),
        error = Color(colors.error().getArgb(source)),
        onError = Color(colors.onError().getArgb(source)),
        errorContainer = Color(colors.errorContainer().getArgb(source)),
        onErrorContainer = Color(colors.onErrorContainer().getArgb(source)),
        outline = Color(colors.outline().getArgb(source)),
        outlineVariant = Color(colors.outlineVariant().getArgb(source)),
        surface = Color(colors.surface().getArgb(source)),
        onSurface = Color(colors.onSurface().getArgb(source)),
        surfaceVariant = Color(colors.surfaceContainerHighest().getArgb(source)),
        onSurfaceVariant = Color(colors.onSurfaceVariant().getArgb(source)),
        inverseSurface = Color(colors.inverseSurface().getArgb(source)),
        inverseOnSurface = Color(colors.inverseOnSurface().getArgb(source)),
        inversePrimary = Color(colors.inversePrimary().getArgb(source)),
        scrim = Color(colors.scrim().getArgb(source)),
        surfaceTint = Color(colors.primary().getArgb(source)),
        surfaceDim = Color(colors.surfaceDim().getArgb(source)),
        surfaceBright = Color(colors.surfaceBright().getArgb(source)),
        surfaceContainerLowest = Color(colors.surfaceContainerLowest().getArgb(source)),
        surfaceContainerLow = Color(colors.surfaceContainerLow().getArgb(source)),
        surfaceContainer = Color(colors.surfaceContainer().getArgb(source)),
        surfaceContainerHigh = Color(colors.surfaceContainerHigh().getArgb(source)),
        surfaceContainerHighest = Color(colors.surfaceContainerHighest().getArgb(source)),
    )
}
