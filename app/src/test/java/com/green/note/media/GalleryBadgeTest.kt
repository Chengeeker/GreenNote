package com.green.note.media

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class GalleryBadgeTest {
    private val url = "https://image.coolapk.com/example.jpg"
    private fun feed(width: Int, height: Int) = JSONObject().put("picArr", JSONArray().put(
        JSONObject().put("url", url).put("large", JSONObject().put("geo", JSONObject().put("width", width).put("height", height)))))

    @Test fun coolPictureAndArticleDoNotGainBadgesFromRawOrDecodedDimensions() {
        assertEquals("", galleryBadge(url, feed(1080, 2400), false))
        assertEquals("", galleryBadge(url, null, false))
    }

    @Test fun nineGridRetainsExplicitMetadataDimensionsAndStrictRatioBoundary() {
        assertEquals("长图", galleryBadge(url, feed(1080, 2400).put("_composeGalleryUseDeclaredDimensions", true), false))
        assertEquals("", galleryBadge(url, feed(1080, 2160).put("_composeGalleryUseDeclaredDimensions", true), false))
        assertEquals("", galleryBadge(url, feed(0, 2400).put("_composeGalleryUseDeclaredDimensions", true), false))
    }

    @Test fun urlAndHdrRulesKeepOriginalPriorityForMainImageAndReel() {
        assertEquals("长图", galleryBadge("$url?is_long=1", null, false))
        assertEquals("HDR", galleryBadge("$url?is_long=1", null, true))
        assertEquals("GIF", galleryBadge("$url?format=.gif&is_long=1", null, true))
    }
}
