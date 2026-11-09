package com.green.note.notifications

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReplyHistoryTest {
    private fun item(id: String, time: Long) = ReplyItem(JSONObject().put("id", id).put("dateline", time))
    @Test fun legacyNullAndZeroIdsKeepTheirFallbackHashAndPreviewsPreserveUnicode() {
        val base = JSONObject().put("message", "😀".repeat(180)).put("lastupdate", 123)
        val zero = JSONObject(base.toString()).put("id", 0).put("notificationId", "alternate")
        assertEquals(ReplyItem(base).id, ReplyItem(zero).id)
        val nullFields = JSONObject(base.toString()).put("dateline", JSONObject.NULL).put("note", JSONObject.NULL)
        assertEquals(ReplyItem(base).id, ReplyItem(nullFields).id)
        assertEquals(123L, ReplyItem(nullFields).timestamp)
        assertEquals("😀".repeat(160), ReplyItem(nullFields).preview)
    }
    @Test fun baselineAndAccountChangesNeverNotifyOldReplies() {
        val first = ReplyHistory().merge("account-a", listOf(item("1", 10)))
        assertTrue(first.second.isEmpty())
        assertTrue(first.first.merge("account-b", listOf(item("2", 20))).second.isEmpty())
    }
    @Test fun deduplicationWatermarkAndBoundedHistorySurviveRoundtrip() {
        val history = ReplyHistory("a", listOf("1"), 10)
        val merged = history.merge("a", listOf(item("old", 9), item("2", 11), item("2", 11), item("1", 12)))
        assertEquals(listOf("2"), merged.second.map { it.id })
        assertEquals(12L, merged.first.watermark)
        assertEquals(merged.first, ReplyHistory.parse(merged.first.json()))
        assertEquals(200, history.merge("a", (1..300).map { item(it.toString(), it.toLong()) }).first.seen.size)
    }
}
