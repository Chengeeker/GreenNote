package com.green.note.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GalleryFlightProgressTest {
    @Test fun usesFlutterHeroCurveAndFlippedReverseCurve() {
        val opened = galleryHeroProgress(.5f, false, 1f)
        assertTrue(opened > .5f)
        assertEquals(1f - opened, galleryHeroProgress(.5f, true, 1f), .0001f)
        assertEquals(1f, galleryHeroProgress(1f, true, 1f), 0f)
        assertEquals(0f, galleryHeroProgress(0f, true, 1f), 0f)
    }

    @Test fun interruptedOpeningReversesFromCurrentHeroBounds() {
        val progress = .37f
        assertEquals(galleryHeroProgress(progress, false, 1f), galleryHeroProgress(progress, true, progress), .0001f)
        assertEquals(0f, galleryHeroProgress(0f, true, progress), 0f)
    }
}
