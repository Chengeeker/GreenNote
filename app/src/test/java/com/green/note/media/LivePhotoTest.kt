package com.green.note.media

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class LivePhotoTest {
    @Test fun recognizesLiveImageWithoutAffectingOrdinaryImages() {
        assertTrue(isLivePhoto("https://image.coolapk.com/a-LIVEPIC.jpg"))
        assertEquals("实况", galleryBadge("https://image.coolapk.com/a-livepic.jpg", null, false))
        assertFalse(isLivePhoto("https://image.coolapk.com/a.jpg"))
        assertEquals("", galleryBadge("https://image.coolapk.com/a.jpg", null, false))
    }

    @Test fun extractsOnlyValidAppendedMp4IncludingChunkBoundary() {
        val file = File.createTempFile("live-test", ".jpg")
        try {
            val image = ByteArray(65530) { 1 }
            val mp4 = byteArrayOf(0, 0, 0, 16, 102, 116, 121, 112, 105, 115, 111, 109, 0, 0, 0, 0)
            file.writeBytes(image + mp4)
            assertEquals(image.size.toLong(), embeddedLiveVideoOffset(file))
            file.writeBytes(image + byteArrayOf(0, 0, 0, 4, 102, 116, 121, 112))
            assertNull(embeddedLiveVideoOffset(file))
            file.writeBytes(image)
            assertNull(embeddedLiveVideoOffset(file))
        } finally { file.delete() }
    }
}
