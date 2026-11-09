package com.green.note.content

import org.junit.Assert.*
import org.junit.Test
import java.util.TimeZone

class MessageTimeTest {
    @Test fun timesUseOriginalTodayYearAndOlderYearLabels() {
        val zone = TimeZone.getTimeZone("UTC")
        val now = 1793836800000L
        assertEquals("08:00", messageTime("2026-11-05T08:00:00Z", now, zone))
        assertEquals("11月4日", messageTime("2026-11-04T10:00:00Z", now, zone))
        assertEquals("25-01-02", messageTime("2025-01-02", now, zone))
        assertEquals("bad-date", messageTime("bad-date", now, zone))
    }
}
