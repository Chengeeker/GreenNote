package com.green.note.content

import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HomeFeedStateTest {
    @Test fun scrollingUsesMeasuredExtentNotFractionOfItemCount() {
        val initial = homeScrollMetrics(0, 2, 0f, 600f, 10, 500f, 0f)
        assertEquals(1500f, initial.first, .001f); assertEquals(0f, initial.second, .001f)
        val middle = homeScrollMetrics(4, 6, -50f, 550f, 10, 500f, 50f)
        assertEquals(650f, middle.first, .001f); assertEquals(850f / 1500f, middle.second, .001f)
        assertEquals(0f, homeScrollMetrics(8, 9, -50f, 350f, 10, 500f, 50f).first, .001f)
    }
    private class Api(val reply: suspend (String, Map<String, String>) -> JSONObject) : ContentApi {
        var owner = "owner"
        override fun imageCacheScope() = owner
        override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
            assertEquals("GET", method); assertNull(body); return reply(path, query)
        }
    }
    private fun feed(id: String) = JSONObject().put("id", id).put("entityType", "feed").put("message", "content")
    private fun page(items: List<JSONObject>, more: Boolean = false) = JSONObject().put("data", JSONArray(items)).put("hasMore", more)
    private fun card() = JSONObject().put("entityType", "card").put("entityTemplate", "selectorLinkCard").put("entities", JSONArray().put(JSONObject().put("title", "all").put("url", "/page?url=all")))

    @Test fun stagedRowsReleaseBeforeNetworkAndRepeatedPagesStop() = runBlocking {
        var calls = 0
        val api = Api { _, _ -> calls++; page((1..10).map { feed("$it") }, true).put("lastItem", "10") }
        val state = HomeFeedState(api, "hot", "/page?url=RANKING")
        state.load(true)
        assertEquals(6, state.rows.size); assertTrue(state.hasBuffer); assertTrue(state.ranked)
        state.load(); assertEquals(10, state.rows.size); assertEquals(1, calls)
        state.load(); assertFalse(state.more); assertEquals(10, state.rows.size); assertEquals(2, calls)
    }
    @Test fun emptyRefreshPreservesContentAndCardsOnlyFirstPageAdvances() = runBlocking {
        var empty = false; val requests = mutableListOf<String>()
        val api = Api { _, q -> requests += q.getValue("page"); when {
            empty -> page(emptyList())
            q["page"] == "1" -> page(listOf(card()), true)
            else -> page(listOf(feed("1")))
        } }
        val state = HomeFeedState(api, "tutorial", "/page?url=tutorial")
        state.load(true); assertEquals(listOf("1", "2"), requests)
        assertEquals("1", state.rows.single().text("id")); assertEquals(1, state.cards.size)
        empty = true; state.load(true)
        assertEquals("1", state.rows.single().text("id")); assertEquals(1, state.cards.size)
    }
    @Test fun categoryChangeDuringRequestPublishesOnlyNewRowsAndRetainsHeader() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val api = Api { _, q ->
            if (q["url"] == "old") { entered.complete(Unit); release.await(); page(listOf(card(), feed("old"))) }
            else page(listOf(card(), feed("new")))
        }
        val state = HomeFeedState(api, "hot", "/page?url=old")
        val work = async { state.load(true) }; entered.await()
        state.select(JSONObject().put("url", "/page?url=new"), 1); release.complete(Unit); work.await()
        assertEquals("new", state.rows.single().text("id")); assertEquals(1, state.activeIndex); assertNull(state.error)
    }
    @Test fun changedAccountCannotPublishPendingResponse() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val api = Api { _, _ -> entered.complete(Unit); release.await(); page(listOf(feed("old"))) }
        val state = HomeFeedState(api, "hot", "/page?url=hot")
        val work = async { state.load(true) }; entered.await(); api.owner = "new"; release.complete(Unit); work.await()
        assertTrue(state.rows.isEmpty()); assertFalse(state.busy)
    }
    @Test fun cacheRejectsOtherAccountsAndMalformedValuesAndBoundsRetainedRows() {
        val raw = JSONObject().put("scope", "anonymous-one").put("feeds", JSONArray((1..30).map { feed("$it") })).put("banners", JSONArray((1..8).map { card() })).toString()
        assertNull(decodeHeadlineSnapshot(raw, "anonymous-two")); assertNull(decodeHeadlineSnapshot("not json", "anonymous-one"))
        val snapshot = decodeHeadlineSnapshot(raw, "anonymous-one")!!
        assertEquals(20, snapshot.feeds.size); assertEquals(5, snapshot.cards.size)
    }
    @Test fun headlineLastCursorUsesIndexFeedOrderAndHomeCardsDoNotCountAsFeeds() = runBlocking {
        val api = Api { path, _ -> if (path.endsWith("headline")) page(listOf(feed("headline"), feed("same"))) else page(listOf(card(), feed("same"), feed("index-last"))) }
        val result = ContentRepository(api).home("/v6/main/headline", 1)
        assertEquals("index-last", result.last); assertEquals(listOf("headline", "same", "index-last"), extractFeeds(JSONObject().put("data", JSONArray(result.rows))).map { it.text("id") })
        val cardsOnly = Api { _, _ -> JSONObject().put("data", JSONArray(List(15) { card() })) }
        assertFalse(ContentRepository(cardsOnly).home("/page?url=hot", 1).more)
    }
    @Test fun feedChildrenNeverBecomeHomeCursorsOrInflatePageSize() {
        val rows = (1..9).map { feed("$it").put("entities", JSONArray().put(JSONObject().put("id", "option-$it"))) }
        val page = parseHomePage(JSONObject(), 1, rows)
        assertEquals("1", page.first); assertEquals("9", page.last); assertFalse(page.more)
        assertTrue(parseHomePage(JSONObject().put("hasMore", JSONObject.NULL).put("has_more", true), 1, rows).more)
    }
    @Test fun cancelledFilterRequestResumesNewSelectionAndVideoIndexCanStayZero() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val hold = CompletableDeferred<Unit>(); var pause = false
        val api = Api { _, q ->
            if (pause && q["url"] == "initial") { entered.complete(Unit); hold.await() }
            page(listOf(feed(q.getValue("url"))))
        }
        val state = HomeFeedState(api, "video", "/page?url=initial")
        state.load(true); pause = true
        val work = launch { state.load(true) }; entered.await()
        state.select(JSONObject().put("url", "/page?url=latest"), 0); work.cancelAndJoin()
        state.resume(); assertEquals("latest", state.rows.single().text("id"))
        state.select(JSONObject().put("url", "/page?url=hot"), 0)
        assertEquals("hot", state.rows.single().text("id")); assertFalse(state.busy)
    }
    @Test fun cacheDeletionStaysInsideItsOwnCanonicalDirectory() {
        val parent = java.nio.file.Files.createTempDirectory("home-cache-test").toFile().canonicalFile
        try {
            val root = java.io.File(parent, "compose-home").apply { mkdirs() }
            val outside = java.io.File(parent, "flutter-cache").apply { mkdirs() }
            val saved = java.io.File(outside, "saved").apply { writeText("retained") }
            java.io.File(root, "nested").mkdirs(); java.io.File(root, "nested/data.json").writeText("cache")
            clearHomeCacheDirectory(root)
            assertTrue(root.isDirectory); assertTrue(root.listFiles()!!.isEmpty()); assertEquals("retained", saved.readText())
            assertThrows(IllegalArgumentException::class.java) { clearHomeCacheDirectory(java.io.File(root, "../flutter-cache")) }
            assertTrue(saved.exists())
        } finally { parent.deleteRecursively() }
    }
}
