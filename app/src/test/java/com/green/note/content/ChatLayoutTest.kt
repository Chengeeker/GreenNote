package com.green.note.content

import org.junit.Assert.assertEquals
import org.junit.Test

class ChatLayoutTest {
    @Test fun bubbleHonorsOriginalFractionAndAvatarSpaceOnNarrowWindows() {
        assertEquals(282.72f, chatBubbleWidth(372f), .001f)
        assertEquals(144f, chatBubbleWidth(200f), .001f)
    }
    @Test fun portraitImagesDoNotFillTheTextBubbleAndWideImagesStayInsideIt() {
        assertEquals(90f, chatImageWidth(280f, .5f), .001f)
        assertEquals(252f, chatImageWidth(280f, 3f), .001f)
    }
}
