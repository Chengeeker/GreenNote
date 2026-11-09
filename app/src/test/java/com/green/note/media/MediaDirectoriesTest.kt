package com.green.note.media

import org.junit.Assert.*
import org.junit.Test

class MediaDirectoriesTest {
    @Test fun pathsPreserveBaselineRulesAndRejectTraversalNames() {
        assertEquals("GreenNote", MediaDirectories.resolve(0))
        assertEquals("GreenNote/MyProfile", MediaDirectories.resolve(1, ".."))
        assertEquals("GreenNote/Unknown", MediaDirectories.resolve(2, author = " "))
        assertEquals("GreenNote/A_B", MediaDirectories.resolve(2, author = "A//B"))
        assertEquals(50, MediaDirectories.sanitize("x".repeat(100)).length)
    }
}
