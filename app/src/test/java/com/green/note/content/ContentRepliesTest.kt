package com.green.note.content

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ContentRepliesTest {
    @Test fun recentFallbackIsBoundedAndRejectsUnrelatedReplies() = runBlocking {
        val active = AtomicInteger(); val maximum = AtomicInteger(); val details = mutableListOf<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (!path.endsWith("replyDetail")) return JSONObject("""{"data":[]} """)
                val id = query.getValue("id"); details += id
                val concurrent = active.incrementAndGet(); maximum.updateAndGet { maxOf(it, concurrent) }
                try { delay(2); return JSONObject().put("data", JSONObject().put("id", id).put("feedId", if (id == "2") "other" else "7").put("uid", "42").put("message", "回复")) }
                finally { active.decrementAndGet() }
            }
        }
        val feed = JSONObject().put("recent_reply_ids", (1..20).joinToString(",") + ",1,no,-2")
        val page = loadContentReplies(api, feed, "7", 0, false, 1, "", "")
        assertEquals(15, details.size); assertEquals(14, page.rows.size)
        assertTrue(maximum.get() <= 3); assertFalse(page.more)
        assertTrue(page.rows.all { it.text("feedid") == "7" && it.text("entityType") == "feed_reply" })
    }

    @Test fun authorFallbackNeverFetchesRecentIdsAndFiltersEmbeddedRows() = runBlocking {
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls++; assertTrue(path.endsWith("replyList")); assertEquals("1", query["fromFeedAuthor"])
                return JSONObject("""{"data":[]} """)
            }
        }
        val feed = JSONObject("""{"uid":"8","recent_reply_ids":"1,2","replyRows":[{"id":"1","uid":"9","message":"其他回复"},{"id":"2","userInfo":{"uid":"8"},"message":"作者回复"},{"id":"3","uid":"8","message":"FEED_DETAIL_REPLY_SPONSOR_CARD"}]}""")
        val result = loadContentReplies(api, feed, "7", 3, true, 1, "", "")
        assertEquals(1, calls); assertEquals(listOf("2"), result.rows.map { it.text("id") })
    }

    @Test fun cancellationDoesNotTriggerFallback() = runBlocking {
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject { calls++; throw CancellationException("leave") }
        }
        try { loadContentReplies(api, JSONObject().put("recent_reply_ids", "1,2"), "7", 0, false, 1, "", ""); fail("must cancel") }
        catch (_: CancellationException) { assertEquals(1, calls) }
    }

    @Test fun laterEmptyPageDoesNotReplayEmbeddedComments() = runBlocking {
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?) = JSONObject("""{"data":[]} """)
        }
        assertTrue(loadContentReplies(api, JSONObject("""{"replyRows":[{"id":"1"}]}"""), "7", 0, false, 2, "1", "2").rows.isEmpty())
    }

    @Test fun replyPageHidesPlaceholderRowsAndRecoversAlternateAuthorFields() = runBlocking {
        val lookups = mutableListOf<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path.endsWith("replyDetail")) {
                    lookups += query.getValue("id")
                    return JSONObject("""{"data":{"id":"33","feedId":"7","username":"补齐的作者","userAvatar":"https://a.test/b.png","uid":"8","message":"完整回复"}}""")
                }
                return JSONObject("""{"hasMore":true,"lastItem":"33","data":[
                    {"id":"31","entityType":"header","title":"评论"},
                    {"id":"32","entityType":"unknown","message":"<p>&nbsp;<br/></p>"},
                    {"reply_id":"34","user_info":{"id":88,"name":"嵌套作者","avatar":"https://a.test/a.png"},"description":"这是回复","create_time":1234},
                    {"id":"33","entityType":"feed_reply"},
                    {"id":"35","username":"只发图片","picArr":["https://a.test/p.png"]}
                ]}""")
            }
        }
        val page = loadContentReplies(api, null, "7", 0, false, 1, "", "")
        assertEquals(listOf("34", "33", "35"), page.rows.map(::replyId))
        assertEquals(listOf("33"), lookups)
        assertEquals(ReplyAuthor("88", "嵌套作者", "https://a.test/a.png"), replyAuthor(page.rows[0]))
        assertEquals("1234", page.rows[0].text("dateline"))
        assertEquals("补齐的作者", replyAuthor(page.rows[1]).name)
        assertEquals("完整回复", replyMessage(page.rows[1]))
        assertEquals("33", page.last)
        assertTrue(page.more)
    }

    @Test fun serviceOnlyPageCanAdvanceAndNestedThreadAcceptsItsParentId() = runBlocking {
        val requestPages = mutableListOf<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requestPages += query.getValue("page")
                return if (query["page"] == "1") JSONObject("""{"hasMore":true,"lastItem":"32","data":[{"id":"32","entityType":"header"}]}""")
                else JSONObject("""{"hasMore":false,"data":[{"id":"34","feedId":"31","username":"回复作者","message":"回复"}]}""")
            }
        }
        val request = ContentRequest("/v6/feed/replyList", mapOf("id" to "31", "feedType" to "feed_reply"))
        val result = loadReplyPage(api, request, "7", 1, "", "")
        assertEquals(listOf("1", "2"), requestPages)
        assertEquals(2, result.page)
        assertEquals(listOf("34"), result.rows.map(::replyId))
        assertEquals("7", result.rows.single().text("feedid"))
    }
}
