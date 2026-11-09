package com.green.note.content

import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class HomeFollowStateTest {
    private class Api(val handler: suspend (String, Map<String, String>) -> JSONObject) : ContentApi {
        override fun imageCacheScope() = "owner"
        override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
            check(method == "GET" && body == null) { "Timeline must remain read-only" }
            return handler(path, query)
        }
    }
    private fun feed(id: String, time: Int, uid: String = id) = JSONObject().put("entityType", "feed").put("id", id).put("uid", uid).put("username", "user$uid").put("message", "feed$id").put("dateline", time)
    private fun page(vararg rows: JSONObject, more: Boolean = false) = JSONObject().put("data", JSONArray(rows.toList())).put("hasMore", more)

    @Test fun originalFilterRoutesAndRecentAuthorsStayDistinct() {
        val route = followFilterRoute("/page?url=FOLLOW&type=old&title=%E5%85%B3%E6%B3%A8", "circle")
        assertEquals(mapOf("url" to "FOLLOW", "type" to "circle", "title" to "关注"), contentRequest(route).query)
        assertFalse(contentRequest(followFilterRoute(route, "")).query.containsKey("type"))
        val feeds = listOf(feed("1", 3, "9"), feed("2", 4, "8"), feed("3", 1, "9"))
        assertEquals(listOf("8", "9"), recentFollowingUsers(emptyList(), feeds).map { it.text("uid") })
        val card = JSONObject().put("title", "最近更新").put("entities", JSONArray().put(JSONObject().put("entityType", "user_follow").put("fUserInfo", JSONObject().put("uid", "5").put("username", "person"))))
        assertEquals(listOf("5"), recentFollowingUsers(listOf(card), feeds).map { it.text("uid") })
        assertTrue(followingAuthor(JSONObject().put("userAction", JSONObject().put("follow", 1))))
        assertFalse(followingAuthor(feed("1", 3)))
    }
    @Test fun changingOfficialFilterDuringLoadCannotPublishOldRows() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val finish = CompletableDeferred<Unit>(); var firstCircle = true
        val api = Api { _, query ->
            if (query["type"] == "circle" && firstCircle) { firstCircle = false; entered.complete(Unit); finish.await(); page(feed("old", 1)) }
            else page(feed(if (query["type"] == "topic") "new" else "recent", 2))
        }
        val state = OfficialHomeFollowState(api, "/page?url=FOLLOW", "owner")
        val initial = async { state.load(true) }
        withTimeout(2000) { entered.await() }
        state.select("topic"); finish.complete(Unit); withTimeout(2000) { initial.await() }
        assertEquals("topic", state.selected); assertEquals(listOf("new"), state.rows.map { it.text("id") })
        assertNull(state.error); assertFalse(state.busy)
    }
    @Test fun openingFollowWhileWarmupIsInFlightSharesTheFirstRequest() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var requests = 0
        val api = Api { _, _ ->
            requests++
            entered.complete(Unit)
            release.await()
            page()
        }
        val state = HomeFollowStore(api).official("/page?url=FOLLOW")
        val warming = launch { state.resume() }
        withTimeout(2000) { entered.await() }
        state.resume()
        release.complete(Unit)
        withTimeout(2000) { warming.join() }
        state.resume()
        assertTrue(state.initialized)
        assertEquals(1, requests)
    }
    @Test fun anonymousRequestsAreBoundedAndFailureDoesNotCancelOtherAuthors() = runBlocking {
        val active = AtomicInteger(); val peak = AtomicInteger(); val firstThree = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val api = Api { path, query ->
            assertEquals("/v6/user/feedList", path)
            val number = active.incrementAndGet(); peak.updateAndGet { maxOf(it, number) }
            if (number == 3) firstThree.complete(Unit)
            try {
                release.await()
                if (query["uid"] == "2") error("temporarily unavailable")
                page(feed(query.getValue("uid"), query.getValue("uid").toInt()))
            } finally { active.decrementAndGet() }
        }
        val state = LocalHomeFollowState(api, LocalFollowSource("profile", "", listOf("1", "2", "3", "4", "5")))
        val work = async { state.refresh() }
        withTimeout(2000) { firstThree.await() }; assertEquals(3, peak.get()); release.complete(Unit)
        withTimeout(2000) { work.await() }
        assertTrue(currentCoroutineContext().isActive); assertTrue(peak.get() <= 3)
        assertEquals(listOf("5", "4", "3", "1"), state.rows.map { it.text("id") })
        assertEquals(1, state.failed); assertEquals(5, state.progress); assertFalse(state.loading)
    }
    @Test fun publicFollowPagesUseCursorsAndFiveMinuteCacheWithoutWritingLocalFollows() = runBlocking {
        var now = 10_000L; var reads = 0
        val api = Api { path, query ->
            if (path == "/v6/user/followList") {
                reads++
                if (query["page"] == "1") page(JSONObject().put("entityType", "user").put("uid", "1"), more = true).put("firstItem", "first").put("lastItem", "last")
                else { assertEquals("first", query["firstItem"]); assertEquals("last", query["lastItem"]); page(JSONObject().put("entityType", "user").put("uid", "1"), JSONObject().put("entityType", "user").put("uid", "2")) }
            } else page(feed(query.getValue("uid"), 1))
        }
        val state = LocalHomeFollowState(api, LocalFollowSource("profile", "99", listOf("local-only")), { now })
        state.refresh(); assertEquals(listOf("1", "2"), state.userIds); assertEquals(2, reads)
        now += 299_999; state.refresh(); assertEquals(2, reads)
        now += 1; state.refresh(); assertEquals(4, reads)
        assertEquals(listOf("local-only"), state.source.userIds)
    }
    @Test fun failedRefreshPreservesCurrentSourceRowsButSourceChangeImmediatelyClearsThem() = runBlocking {
        var fails = false
        val api = Api { _, query -> if (fails) error("offline") else page(feed(query.getValue("uid"), 1)) }
        val store = HomeFollowStore(api)
        val first = store.local(LocalFollowSource("first", "", listOf("1")))
        first.refresh(); fails = true; first.refresh()
        assertEquals("1", first.rows.single().text("id")); assertEquals(1, first.failed)
        val unchanged = store.local(LocalFollowSource("first", "", listOf("1"), revision = 3))
        assertSame(first, unchanged)
        val next = store.local(LocalFollowSource("second", "", listOf("2")))
        assertNotSame(first, next); assertTrue(first.rows.isEmpty()); assertTrue(next.rows.isEmpty())
    }
    @Test fun lateResultFromRetiredIdentityIsDiscarded() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val finish = CompletableDeferred<Unit>()
        val api = Api { _, _ -> entered.complete(Unit); finish.await(); page(feed("old", 1)) }
        val store = HomeFollowStore(api)
        val old = store.local(LocalFollowSource("first", "", listOf("1")))
        val work = async { old.refresh() }; withTimeout(2000) { entered.await() }
        val next = store.local(LocalFollowSource("second", "", listOf("2")))
        finish.complete(Unit)
        try { withTimeout(2000) { work.await() }; fail("old generation must not publish") } catch (_: CancellationException) { }
        assertTrue(old.rows.isEmpty()); assertTrue(next.rows.isEmpty())
    }

    @Test fun cancelledBusyFilterRefreshResumesWithoutShowingPreviousFilterForever() = runBlocking {
        var circleCalls=0;val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>()
        val api=Api { _, query ->
            if(query["type"]=="circle") {
                circleCalls++
                if(circleCalls==2){entered.complete(Unit);release.await()}
                page(feed("circle",1))
            } else page(feed("topic",2))
        }
        val state=OfficialHomeFollowState(api,"/page?url=FOLLOW","owner")
        state.resume();assertEquals("circle",state.rows.single().text("id"))
        val refreshing=launch{state.load(true)}
        withTimeout(2000){entered.await()}
        state.select("topic")
        refreshing.cancelAndJoin()
        assertFalse(state.busy);assertEquals("topic",state.selected)
        withTimeout(2000){state.resume()}
        assertEquals(listOf("topic"),state.rows.map{it.text("id")});assertNull(state.error)
        val callsAfterResume=circleCalls
        state.resume();assertEquals(callsAfterResume,circleCalls)
    }
}
