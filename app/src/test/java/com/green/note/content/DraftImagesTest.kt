package com.green.note.content

import org.junit.Assert.*
import org.junit.Test

class DraftImagesTest {
    @Test fun boundsDeterminePowerOfTwoSampleWithoutDecoding() {
        assertEquals(1, uploadSampleSize(2048, 1000))
        assertEquals(2, uploadSampleSize(4096, 2048))
        assertEquals(4, uploadSampleSize(8000, 6000))
        assertEquals(1048576, uploadSampleSize(Int.MAX_VALUE, 1))
        assertThrows(IllegalArgumentException::class.java) { uploadSampleSize(0, 10) }
    }
}
