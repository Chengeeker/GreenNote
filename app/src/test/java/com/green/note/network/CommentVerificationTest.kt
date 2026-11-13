package com.green.note.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CommentVerificationTest {
    private val signer = RequestSigner(ByteArray(1024) { 65 })
    private val owner = ApiSession("fixture-device", "uid=1; token=fixture")
    private val query = linkedMapOf("id" to "42", "feedType" to "feed_reply", "listType" to "dateline_desc",
        "discussMode" to "1", "fromFeedAuthor" to "0", "page" to "3", "firstItem" to "80", "lastItem" to "50")
    private val accepted = """{"status":0,"data":[{"id":"49","message":"普通评论","replynum":0}],"hasMore":false}"""
    private val upgrade = """{"status":403,"message":"评论接口异常，请尝试升级到新版酷安"}"""

    private fun challenge(field: String = "_v2_post_token") = JSONObject().put("status", 403)
        .put("message", "当前访问需要验证码").put("messageStatus", "err_request_captcha_v2")
        .put("messageExtra", JSONObject().put("captchaType", "NEC").put("captchaId", "abcdefghijklmnop").put("captchaField", field)).toString()

    private fun response(request: Request, body: String, session: String? = null) = Response.Builder()
        .request(request).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
        .apply { if (session != null) header("Set-Cookie", "SESSID=$session; Path=/; Secure") }
        .body(body.toResponseBody()).build()

    private suspend fun challenged(block: suspend () -> Any?): CaptchaRequired {
        try { block() } catch (error: CaptchaRequired) { return error }
        error("Expected a captcha challenge")
    }

    private suspend fun rejected(block: suspend () -> Any?) {
        try { block() } catch (_: ApiException) { return }
        fail("The stale or unsupported verification must fail")
    }

    @Test fun exactCommentGetIsReplayedAndItsResponseIsConsumedOnlyOnce() = runBlocking {
        val calls = mutableListOf<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); calls += request
            response(request, if (request.url.queryParameter("_v2_post_token") == "NEC:abcdefgh:fixture-proof") accepted else challenge())
        }.build()
        val api = ApiClient({ owner }, signer, http)
        val path = "https://api.coolapk.com/v6/feed/replyList"
        val error = challenged { api.request(path, query = query) }
        assertTrue(error.canVerifyComment)
        api.verifyCommentRequest(error, "fixture-proof")
        assertEquals(2, calls.size)
        val replay = calls.last()
        assertEquals("GET", replay.method)
        assertEquals("api.coolapk.com", replay.url.host)
        assertEquals("/v6/feed/replyList", replay.url.encodedPath)
        query.forEach { (name, value) -> assertEquals(value, replay.url.queryParameter(name)) }
        assertEquals(query.keys + "_v2_post_token", replay.url.queryParameterNames)
        assertEquals("2604201", replay.header("X-App-Code"))
        assertEquals(owner.cookie, replay.header("Cookie"))
        val restored = api.request(path, query = query.entries.reversed().associate { it.key to it.value })
        assertEquals("普通评论", restored.getJSONArray("data").getJSONObject(0).getString("message"))
        assertEquals(2, calls.size)
        challenged { api.request(path, query = query) }
        assertEquals(3, calls.size)
    }

    @Test fun upgradedChallengeReplaysItsModernProfileWithoutAnotherUpgradeProbe() = runBlocking {
        val calls = mutableListOf<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); calls += request
            response(request, when {
                request.header("X-App-Code") == "2604201" -> upgrade
                request.url.queryParameter("_v2_post_token") != null -> accepted
                else -> challenge()
            })
        }.build()
        val api = ApiClient({ owner }, signer, http)
        val error = challenged { api.request("/v6/feed/replyList", query = query) }
        api.verifyCommentRequest(error, "fixture-proof")
        assertEquals(listOf("2604201", "2609291", "2609291"), calls.map { it.header("X-App-Code") })
        assertTrue(calls.all { it.url.host == "api2.coolapk.com" })
        assertEquals("16.6.4", calls.last().header("X-App-Version"))
        assertEquals("2609291", calls.last().header("X-App-Supported"))
        query.forEach { (name, value) -> assertEquals(value, calls.last().url.queryParameter(name)) }
        assertEquals(1, api.request("/v6/feed/replyList", query = query).getJSONArray("data").length())
        assertEquals(3, calls.size)
    }

    @Test fun verifiedPrimaryFallbackIsUsedBeforeRepeatingAnUnusableSecondaryRequest() = runBlocking {
        val calls = mutableListOf<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); calls += request
            response(request, when {
                request.url.host == "api2.coolapk.com" -> """{"messageStatus":"err_request_captcha_v2","message":"当前访问需要验证码"}"""
                request.url.queryParameter("_v2_post_token") != null -> accepted
                else -> challenge()
            })
        }.build()
        val api = ApiClient({ owner }, signer, http)
        val error = challenged { api.request("/v6/feed/replyList", query = query) }
        api.verifyCommentRequest(error, "fixture-proof")
        api.request("/v6/feed/replyList", query = query)
        assertEquals(listOf("api2.coolapk.com", "api.coolapk.com", "api.coolapk.com"), calls.map { it.url.host })
    }

    @Test fun replyDetailUsesItsOriginalQueryAndSessionCookieForBlankFieldProof() = runBlocking {
        val calls = mutableListOf<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); calls += request
            response(request, if (request.header("Cookie").orEmpty().contains("validate=")) accepted else challenge(""), "fixture-session")
        }.build()
        val api = ApiClient({ owner }, signer, http)
        val error = challenged { api.request("/v6/feed/replyDetail", query = mapOf("id" to "49")) }
        api.verifyCommentRequest(error, "fixture-proof")
        assertEquals(listOf("/v6/feed/replyDetail", "/v6/feed/replyDetail"), calls.map { it.url.encodedPath })
        assertEquals(setOf("id"), calls.last().url.queryParameterNames)
        assertEquals("49", calls.last().url.queryParameter("id"))
        assertTrue(calls.last().header("Cookie")!!.contains("SESSID=fixture-session"))
        assertTrue(calls.last().header("Cookie")!!.contains("validate=NEC%3Aabcdefgh%3Afixture-proof"))
        api.request("/v6/feed/replyDetail", query = mapOf("id" to "49"))
        assertEquals(2, calls.size)
    }

    @Test fun accountDeviceAndServerSessionChangesInvalidatePendingVerification() = runBlocking {
        val changedOwners = listOf(owner.copy(cookie = "uid=2; token=other", revision = 1), owner.copy(device = "other-device"), owner.copy(anonymous = true))
        for (changedOwner in changedOwners) {
            var current = owner
            var calls = 0
            val http = OkHttpClient.Builder().addInterceptor { chain -> calls++; response(chain.request(), challenge()) }.build()
            val api = ApiClient({ current }, signer, http)
            val error = challenged { api.request("/v6/feed/replyList", query = query) }
            current = changedOwner
            rejected { api.verifyCommentRequest(error, "fixture-proof") }
            assertEquals(1, calls)
        }
        var calls = 0
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            calls++
            if (chain.request().url.encodedPath == "/v6/feed/replyList") response(chain.request(), challenge(), "before")
            else response(chain.request(), accepted, "after")
        }.build()
        val api = ApiClient({ owner }, signer, http)
        val error = challenged { api.request("/v6/feed/replyList", query = query) }
        // A host-only api2 cookie must be changed on api2; another host has an independent session.
        api.request("https://api2.coolapk.com/v6/main/indexV8")
        rejected { api.verifyCommentRequest(error, "fixture-proof") }
        assertEquals(2, calls)
    }

    @Test fun sessionChangeDuringReplayCannotPopulateTheHandoffCache() = runBlocking {
        var current = owner
        var calls = 0
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            calls++
            if (calls == 2) current = owner.copy(cookie = "uid=2; token=other", revision = 1)
            response(chain.request(), if (calls == 1) challenge() else accepted)
        }.build()
        val api = ApiClient({ current }, signer, http)
        val error = challenged { api.request("/v6/feed/replyList", query = query) }
        rejected { api.verifyCommentRequest(error, "fixture-proof") }
        api.request("/v6/feed/replyList", query = query)
        assertEquals(3, calls)
    }

    @Test fun handoffRequiresTheSameHostQueryAndSessionAndExpiresAfterThirtySeconds() = runBlocking {
        var elapsed = 0L
        var current = owner
        val calls = mutableListOf<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); calls += request
            response(request, if (calls.size == 1) challenge() else accepted)
        }.build()
        val api = ApiClient({ current }, signer, http, elapsedNanos = { elapsed })
        val path = "https://api.coolapk.com/v6/feed/replyList"
        val error = challenged { api.request(path, query = query) }
        api.verifyCommentRequest(error, "fixture-proof")
        api.request("https://api2.coolapk.com/v6/feed/replyList", query = query)
        api.request(path, query = query + ("page" to "4"))
        assertEquals(4, calls.size)
        elapsed = TimeUnit.SECONDS.toNanos(31)
        api.request(path, query = query)
        assertEquals(5, calls.size)

        // A newly accepted result also cannot be consumed by another logged-in account.
        val anotherHttp = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); calls += request
            response(request, if (calls.size == 6) challenge() else accepted)
        }.build()
        val anotherApi = ApiClient({ current }, signer, anotherHttp)
        val anotherError = challenged { anotherApi.request(path, query = query) }
        anotherApi.verifyCommentRequest(anotherError, "fixture-proof")
        current = owner.copy(cookie = "uid=2; token=other", revision = 1)
        anotherApi.request(path, query = query)
        assertEquals(8, calls.size)
    }

    @Test fun secondChallengeReturnsWithoutLoopsAndTheSameReplayCannotBeSubmittedTwice() = runBlocking {
        var calls = 0
        val http = OkHttpClient.Builder().addInterceptor { chain -> calls++; response(chain.request(), challenge()) }.build()
        val api = ApiClient({ owner }, signer, http)
        val original = challenged { api.request("/v6/feed/replyList", query = query) }
        val second = challenged { api.verifyCommentRequest(original, "fixture-proof") }
        assertTrue(second.canVerifyComment)
        assertFalse(second.request!!.url.queryParameterNames.contains("_v2_post_token"))
        assertEquals(2, calls)
        rejected { api.verifyCommentRequest(original, "fixture-proof") }
        assertEquals(2, calls)
        challenged { api.request("/v6/feed/replyList", query = query) }
        assertEquals(3, calls)
    }

    @Test fun writesUnrelatedReadsAndForeignClientsCannotUseCommentReplay() = runBlocking {
        var calls = 0
        val http = OkHttpClient.Builder().addInterceptor { chain -> calls++; response(chain.request(), challenge()) }.build()
        val api = ApiClient({ owner }, signer, http)
        for ((path, method) in listOf("/v6/feed/detail" to "GET", "/v6/feed/reply" to "POST", "/v6/feed/replyList" to "POST")) {
            val error = challenged { api.request(path, method, query) }
            assertFalse(error.canVerifyComment)
            rejected { api.verifyCommentRequest(error, "fixture-proof") }
        }
        assertEquals(3, calls)
        val error = challenged { api.request("/v6/feed/replyList", query = query) }
        rejected { ApiClient({ owner }, signer, http).verifyCommentRequest(error, "fixture-proof") }
        assertEquals(4, calls)
    }

    @Test fun diagnosticsNeverIncludeQueryValuesOrUntrustedMessageStatus() {
        val url = "https://api.coolapk.com/v6/feed/replyList?id=private-id&_v2_post_token=private-proof".toHttpUrl()
        val line = ReplyDiagnostics.networkLine(url, 2604201, 200, 403, "secret-status\nCookie: private-cookie", false)!!
        assertTrue(line.contains("path=/v6/feed/replyList"))
        assertTrue(line.contains("messageStatus=other"))
        for (secret in listOf("private-id", "private-proof", "private-cookie", "secret-status", "Cookie", "\n")) assertFalse(line.contains(secret))
        assertNull(ReplyDiagnostics.networkLine("https://api.coolapk.com/v6/account/checkLoginInfo".toHttpUrl(), 2604201, 200, 0, "", false))
    }
}
