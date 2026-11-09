package com.green.note.content

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationBadgeTest {
    @Test fun flutterBadgeUsesFixedSixteenWidthOffsetAndCentersScaledTextAtFour() {
        assertEquals(40f to -4f, notificationBadgeOffset(52f, 16f, false))
        assertEquals(40f to -8f, notificationBadgeOffset(52f, 24f, false))
        assertEquals(-4f to -4f, notificationBadgeOffset(52f, 16f, true))
    }
}
