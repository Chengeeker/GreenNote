package com.green.note.content

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ContentRepliesTest {
    @Test fun shortCommentPagesContinueUntilTheServerEndsTheList() = runBlocking {
        val requests = mutableListOf<Map<String, String>>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                assertEquals("/v6/feed/replyList", path)
                requests += query
                val page = query.getValue("page").toInt()
                val ids = when (page) { 1 -> 1..6; 2 -> 6..10; 3 -> 11..13; else -> IntRange.EMPTY }
                return JSONObject().put("data", org.json.JSONArray(ids.map { id ->
                    JSONObject().put("id", "$id").put("uid", "8").put("username", "作者").put("message", "回复$id")
                }))
            }
        }
        val state = ContentListState()
        state.bind("default") { page, first, last -> loadContentReplies(api, null, "7", 0, false, page, first, last) }
        repeat(5) { if (state.more) state.load() }
        assertEquals((1..13).map(Int::toString), state.rows.map(::replyId))
        assertEquals(listOf("1", "2", "3", "4"), requests.map { it["page"] })
        assertEquals(listOf(null, "1", "1", "1"), requests.map { it["firstItem"] })
        assertEquals(listOf(null, "6", "10", "13"), requests.map { it["lastItem"] })
        assertFalse(state.more)
    }

    @Test fun failedSortDoesNotSubstituteHotOrRecentReplies() = runBlocking {
        val requests = mutableListOf<String>()
        val failure = IllegalStateException("网络失败")
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requests += path
                if (path.endsWith("replyList")) throw failure
                return JSONObject("""{"data":[{"id":"1","username":"作者","message":"其他排序"}]}""")
            }
        }
        try {
            loadContentReplies(api, JSONObject().put("recent_reply_ids", "1,2"), "7", 2, false, 1, "", "")
            fail("A failed latest request must not become a successful hot list")
        } catch (error: IllegalStateException) { assertSame(failure, error) }
        assertEquals(listOf("/v6/feed/replyList"), requests)
    }

    @Test fun emptyServerResultDoesNotResurrectEmbeddedOrRecentReplies() = runBlocking {
        val requests = mutableListOf<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requests += path
                return JSONObject("""{"data":[],"hasMore":false}""")
            }
        }
        val feed = JSONObject("""{"uid":"8","recent_reply_ids":"1,2","replyRows":[{"id":"1","uid":"8","message":"过期回复"}]}""")
        for (order in 0..3) {
            val result = loadContentReplies(api, feed, "7", order, order == 3, 1, "", "")
            assertTrue(result.rows.isEmpty())
            assertFalse(result.more)
        }
        assertEquals(4, requests.size)
    }

    @Test fun challengeLeavesPreviouslyLoadedRepliesAndPaginationIntact() = runBlocking {
        val challenge = com.green.note.network.CaptchaRequired(com.green.note.network.CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "当前访问需要验证码")
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (++calls > 1) throw challenge
                return JSONObject("""{"data":[{"id":"9","uid":"8","username":"作者","message":"已加载的回复"}],"hasMore":true}""")
            }
        }
        val feed = JSONObject("""{"uid":"8","recent_reply_ids":"5,6","replyRows":[{"id":"1","uid":"9","message":"已收到的回复"},{"id":"2","uid":"8","message":"楼主回复"},{"id":"3","feedid":"other","message":"其他帖子"}]}""")
        assertEquals(listOf("1", "2"), embeddedReplies(feed, "7", false).map(::replyId))
        assertEquals(listOf("2"), embeddedReplies(feed, "7", true).map(::replyId))
        val state = ContentListState()
        state.bind("default") { page, first, last -> loadContentReplies(api, feed, "7", 0, false, page, first, last) }
        for (refresh in listOf(true, false)) {
            state.load(refresh)
            assertEquals(listOf("9"), state.rows.map(::replyId))
            assertTrue(state.more)
            assertTrue(state.accessRestricted)
        }
        assertEquals(3, calls)
    }

    @Test fun missingAuthorsAreHydratedWithBoundedConcurrencyAndRejectUnrelatedReplies() = runBlocking {
        val active = AtomicInteger(); val maximum = AtomicInteger(); val details = mutableListOf<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (!path.endsWith("replyDetail")) return JSONObject().put("hasMore", false).put("data",
                    org.json.JSONArray((1..7).map { JSONObject().put("id", "$it").put("entityType", "feed_reply") }))
                val id = query.getValue("id"); details += id
                val concurrent = active.incrementAndGet(); maximum.updateAndGet { maxOf(it, concurrent) }
                try { delay(2); return JSONObject().put("data", JSONObject().put("id", id).put("feedId", if (id == "2") "other" else "7").put("uid", "42").put("message", "回复")) }
                finally { active.decrementAndGet() }
            }
        }
        val page = loadContentReplies(api, null, "7", 0, false, 1, "", "")
        assertEquals(6, details.size); assertEquals(listOf("1", "3", "4", "5", "6"), page.rows.map(::replyId))
        assertTrue(maximum.get() <= 3); assertFalse(page.more)
        assertTrue(page.rows.all { it.text("feedid") == "7" && it.text("entityType") == "feed_reply" })
    }

    @Test fun authorFilterUsesServerResultsAndNeverFetchesRecentIds() = runBlocking {
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls++; assertTrue(path.endsWith("replyList")); assertEquals("1", query["fromFeedAuthor"])
                assertEquals("dateline_desc", query["listType"])
                return JSONObject("""{"hasMore":false,"data":[{"id":"1","uid":"9","username":"其他人","message":"其他回复"},{"id":"2","userInfo":{"uid":"8","username":"楼主"},"message":"作者回复"}]}""")
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
                else JSONObject("""{"hasMore":false,"lastItem":"32","data":[{"id":"34","feedId":"31","username":"回复作者","message":"回复"}]}""")
            }
        }
        val request = ContentRequest("/v6/feed/replyList", mapOf("id" to "31", "feedType" to "feed_reply"))
        val result = loadReplyPage(api, request, "7", 1, "", "")
        assertEquals(listOf("1", "2"), requestPages)
        assertEquals(2, result.page)
        assertEquals(listOf("34"), result.rows.map(::replyId))
        assertEquals("7", result.rows.single().text("feedid"))
    }

    @Test fun repeatedServicePagesAreRetryableRatherThanAFalseEnd() = runBlocking {
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls++
                return JSONObject().put("hasMore", true).put("lastItem", "${query.getValue("page")}")
                    .put("data", org.json.JSONArray("""[{"entityType":"header","title":"服务卡片"}]"""))
            }
        }
        try { loadContentReplies(api, null, "7", 0, false, 1, "", ""); fail("Incomplete comments must remain retryable") }
        catch (error: IllegalStateException) { assertEquals("评论暂未加载完整，请重试", error.message) }
        assertEquals(3, calls)
    }
}
