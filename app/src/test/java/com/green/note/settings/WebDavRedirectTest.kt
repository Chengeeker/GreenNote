package com.green.note.settings

import kotlinx.coroutines.runBlocking
import okhttp3.Credentials
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class WebDavRedirectTest {
    private val authorization = Credentials.basic("synthetic-user", "synthetic-password")
    private val config = WebDavConfig("https://dav.example/", "synthetic-user")
    private val fixture = checkNotNull(javaClass.getResource("/backups/flutter_v3.json")).readText()

    @Test fun successfulConnectionCanDownloadThroughAllStandardRedirects() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val destination = config.copy(url = server.url("/dav/").toString())
            val service = WebDavService()
            server.enqueue(MockResponse().setResponseCode(207))
            assertTrue(service.test(destination, "synthetic-password"))
            assertEquals("PROPFIND", server.takeRequest().method)
            for (code in listOf(301, 302, 303, 307, 308)) {
                server.enqueue(MockResponse().setResponseCode(code).setHeader("Location", "download?signature=synthetic%2Bvalue"))
                server.enqueue(MockResponse().setBody(fixture))
                assertEquals("12345", BackupFormat.validate(service.download(destination, "synthetic-password")!!).local!!
                    .getJSONObject("publicIdentity").getString("uid"))
                assertEquals(authorization, server.takeRequest().getHeader("Authorization"))
                val redirected = server.takeRequest()
                assertEquals("GET", redirected.method)
                assertEquals("/dav/GreenNote/download?signature=synthetic%2Bvalue", redirected.path)
                assertEquals(authorization, redirected.getHeader("Authorization"))
            }
        }
    }

    @Test fun signedHttpsDownloadDoesNotForwardCredentialsEvenWhenItReturnsToTheOriginalHost() = runBlocking {
        val requests = mutableListOf<Request>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request()
            val target = when (requests.size) {
                1 -> "https://cdn.example/file?signature=synthetic%2Bvalue"
                2 -> "https://dav.example/returned-file"
                else -> null
            }
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).message("synthetic")
                .code(if (target == null) 200 else 302).body((if (target == null) fixture else "").toResponseBody())
                .apply { if (target != null) header("Location", target) }.build()
        }.build()
        assertEquals(3, WebDavService(client).download(config, "synthetic-password")!!.getInt("version"))
        assertEquals(3, requests.size)
        assertEquals("synthetic%2Bvalue", requests[1].url.encodedQuery!!.substringAfter('='))
        assertEquals(authorization, requests.first().header("Authorization"))
        requests.drop(1).forEach { request ->
            assertNull(request.header("Authorization"))
            assertNull(request.header("Cookie"))
            assertNull(request.header("Proxy-Authorization"))
        }
    }

    @Test fun unsafeOrMissingRedirectLocationsFailBeforeRequestingTheTarget() = runBlocking {
        for (target in listOf(null, "http://cdn.example/file", "https://user:password@cdn.example/file", "file:///private", "")) {
            var requests = 0
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                requests++
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(302).message("synthetic")
                    .body("".toResponseBody()).apply { if (target != null) header("Location", target) }.build()
            }.build()
            try { WebDavService(client).download(config, "synthetic-password"); fail("Expected redirect rejection") }
            catch (_: IllegalStateException) { }
            assertEquals(1, requests)
        }
    }

    @Test fun redirectLoopsAndExcessiveHopsStopWithoutUnboundedRequests() = runBlocking {
        for (loop in listOf(true, false)) {
            var requests = 0
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                requests++
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(302).message("synthetic")
                    .header("Location", if (loop) chain.request().url.toString() else "/hop-$requests")
                    .body("".toResponseBody()).build()
            }.build()
            try { WebDavService(client).download(config, "synthetic-password"); fail("Expected bounded redirect failure") }
            catch (_: IllegalStateException) { }
            assertEquals(if (loop) 1 else 6, requests)
        }
    }

    @Test fun redirectedMissingFileCanStillUseTheFlutterPathAndSizeLimitStillApplies() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val destination = config.copy(url = server.url("/dav/").toString())
            val service = WebDavService()
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/missing"))
            server.enqueue(MockResponse().setResponseCode(404))
            server.enqueue(MockResponse().setResponseCode(307).setHeader("Location", "/old-file"))
            server.enqueue(MockResponse().setBody(fixture))
            assertNotNull(service.download(destination, "synthetic-password"))
            server.takeRequest(); server.takeRequest()
            assertEquals("/dav//GreenNote/greennote_settings_latest.json", server.takeRequest().path)
            server.takeRequest()
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/large"))
            server.enqueue(MockResponse().setHeader("Content-Length", WebDavService.MAX_BACKUP_BYTES + 1))
            try { service.download(destination, "synthetic-password"); fail("Expected size rejection") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
