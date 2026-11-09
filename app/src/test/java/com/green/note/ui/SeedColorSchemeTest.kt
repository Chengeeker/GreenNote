package com.green.note.ui

import androidx.compose.ui.graphics.toArgb
import com.green.note.settings.AppPreferences
import org.junit.Assert.assertEquals
import org.junit.Test

class SeedColorSchemeTest {
    @Test fun runtimeHctMatchesAllFlutterBaselineRoles() {
        AppPreferences.themeSeeds.forEachIndexed { index,seed ->
            listOf(false,true).forEach { dark ->
                val expected=baselineSchemes[index*2+if(dark)1 else 0]
                val actual=seedColorScheme(seed,dark)
                assertEquals("seed=$seed dark=$dark primary",expected.primary.toArgb(),actual.primary.toArgb())
                assertEquals("seed=$seed dark=$dark onPrimary",expected.onPrimary.toArgb(),actual.onPrimary.toArgb())
                assertEquals("seed=$seed dark=$dark primaryContainer",expected.primaryContainer.toArgb(),actual.primaryContainer.toArgb())
                assertEquals("seed=$seed dark=$dark onPrimaryContainer",expected.onPrimaryContainer.toArgb(),actual.onPrimaryContainer.toArgb())
                assertEquals("seed=$seed dark=$dark secondary",expected.secondary.toArgb(),actual.secondary.toArgb())
                assertEquals("seed=$seed dark=$dark onSecondary",expected.onSecondary.toArgb(),actual.onSecondary.toArgb())
                assertEquals("seed=$seed dark=$dark secondaryContainer",expected.secondaryContainer.toArgb(),actual.secondaryContainer.toArgb())
                assertEquals("seed=$seed dark=$dark onSecondaryContainer",expected.onSecondaryContainer.toArgb(),actual.onSecondaryContainer.toArgb())
                assertEquals("seed=$seed dark=$dark tertiary",expected.tertiary.toArgb(),actual.tertiary.toArgb())
                assertEquals("seed=$seed dark=$dark onTertiary",expected.onTertiary.toArgb(),actual.onTertiary.toArgb())
                assertEquals("seed=$seed dark=$dark tertiaryContainer",expected.tertiaryContainer.toArgb(),actual.tertiaryContainer.toArgb())
                assertEquals("seed=$seed dark=$dark onTertiaryContainer",expected.onTertiaryContainer.toArgb(),actual.onTertiaryContainer.toArgb())
                assertEquals("seed=$seed dark=$dark error",expected.error.toArgb(),actual.error.toArgb())
                assertEquals("seed=$seed dark=$dark onError",expected.onError.toArgb(),actual.onError.toArgb())
                assertEquals("seed=$seed dark=$dark errorContainer",expected.errorContainer.toArgb(),actual.errorContainer.toArgb())
                assertEquals("seed=$seed dark=$dark onErrorContainer",expected.onErrorContainer.toArgb(),actual.onErrorContainer.toArgb())
                assertEquals("seed=$seed dark=$dark outline",expected.outline.toArgb(),actual.outline.toArgb())
                assertEquals("seed=$seed dark=$dark outlineVariant",expected.outlineVariant.toArgb(),actual.outlineVariant.toArgb())
                assertEquals("seed=$seed dark=$dark surface",expected.surface.toArgb(),actual.surface.toArgb())
                assertEquals("seed=$seed dark=$dark onSurface",expected.onSurface.toArgb(),actual.onSurface.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceVariant",expected.surfaceVariant.toArgb(),actual.surfaceVariant.toArgb())
                assertEquals("seed=$seed dark=$dark onSurfaceVariant",expected.onSurfaceVariant.toArgb(),actual.onSurfaceVariant.toArgb())
                assertEquals("seed=$seed dark=$dark inverseSurface",expected.inverseSurface.toArgb(),actual.inverseSurface.toArgb())
                assertEquals("seed=$seed dark=$dark inverseOnSurface",expected.inverseOnSurface.toArgb(),actual.inverseOnSurface.toArgb())
                assertEquals("seed=$seed dark=$dark inversePrimary",expected.inversePrimary.toArgb(),actual.inversePrimary.toArgb())
                assertEquals("seed=$seed dark=$dark scrim",expected.scrim.toArgb(),actual.scrim.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceTint",expected.surfaceTint.toArgb(),actual.surfaceTint.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceDim",expected.surfaceDim.toArgb(),actual.surfaceDim.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceBright",expected.surfaceBright.toArgb(),actual.surfaceBright.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceContainerLowest",expected.surfaceContainerLowest.toArgb(),actual.surfaceContainerLowest.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceContainerLow",expected.surfaceContainerLow.toArgb(),actual.surfaceContainerLow.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceContainer",expected.surfaceContainer.toArgb(),actual.surfaceContainer.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceContainerHigh",expected.surfaceContainerHigh.toArgb(),actual.surfaceContainerHigh.toArgb())
                assertEquals("seed=$seed dark=$dark surfaceContainerHighest",expected.surfaceContainerHighest.toArgb(),actual.surfaceContainerHighest.toArgb())
            }
        }
    }
}
