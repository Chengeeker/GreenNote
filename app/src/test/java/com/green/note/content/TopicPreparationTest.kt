package com.green.note.content

import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TopicPreparationTest {
    @Test fun failedPreparationDoesNotCancelOwnerAndCanRetry() = runBlocking {
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject { calls++; if (calls == 1) error("offline"); return JSONObject("""{"data":{"title":"ok"}}""") }
        }
        val cache = TopicPreparation(api, this)
        try { cache.prepare("ok").await(); fail("must fail") } catch (expected: IllegalStateException) { assertEquals("offline", expected.message) }
        assertTrue(isActive); assertNull(cache.ready("ok")); assertEquals("ok", cache.prepare("ok").await().detail.text("title")); assertEquals(2, calls)
    }
    @Test fun mergesPendingAndKeepsDefaultPageCursorsAcrossOpen() = runBlocking {
        val permit = CompletableDeferred<Unit>(); var detailCalls = 0; var pageCalls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                if (path.endsWith("newTagDetail")) { detailCalls++; permit.await(); return JSONObject("""{"data":{"title":"活动","tabList":[{"title":"活动详情","page_name":"main","url":"/page?url=FIRST"}],"selectedTab":"main"}}""") }
                pageCalls++; return JSONObject("""{"data":[{"id":"10"},{"id":"20"}],"hasMore":true}""")
            }
        }
        val cache = TopicPreparation(api, this)
        val first = cache.prepare("活动"); val duplicate = cache.prepare("活动"); assertSame(first, duplicate)
        permit.complete(Unit); val ready = first.await()
        assertEquals("10", ready.firstPage?.first); assertEquals("20", ready.firstPage?.last); assertTrue(ready.firstPage!!.more)
        assertSame(first, cache.prepare("活动")); assertEquals(1, detailCalls); assertEquals(1, pageCalls)
        cache.following("活动", true); yield(); assertEquals(1, cache.ready("活动")!!.detail.getJSONObject("userAction").getInt("follow"))
        cache.rememberPage("活动", "/other", ContentPage(emptyList(), 1, "", "", false)); yield(); assertEquals("20", cache.ready("活动")!!.firstPage!!.last)
    }

    @Test fun sessionsAndCacheClearInvalidateWithoutExpiry() = runBlocking {
        var owner = "a"; var calls = 0
        val api = object : ContentApi {
            override fun imageCacheScope() = owner
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject { calls++; return JSONObject("""{"data":{"title":"normal"}}""") }
        }
        val cache = TopicPreparation(api, this)
        val first = cache.prepare("normal"); first.await(); assertSame(first, cache.prepare("normal"))
        owner = "b"; assertNull(cache.ready("normal")); val second = cache.prepare("normal"); second.await(); assertNotSame(first, second)
        clearPreparedTopics(); assertNull(cache.ready("normal")); cache.prepare("normal").await(); assertEquals(3, calls)
    }

    @Test fun boundedSnapshotsAndOfficialDocumentsDoNotPreloadHtml() = runBlocking {
        val requests = mutableListOf<String>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                requests += path
                return JSONObject("""{"data":{"tabList":[{"title":"活动详情","url":"https://www.coolapk.com/activity/doc"}]}}""")
            }
        }
        val cache = TopicPreparation(api, this)
        repeat(13) { cache.prepare("$it").await() }
        assertNull(cache.ready("0")); assertNotNull(cache.ready("12")); assertEquals(13, requests.size)
        assertTrue(requests.all { it.endsWith("newTagDetail") })
    }
}
