package com.green.note.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import org.junit.Assert.*
import org.junit.Test

class TypographyHeightTest {
    @Test fun bodyFontSizeOverridePreservesFlutterHeightRatio() {
        val body=reviewTypography(Color.Gray,0).bodyMedium
        assertEquals(16.sp,body.fontSize)
        assertEquals(1.43.em,body.lineHeight)
        assertEquals(1.43.em,body.copy(fontSize=13.sp).lineHeight)
        assertEquals(18.sp,body.copy(fontSize=13.sp,lineHeight=18.sp).lineHeight)
    }
    @Test fun material2021RatiosAreNotRoundedPixelHeights() {
        val theme=reviewTypography(Color.Gray,0)
        assertEquals(1.12.em,theme.displayLarge.lineHeight)
        assertEquals(1.27.em,theme.titleLarge.lineHeight)
        assertEquals(1.5.em,theme.bodyLarge.lineHeight)
        assertEquals(1.33.em,theme.labelMedium.lineHeight)
        assertEquals(1.45.em,theme.labelSmall.lineHeight)
    }
}
