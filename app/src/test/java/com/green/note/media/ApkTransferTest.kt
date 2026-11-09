package com.green.note.media

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ApkTransferTest {
    @get:Rule val folder = TemporaryFolder()
    private val client = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
    private val part get() = File(folder.root, "partial.apk")
    private val checkpoint get() = File(folder.root, "partial.etag")

    @Test fun streamsFullResponseAndReportsFinalBytes() = MockWebServer().use { server ->
        server.enqueue(MockResponse().setBody("abcdef").setHeader("ETag", "\"one\""))
        val sizes = mutableListOf<Pair<Long, Long>>()
        ApkTransfer().download(client, server.url("/app.apk"), part, checkpoint) { bytes, total, _ ->
            sizes += bytes to total
        }
        assertEquals("abcdef", part.readText())
        assertEquals(6L to 6L, sizes.last())
        assertEquals("identity", server.takeRequest().getHeader("Accept-Encoding"))
    }

    @Test fun resumesOnlyMatchingRangeAndStrongValidator() = MockWebServer().use { server ->
        preparePart(server)
        server.enqueue(MockResponse().setResponseCode(206).setBody("def")
            .setHeader("ETag", "\"one\"").setHeader("Content-Range", "bytes 3-5/6"))
        ApkTransfer().download(client, server.url("/app.apk"), part, checkpoint) { _, _, _ -> }
        val request = server.takeRequest()
        assertEquals("bytes=3-", request.getHeader("Range"))
        assertEquals("\"one\"", request.getHeader("If-Range"))
        assertEquals("abcdef", part.readText())
    }

    @Test fun mismatchedRangeRestartsWithoutAppending() = MockWebServer().use { server ->
        preparePart(server)
        server.enqueue(MockResponse().setResponseCode(206).setBody("bad")
            .setHeader("ETag", "\"one\"").setHeader("Content-Range", "bytes 2-4/6"))
        server.enqueue(MockResponse().setBody("uvwxyz"))
        ApkTransfer().download(client, server.url("/app.apk"), part, checkpoint) { _, _, _ -> }
        assertNotNull(server.takeRequest().getHeader("Range"))
        assertNull(server.takeRequest().getHeader("Range"))
        assertEquals("uvwxyz", part.readText())
        assertFalse(checkpoint.exists())
    }

    @Test fun fullResponseToResumeReplacesPartialFile() = MockWebServer().use { server ->
        preparePart(server)
        server.enqueue(MockResponse().setBody("newAPK").setHeader("ETag", "\"two\""))
        ApkTransfer().download(client, server.url("/app.apk"), part, checkpoint) { _, _, _ -> }
        assertEquals("newAPK", part.readText())
        assertEquals("\"two\"", JSONObject(checkpoint.readText()).getString("etag"))
    }

    @Test fun interruptedResponseRetainsOnlyReceivedBytes() = MockWebServer().use { server ->
        val body = "a".repeat(131072)
        server.enqueue(MockResponse().setBody(body).setHeader("ETag", "\"one\"")
            .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY))
        assertThrows(IOException::class.java) {
            ApkTransfer().download(client, server.url("/app.apk"), part, checkpoint) { _, _, _ -> }
        }
        assertTrue(part.length() in 1 until body.length.toLong())
        assertTrue(checkpoint.isFile)
    }

    @Test fun pauseCancelsAnEstablishedNetworkCall() = MockWebServer().use { server ->
        server.enqueue(MockResponse().setBody("a".repeat(131072)).setBodyDelay(2, TimeUnit.SECONDS))
        val transfer = ApkTransfer()
        val headers = CountDownLatch(1)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val result = worker.submit<Boolean> {
                runCatching { transfer.download(client, server.url("/app.apk"), part, checkpoint) { _, _, _ -> headers.countDown() } }
                    .isFailure
            }
            assertTrue(headers.await(5, TimeUnit.SECONDS))
            transfer.cancel()
            assertTrue(result.get(3, TimeUnit.SECONDS))
        } finally {
            transfer.cancel()
            worker.shutdownNow()
        }
    }

    @Test fun expiryRequestsNewUrlAndRejectsUnsafeSources() = MockWebServer().use { server ->
        server.enqueue(MockResponse().setResponseCode(403))
        val failure = assertThrows(ApkTransferFailure::class.java) {
            ApkTransfer().download(client, server.url("/app.apk"), part, checkpoint) { _, _, _ -> }
        }
        assertTrue(failure.renewUrl)
        assertFalse(part.exists())
        for (url in listOf("http://example.org/a.apk", "https://user:password@example.org/a.apk", "file:///sdcard/a.apk")) {
            assertThrows(IllegalArgumentException::class.java) { checkedStoreUrl(url) }
        }
    }

    private fun preparePart(server: MockWebServer) {
        part.writeText("abc")
        checkpoint.writeText(JSONObject().put("etag", "\"one\"").put("url", server.url("/app.apk").toString())
            .put("total", 6).toString())
    }
}
