package com.green.note.ui

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.utilities.TonalPalette

// Same resource ordering as dynamic_color 1.9.0: five palettes, tones 0..100.
// Keep the actual OS colors, including OEM overrides; do not infer a replacement palette from one seed.
@RequiresApi(31)
private fun readSystemCorePalette(context: Context): IntArray = intArrayOf(
    android.R.color.system_accent1_1000,
    android.R.color.system_accent1_900,
    android.R.color.system_accent1_800,
    android.R.color.system_accent1_700,
    android.R.color.system_accent1_600,
    android.R.color.system_accent1_500,
    android.R.color.system_accent1_400,
    android.R.color.system_accent1_300,
    android.R.color.system_accent1_200,
    android.R.color.system_accent1_100,
    android.R.color.system_accent1_50,
    android.R.color.system_accent1_10,
    android.R.color.system_accent1_0,
    android.R.color.system_accent2_1000,
    android.R.color.system_accent2_900,
    android.R.color.system_accent2_800,
    android.R.color.system_accent2_700,
    android.R.color.system_accent2_600,
    android.R.color.system_accent2_500,
    android.R.color.system_accent2_400,
    android.R.color.system_accent2_300,
    android.R.color.system_accent2_200,
    android.R.color.system_accent2_100,
    android.R.color.system_accent2_50,
    android.R.color.system_accent2_10,
    android.R.color.system_accent2_0,
    android.R.color.system_accent3_1000,
    android.R.color.system_accent3_900,
    android.R.color.system_accent3_800,
    android.R.color.system_accent3_700,
    android.R.color.system_accent3_600,
    android.R.color.system_accent3_500,
    android.R.color.system_accent3_400,
    android.R.color.system_accent3_300,
    android.R.color.system_accent3_200,
    android.R.color.system_accent3_100,
    android.R.color.system_accent3_50,
    android.R.color.system_accent3_10,
    android.R.color.system_accent3_0,
    android.R.color.system_neutral1_1000,
    android.R.color.system_neutral1_900,
    android.R.color.system_neutral1_800,
    android.R.color.system_neutral1_700,
    android.R.color.system_neutral1_600,
    android.R.color.system_neutral1_500,
    android.R.color.system_neutral1_400,
    android.R.color.system_neutral1_300,
    android.R.color.system_neutral1_200,
    android.R.color.system_neutral1_100,
    android.R.color.system_neutral1_50,
    android.R.color.system_neutral1_10,
    android.R.color.system_neutral1_0,
    android.R.color.system_neutral2_1000,
    android.R.color.system_neutral2_900,
    android.R.color.system_neutral2_800,
    android.R.color.system_neutral2_700,
    android.R.color.system_neutral2_600,
    android.R.color.system_neutral2_500,
    android.R.color.system_neutral2_400,
    android.R.color.system_neutral2_300,
    android.R.color.system_neutral2_200,
    android.R.color.system_neutral2_100,
    android.R.color.system_neutral2_50,
    android.R.color.system_neutral2_10,
    android.R.color.system_neutral2_0,
).map { context.resources.getColor(it, null) }.toIntArray()

internal fun baselineDynamicColorScheme(context: Context, dark: Boolean, fallback: ColorScheme): ColorScheme =
    resolveBaselineDynamicColors(dark, fallback) {
        if (Build.VERSION.SDK_INT >= 31 && DynamicColors.isDynamicColorAvailable()) readSystemCorePalette(context) else null
    }

// Reading an incomplete/unavailable vendor palette must not break the entire app theme.
internal fun resolveBaselineDynamicColors(dark: Boolean, fallback: ColorScheme, read: () -> IntArray?): ColorScheme =
    try { read()?.let { baselineDynamicColorScheme(it, dark) } ?: fallback } catch (_: Exception) { fallback }

// Mirrors CorePalette.toColorScheme in dynamic_color 1.9.0. Restricted MCU dependency is pinned
// to Material 1.13.0 and checked against fixtures executed by the original Flutter extension.
@SuppressLint("RestrictedApi")
internal fun baselineDynamicColorScheme(palette: IntArray, dark: Boolean): ColorScheme {
    require(palette.size == 65) { "Expected five complete OS tonal palettes" }
    val tones = intArrayOf(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100)
    fun tone(group: Int, value: Int) = Color(palette[group * 13 + tones.indexOf(value)])
    val error = TonalPalette.fromHueAndChroma(25.0, 84.0)
    fun errorTone(value: Int) = Color(error.tone(value))
    val main = if (dark) 80 else 40
    val onMain = if (dark) 20 else 100
    val container = if (dark) 30 else 90
    val onContainer = if (dark) 90 else 10
    val seed = palette[tones.indexOf(main)].toLong() and 0xffffffffL
    return seedColorScheme(seed, dark).copy(
        primary = tone(0, main), onPrimary = tone(0, onMain),
        primaryContainer = tone(0, container), onPrimaryContainer = tone(0, onContainer),
        secondary = tone(1, main), onSecondary = tone(1, onMain),
        secondaryContainer = tone(1, container), onSecondaryContainer = tone(1, onContainer),
        tertiary = tone(2, main), onTertiary = tone(2, onMain),
        tertiaryContainer = tone(2, container), onTertiaryContainer = tone(2, onContainer),
        error = errorTone(main), onError = errorTone(onMain),
        errorContainer = errorTone(container), onErrorContainer = errorTone(if (dark) 80 else 10),
        outline = tone(4, if (dark) 60 else 50), outlineVariant = tone(4, if (dark) 30 else 80),
        surface = tone(3, if (dark) 10 else 99), onSurface = tone(3, if (dark) 90 else 10),
        surfaceVariant = tone(4, if (dark) 30 else 90), onSurfaceVariant = tone(4, if (dark) 80 else 30),
        inverseSurface = tone(3, if (dark) 90 else 20), inverseOnSurface = tone(3, if (dark) 20 else 95),
        inversePrimary = tone(0, if (dark) 40 else 80), surfaceTint = tone(0, main), scrim = tone(3, 0),
    )
}
