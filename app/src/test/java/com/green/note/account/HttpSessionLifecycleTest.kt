package com.green.note.account

import okhttp3.Call
import okhttp3.Callback
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Timeout
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class HttpSessionLifecycleTest {
    private val request = Request.Builder().url("https://account.coolapk.com/auth/login").build()

    @Test fun closeClearsAndCancelsImmediatelyButReleasesConnectionsOffCallerThreadOnce() {
        val queued = mutableListOf<Runnable>()
        var secret = "temporary cookie"
        var cleared = 0
        var releases = 0
        val releaseThread = AtomicReference<Thread>()
        val call = FakeCall(request)
        val lifecycle = HttpSessionLifecycle(Call.Factory { call }, { releases++; releaseThread.set(Thread.currentThread()) }, Executor { queued += it })
        val reading = CountDownLatch(1); val finish = CountDownLatch(1)
        val failure = AtomicReference<Throwable>()
        val reader = Thread {
            try { lifecycle.readResponse(request) { reading.countDown(); check(finish.await(3, TimeUnit.SECONDS)); "late response" } }
            catch (error: Throwable) { failure.set(error) }
        }.apply { start() }
        assertTrue(reading.await(3, TimeUnit.SECONDS))
        lifecycle.close { secret = ""; cleared++ }
        lifecycle.close { cleared++ }
        assertTrue(lifecycle.isClosed)
        assertEquals("", secret)
        assertEquals(1, cleared)
        assertTrue(call.isCanceled())
        assertEquals(0, releases)
        assertEquals(1, queued.size)
        finish.countDown(); reader.join(3000)
        assertFalse(reader.isAlive)
        assertTrue(failure.get() is IllegalStateException)
        val release = Thread(queued.single()).apply { start(); join(3000) }
        assertFalse(release.isAlive)
        assertEquals(1, releases)
        assertNotSame(Thread.currentThread(), releaseThread.get())
    }

    @Test fun closedSessionRejectsNewRequestsBeforeCallCreation() {
        var created = 0
        val lifecycle = HttpSessionLifecycle(Call.Factory { created++; FakeCall(it) }, {}, Executor { it.run() })
        lifecycle.close()
        assertThrows(IllegalStateException::class.java) { lifecycle.readResponse(request) { "unexpected" } }
        assertEquals(0, created)
    }

    @Test fun defaultDispatcherNeverRunsConnectionCleanupOnClosingThread() {
        val finished = CountDownLatch(1)
        val thread = AtomicReference<Thread>()
        val lifecycle = HttpSessionLifecycle(Call.Factory { FakeCall(it) }, { thread.set(Thread.currentThread()); finished.countDown() })
        lifecycle.close()
        assertTrue(finished.await(3, TimeUnit.SECONDS))
        assertNotSame(Thread.currentThread(), thread.get())
    }

    private class FakeCall(private val request: Request) : Call {
        @Volatile private var canceled = false
        @Volatile private var executed = false
        override fun request() = request
        override fun execute(): Response {
            executed = true
            return Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("".toResponseBody()).build()
        }
        override fun enqueue(responseCallback: Callback) = error("Not used")
        override fun cancel() { canceled = true }
        override fun isExecuted() = executed
        override fun isCanceled() = canceled
        override fun timeout() = Timeout.NONE
        override fun clone(): Call = FakeCall(request)
    }
}
