package com.green.note.network

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class ApiClientTest {
    private val signer = RequestSigner(ByteArray(1024) { 65 })
    @Test fun versionRejectedReplyReadsRetryWithMatchingHeadersAndSignature() = runBlocking {
        val requests = mutableListOf<okhttp3.Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request
            val rejected = request.url.encodedPath == "/v6/feed/replyList" && request.header("X-App-Code") == "2604201"
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body((if (rejected) """{"status":403,"message":"评论接口异常，请尝试升级到新版酷安"}"""
                    else """{"status":0,"data":[]}""").toResponseBody()).build()
        }.build()
        val api = ApiClient({ ApiSession("device", "uid=1") }, signer, http)
        api.request("/v6/feed/replyList", query = mapOf("id" to "42", "feedType" to "feed"))
        api.request("https://api.coolapk.com/v6/feed/replyList", query = mapOf("id" to "43", "feedType" to "feed_reply"))
        api.request("/v6/topic/newTagDetail", query = mapOf("tag" to "OriginOS7"))
        api.request("/v6/feed/hotReplyList", query = mapOf("id" to "42"))
        assertEquals(listOf("2604201", "2609291", "2604201", "2609291", "2604201", "2604201"), requests.map { it.header("X-App-Code") })
        requests.forEach { request ->
            val code = request.header("X-App-Code")!!
            val version = if (code == "2609291") "16.6.4" else "16.2.0"
            assertEquals(version, request.header("X-App-Version"))
            assertEquals(code, request.header("X-App-Supported"))
            assertTrue(request.header("User-Agent")!!.contains("+CoolMarket/$version-$code-universal"))
            assertEquals("16", request.header("X-Api-Version"))
            assertEquals("uid=1", request.header("Cookie"))
            assertNotNull(request.header("X-App-Token"))
        }
        assertEquals("feed_reply", requests[3].url.queryParameter("feedType"))
        assertEquals("42", requests[1].url.queryParameter("id"))
    }
    @Test fun successfulReplyReadsRetainTheirOriginalProtocol() = runBlocking {
        var count = 0
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            count++
            assertEquals("2604201", chain.request().header("X-App-Code"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"status":0,"data":[]}""".toResponseBody()).build()
        }.build()
        ApiClient({ ApiSession("device") }, signer, http).request("/v6/feed/replyList", query = mapOf("id" to "42"))
        assertEquals(1, count)
    }
    @Test fun aVersionErrorCannotReplayPublishingOrOtherEndpoints() = runBlocking {
        val requests = mutableListOf<okhttp3.Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"status":403,"message":"评论接口异常，请尝试升级到新版酷安"}""".toResponseBody()).build()
        }.build()
        val api = ApiClient({ ApiSession("device", "uid=1") }, signer, http)
        for ((path, method) in listOf("/v6/feed/createFeed" to "POST", "/v6/topic/newTagDetail" to "GET")) {
            try { api.request(path, method); fail("rejection hidden") } catch (_: ApiException) { }
        }
        assertEquals(2, requests.size)
        assertTrue(requests.all { it.header("X-App-Code") == "2604201" })
    }
    @Test fun replyFallbackPreservesQueryAndStopsOnAccountChange() = runBlocking {
        val hosts = mutableListOf<String>()
        var state = ApiSession("device", "uid=old")
        var changeAccount = false
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            hosts += request.url.host
            assertEquals("42", request.url.queryParameter("id"))
            if (changeAccount) state = state.copy(revision = state.revision + 1)
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(if (request.url.host.startsWith("api2")) 503 else 200).message("fixture")
                .body("{\"status\":0,\"data\":[]}".toResponseBody()).build()
        }.build()
        val api = ApiClient({ state }, signer, http)
        api.request("/v6/feed/replyList", query = mapOf("id" to "42"))
        assertEquals(listOf("api2.coolapk.com", "api.coolapk.com"), hosts)
        hosts.clear(); changeAccount = true
        try { api.request("/v6/feed/hotReplyList", query = mapOf("id" to "42")); fail("stale response accepted") }
        catch (_: ApiException) { }
        assertEquals(listOf("api2.coolapk.com"), hosts)
    }
    @Test fun candidateAndPublicRequestsCannotInheritCurrentCredentials() = runBlocking {
        val captured = mutableListOf<String?>()
        val state = ApiSession("device", "uid=old; token=old")
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            captured += chain.request().header("Cookie")
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("{\"status\":0,\"data\":{\"uid\":123}}".toResponseBody()).build()
        }.build()
        val api = ApiClient({ state }, signer, http)
        api.validateCookie("uid=123; token=candidate")
        api.requestPublic("/v6/user/space", mapOf("uid" to "123"))
        api.request("/v6/feed/detail", query = mapOf("id" to "1"))
        assertEquals(listOf("uid=123; token=candidate", null, "uid=old; token=old"), captured)
    }
    @Test fun aLateResponseCannotCrossAccountChanges() = runBlocking {
        var state = ApiSession("device", "uid=old; token=old")
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            state = state.copy(cookie = "uid=new; token=new", revision = 1)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("{\"status\":0,\"data\":[]}".toResponseBody()).build()
        }.build()
        val api = ApiClient({ state }, signer, http)
        var rejected = false
        try { api.request("/v6/feed/detail", query = mapOf("id" to "1")) }
        catch (error: ApiException) { rejected = error.message!!.contains("账号或设备已变更") }
        assertTrue(rejected)
    }
    @Test fun anAnonymousRequestNeverSendsStoredLoginCookies() = runBlocking {
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            assertNull(chain.request().header("Cookie"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("[]".toResponseBody()).build()
        }.build()
        val api = ApiClient({ ApiSession("device", "uid=old; token=secret", anonymous = true) }, signer, http)
        assertEquals(0, api.request("/v6/main/indexV8").getJSONArray("data").length())
    }
}
