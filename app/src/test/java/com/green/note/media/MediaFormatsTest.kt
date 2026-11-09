package com.green.note.media

import org.junit.Assert.*
import org.junit.Test

class MediaFormatsTest {
    @Test fun rejectedErrorBodiesAndPlaylistsCannotBecomeSuccessfulSavedMedia() {
        listOf("text/html" to "<html>Denied", "application/octet-stream" to "{\"error\":1}", "application/vnd.apple.mpegurl" to "#EXTM3U").forEach { (type, body) ->
            try { MediaFiles.validateMediaPayload(type, body.toByteArray()); fail("Error payload was accepted") } catch (_: IllegalArgumentException) { }
        }
        MediaFiles.validateMediaPayload("image/jpeg", byteArrayOf(0xff.toByte(), 0xd8.toByte()))
        MediaFiles.validateMediaPayload("application/octet-stream", byteArrayOf(0, 0, 0, 24, 102, 116, 121, 112))
    }
    @Test fun gainmapMetadataIsCaseInsensitiveAndBoundedToHeader() {
        assertTrue(HdrImageDetection.hasMetadata("abcdefghijklmnop urn:iso:std:iso:ts:21496:-1".toByteArray()))
        assertTrue(HdrImageDetection.hasMetadata("abcdefghijklmnop HDR-GAIN-MAP".toByteArray()))
        assertFalse(HdrImageDetection.hasMetadata(ByteArray(131072) + "gainmap".toByteArray()))
        assertFalse(HdrImageDetection.hasMetadata("jpeg".toByteArray()))
    }
    @Test fun storedFileExtensionMatchesActualContentType() {
        assertEquals("gif", MediaFiles.extension("image/gif; charset=binary", false))
        assertEquals("png", MediaFiles.extension("image/png", false))
        assertEquals("webm", MediaFiles.extension("video/webm", true))
        assertEquals("mp4", MediaFiles.extension("", true))
    }
    @Test fun hdrBadgeKeepsFeedAndPerPictureDeclarationsWithoutInventingOtherPictureFlags() {
        val feed = org.json.JSONObject().put("picArr", org.json.JSONArray().put(org.json.JSONObject().put("url", "http://img/a").put("hdr", 1)))
        assertTrue(galleryDeclaredHdr("https://img/a", feed))
        assertFalse(galleryDeclaredHdr("https://img/b", feed))
        assertTrue(galleryDeclaredHdr("https://img/b", org.json.JSONObject().put("isHdr", true)))
        assertTrue(galleryDeclaredHdr("https://img/c?is_hdr=1", null))
    }
}
