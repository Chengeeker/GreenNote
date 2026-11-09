package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class GlassPhysicsTest {
    @Test fun waterRequiresHoldAndReleaseImmediatelyHandsBackToFrost() {
        assertFalse(navigationWaterHeld(touching = true, longPressed = false))
        assertTrue(navigationWaterHeld(touching = true, longPressed = true))
        assertFalse(navigationWaterHeld(touching = false, longPressed = true))
        val release = navigationWaterSpec(false) as androidx.compose.animation.core.TweenSpec<Float>
        assertEquals(240, release.durationMillis)
        val frostEarly = navigationFrostWeight(1f - release.easing.transform(.1f))
        assertTrue(frostEarly > 0f)
        assertTrue(navigationFrostWeight(1f - release.easing.transform(.5f)) > frostEarly)
        assertEquals(1f, navigationFrostWeight(0f), 0f)
    }
    @Test fun pointerTracksTheSameFiveSlotCentersAsTheRenderer() {
        for (slot in 0..4) {
            val center = (slot + .5f) * 60f
            assertEquals(slot, navigationSlot(center, 300f))
            assertEquals(slot.toFloat(), navigationLensTarget(center, 300f), .0001f)
        }
        assertEquals(0f, navigationLensTarget(-200f, 300f), .0001f)
        assertEquals(4f, navigationLensTarget(1000f, 300f), .0001f)
        assertEquals(2.25f, navigationLensTarget(165f, 300f), .0001f)
    }
    @Test fun quickFlickSkipsPublishAndNeverOverflowsTabs() {
        assertEquals(3, navigationDragChoice(1, 1, 900f))
        assertEquals(1, navigationDragChoice(3, 3, -900f))
        assertEquals(4, navigationDragChoice(0, 4, 900f))
        assertNull(navigationDragChoice(0, 0, -900f))
        assertNull(navigationDragChoice(4, 4, 900f))
        assertNull(navigationDragChoice(1, PublishNavigationSlot, 900f))
        assertNull(navigationDragChoice(3, 3, 799f))
    }
    @Test fun jellyIsNeutralWithoutMotionAndBoundedAtExtremeVelocity() {
        assertArrayEquals(floatArrayOf(1f, 1f), jellyScale(0f), .0001f)
        assertArrayEquals(floatArrayOf(1f, 1f), jellyScale(Float.NaN), .0001f)
        val (x,y)=jellyScale(10000f)
        assertEquals(.72f,x,.0001f);assertEquals(1.168f,y,.0001f)
    }
    @Test fun galleryNativeGrowthUsesLongestSideAndWideButtonsDoNotOverstretch() {
        assertEquals(1+17f/48,GalleryStretch.calculate(48f,48f,0f,0f,1f).scaleX,.0001f)
        assertEquals(1+17f/132,GalleryStretch.calculate(132f,48f,0f,0f,1f).scaleY,.0001f)
        val circle=GalleryStretch.calculate(48f,48f,20f,0f,0f)
        val wide=GalleryStretch.calculate(300f,48f,20f,0f,0f)
        assertTrue(wide.scaleX<circle.scaleX);assertTrue(wide.translationX<circle.translationX)
        val reversed=GalleryStretch.calculate(48f,48f,-20f,0f,0f)
        assertEquals(circle.scaleX,reversed.scaleX,.0001f);assertEquals(-circle.translationX,reversed.translationX,.0001f)
    }
}
