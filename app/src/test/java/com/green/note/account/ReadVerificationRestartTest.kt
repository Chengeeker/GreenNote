package com.green.note.account

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.green.note.network.ApiClient
import com.green.note.network.ApiSession
import com.green.note.network.CaptchaRequired
import com.green.note.network.RequestSigner
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList
import javax.crypto.KeyGenerator

/** Uses the real encrypted account repository and network client on both sides of a restart. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], shadows = [ReplacingAtomicFileShadow::class])
class ReadVerificationRestartTest {
    @Test fun acceptedCommentSessionSurvivesRepositoryAndClientRecreationWithoutAnotherVerification() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val firstAccounts = AccountRepository(context) { key }
        firstAccounts.initialize()
        firstAccounts.writeSecret("guest_device_code", "restart-fixture-device")
        fun owner(accounts: AccountRepository) = accounts.state.value.let {
            ApiSession("restart-fixture-device", it.requestCookie, it.anonymous, it.sessionRevision)
        }
        val calls = CopyOnWriteArrayList<Request>()
        val proof = "NEC%3Aabcdefgh%3Arestart-fixture-proof"
        val challenge = """{"status":403,"messageStatus":"err_request_captcha_v2","message":"请完成验证","messageExtra":{"captchaType":"NEC","captchaId":"abcdefghijklmnop","captchaField":""}}"""
        val accepted = """{"status":0,"data":[{"id":"9","message":"没有子回复的普通评论","replynum":0}],"hasMore":false}"""
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            calls += request
            val verified = request.header("Cookie").orEmpty().contains("validate=$proof")
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .apply { if (verified) header("Set-Cookie", "SESSID=restart-verified-session; Path=/; Max-Age=900; Secure; HttpOnly") }
                .body((if (verified) accepted else challenge).toResponseBody()).build()
        }.build()
        val signer = RequestSigner(ByteArray(1024) { 65 })
        val first = ApiClient({ owner(firstAccounts) }, signer, http,
            verifiedReadSessionStore = AccountVerifiedReadSessionStore(firstAccounts) { owner(firstAccounts) })
        val query = mapOf("id" to "42", "page" to "1")
        val required = try { first.request("/v6/feed/replyList", query = query); error("Expected first verification") }
            catch (error: CaptchaRequired) { error }
        first.verifyCommentRequest(required, "restart-fixture-proof")
        assertEquals(1, first.request("/v6/feed/replyList", query = query).getJSONArray("data").length())
        assertEquals(2, calls.size)

        val restartedAccounts = AccountRepository(context) { key }
        restartedAccounts.initialize()
        assertEquals(firstAccounts.state.value.sessionRevision, restartedAccounts.state.value.sessionRevision)
        val restarted = ApiClient({ owner(restartedAccounts) }, signer, http,
            verifiedReadSessionStore = AccountVerifiedReadSessionStore(restartedAccounts) { owner(restartedAccounts) })
        val restored = restarted.request("/v6/feed/replyList", query = query)
        assertEquals("没有子回复的普通评论", restored.getJSONArray("data").getJSONObject(0).getString("message"))
        assertEquals(3, calls.size)
        assertTrue(calls.last().header("Cookie").orEmpty().contains("SESSID=restart-verified-session"))
        assertTrue(calls.last().header("Cookie").orEmpty().contains("validate=$proof"))
        assertNull(calls.last().url.queryParameter("_v2_post_token"))
    }

    @Test fun queryVerificationRestoresOnlyTheGrantedSessionCookieAcrossRepositoryAndClientRecreation() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val firstAccounts = AccountRepository(context) { key }
        firstAccounts.initialize()
        firstAccounts.writeSecret("guest_device_code", "restart-query-fixture-device")
        fun owner(accounts: AccountRepository) = accounts.state.value.let {
            ApiSession("restart-query-fixture-device", it.requestCookie, it.anonymous, it.sessionRevision)
        }
        val calls = CopyOnWriteArrayList<Request>()
        val proof = "NEC:abcdefgh:restart-query-fixture-proof"
        val grantedCookie = "SESSID=restart-query-session"
        val challenge = """{"status":403,"messageStatus":"err_request_captcha_v2","message":"请完成验证","messageExtra":{"captchaType":"NEC","captchaId":"abcdefghijklmnop","captchaField":"_v2_post_token"}}"""
        val accepted = """{"status":0,"data":[{"id":"10","message":"会话恢复后可读的普通评论","replynum":0}],"hasMore":false}"""
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            calls += request
            val verified = request.url.queryParameter("_v2_post_token") == proof
            val resumed = request.header("Cookie").orEmpty().split(';').any { it.trim() == grantedCookie }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .apply { if (verified) header("Set-Cookie", "$grantedCookie; Path=/v6/feed/; Secure; HttpOnly") }
                .body((if (verified || resumed) accepted else challenge).toResponseBody()).build()
        }.build()
        val signer = RequestSigner(ByteArray(1024) { 65 })
        val first = ApiClient({ owner(firstAccounts) }, signer, http,
            verifiedReadSessionStore = AccountVerifiedReadSessionStore(firstAccounts) { owner(firstAccounts) })
        val query = mapOf("id" to "42", "page" to "1")
        val required = try { first.request("/v6/feed/replyList", query = query); error("Expected first verification") }
            catch (error: CaptchaRequired) { error }
        first.verifyCommentRequest(required, "restart-query-fixture-proof")
        assertEquals(proof, calls.last().url.queryParameter("_v2_post_token"))
        assertEquals(1, first.request("/v6/feed/replyList", query = query).getJSONArray("data").length())
        assertEquals(2, calls.size)

        val restartedAccounts = AccountRepository(context) { key }
        restartedAccounts.initialize()
        assertEquals(firstAccounts.state.value.sessionRevision, restartedAccounts.state.value.sessionRevision)
        val restarted = ApiClient({ owner(restartedAccounts) }, signer, http,
            verifiedReadSessionStore = AccountVerifiedReadSessionStore(restartedAccounts) { owner(restartedAccounts) })
        val restored = restarted.request("/v6/feed/replyList", query = query)
        assertEquals("会话恢复后可读的普通评论", restored.getJSONArray("data").getJSONObject(0).getString("message"))
        assertEquals(3, calls.size)
        assertEquals("api2.coolapk.com", calls.last().url.host)
        assertTrue(calls.last().header("Cookie").orEmpty().split(';').any { it.trim() == grantedCookie })
        assertFalse(calls.last().header("Cookie").orEmpty().contains("validate="))
        assertNull(calls.last().url.queryParameter("_v2_post_token"))
    }
}
