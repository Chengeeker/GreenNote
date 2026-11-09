package com.green.note.media

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaGestureRulesTest {
    @Test fun galleryInertiaThresholdAndDistanceScaleInLogicalPixels() {
        assertEquals(0f to 0f, galleryInertiaDelta(1199f, 0f, 3f))
        assertEquals(360f to 0f, galleryInertiaDelta(1200f, 0f, 3f))
        assertEquals(-72f to 96f, galleryInertiaDelta(-300f, 400f, 1f))
    }
    @Test fun originalFlingSpringIsMonotoneAndEndsWithoutOvershoot() {
        assertEquals(0f, gallerySpringFraction(0f), 0f)
        var previous = 0f
        for (millis in 1..500) {
            val next = gallerySpringFraction(millis / 1000f)
            org.junit.Assert.assertTrue(next >= previous && next <= 1f)
            previous = next
        }
        assertEquals(1f, previous, 0f)
    }
    @Test fun doubleTapUsesOriginalThreeRegionsIncludingBoundaries() {
        assertEquals(-10, videoDoubleTapSeconds(34.99f, 100f))
        assertEquals(0, videoDoubleTapSeconds(35f, 100f))
        assertEquals(0, videoDoubleTapSeconds(50f, 100f))
        assertEquals(0, videoDoubleTapSeconds(65f, 100f))
        assertEquals(10, videoDoubleTapSeconds(65.01f, 100f))
    }
}
