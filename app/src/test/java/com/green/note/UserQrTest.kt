package com.green.note

import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.decoder.Decoder
import org.junit.Assert.*
import org.junit.Test

class UserQrTest {
    @Test fun generatedQrDecodesToExactPublicProfileUrl() {
        val matrix = userQrMatrix("123456789")
        val bits = BitMatrix(matrix.width)
        for (y in 0 until matrix.height) for (x in 0 until matrix.width) if (matrix.get(x,y).toInt() != 0) bits.set(x,y)
        assertEquals("https://www.coolapk.com/u/123456789", Decoder().decode(bits).text)
    }
    @Test fun invalidProfileIdentifiersCannotBecomeQrLinks() {
        for (id in listOf("", "0", "../other", "1?token=x")) assertThrows(IllegalArgumentException::class.java) { userProfileUrl(id) }
    }
}
