package com.green.note.account

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import okhttp3.Call
import okhttp3.Request
import okhttp3.Response
import java.util.concurrent.Executor

/** Marks the session closed and cancels calls immediately; TLS pool disposal runs on IO.
 * Tracking covers response-body reads as well as the pre-execute registration race. */
internal class HttpSessionLifecycle(
    private val calls: Call.Factory,
    private val releaseConnections: () -> Unit,
    private val executor: Executor = Dispatchers.IO.asExecutor(),
) {
    private val lock = Any()
    private val pending = mutableSetOf<Call>()
    @Volatile var isClosed = false
        private set

    fun <T> readResponse(request: Request, read: (Response) -> T): T {
        val call = synchronized(lock) {
            check(!isClosed) { "网络会话已关闭" }
            calls.newCall(request).also(pending::add)
        }
        return try {
            call.execute().use { response ->
                check(!isClosed) { "网络会话已关闭" }
                read(response).also { check(!isClosed) { "网络会话已关闭" } }
            }
        } finally { synchronized(lock) { pending.remove(call) } }
    }

    fun close(clearCredentials: () -> Unit = {}) {
        val cancel = synchronized(lock) {
            if (isClosed) return
            isClosed = true
            pending.toList().also { pending.clear() }
        }
        // Never postpone credential clearing to a dispatcher or a disposed Compose scope.
        try {
            clearCredentials()
        } finally {
            try { cancel.forEach(Call::cancel) }
            finally { executor.execute { releaseConnections() } }
        }
    }
}
