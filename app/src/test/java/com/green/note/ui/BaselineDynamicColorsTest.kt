package com.green.note.ui

import androidx.compose.ui.graphics.toArgb
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class BaselineDynamicColorsTest {
    @Test fun completeSchemesMatchOriginalFlutterPluginForEveryRole() {
        val source = requireNotNull(javaClass.getResourceAsStream("/dynamic-color-fixtures.json"))
            .bufferedReader().use { it.readText() }
        val fixtures = JSONArray(source)
        assertEquals(6, fixtures.length())
        for (index in 0 until fixtures.length()) {
            val fixture = fixtures.getJSONObject(index)
            val colors = fixture.getJSONArray("palette")
            val actual = baselineDynamicColorScheme(IntArray(colors.length()) { colors.getLong(it).toInt() }, fixture.getBoolean("dark"))
            val expected = fixture.getJSONObject("roles")
            val roles = mapOf(
                "background" to actual.background,
                "onBackground" to actual.onBackground,
                "primary" to actual.primary,
                "onPrimary" to actual.onPrimary,
                "primaryContainer" to actual.primaryContainer,
                "onPrimaryContainer" to actual.onPrimaryContainer,
                "secondary" to actual.secondary,
                "onSecondary" to actual.onSecondary,
                "secondaryContainer" to actual.secondaryContainer,
                "onSecondaryContainer" to actual.onSecondaryContainer,
                "tertiary" to actual.tertiary,
                "onTertiary" to actual.onTertiary,
                "tertiaryContainer" to actual.tertiaryContainer,
                "onTertiaryContainer" to actual.onTertiaryContainer,
                "error" to actual.error,
                "onError" to actual.onError,
                "errorContainer" to actual.errorContainer,
                "onErrorContainer" to actual.onErrorContainer,
                "outline" to actual.outline,
                "outlineVariant" to actual.outlineVariant,
                "surface" to actual.surface,
                "onSurface" to actual.onSurface,
                "surfaceVariant" to actual.surfaceVariant,
                "onSurfaceVariant" to actual.onSurfaceVariant,
                "inverseSurface" to actual.inverseSurface,
                "inverseOnSurface" to actual.inverseOnSurface,
                "inversePrimary" to actual.inversePrimary,
                "scrim" to actual.scrim,
                "surfaceTint" to actual.surfaceTint,
                "surfaceDim" to actual.surfaceDim,
                "surfaceBright" to actual.surfaceBright,
                "surfaceContainerLowest" to actual.surfaceContainerLowest,
                "surfaceContainerLow" to actual.surfaceContainerLow,
                "surfaceContainer" to actual.surfaceContainer,
                "surfaceContainerHigh" to actual.surfaceContainerHigh,
                "surfaceContainerHighest" to actual.surfaceContainerHighest,
            )
            assertEquals(36, roles.size)
            assertEquals(expected.length(), roles.size)
            roles.forEach { (role, color) ->
                assertEquals("${fixture.getString("name")} dark=${fixture.getBoolean("dark")} $role", expected.getLong(role).toInt(), color.toArgb())
            }
        }
    }

    @Test fun unavailableOrBrokenVendorResourcesKeepTheSelectedUserSeed() {
        listOf(false, true).forEach { dark ->
            val fallback = seedColorScheme(0xffe91e63, dark)
            assertSame(fallback, resolveBaselineDynamicColors(dark, fallback) { null })
            assertSame(fallback, resolveBaselineDynamicColors(dark, fallback) { throw IllegalStateException("missing OS resource") })
            assertSame(fallback, resolveBaselineDynamicColors(dark, fallback) { IntArray(64) })
        }
    }
}
