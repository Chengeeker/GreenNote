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

    // Real HTTP/TLS servers in WebDavTransportTest cover cross-origin secrets and unsafe redirects.
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
            catch (_: IllegalStateException) { }
        }
    }
}
