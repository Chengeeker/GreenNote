package com.green.note

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class GalleryActionsTest {
    @Test fun favoriteCountsTrackChangesButDoNotFabricateLocalCounts() {
        val feed = JSONObject("""{"favnum":"10","userAction":{"favorite":1}}""")
        assertEquals(9, galleryFavorite(feed, false, false).getInt("favnum"))
        assertEquals(10, galleryFavorite(feed, true, false).getInt("favnum"))
        assertEquals(10, galleryFavorite(feed, false, true).getInt("favnum"))
        assertEquals(1, feed.getJSONObject("userAction").getInt("favorite"))
        assertEquals("1万", galleryFavorite(JSONObject("""{"favnum":"1万"}"""), true, false).getString("favnum"))
    }
}
