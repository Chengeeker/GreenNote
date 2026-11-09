package com.green.note.nativebridge

import org.junit.Assert.*
import org.junit.Test

class VivoOsNameTest {
    @Test fun explicitOriginVersionWinsOverStaleFuntouchCompatibilityProperties() {
        assertEquals("OriginOS 7.0", vivoOsName("OriginOS 7", "Funtouch", "17"))
        assertEquals("Funtouch OS 14.0", vivoOsName("Funtouch OS 14", "OriginOS", "4"))
        assertEquals("OriginOS 5.0", vivoOsName("", "OriginOS", "5"))
        assertNull(vivoOsName("", "", "unknown"))
    }
}
