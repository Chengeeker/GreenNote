package com.green.note.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import org.junit.Assert.*
import org.junit.Test

class TypographyColorTest {
    @Test fun everyTypographyStyleKeepsChineseFallbackThroughSizeAndColorOverrides() {
        val original = java.util.Locale.getDefault()
        try {
            listOf("en-US", "ar-EG").forEach { language ->
                java.util.Locale.setDefault(java.util.Locale.forLanguageTag(language))
                val typography = reviewTypography(Color.Gray, 0)
                val styles = listOf(typography.displayLarge, typography.displayMedium, typography.displaySmall,
                    typography.headlineLarge, typography.headlineMedium, typography.headlineSmall,
                    typography.titleLarge, typography.titleMedium, typography.titleSmall,
                    typography.bodyLarge, typography.bodyMedium, typography.bodySmall,
                    typography.labelLarge, typography.labelMedium, typography.labelSmall)
                styles.forEach { style ->
                    assertEquals("zh-CN", style.localeList!!.single().toLanguageTag())
                    assertEquals(style.localeList, style.merge(TextStyle(color = Color.Red)).localeList)
                    assertEquals(style.localeList, style.copy(fontSize = 19.sp).localeList)
                }
            }
        } finally { java.util.Locale.setDefault(original) }
    }

    @Test fun componentForegroundCanOverridePageForegroundInBothThemes() {
        listOf(Color(0xffeeeeee),Color(0xff333333)).forEach { secondary ->
            val styles=reviewTypography(secondary,0)
            // Material3 merges the page style with the component label before resolving contentColor.
            val buttonStyle=styles.bodyLarge.merge(styles.labelLarge)
            assertEquals(Color.Unspecified,buttonStyle.color)
            assertEquals(Color.Unspecified,styles.bodyLarge.merge(styles.labelMedium).color)
            assertEquals(Color.Unspecified,styles.titleMedium.color)
            assertEquals(secondary,styles.bodySmall.color)
            assertEquals(Color.Red,buttonStyle.merge(TextStyle(color=Color.Red)).color)
        }
    }
}
