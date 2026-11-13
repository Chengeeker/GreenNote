package com.green.note.content

import com.green.note.network.CaptchaChallenge
import com.green.note.network.CaptchaRequired
import com.green.note.network.CommentCaptchaRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ContentListRecoveryTest {
    @Test fun partialSecondPageRetriesItsCursorAndRestoresServerOrderBeforeContinuing() = runBlocking {
        val requests = mutableListOf<Triple<Int, String, String>>()
        var attempts = 0
        val state = ContentListState()
        state.bind("default") { page, first, last ->
            requests += Triple(page, first, last)
            when (page) {
                1 -> result(1, "0")
                2 -> if (attempts++ == 0) result(2, "A", "C").copy(error = challenge(), pendingReplyCount = 1, more = false)
                    else result(2, "A", "B", "C")
                else -> result(3, "D").copy(more = false)
            }
        }
        state.load()
        assertEquals(listOf("0", "A", "C"), state.ids())
        assertNotNull(state.error)
        assertEquals(1, state.pendingReplyCount)
        state.load()
        assertEquals(listOf("0", "A", "B", "C"), state.ids())
        assertNull(state.error)
        assertEquals(0, state.pendingReplyCount)
        assertTrue(state.more)
        state.load()
        assertEquals(listOf(Triple(1, "", ""), Triple(2, "0", "0"), Triple(2, "0", "0"), Triple(3, "0", "C")), requests)
        assertEquals(listOf("0", "A", "B", "C", "D"), state.ids())
        assertFalse(state.more)
    }

    @Test fun completeRetryWithNoNewVisibleIdsStillAllowsTheNextPage() = runBlocking {
        var attempts = 0
        val pages = mutableListOf<Int>()
        val state = ContentListState()
        state.bind("default") { page, _, _ ->
            pages += page
            when (page) {
                1 -> result(1, "0")
                2 -> result(2, "A", "C").let { if (attempts++ == 0) it.copy(error = challenge(), pendingReplyCount = 1) else it }
                else -> result(page, "D").copy(more = false)
            }
        }
        state.load(); state.load()
        assertTrue(state.more)
        state.load()
        assertEquals(listOf(1, 2, 2, 3), pages)
        assertEquals(listOf("0", "A", "C", "D"), state.ids())
    }

    @Test fun partialRefreshOfAnExhaustedListCanRetryAndEventuallyReplacesOldRows() = runBlocking {
        var attempt = 0
        val requests = mutableListOf<Triple<Int, String, String>>()
        val state = ContentListState()
        state.bind("default") { page, first, last ->
            requests += Triple(page, first, last)
            when (attempt++) {
                0 -> result(1, "X", "Y").copy(more = false)
                1 -> result(1, "A", "C").copy(error = challenge(), pendingReplyCount = 1, more = false)
                else -> result(1, "A", "B", "C")
            }
        }
        state.load(true)
        assertEquals(listOf("A", "C", "X", "Y"), state.ids())
        assertFalse(state.more)
        state.load()
        assertEquals(listOf("A", "B", "C"), state.ids())
        assertEquals(List(3) { Triple(1, "", "") }, requests)
        assertNull(state.error)
        assertTrue(state.more)
    }

    @Test fun partialNewSourceDoesNotMixWithThePreviousSort() = runBlocking {
        val state = ContentListState()
        state.bind("default") { _, _, _ -> result(1, "old") }
        var attempts = 0
        state.bind("latest") { page, first, last ->
            assertEquals(Triple(1, "", ""), Triple(page, first, last))
            if (attempts++ == 0) result(1, "A", "C").copy(error = challenge(), pendingReplyCount = 1)
            else result(1, "A", "B", "C")
        }
        assertEquals(listOf("A", "C"), state.ids())
        state.load()
        assertEquals(listOf("A", "B", "C"), state.ids())
        assertEquals("latest", state.appliedSource)
    }

    @Test fun explicitVerificationResumesTheSavedSecondPageExactlyOnce() = runBlocking {
        var verified = false
        var verificationCalls = 0
        val requests = mutableListOf<Triple<Int, String, String>>()
        val required = challenge()
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) {
                assertSame(required, challenge)
                verificationCalls++
                verified = true
            }
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject = error("Unexpected request")
        }
        val state = ContentListState()
        state.bind("default") { page, first, last ->
            requests += Triple(page, first, last)
            if (page == 1) result(1, "0")
            else if (!verified) result(2, "A").copy(error = required, pendingReplyCount = 1, more = false)
            else result(2, "A", "B").copy(more = false)
        }
        state.load()
        assertEquals(0, verificationCalls)
        assertSame(required, state.verificationChallenge)
        state.verify(api)
        state.verify(api)
        assertEquals(1, verificationCalls)
        assertEquals(listOf(Triple(1, "", ""), Triple(2, "0", "0"), Triple(2, "0", "0")), requests)
        assertEquals(listOf("0", "A", "B"), state.ids())
        assertNull(state.error)
        assertFalse(state.verifying)
    }

    @Test fun oldVerificationFailureCannotClearTheNewSourcesBusyStateOrReplaceItsError() = runBlocking {
        val releaseVerification = CompletableDeferred<Unit>()
        val releaseNewSource = CompletableDeferred<ContentPage>()
        val state = ContentListState()
        state.bind("old") { _, _, _ -> throw challenge() }
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) {
                releaseVerification.await()
                error("Old verification failed")
            }
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject = error("Unexpected request")
        }
        val verification = launch(start = CoroutineStart.UNDISPATCHED) { state.verify(api) }
        val replacement = launch(start = CoroutineStart.UNDISPATCHED) { state.bind("new") { _, _, _ -> releaseNewSource.await() } }
        releaseVerification.complete(Unit)
        verification.join()
        assertTrue(state.busy)
        assertNull(state.error)
        releaseNewSource.complete(result(1, "new"))
        replacement.join()
        assertEquals(listOf("new"), state.ids())
        assertEquals("new", state.appliedSource)
        assertFalse(state.busy)
        assertNull(state.error)
    }

    @Test fun cancellingVerificationKeepsTheReadableRowsAndRetryChallenge() = runBlocking {
        val required = challenge()
        val state = ContentListState()
        state.bind("default") { _, _, _ -> result(1, "readable").copy(error = required, pendingReplyCount = 1) }
        val api = object : ContentApi {
            override suspend fun verifyCommentRequest(challenge: CaptchaRequired) { throw CancellationException("dismissed") }
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject = error("Unexpected request")
        }
        try { state.verify(api); fail("Cancellation must propagate") } catch (_: CancellationException) { }
        assertEquals(listOf("readable"), state.ids())
        assertSame(required, state.verificationChallenge)
        assertFalse(state.busy)
        assertFalse(state.verifying)
    }

    private fun ContentListState.ids() = rows.map { it.text("id") }
    private fun result(page: Int, vararg ids: String) = ContentPage(
        ids.map { JSONObject().put("entityType", "feed_reply").put("id", it).put("message", it) }, page,
        if (page == 1) ids.firstOrNull().orEmpty() else "0", ids.lastOrNull().orEmpty(), true,
    )
    private fun challenge() = CaptchaRequired(CaptchaChallenge("abcdefghijklmnop", ""), "fixture", "请完成验证",
        CommentCaptchaRequest("https://api.coolapk.com/v6/feed/replyList?id=42".toHttpUrl(), false, Any()))
}
