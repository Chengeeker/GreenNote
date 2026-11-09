package com.green.note.media

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaMimeTypeTest {
    @Test fun genericGifResponseRetainsAnimationMimeAndExtension() {
        val type = MediaFiles.mediaMimeType("application/octet-stream", "https://img.example/photo.GIF?size=original")
        assertEquals("image/gif", type)
        assertEquals("gif", MediaFiles.extension(type, false))
    }
    @Test fun explicitMimeWinsAndIsNormalized() {
        assertEquals("image/png", MediaFiles.mediaMimeType("IMAGE/PNG; charset=binary", "https://img.example/photo.gif"))
        assertEquals("video/webm", MediaFiles.mediaMimeType("video/webm", "https://img.example/v"))
        assertEquals("application/octet-stream", MediaFiles.mediaMimeType("application/octet-stream", "https://img.example/v"))
    }
}
