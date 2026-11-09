package com.green.note.content

import org.junit.Assert.assertEquals
import org.junit.Test

class AvatarInitialTest {
    @Test fun fallbackUsesOriginalTrimmedUppercaseUnicodeCodePoint() {
        assertEquals("", avatarInitial("  "))
        assertEquals("A", avatarInitial(" alice"))
        assertEquals("中", avatarInitial("中文"))
        assertEquals("😀", avatarInitial("😀name"))
    }
}
