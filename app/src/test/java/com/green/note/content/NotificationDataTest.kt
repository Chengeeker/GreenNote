package com.green.note.content

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NotificationDataTest {
    @Test fun notificationsResolveOnlyOfficialFeedAndReplyTargets() {
        val note = JSONObject("""{"note":"<a href='https://www.coolapk.com/feed/123?rid=456&amp;x=1'>回复</a>"}""")
        assertEquals("123", notificationTarget(note).feedId)
        assertEquals("456", notificationTarget(note).replyId)
        assertEquals("", notificationTarget(JSONObject("""{"url":"https://example.com/feed/123?rid=456"}""")).feedId)
        assertEquals("456", notificationTarget(JSONObject("""{"url":"coolmarket://reply/456"}""")).replyId)
        val parts = notificationText(JSONObject("""{"fromusername":"甲","fromuid":"2","note":"<a href='/u/2'>甲</a>回复了你：<a href='/feed/123'>你好</a>"}"""), "/v6/notification/list")
        assertEquals("甲", parts.sender); assertEquals("回复了你", parts.action); assertFalse(parts.content.contains("href"))
    }
    @Test fun clearSnapshotsAllPagesBeforeMutatingAndRejectsRepeatedPages() = runBlocking {
        val calls = mutableListOf<String>()
        var repeated = false
        val api = object : ContentApi {
            override fun imageCacheScope() = "same-account"
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls += "$method:$path:${query["page"] ?: query["id"]}"
                if (method == "POST") return JSONObject("""{"status":0}""")
                val page = query["page"]!!.toInt()
                return JSONObject().put("data", org.json.JSONArray().put(JSONObject().put("id", if (repeated) 1 else page)))
                    .put("hasMore", repeated || page == 1)
            }
        }
        assertEquals(2, clearInboxNotifications(api, "same-account"))
        assertEquals(listOf("GET:/v6/notification/list:1", "GET:/v6/notification/list:2", "POST:/v6/notification/delete:1", "POST:/v6/notification/delete:2"), calls)
        calls.clear(); repeated = true
        try { clearInboxNotifications(api, "same-account"); fail("duplicate pages should abort before deletion") } catch (_: IllegalStateException) { }
        assertTrue(calls.none { it.startsWith("POST") })
    }
}
