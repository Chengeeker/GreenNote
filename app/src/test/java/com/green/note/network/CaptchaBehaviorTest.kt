package com.green.note.network

import android.app.Application
import com.green.note.account.AccountRepository
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class CaptchaBehaviorTest {
    private val challenge = """{"status":403,"message":"当前访问需要验证码","messageStatus":"err_request_captcha_v2","messageExtra":{"captchaType":"NEC","captchaId":"abcdefghijklmnop","captchaField":""}}"""

    @Test fun loggedInReadsAndWritesNeverOpenVerificationImplicitly() = runBlocking {
        var prompts = 0
        val requests = mutableListOf<okhttp3.Request>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .body(challenge.toResponseBody()).build()
        }.build()
        val owner = ApiSession("fixture-device", "uid=1; token=fixture")
        val api = ApiClient({ owner }, RequestSigner(ByteArray(1024) { 65 }), client)
        val actions = ContentActions(api, AccountRepository(RuntimeEnvironment.getApplication()), { owner }) { prompts++; "fixture-proof" }
        for ((path, method) in listOf("/v6/feed/detail" to "GET", "/v6/feed/replyList" to "GET", "/v6/feed/reply" to "POST")) {
            try { actions.request(path, method, mapOf("id" to "42")); fail("challenge lost") }
            catch (_: CaptchaRequired) { }
        }
        assertEquals(0, prompts)
        assertEquals(3, requests.size)
        assertTrue(requests.all { it.header("Cookie") == owner.cookie })
        assertEquals("api2.coolapk.com", requests[1].url.host)
    }

    @Test fun explicitVerificationReplaysOnceAndReusesOnlyAcceptedSessionProof() = runBlocking {
        var prompts = 0
        var accept = false
        val requests = mutableListOf<okhttp3.Request>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request()
            // This fixture intentionally shares one server session across api and api2.
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .header("Set-Cookie", "SESSID=fixture-session; Domain=coolapk.com; Path=/; Secure")
                .body((if (accept) """{"status":0,"data":{"id":"42","message":"正文"}}""" else challenge).toResponseBody()).build()
        }.build()
        var owner = ApiSession("fixture-device", "uid=1; token=fixture")
        val api = ApiClient({ owner }, RequestSigner(ByteArray(1024) { 65 }), client)
        val actions = ContentActions(api, AccountRepository(RuntimeEnvironment.getApplication()), { owner }) { prompts++; "fixture-proof" }
        val error = try { actions.request("/v6/feed/detail", query = mapOf("id" to "42")); error("missing challenge") }
            catch (failure: CaptchaRequired) { failure }
        accept = true
        actions.verifyFeedDetail("42", error)
        assertEquals(1, prompts)
        assertEquals(2, requests.size)
        actions.request("/v6/feed/hotReplyList", query = mapOf("id" to "42"))
        assertTrue(requests.last().header("Cookie")!!.contains("validate="))
        assertTrue(requests.last().header("Cookie")!!.contains("SESSID=fixture-session"))
        owner = owner.copy(cookie = "uid=2; token=new-fixture", revision = 1)
        actions.request("/v6/feed/detail", query = mapOf("id" to "43"))
        assertEquals(owner.cookie, requests.last().header("Cookie"))
    }

    @Test fun aSecondChallengeOrCancellationDoesNotLoopOrSaveARejectedProof() = runBlocking {
        var calls = 0
        var prompts = 0
        var cancelled = false
        val cookies = mutableListOf<String?>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            calls++; cookies += chain.request().header("Cookie")
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .body(challenge.toResponseBody()).build()
        }.build()
        val owner = ApiSession("fixture-device", "uid=1; token=fixture")
        val api = ApiClient({ owner }, RequestSigner(ByteArray(1024) { 65 }), client)
        val actions = ContentActions(api, AccountRepository(RuntimeEnvironment.getApplication()), { owner }) { prompts++; if (cancelled) null else "fixture-proof" }
        val error = try { actions.request("/v6/feed/detail", query = mapOf("id" to "42")); error("missing challenge") }
            catch (failure: CaptchaRequired) { failure }
        try { actions.verifyFeedDetail("42", error); fail("second challenge lost") } catch (_: CaptchaRequired) { }
        assertEquals(2, calls); assertEquals(1, prompts)
        try { actions.request("/v6/feed/detail", query = mapOf("id" to "42")); fail("challenge lost") } catch (_: CaptchaRequired) { }
        assertFalse(cookies.last().orEmpty().contains("validate="))
        cancelled = true
        try { actions.verifyFeedDetail("42", error); fail("cancellation lost") } catch (_: CaptchaRequired) { }
        assertEquals(3, calls); assertEquals(2, prompts)
    }

    @Test fun commentVerificationIsExplicitAndCancellationLeavesTheOriginalRequestUnreplayed() = runBlocking {
        var prompts = 0
        var cancelled = true
        var calls = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            calls++
            val request = chain.request()
            val result = if (request.header("Cookie").orEmpty().contains("validate="))
                """{"status":0,"data":[{"id":"6","message":"普通评论","replynum":0}]}""" else challenge
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .body(result.toResponseBody()).build()
        }.build()
        val owner = ApiSession("fixture-device", "uid=1; token=fixture")
        val api = ApiClient({ owner }, RequestSigner(ByteArray(1024) { 65 }), client)
        val actions = ContentActions(api, AccountRepository(RuntimeEnvironment.getApplication()), { owner }) {
            prompts++
            if (cancelled) null else "fixture-proof"
        }
        val error = try { actions.request("/v6/feed/replyList", query = mapOf("id" to "42")); error("missing challenge") }
            catch (failure: CaptchaRequired) { failure }
        assertTrue(error.canVerifyComment)
        assertEquals(0, prompts)
        try { actions.verifyCommentRequest(error); fail("cancellation lost") } catch (_: CaptchaRequired) { }
        assertEquals(1, calls)
        assertEquals(1, prompts)
        cancelled = false
        actions.verifyCommentRequest(error)
        assertEquals(2, calls)
        assertEquals(2, prompts)
        val result = actions.request("/v6/feed/replyList", query = mapOf("id" to "42"))
        assertEquals("普通评论", result.getJSONArray("data").getJSONObject(0).getString("message"))
        assertEquals(2, calls)
    }
}
