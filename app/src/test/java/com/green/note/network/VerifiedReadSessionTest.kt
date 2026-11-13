package com.green.note.network

import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class VerifiedReadSessionTest {
    private val owner = ApiSession("private-device", "uid=1; token=private-account-token", revision = 7)
    private val signer = RequestSigner(ByteArray(1024) { 65 })
    private val path = "https://api2.coolapk.com/v6/feed/replyDetail"
    private val accepted = """{"status":0,"data":{"id":"private-id","message":"private-body"}}"""
    private fun challenge(field: String = "") = JSONObject().put("status", 403).put("messageStatus", "err_request_captcha_v2")
        .put("messageExtra", JSONObject().put("captchaType", "NEC").put("captchaId", "abcdefghijklmnop").put("captchaField", field)).toString()
    private fun response(request: Request, body: String = accepted, cookies: List<String> = emptyList()) = Response.Builder()
        .request(request).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
        .apply { cookies.forEach { addHeader("Set-Cookie", it) } }.body(body.toResponseBody()).build()
    private suspend fun challenged(block: suspend () -> Any?): CaptchaRequired {
        try { block() } catch (error: CaptchaRequired) { return error }; error("Expected challenge")
    }
    private open class Store : VerifiedReadSessionStore {
        @Volatile var value: String? = null
        val writes = CopyOnWriteArrayList<String?>()
        override suspend fun read(owner: ApiSession): String? = value
        override suspend fun compareAndSet(owner: ApiSession, expected: String?, replacement: String?): Boolean = synchronized(this) {
            if (value != expected) false else { value = replacement; writes += replacement; true }
        }
    }
    private fun client(store: VerifiedReadSessionStore, http: OkHttpClient, clock: () -> Long = System::currentTimeMillis,
                       session: () -> ApiSession = { owner }) = ApiClient(session, signer, http,
        verifiedReadSessionStore = store, wallClockMillis = clock)

    @Test fun cookieVerificationSurvivesRestartWithoutPersistingBodiesOrOwnerCredentials() = runBlocking {
        val store = Store(); val requests = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); requests += request
            val verified = request.header("Cookie").orEmpty().contains("validate=")
            response(request, if (verified) accepted else challenge(), if (verified)
                listOf("SESSID=server-session; Path=/; Secure; HttpOnly") else emptyList())
        }.build()
        val first = client(store, http)
        first.verifyCommentRequest(challenged { first.request(path, query = mapOf("id" to "private-id")) }, "accepted-proof")
        val encoded = store.value!!
        for (secret in listOf(owner.device, owner.cookie, "private-account-token", "private-id", "private-body")) assertFalse(encoded.contains(secret))
        assertFalse(JSONObject(encoded).getJSONObject("session").getBoolean("persistent"))
        val second = client(store, http)
        second.request(path, query = mapOf("id" to "another-id"))
        assertEquals(3, requests.size)
        assertTrue(requests.last().header("Cookie")!!.contains("SESSID=server-session"))
        assertTrue(requests.last().header("Cookie")!!.contains("accepted-proof"))
        assertEquals(1, store.writes.size)
    }

    @Test fun originalExpiryAndClockRollbackNeverRenewVerificationOnRestart() = runBlocking {
        var clock = System.currentTimeMillis()
        val store = Store(); val observed = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            observed += chain.request()
            response(chain.request(), if (observed.size == 1) challenge() else accepted)
        }.build()
        val first = client(store, http, { clock })
        first.verifyCommentRequest(challenged { first.request(path) }, "bounded-proof")
        val saved = store.value!!; val expires = JSONObject(saved).getLong("expires")
        clock += 30 * 60 * 1000L
        client(store, http, { clock }).request(path)
        assertTrue(observed.last().header("Cookie")!!.contains("bounded-proof"))
        assertEquals(expires, JSONObject(store.value!!).getLong("expires"))
        clock = expires
        client(store, http, { clock }).request(path)
        assertFalse(observed.last().header("Cookie").orEmpty().contains("validate="))
        assertNull(store.value)
        store.value = saved; clock = JSONObject(saved).getLong("issued") - 1
        client(store, http, { clock }).request(path)
        assertFalse(observed.last().header("Cookie").orEmpty().contains("validate="))
        assertNull(store.value)
    }

    @Test fun restoredHostOnlyCookieAndProofRespectHostAndPathWhileDomainCookieCanMatchBothHosts() = runBlocking {
        for (domain in listOf("", "; Domain=coolapk.com")) {
            val store = Store(); val seen = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); seen += request
                response(request, if (seen.size == 1) challenge() else accepted,
                    if (seen.size == 2) listOf("SESSID=scoped; Path=/v6/feed; Secure$domain") else emptyList())
            }.build()
            val api = client(store, http)
            api.verifyCommentRequest(challenged { api.request(path) }, "scope-proof")
            val resumed = client(store, http)
            resumed.request(path)
            assertTrue(seen.last().header("Cookie")!!.contains("SESSID=scoped"))
            resumed.request("https://api.coolapk.com/v6/feed/replyDetail")
            assertEquals(domain.isNotEmpty(), seen.last().header("Cookie").orEmpty().contains("SESSID=scoped"))
            assertEquals(domain.isNotEmpty(), seen.last().header("Cookie").orEmpty().contains("validate="))
            resumed.request("https://api2.coolapk.com/v6/main/indexV8")
            assertFalse(seen.last().header("Cookie").orEmpty().contains("SESSID=scoped"))
            assertFalse(seen.last().header("Cookie").orEmpty().contains("validate="))
        }
    }

    @Test fun queryProofIsNeverSavedAndTheAcceptedServerSessionResumesWithItsOriginalDeadline() = runBlocking {
        for (expiry in listOf("", "; Max-Age=900")) {
            var clock = System.currentTimeMillis()
            val store = Store(); val seen = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); seen += request
                response(request, if (seen.size == 1) challenge("_v2_post_token") else accepted,
                    if (seen.size == 2) listOf("SESSID=query-session; Path=/; Secure$expiry") else emptyList())
            }.build()
            val api = client(store, http, { clock })
            api.verifyCommentRequest(challenged { api.request(path) }, "query-proof-must-not-persist")
            assertFalse(store.value.orEmpty().contains("query-proof-must-not-persist"))
            assertTrue(JSONObject(store.value!!).isNull("proof"))
            assertEquals(expiry.isNotEmpty(), JSONObject(store.value!!).getJSONObject("session").getBoolean("persistent"))
            val deadline = JSONObject(store.value!!).getLong("expires")
            client(store, http, { clock }).request(path)
            assertTrue(seen.last().header("Cookie").orEmpty().contains("SESSID=query-session"))
            assertFalse(seen.last().header("Cookie").orEmpty().contains("validate="))
            assertNull(seen.last().url.queryParameter("_v2_post_token"))
            assertEquals(deadline, JSONObject(store.value!!).getLong("expires"))
            clock = deadline
            client(store, http, { clock }).request(path)
            assertFalse(seen.last().header("Cookie").orEmpty().contains("SESSID=query-session"))
            assertNull(store.value)
        }
    }

    @Test fun shorterServerExpiryCapsTheSavedCookieProof() = runBlocking {
        var clock = System.currentTimeMillis()
        val store = Store(); val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            seen += chain.request()
            response(chain.request(), if (seen.size == 1) challenge() else accepted,
                if (seen.size == 2) listOf("SESSID=short-session; Path=/; Secure; Max-Age=60") else emptyList())
        }.build()
        val api = client(store, http, { clock })
        api.verifyCommentRequest(challenged { api.request(path) }, "short-proof")
        val saved = JSONObject(store.value!!)
        assertEquals(saved.getJSONObject("session").getLong("expires"), saved.getLong("expires"))
        assertTrue(saved.getLong("expires") - saved.getLong("issued") < 3600000)
        clock = saved.getLong("expires")
        client(store, http, { clock }).request(path)
        assertFalse(seen.last().header("Cookie").orEmpty().contains("validate="))
        assertFalse(seen.last().header("Cookie").orEmpty().contains("short-session"))
        assertNull(store.value)
    }

    @Test fun expiredNarrowCookieDoesNotHideALiveWiderCookie() = runBlocking {
        val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            seen += chain.request()
            response(chain.request(), cookies = if (seen.size == 1) listOf(
                "SESSID=live; Path=/; Secure", "SESSID=; Path=/v6/feed; Secure; Max-Age=0") else emptyList())
        }.build()
        val api = client(Store(), http)
        api.request(path); api.request(path)
        assertTrue(seen.last().header("Cookie")!!.contains("SESSID=live"))
    }

    @Test fun accountDeviceAnonymousModeAndPersistentEpochAllIsolateSavedProof() = runBlocking {
        val store = Store(); val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            seen += chain.request(); response(chain.request(), if (seen.size == 1) challenge() else accepted)
        }.build()
        val api = client(store, http)
        api.verifyCommentRequest(challenged { api.request(path) }, "isolated-proof")
        val original = store.value
        for (other in listOf(owner.copy(cookie = "uid=2; token=other"), owner.copy(device = "other-device"),
            owner.copy(anonymous = true), owner.copy(revision = 8))) {
            store.value = original
            client(store, http, session = { other }).request(path)
            assertFalse(seen.last().header("Cookie").orEmpty().contains("isolated-proof"))
        }
    }

    @Test fun lateChallengeCannotClearOrRotateANewerVerifiedSession() = runBlocking {
        val store = Store(); val started = CountDownLatch(1); val release = CountDownLatch(1)
        val seen = ConcurrentHashMap<String, Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); val id = request.url.queryParameter("id")!!; seen[id] = request
            val proof = request.header("Cookie").orEmpty()
            when {
                id == "stale" -> { started.countDown(); check(release.await(10, TimeUnit.SECONDS));
                    response(request, challenge(), listOf("SESSID=stale-overwrite; Path=/; Secure")) }
                id == "first" && !proof.contains("proof-A") -> response(request, challenge())
                id == "second" && !proof.contains("proof-B") -> response(request, challenge())
                else -> response(request)
            }
        }.build()
        val api = client(store, http)
        api.verifyCommentRequest(challenged { api.request(path, query = mapOf("id" to "first")) }, "proof-A")
        val stale = async(Dispatchers.Default) { challenged { api.request(path, query = mapOf("id" to "stale")) } }
        try {
            assertTrue(started.await(10, TimeUnit.SECONDS))
            api.verifyCommentRequest(challenged { api.request(path, query = mapOf("id" to "second")) }, "proof-B")
            val newest = store.value
            release.countDown(); stale.await()
            assertEquals(newest, store.value)
            api.request(path, query = mapOf("id" to "probe"))
            assertTrue(seen["probe"]!!.header("Cookie")!!.contains("proof-B"))
            assertFalse(seen["probe"]!!.header("Cookie")!!.contains("stale-overwrite"))
        } finally { release.countDown() }
    }

    @Test fun staleClientCompareAndSetCannotDeleteAnotherClientsNewerSnapshot() = runBlocking {
        val store = Store(); val started = CountDownLatch(1); val release = CountDownLatch(1)
        val seen = ConcurrentHashMap<String, Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); val id = request.url.queryParameter("id")!!; seen[id] = request
            when {
                id == "stale" -> { started.countDown(); check(release.await(10, TimeUnit.SECONDS)); response(request, challenge()) }
                id == "A" && !request.header("Cookie").orEmpty().contains("proof-A") -> response(request, challenge())
                id == "B" && !request.header("Cookie").orEmpty().contains("proof-B") -> response(request, challenge())
                else -> response(request)
            }
        }.build()
        val first = client(store, http)
        first.verifyCommentRequest(challenged { first.request(path, query = mapOf("id" to "A")) }, "proof-A")
        val stale = async(Dispatchers.Default) { challenged { first.request(path, query = mapOf("id" to "stale")) } }
        try {
            assertTrue(started.await(10, TimeUnit.SECONDS))
            val second = client(store, http)
            second.verifyCommentRequest(challenged { second.request(path, query = mapOf("id" to "B")) }, "proof-B")
            val newest = store.value
            release.countDown(); stale.await()
            assertEquals(newest, store.value)
            client(store, http).request(path, query = mapOf("id" to "resumed"))
            assertTrue(seen["resumed"]!!.header("Cookie")!!.contains("proof-B"))
        } finally { release.countDown() }
    }

    @Test fun diskFailureDoesNotTurnAnAcceptedReadIntoAnError() = runBlocking {
        val store = object : Store() {
            override suspend fun compareAndSet(owner: ApiSession, expected: String?, replacement: String?): Boolean = throw IOException("fixture disk failure")
        }
        val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            seen += chain.request(); response(chain.request(), if (seen.size == 1) challenge() else accepted)
        }.build()
        val api = client(store, http)
        api.verifyCommentRequest(challenged { api.request(path) }, "memory-proof")
        api.request(path, query = mapOf("id" to "new"))
        assertTrue(seen.last().header("Cookie")!!.contains("memory-proof"))
        assertNull(store.value)
    }

    @Test fun suspendedOldDiskWriteFinishesWithTheNewestSuccessfulVerification() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val store = object : Store() {
            override suspend fun compareAndSet(owner: ApiSession, expected: String?, replacement: String?): Boolean {
                if (replacement?.contains("proof-A") == true) { entered.complete(Unit); release.await() }
                return super.compareAndSet(owner, expected, replacement)
            }
        }
        val observed = ConcurrentHashMap<String, Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); val id = request.url.queryParameter("id")!!; observed[id] = request
            response(request, if (id != "probe" && request.header("Cookie").orEmpty().contains("validate=").not()) challenge() else accepted)
        }.build()
        val api = client(store, http)
        val first = challenged { api.request(path, query = mapOf("id" to "A")) }
        val second = challenged { api.request(path, query = mapOf("id" to "B")) }
        val old = async(Dispatchers.Default) { try { api.verifyCommentRequest(first, "proof-A") } catch (_: ApiException) { } }
        try {
            withTimeout(5000) { entered.await() }
            val newest = async(Dispatchers.Default) { api.verifyCommentRequest(second, "proof-B") }
            withTimeout(5000) {
                do { api.request(path, query = mapOf("id" to "probe")); yield() }
                while (observed["probe"]?.header("Cookie").orEmpty().contains("proof-B").not())
            }
            release.complete(Unit)
            old.await(); newest.await()
            assertTrue(store.value!!.contains("proof-B"))
            assertFalse(store.value!!.contains("proof-A"))
            client(store, http).request(path, query = mapOf("id" to "probe"))
            assertTrue(observed["probe"]!!.header("Cookie")!!.contains("proof-B"))
        } finally { release.complete(Unit) }
    }

    @Test fun serverCookieDeletionOnAnErrorCannotResurrectOldVerifiedStateAfterRestart() = runBlocking {
        for (redirect in listOf(false, true)) {
        val store = Store(); val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); seen += request
            when (request.url.queryParameter("id")) {
                "fail" -> response(request, """{"status":403,"message":"fixture refusal"}""", listOf("SESSID=; Path=/; Max-Age=0; Secure"))
                    .newBuilder().code(if (redirect) 302 else 200).build()
                else -> response(request, if (seen.size == 1) challenge() else accepted,
                    if (seen.size == 2) listOf("SESSID=old-session; Path=/; Secure") else emptyList())
            }
        }.build()
        val api = client(store, http)
        api.verifyCommentRequest(challenged { api.request(path) }, "revoked-proof")
        try { api.request(path, query = mapOf("id" to "fail")); fail("Expected refusal") } catch (_: ApiException) { }
        assertNull(store.value)
        client(store, http).request(path)
        assertFalse(seen.last().header("Cookie").orEmpty().contains("validate="))
        assertFalse(seen.last().header("Cookie").orEmpty().contains("old-session"))
        }
    }

    @Test fun legacyFeedVerificationCannotInstallProofIntoAConcurrentlyChangedSession() = runBlocking {
        val store = Store(); val entered = CountDownLatch(1); val release = CountDownLatch(1)
        val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); seen += request
            when {
                request.url.encodedPath == "/v6/main/indexV8" -> response(request, cookies = listOf("SESSID=new-session; Path=/; Secure"))
                request.header("Cookie").orEmpty().contains("validate=") -> {
                    entered.countDown(); check(release.await(10, TimeUnit.SECONDS)); response(request)
                }
                else -> response(request, challenge())
            }
        }.build()
        val api = client(store, http)
        val error = challenged { api.request("/v6/feed/detail", query = mapOf("id" to "1")) }
        val replay = async(Dispatchers.Default) {
            try { api.verifyFeedDetail("1", error, "late-proof"); false } catch (_: ApiException) { true }
        }
        try {
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            api.request("/v6/main/indexV8")
            release.countDown()
            assertTrue(replay.await())
            assertNull(store.value)
            api.request("/v6/main/indexV8")
            assertFalse(seen.last().header("Cookie").orEmpty().contains("validate="))
        } finally { release.countDown() }
    }

    @Test fun anUnrelatedHostFailureCannotRevokeTheVerifiedOriginSession() = runBlocking {
        val store = Store(); val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); seen += request
            when {
                request.url.host == "api.coolapk.com" -> response(request,
                    """{"status":403,"message":"fixture error"}""", listOf("SESSID=main-only; Path=/; Secure"))
                seen.size == 1 -> response(request, challenge())
                seen.size == 2 -> response(request, cookies = listOf("SESSID=api2-only; Path=/; Secure"))
                else -> response(request)
            }
        }.build()
        val api = client(store, http)
        api.verifyCommentRequest(challenged { api.request(path) }, "api2-proof")
        val saved = store.value
        try { api.request("https://api.coolapk.com/v6/main/indexV8"); fail("Expected error") } catch (_: ApiException) { }
        assertEquals(saved, store.value)
        api.request(path, query = mapOf("id" to "new"))
        assertTrue(seen.last().header("Cookie")!!.contains("api2-proof"))
        assertTrue(seen.last().header("Cookie")!!.contains("SESSID=api2-only"))
        assertFalse(seen.last().header("Cookie")!!.contains("main-only"))
    }

    @Test fun malformedAndUnreasonablyLongSnapshotsAreRejected() = runBlocking {
        val store = Store(); val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            seen += chain.request(); response(chain.request(), if (seen.size == 1) challenge() else accepted)
        }.build()
        val api = client(store, http)
        api.verifyCommentRequest(challenged { api.request(path) }, "fixture-proof")
        val valid = JSONObject(store.value!!)
        for (invalid in listOf("not-json", "x".repeat(30000),
            JSONObject(valid.toString()).put("expires", valid.getLong("issued") + 7200000).toString())) {
            store.value = invalid
            client(store, http).request(path)
            assertNull(store.value)
            assertFalse(seen.last().header("Cookie").orEmpty().contains("validate="))
        }
    }
}
