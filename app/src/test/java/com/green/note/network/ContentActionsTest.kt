package com.green.note.network

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer

class ContentActionsTest {
    @Test fun uploadsRejectDangerousHostsAndOversizedPixelCounts() {
        for (url in listOf("file:///secret", "https://coolapk.com.evil.test/a", "https://user:pass@image.coolapk.com/a")) {
            assertThrows(IllegalArgumentException::class.java) { ContentActions.validImageUrl(url) }
        }
        assertEquals("https://image.coolapk.com/a", ContentActions.validImageUrl("http://image.coolapk.com/a"))
        val bytes = ByteArray(24)
        listOf(137,80,78,71,13,10,26,10).forEachIndexed { index, value -> bytes[index] = value.toByte() }
        ByteBuffer.wrap(bytes,16,8).putInt(192).putInt(192)
        assertEquals(192 to 192, ContentActions.pngDimensions(bytes))
        ByteBuffer.wrap(bytes,16,8).putInt(Int.MAX_VALUE).putInt(Int.MAX_VALUE)
        assertThrows(IllegalArgumentException::class.java) { ContentActions.pngDimensions(bytes) }
        assertThrows(IllegalArgumentException::class.java) { ContentActions.pngDimensions(byteArrayOf(137.toByte(),80)) }
    }
}
