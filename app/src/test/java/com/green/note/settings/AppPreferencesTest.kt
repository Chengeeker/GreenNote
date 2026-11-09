package com.green.note.settings

import org.junit.Assert.*
import org.junit.Test

class AppPreferencesTest {
    @Test fun flutterStorageTypesAndNamesAreImportedStrictlyWithoutMutation() {
        val original=mapOf("flutter.greennote.theme_mode" to 2L,"flutter.greennote.theme_seed_argb" to "ff1976d2",
            "flutter.greennote.font_scale" to "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu1.2", "flutter.greennote.enable_haptics" to false,
            "flutter.greennote.webdav.url" to "https://example.test/", "flutter.greennote.webdav.directory" to "archive")
        val snapshot=original.toMap()
        val (settings,dav)=FlutterPreferences.read(original)
        assertEquals(2,settings.themeMode);assertEquals(0xFF1976D2,settings.themeSeedArgb);assertEquals(1.2f,settings.fontScale)
        assertFalse(settings.haptics);assertEquals("archive",dav.directory);assertEquals(snapshot,original)
        assertThrows(IllegalArgumentException::class.java) { FlutterPreferences.read(original+mapOf("flutter.greennote.theme_mode" to 3L)) }
        assertThrows(IllegalArgumentException::class.java) { FlutterPreferences.read(original+mapOf("flutter.greennote.enable_haptics" to "false")) }
    }
    @Test fun legacyPreviewPreferencesRemainReadableWithoutTouchingFlutter() {
        val settings = AppPreferences.fromMap(mapOf("theme_mode" to "DARK", "dynamic_color" to true, "pure_black" to true))
        assertEquals(2, settings.themeMode)
        assertTrue(settings.dynamicColor)
        assertTrue(settings.pureBlackDark)
        assertTrue(settings.floatingNavBar)
        assertTrue(settings.liquidGlassNavBar)
    }

    @Test fun settingsRoundTripAndInvalidValuesFallBack() {
        val changed = AppPreferences(themeMode = 1, fontScale = 1.2f, themeSeedArgb = 0xFF1976D2, customFontWeightDelta = 200,
            haptics = false, floatingNavBar = false, imageSavePathType = 2)
        assertEquals(changed, AppPreferences.fromMap(changed.asMap()))
        val invalid = AppPreferences.fromMap(mapOf("fontScale" to Float.NaN, "themeMode" to 8, "customFontWeightDelta" to 999, "imageSavePathType" to -1))
        assertEquals(AppPreferences(), invalid)
    }

    @Test fun sevenWeightLevelsRoundTripWithoutChangingTheSavedSelection() {
        for (delta in listOf(-300, -200, -100, 0, 100, 200, 300)) {
            val enabled = AppPreferences(useCustomFontWeight = true, customFontWeightDelta = delta)
            assertEquals(enabled, AppPreferences.fromMap(enabled.asMap()))
            val system = enabled.copy(useCustomFontWeight = false)
            assertEquals(system, AppPreferences.fromMap(system.asMap()))
        }
    }

    @Test fun mediaPathsKeepFilesWithinNamedFolders() {
        assertEquals("MyProfile", StoragePaths.sanitize("..", "MyProfile"))
        assertEquals("a_b_c", StoragePaths.sanitize("a/b\\c"))
        assertEquals("GreenNote/Unknown", StoragePaths.subdirectory(2, "me", ""))
        assertEquals("GreenNote", StoragePaths.subdirectory(0, "me", "author"))
        assertEquals(50, StoragePaths.sanitize("a".repeat(80)).length)
        assertEquals("Picture/GreenNote/该条动态发布用户昵称/", StoragePaths.summary(2, "me", false))
    }
}
