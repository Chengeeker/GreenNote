package com.green.note.content

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TopicPaginationTest {
    @Test fun hotPrefetchKeepsCursorsAndPinnedOrder() = runBlocking {
        val calls = mutableListOf<Map<String, String>>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls += query
                return if (query["page"] == "1") JSONObject("""{"data":[{"id":"a","likenum":10},{"id":"b","is_top":1}],"hasMore":true}""") else JSONObject("""{"data":[{"id":"a","likenum":10},{"id":"c","replynum":10}],"hasMore":true}""")
            }
        }
        val page = topicPage(api, ContentRequest("/v6/topic/tagFeedList", mapOf("listType" to "hot")), 1, "", "")
        assertEquals(2, page.page); assertEquals("a", page.first); assertEquals("c", page.last)
        assertEquals("a", calls[1]["firstItem"]); assertEquals("b", calls[1]["lastItem"])
        assertEquals(listOf("b", "c", "a"), page.rows.map { it.text("id") })
    }
    @Test fun failedSecondPageKeepsFirstPageAvailableForRetry() = runBlocking {
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (query["page"] == "2") error("offline")
                return JSONObject("""{"data":[{"id":"a"}],"hasMore":true}""")
            }
        }
        val page = topicPage(api, ContentRequest("/v6/page/dataList", mapOf("listType" to "hot_desc")), 1, "", "")
        assertEquals(1, page.page); assertEquals("a", page.last); assertTrue(page.more)
    }
    @Test fun countSuffixAndDateTiebreakMatchOriginal() {
        assertEquals(23_000L, topicHeat(JSONObject("""{"likenum":"1w","replynum":"1k"}""")))
        val rows = listOf(JSONObject("""{"id":"old","dateline":1}"""), JSONObject("""{"id":"new","dateline":2}"""))
        assertEquals("new", rows.sortedWith(topicFeedComparator(false)).first().text("id"))
    }
}
