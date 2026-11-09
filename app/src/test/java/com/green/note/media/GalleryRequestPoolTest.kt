package com.green.note.media

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class GalleryRequestPoolTest {
    @Test fun mainAndThumbnailShareFetchAndOneReaderCancellationDoesNotStopOther() = runBlocking {
        val owner = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val pool = GalleryRequestPool<String, Int>(owner)
            val entered = CompletableDeferred<Unit>(); val finish = CompletableDeferred<Int>(); val calls = AtomicInteger()
            val request: suspend () -> Int = { calls.incrementAndGet(); entered.complete(Unit); finish.await() }
            val first = async(start = CoroutineStart.UNDISPATCHED) { pool.load("scope|url", request) }
            val second = async(start = CoroutineStart.UNDISPATCHED) { pool.load("scope|url", request) }
            withTimeout(2000) { entered.await() }; first.cancelAndJoin()
            finish.complete(42)
            assertEquals(42, withTimeout(2000) { second.await() })
            assertEquals(42, pool.load("scope|url") { error("successful value must be reused") })
            assertEquals(1, calls.get())
        } finally { owner.cancel() }
    }
    @Test fun lastReaderDisposalCancelsProducerAndNextVisitStartsFresh() = runBlocking {
        val owner = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val pool = GalleryRequestPool<String, Int>(owner)
            val entered = CompletableDeferred<Unit>(); val stopped = CompletableDeferred<Unit>()
            val reader = async(start = CoroutineStart.UNDISPATCHED) { pool.load("image") {
                entered.complete(Unit)
                try { awaitCancellation() } finally { stopped.complete(Unit) }
            } }
            withTimeout(2000) { entered.await() }; reader.cancelAndJoin()
            withTimeout(2000) { stopped.await() }
            assertEquals(7, pool.load("image") { 7 })
        } finally { owner.cancel() }
    }
    @Test fun failedFetchIsNotCachedAsSuccess() = runBlocking {
        val owner = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val pool = GalleryRequestPool<String, Int>(owner)
            try { pool.load("image") { throw IllegalStateException("broken") }; fail() } catch (_: IllegalStateException) { }
            assertEquals(8, pool.load("image") { 8 })
        } finally { owner.cancel() }
    }
    @Test fun distinctSessionAndHeadersNeverShareData() = runBlocking {
        val owner = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val pool = GalleryRequestPool<GalleryRequestIdentity, Int>(owner)
            val guest = GalleryRequestIdentity("guest", "https://example.test/a", emptyList(), 0)
            assertEquals(1, pool.load(guest) { 1 })
            assertEquals(2, pool.load(guest.copy(scope = "other")) { 2 })
            assertEquals(3, pool.load(guest.copy(headers = listOf("referer" to "different"))) { 3 })
        } finally { owner.cancel() }
    }
    @Test fun fetchFailureDoesNotCancelRegularParentOrAnotherIdentity() = runBlocking {
        val parent = Job()
        val owner = CoroutineScope(parent + Dispatchers.Default)
        try {
            val pool = GalleryRequestPool<String, Int>(owner)
            val gate = CompletableDeferred<Int>(); val started = CompletableDeferred<Unit>()
            val sibling = async(start = CoroutineStart.UNDISPATCHED) { pool.load("other") { started.complete(Unit); gate.await() } }
            withTimeout(2000) { started.await() }
            try { pool.load("broken") { throw IllegalArgumentException("network error") }; fail() } catch (_: IllegalArgumentException) { }
            assertTrue(parent.isActive)
            gate.complete(3)
            assertEquals(3, withTimeout(2000) { sibling.await() })
            assertEquals(4, pool.load("later") { 4 })
        } finally { owner.cancel() }
    }

}
