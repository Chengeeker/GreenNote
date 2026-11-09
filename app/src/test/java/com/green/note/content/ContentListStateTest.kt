package com.green.note.content

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ContentListStateTest {
    @Test fun paginationPreparesOffCallerThreadAndDoesNotRestoreAConcurrentRemoval() = runBlocking {
        val caller = Thread.currentThread()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val firstRead = AtomicBoolean(true)
        val removed = object : JSONObject() {
            override fun opt(key: String): Any? {
                if (key == "id" && Thread.currentThread() !== caller && firstRead.compareAndSet(true, false)) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS)) { "Test did not release page preparation" }
                }
                return super.opt(key)
            }
        }.put("entityType", "feed").put("id", "removed")
        val kept = result("kept").rows.single()
        val incoming = result("new").rows.single()
        val state = ContentListState(listOf(removed, kept)) { _, _, _ ->
            ContentPage(listOf(kept, incoming, incoming), 2, "kept", "new", true)
        }
        val load = launch(start = CoroutineStart.UNDISPATCHED) { state.load() }
        try {
            assertTrue("Historical keys must be prepared off the caller thread", entered.await(5, TimeUnit.SECONDS))
            state.remove(removed)
        } finally {
            release.countDown()
        }
        withTimeout(5000) { load.join() }
        assertEquals(listOf("kept", "new"), state.rows.map { it.text("id") })
        assertNull(state.error)
        assertFalse(state.busy)
    }

    @Test fun sortingKeepsRowsAndIgnoresOlderResultsAndPagination() = runBlocking {
        val state = ContentListState()
        val nextPage = CompletableDeferred<ContentPage>()
        state.bind("default") { page, _, _ -> if (page == 1) result("default") else nextPage.await() }
        val pagination = launch(start = CoroutineStart.UNDISPATCHED) { state.load() }
        val latestPage = CompletableDeferred<ContentPage>()
        val latest = launch(start = CoroutineStart.UNDISPATCHED) {
            state.bind("latest") { _, _, _ -> latestPage.await() }
        }
        assertEquals("default", state.rows.single().text("id"))
        state.bind("hot") { page, first, last ->
            assertEquals(1, page)
            assertEquals("", first)
            assertEquals("", last)
            result("hot")
        }
        nextPage.complete(result("old-next", page = 2))
        latestPage.complete(result("old-latest"))
        pagination.join()
        latest.join()
        assertEquals("hot", state.rows.single().text("id"))
        assertEquals("hot", state.appliedSource)
        assertFalse(state.busy)
    }

    @Test fun failedSortRetriesItsFirstPageEvenWhenOldListWasExhausted() = runBlocking {
        val state = ContentListState()
        state.bind("default") { _, _, _ -> result("default").copy(more = false) }
        var attempt = 0
        state.bind("latest") { page, first, last ->
            assertEquals(1, page)
            assertTrue(first.isEmpty() && last.isEmpty())
            if (attempt++ == 0) error("network")
            result("latest").copy(rows = emptyList())
        }
        assertEquals("default", state.rows.single().text("id"))
        assertEquals("default", state.appliedSource)
        assertEquals("network", state.error)
        state.load()
        assertTrue(state.rows.isEmpty())
        assertNull(state.error)
        assertEquals("latest", state.appliedSource)
    }

    private fun result(id: String, page: Int = 1) =
        ContentPage(listOf(JSONObject().put("entityType", "feed").put("id", id)), page, id, id, true)
}
